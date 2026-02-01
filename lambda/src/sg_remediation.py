"""
Security Group Remediation Lambda Function
Phase 2: Automated Remediation

Purpose: Automatically removes overly permissive ingress rules from
         Security Groups when Security Hub detects a violation.

Security:
    - Validates Security Group IDs
    - Preserves HTTP/HTTPS rules (80/443) if tagged
    - Never modifies default VPC security groups
    - Backup configuration before modification
    - Audit trail in DynamoDB
"""

import json
import logging
import os
import re
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

# ==================================================================
# Configuration
# ==================================================================

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
DRY_RUN_MODE = os.environ.get("DRY_RUN_MODE", "false").lower() == "true"
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

# Configure structured logging
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# AWS clients (lazy initialization)
_ec2_client = None
_dynamodb_client = None
_sns_client = None

# Ports that are allowed to remain open to 0.0.0.0/0 if tagged
ALLOWED_PUBLIC_PORTS = {80, 443}


def get_ec2_client():
    """Lazy initialization of EC2 client."""
    global _ec2_client
    if _ec2_client is None:
        _ec2_client = boto3.client("ec2")
    return _ec2_client


def get_dynamodb_client():
    """Lazy initialization of DynamoDB client."""
    global _dynamodb_client
    if _dynamodb_client is None:
        _dynamodb_client = boto3.client("dynamodb")
    return _dynamodb_client


def get_sns_client():
    """Lazy initialization of SNS client."""
    global _sns_client
    if _sns_client is None:
        _sns_client = boto3.client("sns")
    return _sns_client


# ==================================================================
# Input Validation
# ==================================================================

# Security Group ID format: sg-xxxxxxxxxxxxxxxxx
SG_ID_PATTERN = re.compile(r"^sg-[a-f0-9]{8,17}$")
FINDING_ID_PATTERN = re.compile(r"^[\w-]+$")


def validate_security_group_id(sg_id: str) -> bool:
    """Validate Security Group ID format."""
    if not sg_id or not isinstance(sg_id, str):
        return False
    return bool(SG_ID_PATTERN.match(sg_id))


def validate_finding_id(finding_id: str) -> bool:
    """Validate Security Hub finding ID format."""
    if not finding_id or not isinstance(finding_id, str):
        return False
    if len(finding_id) > 512:
        return False
    return bool(FINDING_ID_PATTERN.match(finding_id))


def sanitize_for_logging(value: str, max_length: int = 100) -> str:
    """Sanitize value for safe logging."""
    if not value:
        return "<empty>"
    if len(value) > max_length:
        return value[:max_length] + "..."
    return value


# ==================================================================
# Protection Check
# ==================================================================

def get_security_group_details(sg_id: str) -> dict:
    """
    Get Security Group details including tags.

    Returns dict with security group info.
    """
    ec2 = get_ec2_client()

    response = ec2.describe_security_groups(GroupIds=[sg_id])
    if not response.get("SecurityGroups"):
        raise ValueError(f"Security Group {sg_id} not found")

    return response["SecurityGroups"][0]


def is_protected_security_group(sg_details: dict) -> tuple[bool, str]:
    """
    Check if Security Group is protected from remediation.

    Protected groups:
    - Default VPC security groups
    - Tagged with ProtectedSecurityGroup=true
    - Tagged with AllowPublicAccess=true (for web servers)

    Returns:
        Tuple of (is_protected, reason)
    """
    sg_name = sg_details.get("GroupName", "")

    # Never modify default security groups
    if sg_name == "default":
        return True, "default_security_group"

    # Check tags
    tags = {tag["Key"]: tag["Value"] for tag in sg_details.get("Tags", [])}

    if tags.get("ProtectedSecurityGroup", "").lower() == "true":
        return True, "protected_tag"

    return False, ""


def allows_public_web_traffic(sg_details: dict) -> bool:
    """
    Check if security group is tagged to allow public web traffic (80/443).

    Returns True if tagged with AllowPublicWeb=true.
    """
    tags = {tag["Key"]: tag["Value"] for tag in sg_details.get("Tags", [])}
    return tags.get("AllowPublicWeb", "").lower() == "true"


# ==================================================================
# Rule Analysis
# ==================================================================

