"""
S3 Remediation Lambda Function
Phase 2: Automated Remediation

Purpose: Automatically secures S3 buckets when Security Hub detects:
         - Public access enabled
         - Missing encryption
         - Missing versioning

Security:
    - Input validation on bucket names
    - Skips protected buckets (tagged)
    - No sensitive data in logs
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
_s3_client = None
_dynamodb_client = None
_sns_client = None


def get_s3_client():
    """Lazy initialization of S3 client."""
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3")
    return _s3_client


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

# S3 bucket naming rules: 3-63 chars, lowercase, numbers, hyphens, periods
BUCKET_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$")
FINDING_ID_PATTERN = re.compile(r"^[\w:/.+-]+$")


def validate_bucket_name(bucket_name: str) -> bool:
    """
    Validate S3 bucket name format.

    Rules:
    - 3-63 characters
    - Lowercase letters, numbers, hyphens, periods
    - Must start and end with letter or number
    - Cannot be formatted as IP address
    """
    if not bucket_name or not isinstance(bucket_name, str):
        return False
    if len(bucket_name) < 3 or len(bucket_name) > 63:
        return False
    if not BUCKET_NAME_PATTERN.match(bucket_name):
        return False
    # Check not IP address format
    if re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", bucket_name):
        return False
    return True


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

def is_protected_bucket(bucket_name: str) -> bool:
    """
    Check if bucket is protected from remediation.

    Protected buckets:
    - Tagged with ProtectedBucket=true
    - CloudTrail log buckets
    - Config log buckets
    """
    s3 = get_s3_client()

    # Check for protection tag
    try:
        tags_response = s3.get_bucket_tagging(Bucket=bucket_name)
        tags = {tag["Key"]: tag["Value"] for tag in tags_response.get("TagSet", [])}

        if tags.get("ProtectedBucket", "").lower() == "true":
            logger.info(f"Bucket is protected by tag", extra={"bucket": bucket_name})
            return True

        # Check for known infrastructure buckets
        if tags.get("Purpose") in ["cloudtrail-logs", "config-logs", "terraform-state"]:
            logger.info(f"Bucket is infrastructure bucket", extra={"bucket": bucket_name})
            return True

    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchTagSet":
            pass  # No tags, not protected
        else:
            # Fix 3: Fail-closed on unexpected errors — treat as protected to block
            # remediation until the error is investigated (permissions issue, network, etc.).
            logger.warning(
                "Unexpected error checking bucket tags — treating bucket as protected to fail safely",
                extra={"bucket": bucket_name, "error": str(e)},
            )
            return True

    return False


# ==================================================================
# Current Configuration Capture
# ==================================================================

def get_current_configuration(bucket_name: str) -> dict:
    """
    Capture current bucket configuration for backup/rollback.

    Returns dict with public access, encryption, and versioning settings.
    """
    s3 = get_s3_client()
    config = {
        "bucket_name": bucket_name,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "public_access_block": None,
        "encryption": None,
        "versioning": None,
        "acl": None
    }

    # Get Public Access Block
    try:
        pab_response = s3.get_public_access_block(Bucket=bucket_name)
        config["public_access_block"] = pab_response.get("PublicAccessBlockConfiguration", {})
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchPublicAccessBlockConfiguration":
            config["public_access_block"] = {"status": "not_configured"}
        else:
            config["public_access_block"] = {"error": str(e)}

    # Get Encryption
    try:
        enc_response = s3.get_bucket_encryption(Bucket=bucket_name)
        config["encryption"] = enc_response.get("ServerSideEncryptionConfiguration", {})
    except ClientError as e:
        if e.response["Error"]["Code"] == "ServerSideEncryptionConfigurationNotFoundError":
            config["encryption"] = {"status": "not_configured"}
        else:
            config["encryption"] = {"error": str(e)}

    # Get Versioning
    try:
        ver_response = s3.get_bucket_versioning(Bucket=bucket_name)
        config["versioning"] = {
            "Status": ver_response.get("Status", "Disabled"),
            "MFADelete": ver_response.get("MFADelete", "Disabled")
        }
    except ClientError as e:
        config["versioning"] = {"error": str(e)}

    # Get ACL
    try:
        acl_response = s3.get_bucket_acl(Bucket=bucket_name)
        # Simplify ACL for logging (don't expose full grant details)
        grants = acl_response.get("Grants", [])
        public_grants = [g for g in grants if "AllUsers" in str(g) or "AuthenticatedUsers" in str(g)]
        config["acl"] = {
            "total_grants": len(grants),
            "public_grants": len(public_grants)
        }
    except ClientError as e:
        config["acl"] = {"error": str(e)}

    return config


# ==================================================================
# Remediation Actions
# ==================================================================

def block_public_access(bucket_name: str) -> dict:
    """
    Block all public access to the bucket.

    Sets all four public access block settings to True.
    """
    s3 = get_s3_client()

    public_access_block_config = {
        "BlockPublicAcls": True,
        "IgnorePublicAcls": True,
        "BlockPublicPolicy": True,
        "RestrictPublicBuckets": True
    }

    if DRY_RUN_MODE:
        logger.info("DRY RUN: Would block public access", extra={"bucket": bucket_name})
        return {"action": "block_public_access", "status": "dry_run"}

    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration=public_access_block_config
    )

    logger.info("Blocked public access", extra={"bucket": bucket_name})
    return {"action": "block_public_access", "status": "applied"}


def enable_encryption(bucket_name: str) -> dict:
    """
    Enable default server-side encryption with SSE-S3.

    Uses AES-256 (SSE-S3) as it's free and requires no key management.
    """
    s3 = get_s3_client()

    encryption_config = {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": True
            }
        ]
    }

    if DRY_RUN_MODE:
        logger.info("DRY RUN: Would enable encryption", extra={"bucket": bucket_name})
        return {"action": "enable_encryption", "status": "dry_run"}

    s3.put_bucket_encryption(
        Bucket=bucket_name,
        ServerSideEncryptionConfiguration=encryption_config
    )

    logger.info("Enabled default encryption (SSE-S3)", extra={"bucket": bucket_name})
    return {"action": "enable_encryption", "status": "applied"}


def enable_versioning(bucket_name: str) -> dict:
    """
    Enable bucket versioning.

    Versioning helps protect against accidental deletion and
    enables recovery of previous object versions.
    """
    s3 = get_s3_client()

    if DRY_RUN_MODE:
        logger.info("DRY RUN: Would enable versioning", extra={"bucket": bucket_name})
        return {"action": "enable_versioning", "status": "dry_run"}

    s3.put_bucket_versioning(
        Bucket=bucket_name,
        VersioningConfiguration={"Status": "Enabled"}
    )

    logger.info("Enabled versioning", extra={"bucket": bucket_name})
    return {"action": "enable_versioning", "status": "applied"}


def remediate_bucket(bucket_name: str) -> list[dict]:
    """
    Apply all S3 security remediations to a bucket.

    Returns list of actions taken.
    """
    actions = []

    # Block public access
    try:
        result = block_public_access(bucket_name)
        actions.append(result)
    except ClientError as e:
        actions.append({
            "action": "block_public_access",
            "status": "failed",
            "error": e.response["Error"]["Code"]
        })

    # Enable encryption
    try:
        result = enable_encryption(bucket_name)
        actions.append(result)
    except ClientError as e:
        actions.append({
            "action": "enable_encryption",
            "status": "failed",
            "error": e.response["Error"]["Code"]
        })

    # Enable versioning
    try:
        result = enable_versioning(bucket_name)
        actions.append(result)
    except ClientError as e:
        actions.append({
            "action": "enable_versioning",
            "status": "failed",
            "error": e.response["Error"]["Code"]
        })

    return actions


# ==================================================================
# State Tracking (DynamoDB)
# ==================================================================

def log_remediation_to_dynamodb(
    finding_id: str,
    bucket_name: str,
    original_config: dict,
    actions: list[dict],
    success: bool,
    error_message: str = ""
) -> None:
    """Log remediation action to DynamoDB for audit trail."""
    if not DYNAMODB_TABLE:
        logger.warning("DynamoDB table not configured, skipping audit log")
        return

    dynamodb = get_dynamodb_client()
    timestamp = datetime.now(timezone.utc).isoformat()

    # Count successful actions
    successful_actions = sum(1 for a in actions if a.get("status") in ["applied", "dry_run"])

    item = {
        "violation_type": {"S": "S3_PUBLIC_BUCKET"},
        "timestamp": {"S": timestamp},
        "finding_id": {"S": finding_id},
        "resource_arn": {"S": f"arn:aws:s3:::{bucket_name}"},
        "environment": {"S": ENVIRONMENT},
        "remediation_status": {"S": "SUCCESS" if success else "FAILED"},
        "dry_run": {"BOOL": DRY_RUN_MODE},
        "original_config": {"S": json.dumps(original_config)},
        "actions_taken": {"S": json.dumps(actions)},
        "actions_count": {"N": str(len(actions))},
        "successful_actions": {"N": str(successful_actions)},
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
    bucket_name: str,
    finding_id: str,
    actions: list[dict],
    success: bool,
    error_message: str = ""
) -> None:
    """Send SNS notification about remediation action."""
    if not SNS_TOPIC_ARN:
        logger.debug("SNS topic not configured, skipping notification")
        return

    sns = get_sns_client()
    successful = sum(1 for a in actions if a.get("status") in ["applied", "dry_run"])

    if success:
        subject = f"[{ENVIRONMENT.upper()}] S3 Bucket Secured"
        message = f"""S3 Bucket Remediation Completed

