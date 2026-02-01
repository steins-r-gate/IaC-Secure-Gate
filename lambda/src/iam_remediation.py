"""
IAM Remediation Lambda Function
Phase 2: Automated Remediation

Purpose: Automatically removes wildcard (*) permissions from IAM policies
         when Security Hub detects a violation.

Security:
    - Input validation on all parameters
    - No sensitive data in logs
    - Least privilege IAM permissions
    - Backup before modification
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

# Environment variables (with secure defaults)
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
DRY_RUN_MODE = os.environ.get("DRY_RUN_MODE", "false").lower() == "true"
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

# Configure structured logging
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# AWS clients (initialized lazily)
_iam_client = None
_dynamodb_client = None
_sns_client = None


def get_iam_client():
    """Lazy initialization of IAM client."""
    global _iam_client
    if _iam_client is None:
        _iam_client = boto3.client("iam")
    return _iam_client


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

# Regex patterns for validation
ARN_PATTERN = re.compile(
    r"^arn:aws:iam::[0-9]{12}:(policy|user|group|role)/[a-zA-Z0-9+=,.@_/-]+$"
)
POLICY_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9+=,.@_-]+$")
FINDING_ID_PATTERN = re.compile(r"^[\w-]+$")


def validate_arn(arn: str) -> bool:
    """Validate IAM ARN format."""
    if not arn or not isinstance(arn, str):
        return False
    return bool(ARN_PATTERN.match(arn))


def validate_policy_name(name: str) -> bool:
    """Validate IAM policy name format."""
    if not name or not isinstance(name, str):
        return False
    if len(name) > 128:
        return False
    return bool(POLICY_NAME_PATTERN.match(name))


def validate_finding_id(finding_id: str) -> bool:
    """Validate Security Hub finding ID format."""
    if not finding_id or not isinstance(finding_id, str):
        return False
    if len(finding_id) > 512:
        return False
    return bool(FINDING_ID_PATTERN.match(finding_id))


def sanitize_for_logging(value: str, max_length: int = 100) -> str:
    """Sanitize value for safe logging (no secrets, truncated)."""
    if not value:
        return "<empty>"
    # Truncate long values
    if len(value) > max_length:
        return value[:max_length] + "..."
    return value


# ==================================================================
# Policy Analysis
# ==================================================================

def is_dangerous_wildcard_action(statement: dict) -> bool:
    """
    Check if a statement contains dangerous wildcard actions.

    Dangerous patterns:
    - "*" (full admin)
    - "iam:*" (full IAM admin)
    - "*:*" (any service, any action)

    Returns True if the statement should be remediated.
    """
    if statement.get("Effect") != "Allow":
        return False

    actions = statement.get("Action", [])
    if isinstance(actions, str):
        actions = [actions]

    dangerous_patterns = [
        "*",           # Full admin
        "iam:*",       # Full IAM admin
        "*:*",         # Any service admin
    ]

    for action in actions:
        if action in dangerous_patterns:
            return True

    return False


def is_overly_permissive_resource(statement: dict) -> bool:
    """
    Check if a statement has overly permissive resource scope.

    Returns True if Resource is "*" with dangerous actions.
    """
    resources = statement.get("Resource", [])
    if isinstance(resources, str):
        resources = [resources]

    return "*" in resources and is_dangerous_wildcard_action(statement)


def remediate_policy_document(policy_document: dict) -> tuple[dict, list[dict]]:
    """
    Remediate a policy document by removing dangerous statements.

    Args:
        policy_document: Original IAM policy document

    Returns:
        Tuple of (remediated_policy, removed_statements)
    """
    if not isinstance(policy_document, dict):
        raise ValueError("Policy document must be a dictionary")

    statements = policy_document.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]

    safe_statements = []
    removed_statements = []

    for statement in statements:
        if is_overly_permissive_resource(statement):
            removed_statements.append(statement)
            logger.info(
                "Removing dangerous statement",
                extra={
                    "sid": statement.get("Sid", "no-sid"),
                    "actions": sanitize_for_logging(str(statement.get("Action", []))),
                }
            )
        else:
            safe_statements.append(statement)

    # Create remediated policy
    remediated_policy = {
        "Version": policy_document.get("Version", "2012-10-17"),
        "Statement": safe_statements if safe_statements else [
            {
                "Sid": "RemediatedEmptyPolicy",
                "Effect": "Deny",
                "Action": "none:null",
                "Resource": "*"
            }
        ]
    }

    return remediated_policy, removed_statements


# ==================================================================
# AWS Operations
# ==================================================================

def get_policy_document(policy_arn: str) -> tuple[dict, str]:
    """
    Get the current policy document and version.

    Args:
        policy_arn: IAM policy ARN

    Returns:
        Tuple of (policy_document, version_id)
    """
    iam = get_iam_client()

    # Get policy to find default version
    policy_response = iam.get_policy(PolicyArn=policy_arn)
    default_version_id = policy_response["Policy"]["DefaultVersionId"]

    # Get the policy document
    version_response = iam.get_policy_version(
        PolicyArn=policy_arn,
        VersionId=default_version_id
    )

    policy_document = version_response["PolicyVersion"]["Document"]

    return policy_document, default_version_id


def create_policy_version(policy_arn: str, policy_document: dict) -> str:
    """
    Create a new policy version with the remediated document.

    AWS limits policies to 5 versions, so we delete the oldest non-default
    version if needed.

    Args:
        policy_arn: IAM policy ARN
        policy_document: New policy document

    Returns:
        New version ID
    """
    iam = get_iam_client()

    # List existing versions
    versions_response = iam.list_policy_versions(PolicyArn=policy_arn)
    versions = versions_response["Versions"]

    # If at version limit (5), delete oldest non-default version
    if len(versions) >= 5:
        non_default_versions = [
            v for v in versions
            if not v["IsDefaultVersion"]
        ]
        if non_default_versions:
            oldest_version = min(
                non_default_versions,
                key=lambda v: v["CreateDate"]
            )
            iam.delete_policy_version(
                PolicyArn=policy_arn,
                VersionId=oldest_version["VersionId"]
            )
            logger.info(
                "Deleted old policy version to make room",
                extra={"version_id": oldest_version["VersionId"]}
            )

    # Create new version and set as default
    new_version_response = iam.create_policy_version(
        PolicyArn=policy_arn,
        PolicyDocument=json.dumps(policy_document),
        SetAsDefault=True
    )

    return new_version_response["PolicyVersion"]["VersionId"]


# ==================================================================
# State Tracking (DynamoDB)
# ==================================================================

def log_remediation_to_dynamodb(
    finding_id: str,
    resource_arn: str,
    original_policy: dict,
    remediated_policy: dict,
    removed_statements: list[dict],
    success: bool,
    error_message: str = ""
) -> None:
    """
    Log remediation action to DynamoDB for audit trail.

    Args:
        finding_id: Security Hub finding ID
        resource_arn: ARN of remediated resource
        original_policy: Original policy document (for rollback)
        remediated_policy: New policy document
        removed_statements: Statements that were removed
        success: Whether remediation succeeded
        error_message: Error message if failed
    """
    if not DYNAMODB_TABLE:
        logger.warning("DynamoDB table not configured, skipping audit log")
        return

    dynamodb = get_dynamodb_client()
    timestamp = datetime.now(timezone.utc).isoformat()

    item = {
        "violation_type": {"S": "IAM_WILDCARD_POLICY"},
        "timestamp": {"S": timestamp},
        "finding_id": {"S": finding_id},
        "resource_arn": {"S": resource_arn},
        "environment": {"S": ENVIRONMENT},
        "remediation_status": {"S": "SUCCESS" if success else "FAILED"},
        "dry_run": {"BOOL": DRY_RUN_MODE},
        "original_policy": {"S": json.dumps(original_policy)},
        "remediated_policy": {"S": json.dumps(remediated_policy)},
        "removed_statements_count": {"N": str(len(removed_statements))},
        "removed_statements": {"S": json.dumps(removed_statements)},
        "ttl": {"N": str(int((datetime.now(timezone.utc).timestamp()) + 90 * 24 * 60 * 60))}  # 90 days
    }

    if error_message:
        item["error_message"] = {"S": error_message[:1000]}  # Truncate for safety

    try:
        dynamodb.put_item(
            TableName=DYNAMODB_TABLE,
            Item=item
        )
        logger.info("Remediation logged to DynamoDB")
    except ClientError as e:
        logger.error(
            "Failed to log remediation to DynamoDB",
            extra={"error": str(e)}
        )


# ==================================================================
# Notifications (SNS)
# ==================================================================

def send_notification(
    resource_arn: str,
    finding_id: str,
    removed_count: int,
    success: bool,
    error_message: str = ""
) -> None:
    """
    Send SNS notification about remediation action.

    Args:
        resource_arn: ARN of remediated resource
        finding_id: Security Hub finding ID
        removed_count: Number of statements removed
        success: Whether remediation succeeded
        error_message: Error message if failed
    """
    if not SNS_TOPIC_ARN:
        logger.debug("SNS topic not configured, skipping notification")
        return

    sns = get_sns_client()

    if success:
        subject = f"[{ENVIRONMENT.upper()}] IAM Policy Remediated"
        message = f"""IAM Policy Remediation Completed