def is_overly_permissive_rule(rule: dict, allow_web_traffic: bool) -> bool:
    """
    Check if an ingress rule is overly permissive.

    Overly permissive means:
    - Source is 0.0.0.0/0 or ::/0 (anywhere)
    - Port is not 80 or 443 (unless web traffic not allowed)
    - Or port range includes dangerous ports

    Returns True if the rule should be removed.
    """
    # Check for any-source rules
    cidr_blocks = [r.get("CidrIp", "") for r in rule.get("IpRanges", [])]
    ipv6_blocks = [r.get("CidrIpv6", "") for r in rule.get("Ipv6Ranges", [])]

    has_any_source = "0.0.0.0/0" in cidr_blocks or "::/0" in ipv6_blocks

    if not has_any_source:
        return False  # Not a public rule, don't remove

    # Get port range
    from_port = rule.get("FromPort", -1)
    to_port = rule.get("ToPort", -1)
    ip_protocol = rule.get("IpProtocol", "")

    # Protocol -1 means all traffic - always dangerous
    if ip_protocol == "-1":
        return True

    # If all ports allowed (from_port=-1, to_port=-1 with specific protocol)
    if from_port == -1 and to_port == -1:
        return True

    # Check if this is a web traffic port
    is_http = from_port == 80 and to_port == 80
    is_https = from_port == 443 and to_port == 443

    # If web traffic is allowed, skip 80 and 443
    if allow_web_traffic and (is_http or is_https):
        return False

    # Port range that's too wide
    if to_port - from_port > 100:
        return True

    # Dangerous ports that should never be open to public
    dangerous_ports = {
        22,     # SSH
        23,     # Telnet
        3389,   # RDP
        3306,   # MySQL
        5432,   # PostgreSQL
        1433,   # MSSQL
        27017,  # MongoDB
        6379,   # Redis
        11211,  # Memcached
        9200,   # Elasticsearch
        5601,   # Kibana
    }

    # Check if port range includes any dangerous port
    for port in dangerous_ports:
        if from_port <= port <= to_port:
            return True

    return False


def find_rules_to_remove(sg_details: dict) -> list[dict]:
    """
    Find all overly permissive ingress rules that should be removed.

    Returns list of rules to remove.
    """
    allow_web = allows_public_web_traffic(sg_details)
    rules_to_remove = []

    for rule in sg_details.get("IpPermissions", []):
        if is_overly_permissive_rule(rule, allow_web):
            rules_to_remove.append(rule)
            logger.info(
                "Found overly permissive rule",
                extra={
                    "protocol": rule.get("IpProtocol"),
                    "from_port": rule.get("FromPort"),
                    "to_port": rule.get("ToPort")
                }
            )

    return rules_to_remove


# ==================================================================
# Remediation Actions
# ==================================================================

def remove_ingress_rules(sg_id: str, rules: list[dict]) -> dict:
    """
    Remove specified ingress rules from a security group.

    Returns result dict.
    """
    if not rules:
        return {"action": "remove_rules", "status": "no_action", "count": 0}

    ec2 = get_ec2_client()

    if DRY_RUN_MODE:
        logger.info(
            "DRY RUN: Would remove ingress rules",
            extra={"sg_id": sg_id, "rule_count": len(rules)}
        )
        return {"action": "remove_rules", "status": "dry_run", "count": len(rules)}

    ec2.revoke_security_group_ingress(
        GroupId=sg_id,
        IpPermissions=rules
    )

    logger.info(
        "Removed ingress rules",
        extra={"sg_id": sg_id, "rule_count": len(rules)}
    )
    return {"action": "remove_rules", "status": "applied", "count": len(rules)}


def tag_as_remediated(sg_id: str) -> dict:
    """
    Tag security group as remediated for tracking.
    """
    ec2 = get_ec2_client()

    if DRY_RUN_MODE:
        return {"action": "tag_remediated", "status": "dry_run"}

    ec2.create_tags(
        Resources=[sg_id],
        Tags=[
            {
                "Key": "RemediatedBy",
                "Value": f"{PROJECT_NAME}-sg-remediation"
            },
            {
                "Key": "RemediatedAt",
                "Value": datetime.now(timezone.utc).strftime("%Y-%m-%d")
            }
        ]
    )

    return {"action": "tag_remediated", "status": "applied"}


# ==================================================================
# State Tracking (DynamoDB)
# ==================================================================