Environment: {ENVIRONMENT}
Bucket: {bucket_name}
Finding ID: {sanitize_for_logging(finding_id, 100)}
Actions Applied: {successful}/{len(actions)}
Mode: {"DRY RUN" if DRY_RUN_MODE else "ACTIVE"}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Actions Taken:
{chr(10).join(f"  - {a['action']}: {a['status']}" for a in actions)}

The bucket has been automatically secured.
Check DynamoDB for the original configuration if rollback is needed.
"""
    else:
        subject = f"[{ENVIRONMENT.upper()}] S3 Remediation FAILED"
        message = f"""S3 Bucket Remediation Failed - Manual Review Required

Environment: {ENVIRONMENT}
Bucket: {bucket_name}
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

    Extracts finding ID and S3 bucket name from the event.

    Returns:
        Tuple of (finding_id, bucket_name)
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

        # Find S3 bucket resource
        bucket_name = None
        for resource in resources:
            resource_type = resource.get("Type", "")
            resource_id = resource.get("Id", "")

            if resource_type == "AwsS3Bucket":
                # Resource ID format: arn:aws:s3:::bucket-name
                if resource_id.startswith("arn:aws:s3:::"):
                    bucket_name = resource_id.split(":::")[-1]
                else:
                    bucket_name = resource_id
                break

        if not bucket_name:
            raise ValueError("No S3 bucket resource found in finding")

        return finding_id, bucket_name

    except (KeyError, TypeError, IndexError) as e:
        raise ValueError(f"Invalid event structure: {e}")