Environment: {ENVIRONMENT}
Resource: {sanitize_for_logging(resource_arn, 200)}
Finding ID: {sanitize_for_logging(finding_id, 100)}
Statements Removed: {removed_count}
Mode: {"DRY RUN" if DRY_RUN_MODE else "ACTIVE"}
Timestamp: {datetime.now(timezone.utc).isoformat()}

The dangerous wildcard permissions have been automatically removed.
Check DynamoDB for the original policy if rollback is needed.
"""
    else:
        subject = f"[{ENVIRONMENT.upper()}] IAM Remediation FAILED"
        message = f"""IAM Policy Remediation Failed - Manual Review Required

Environment: {ENVIRONMENT}
Resource: {sanitize_for_logging(resource_arn, 200)}
Finding ID: {sanitize_for_logging(finding_id, 100)}
Error: {sanitize_for_logging(error_message, 500)}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Please investigate and remediate manually.
"""

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # SNS subject limit
            Message=message
        )
        logger.info("Notification sent successfully")
    except ClientError as e:
        logger.error(
            "Failed to send SNS notification",
            extra={"error": str(e)}
        )


# ==================================================================
# Event Parsing
# ==================================================================

def parse_security_hub_event(event: dict) -> tuple[str, str]:
    """
    Parse Security Hub finding from EventBridge event.

    Expected event structure (from EventBridge):
    {
        "detail": {
            "findings": [{
                "Id": "finding-id",
                "Resources": [{
                    "Id": "arn:aws:iam::...",
                    "Type": "AwsIamPolicy"
                }]
            }]
        }
    }

    Args:
        event: EventBridge event

    Returns:
        Tuple of (finding_id, resource_arn)

    Raises:
        ValueError: If event structure is invalid
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

        # Find IAM policy resource
        policy_arn = None
        for resource in resources:
            resource_type = resource.get("Type", "")
            resource_id = resource.get("Id", "")

            if resource_type == "AwsIamPolicy" and resource_id.startswith("arn:aws:iam:"):
                policy_arn = resource_id
                break

        if not policy_arn:
            raise ValueError("No IAM policy resource found in finding")

        return finding_id, policy_arn

    except (KeyError, TypeError, IndexError) as e:
        raise ValueError(f"Invalid event structure: {e}")