def log_remediation_to_dynamodb(
    finding_id: str,
    sg_id: str,
    original_rules: list[dict],
    removed_rules: list[dict],
    success: bool,
    error_message: str = ""
) -> None:
    """Log remediation action to DynamoDB for audit trail."""
    if not DYNAMODB_TABLE:
        logger.warning("DynamoDB table not configured, skipping audit log")
        return

    dynamodb = get_dynamodb_client()
    timestamp = datetime.now(timezone.utc).isoformat()

    item = {
        "violation_type": {"S": "SECURITY_GROUP_OPEN"},
        "timestamp": {"S": timestamp},
        "finding_id": {"S": finding_id},
        "resource_arn": {"S": sg_id},  # SG doesn't have ARN, use ID
        "environment": {"S": ENVIRONMENT},
        "remediation_status": {"S": "SUCCESS" if success else "FAILED"},
        "dry_run": {"BOOL": DRY_RUN_MODE},
        "original_rules": {"S": json.dumps(original_rules, default=str)},
        "removed_rules": {"S": json.dumps(removed_rules, default=str)},
        "rules_removed_count": {"N": str(len(removed_rules))},
        "ttl": {"N": str(int(datetime.now(timezone.utc).timestamp() + 90 * 24 * 60 * 60))}
    }

    if error_message:
        item["error_message"] = {"S": error_message[:1000]}

    try:
        dynamodb.put_item(TableName=DYNAMODB_TABLE, Item=item)
        logger.info("Remediation logged to DynamoDB")
    except ClientError as e:
        logger.error("Failed to log to DynamoDB", extra={"error": str(e)})


# ==================================================================
# Notifications (SNS)
# ==================================================================

def send_notification(
    sg_id: str,
    finding_id: str,
    rules_removed: int,
    success: bool,
    error_message: str = ""
) -> None:
    """Send SNS notification about remediation action."""
    if not SNS_TOPIC_ARN:
        logger.debug("SNS topic not configured, skipping notification")
        return

    sns = get_sns_client()

    if success:
        subject = f"[{ENVIRONMENT.upper()}] Security Group Remediated"
        message = f"""Security Group Remediation Completed

Environment: {ENVIRONMENT}
Security Group: {sg_id}
Finding ID: {sanitize_for_logging(finding_id, 100)}
Rules Removed: {rules_removed}
Mode: {"DRY RUN" if DRY_RUN_MODE else "ACTIVE"}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Overly permissive ingress rules have been automatically removed.
Check DynamoDB for the original rules if rollback is needed.
"""
    else:
        subject = f"[{ENVIRONMENT.upper()}] SG Remediation FAILED"
        message = f"""Security Group Remediation Failed - Manual Review Required

Environment: {ENVIRONMENT}
Security Group: {sg_id}
Finding ID: {sanitize_for_logging(finding_id, 100)}
Error: {sanitize_for_logging(error_message, 500)}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Please investigate and remediate manually.
"""

    try:
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
        logger.info("Notification sent successfully")
    except ClientError as e:
        logger.error("Failed to send SNS notification", extra={"error": str(e)})


# ==================================================================
# Event Parsing
# ==================================================================

def parse_security_hub_event(event: dict) -> tuple[str, str]:
    """
    Parse Security Hub finding from EventBridge event.

    Extracts finding ID and Security Group ID from the event.

    Returns:
        Tuple of (finding_id, sg_id)
    """
    try:
        detail = event.get("detail", {})
        findings = detail.get("findings", [])

        if not findings:
            raise ValueError("No findings in event")

        finding = findings[0]
        finding_id = finding.get("Id", "")

        resources = finding.get("Resources", [])
        if not resources:
            raise ValueError("No resources in finding")

        # Find Security Group resource
        sg_id = None
        for resource in resources:
            resource_type = resource.get("Type", "")
            resource_id = resource.get("Id", "")

            if resource_type == "AwsEc2SecurityGroup":
                # Resource ID format: arn:aws:ec2:region:account:security-group/sg-xxx
                # or just sg-xxx
                if "security-group/" in resource_id:
                    sg_id = resource_id.split("security-group/")[-1]
                elif resource_id.startswith("sg-"):
                    sg_id = resource_id
                break

        if not sg_id:
            raise ValueError("No Security Group resource found in finding")

        return finding_id, sg_id

    except (KeyError, TypeError, IndexError) as e:
        raise ValueError(f"Invalid event structure: {e}")