# ==================================================================
# Main Handler
# ==================================================================

def lambda_handler(event: dict, context: Any) -> dict:
    """
    Lambda entry point for S3 bucket remediation.

    Triggered by EventBridge when Security Hub detects an S3 bucket
    with public access, missing encryption, or missing versioning.
    """
    logger.info(
        "S3 Remediation Lambda invoked",
        extra={"environment": ENVIRONMENT, "dry_run": DRY_RUN_MODE}
    )

    finding_id = ""
    bucket_name = ""
    original_config = {}
    actions = []

    try:
        # Parse event
        finding_id, bucket_name = parse_security_hub_event(event)

        # Validate inputs
        if not validate_finding_id(finding_id):
            raise ValueError("Invalid finding ID format")

        if not validate_bucket_name(bucket_name):
            raise ValueError("Invalid bucket name format")

        logger.info(
            "Processing S3 bucket remediation",
            extra={
                "finding_id": sanitize_for_logging(finding_id),
                "bucket": bucket_name
            }
        )

        # Check if bucket is protected
        if is_protected_bucket(bucket_name):
            logger.info("Bucket is protected, skipping remediation")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "SKIPPED",
                    "reason": "protected_bucket",
                    "bucket": bucket_name
                })
            }

        # Capture current configuration for backup
        original_config = get_current_configuration(bucket_name)

        # Apply remediations
        actions = remediate_bucket(bucket_name)

        # Check if all actions succeeded
        failed_actions = [a for a in actions if a.get("status") == "failed"]
        success = len(failed_actions) == 0

        # Log to DynamoDB
        log_remediation_to_dynamodb(
            finding_id=finding_id,
            bucket_name=bucket_name,
            original_config=original_config,
            actions=actions,
            success=success
        )

        # Send notification
        send_notification(
            bucket_name=bucket_name,
            finding_id=finding_id,
            actions=actions,
            success=success
        )

        if success:
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "REMEDIATED",
                    "bucket": bucket_name,
                    "finding_id": finding_id,
                    "actions": actions,
                    "dry_run": DRY_RUN_MODE
                })
            }
        else:
            return {
                "statusCode": 207,  # Multi-status
                "body": json.dumps({
                    "status": "PARTIAL",
                    "bucket": bucket_name,
                    "actions": actions,
                    "failed_count": len(failed_actions)
                })
            }

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_message = f"AWS API error: {error_code}"

        logger.error(
            "AWS API error during remediation",
            extra={"error_code": error_code, "bucket": bucket_name}
        )

        log_remediation_to_dynamodb(
            finding_id=finding_id or "unknown",
            bucket_name=bucket_name or "unknown",
            original_config=original_config,
            actions=actions,
            success=False,
            error_message=error_message
        )

        send_notification(
            bucket_name=bucket_name or "unknown",
            finding_id=finding_id or "unknown",
            actions=actions,
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
            bucket_name=bucket_name or "unknown",
            original_config=original_config,
            actions=actions,
            success=False,
            error_message=error_message
        )

        send_notification(
            bucket_name=bucket_name or "unknown",
            finding_id=finding_id or "unknown",
            actions=actions,
            success=False,
            error_message=error_message
        )

        return {
            "statusCode": 500,
            "body": json.dumps({"status": "FAILED", "error": error_message})
        }