# ==================================================================
# Main Handler
# ==================================================================

def lambda_handler(event: dict, context: Any) -> dict:
    """
    Lambda entry point for IAM policy remediation.

    Triggered by EventBridge when Security Hub detects an IAM policy
    with dangerous wildcard permissions.

    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda context (unused)

    Returns:
        Response dict with remediation status
    """
    logger.info(
        "IAM Remediation Lambda invoked",
        extra={
            "environment": ENVIRONMENT,
            "dry_run": DRY_RUN_MODE,
        }
    )

    finding_id = ""
    policy_arn = ""
    original_policy = {}
    remediated_policy = {}
    removed_statements = []

    try:
        # Parse event
        finding_id, policy_arn = parse_security_hub_event(event)

        # Validate inputs
        if not validate_finding_id(finding_id):
            raise ValueError(f"Invalid finding ID format")

        if not validate_arn(policy_arn):
            raise ValueError(f"Invalid policy ARN format")

        logger.info(
            "Processing IAM policy remediation",
            extra={
                "finding_id": sanitize_for_logging(finding_id),
                "policy_arn": sanitize_for_logging(policy_arn),
            }
        )

        # Get current policy
        original_policy, version_id = get_policy_document(policy_arn)

        # Analyze and remediate
        remediated_policy, removed_statements = remediate_policy_document(original_policy)

        if not removed_statements:
            logger.info("No dangerous statements found, no remediation needed")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "NO_ACTION_NEEDED",
                    "finding_id": finding_id,
                    "message": "Policy does not contain dangerous wildcard statements"
                })
            }

        # Apply remediation (unless dry run)
        if DRY_RUN_MODE:
            logger.info(
                "DRY RUN: Would remediate policy",
                extra={
                    "statements_to_remove": len(removed_statements),
                }
            )
            new_version_id = "DRY_RUN"
        else:
            new_version_id = create_policy_version(policy_arn, remediated_policy)
            logger.info(
                "Policy remediated successfully",
                extra={
                    "new_version_id": new_version_id,
                    "statements_removed": len(removed_statements),
                }
            )

        # Log to DynamoDB
        log_remediation_to_dynamodb(
            finding_id=finding_id,
            resource_arn=policy_arn,
            original_policy=original_policy,
            remediated_policy=remediated_policy,
            removed_statements=removed_statements,
            success=True
        )

        # Send notification
        send_notification(
            resource_arn=policy_arn,
            finding_id=finding_id,
            removed_count=len(removed_statements),
            success=True
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "REMEDIATED",
                "finding_id": finding_id,
                "policy_arn": policy_arn,
                "new_version_id": new_version_id,
                "statements_removed": len(removed_statements),
                "dry_run": DRY_RUN_MODE
            })
        }

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_message = f"AWS API error: {error_code}"

        logger.error(
            "AWS API error during remediation",
            extra={
                "error_code": error_code,
                "finding_id": sanitize_for_logging(finding_id),
            }
        )

        # Log failure to DynamoDB
        log_remediation_to_dynamodb(
            finding_id=finding_id or "unknown",
            resource_arn=policy_arn or "unknown",
            original_policy=original_policy,
            remediated_policy=remediated_policy,
            removed_statements=removed_statements,
            success=False,
            error_message=error_message
        )

        # Send failure notification
        send_notification(
            resource_arn=policy_arn or "unknown",
            finding_id=finding_id or "unknown",
            removed_count=0,
            success=False,
            error_message=error_message
        )

        return {
            "statusCode": 500,
            "body": json.dumps({
                "status": "FAILED",
                "error": error_message
            })
        }

    except ValueError as e:
        error_message = str(e)
        logger.error(
            "Validation error",
            extra={"error": error_message}
        )

        return {
            "statusCode": 400,
            "body": json.dumps({
                "status": "INVALID_INPUT",
                "error": error_message
            })
        }

    except Exception as e:
        error_message = "Internal error during remediation"
        logger.exception("Unexpected error during remediation")

        # Log failure to DynamoDB
        log_remediation_to_dynamodb(
            finding_id=finding_id or "unknown",
            resource_arn=policy_arn or "unknown",
            original_policy=original_policy,
            remediated_policy=remediated_policy,
            removed_statements=removed_statements,
            success=False,
            error_message=error_message
        )

        # Send failure notification
        send_notification(
            resource_arn=policy_arn or "unknown",
            finding_id=finding_id or "unknown",
            removed_count=0,
            success=False,
            error_message=error_message
        )

        return {
            "statusCode": 500,
            "body": json.dumps({
                "status": "FAILED",
                "error": error_message
            })
        }