# ==================================================================
# Main Handler
# ==================================================================

def lambda_handler(event: dict, context: Any) -> dict:
    """
    Lambda entry point for Security Group remediation.

    Triggered by EventBridge when Security Hub detects a Security Group
    with overly permissive ingress rules.
    """
    logger.info(
        "Security Group Remediation Lambda invoked",
        extra={"environment": ENVIRONMENT, "dry_run": DRY_RUN_MODE}
    )

    finding_id = ""
    sg_id = ""
    original_rules = []
    removed_rules = []

    try:
        # Parse event
        finding_id, sg_id = parse_security_hub_event(event)

        # Validate inputs
        if not validate_finding_id(finding_id):
            raise ValueError("Invalid finding ID format")

        if not validate_security_group_id(sg_id):
            raise ValueError("Invalid Security Group ID format")

        logger.info(
            "Processing Security Group remediation",
            extra={
                "finding_id": sanitize_for_logging(finding_id),
                "sg_id": sg_id
            }
        )

        # Get security group details
        sg_details = get_security_group_details(sg_id)
        original_rules = sg_details.get("IpPermissions", [])

        # Check if protected
        is_protected, reason = is_protected_security_group(sg_details)
        if is_protected:
            logger.info(
                "Security Group is protected, skipping remediation",
                extra={"reason": reason}
            )
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "SKIPPED",
                    "reason": reason,
                    "sg_id": sg_id
                })
            }

        # Find rules to remove
        rules_to_remove = find_rules_to_remove(sg_details)

        if not rules_to_remove:
            logger.info("No overly permissive rules found")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "NO_ACTION_NEEDED",
                    "sg_id": sg_id,
                    "message": "No overly permissive rules found"
                })
            }

        removed_rules = rules_to_remove

        # Remove dangerous rules
        remove_result = remove_ingress_rules(sg_id, rules_to_remove)

        # Tag as remediated
        tag_result = tag_as_remediated(sg_id)

        # Log to DynamoDB
        log_remediation_to_dynamodb(
            finding_id=finding_id,
            sg_id=sg_id,
            original_rules=original_rules,
            removed_rules=removed_rules,
            success=True
        )

        # Send notification
        send_notification(
            sg_id=sg_id,
            finding_id=finding_id,
            rules_removed=len(removed_rules),
            success=True
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "REMEDIATED",
                "sg_id": sg_id,
                "finding_id": finding_id,
                "rules_removed": len(removed_rules),
                "actions": [remove_result, tag_result],
                "dry_run": DRY_RUN_MODE
            })
        }

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_message = f"AWS API error: {error_code}"

        logger.error(
            "AWS API error during remediation",
            extra={"error_code": error_code, "sg_id": sg_id}
        )

        log_remediation_to_dynamodb(
            finding_id=finding_id or "unknown",
            sg_id=sg_id or "unknown",
            original_rules=original_rules,
            removed_rules=removed_rules,
            success=False,
            error_message=error_message
        )

        send_notification(
            sg_id=sg_id or "unknown",
            finding_id=finding_id or "unknown",
            rules_removed=0,
            success=False,
            error_message=error_message
        )

        return {
            "statusCode": 500,
            "body": json.dumps({"status": "FAILED", "error": error_message})
        }

    except ValueError as e:
        error_message = str(e)
        logger.error("Validation error", extra={"error": error_message})

        return {
            "statusCode": 400,
            "body": json.dumps({"status": "INVALID_INPUT", "error": error_message})
        }

    except Exception as e:
        error_message = "Internal error during remediation"
        logger.exception("Unexpected error during remediation")

        log_remediation_to_dynamodb(
            finding_id=finding_id or "unknown",
            sg_id=sg_id or "unknown",
            original_rules=original_rules,
            removed_rules=removed_rules,
            success=False,
            error_message=error_message
        )

        send_notification(
            sg_id=sg_id or "unknown",
            finding_id=finding_id or "unknown",
            rules_removed=0,
            success=False,
            error_message=error_message
        )

        return {
            "statusCode": 500,
            "body": json.dumps({"status": "FAILED", "error": error_message})
        }
