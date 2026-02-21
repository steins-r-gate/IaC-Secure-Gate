"""
Finding Triage Lambda
lambda/src/finding_triage.py

Classifies Security Hub findings by severity, checks the false positive
registry in DynamoDB, and returns a routing decision:
- AUTO_REMEDIATE: severity >= threshold and not a false positive
- SKIP_FALSE_POSITIVE: resource+control is in the false positive registry
- REQUEST_APPROVAL: severity below threshold, needs human review
"""

import json
import logging
import os
import time

import boto3
from boto3.dynamodb.conditions import Key

# ── Configuration ────────────────────────────────────────────────────

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
AUTO_REMEDIATE_SEVERITY = os.environ.get("AUTO_REMEDIATE_SEVERITY", "HIGH")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

dynamodb = boto3.resource("dynamodb")

SEVERITY_LEVELS = {
    "CRITICAL": 4,
    "HIGH": 3,
    "MEDIUM": 2,
    "LOW": 1,
    "INFORMATIONAL": 0,
}


def parse_finding(event):
    """Extract key fields from the Security Hub finding event."""
    detail = event.get("detail", event)
    findings = detail.get("findings", [])

    if not findings:
        raise ValueError("No findings in event")

    finding = findings[0]

    control_id = finding.get("Compliance", {}).get("SecurityControlId", "UNKNOWN")
    severity = finding.get("Severity", {}).get("Label", "UNKNOWN")
    title = finding.get("Title", "")

    resources = finding.get("Resources", [])
    resource_arn = resources[0].get("Id", "UNKNOWN") if resources else "UNKNOWN"
    resource_type = resources[0].get("Type", "UNKNOWN") if resources else "UNKNOWN"

    return {
        "control_id": control_id,
        "severity": severity,
        "title": title,
        "resource_arn": resource_arn,
        "resource_type": resource_type,
    }


def check_false_positive_registry(resource_arn, control_id):
    """Check if a resource+control combination is in the false positive registry."""
    if not DYNAMODB_TABLE:
        return False

    table = dynamodb.Table(DYNAMODB_TABLE)
    now_epoch = int(time.time())

    try:
        response = table.query(
            KeyConditionExpression=Key("violation_type").eq("FALSE_POSITIVE"),
            FilterExpression="resource_arn = :arn AND control_id = :cid AND expiration_time > :now",
            ExpressionAttributeValues={
                ":arn": resource_arn,
                ":cid": control_id,
                ":now": now_epoch,
            },
            Limit=1,
        )
        items = response.get("Items", [])
        if items:
            logger.info(
                "False positive match: resource=%s, control=%s",
                resource_arn, control_id,
            )
            return True
    except Exception as e:
        logger.warning("False positive registry check failed: %s", e)

    return False


def determine_decision(severity, is_false_positive):
    """Determine the routing decision based on severity and false positive status."""
    if is_false_positive:
        return "SKIP_FALSE_POSITIVE"

    threshold = SEVERITY_LEVELS.get(AUTO_REMEDIATE_SEVERITY, 3)
    finding_severity = SEVERITY_LEVELS.get(severity, 0)

    if finding_severity >= threshold:
        return "AUTO_REMEDIATE"

    return "REQUEST_APPROVAL"


def lambda_handler(event, context):
    """
    Entry point. Expected input from Step Functions:
    {
        "detail": { "findings": [...] },
        "source": "aws.securityhub",
        "detail-type": "Security Hub Findings - Imported"
    }

    Returns:
    {
        "decision": "AUTO_REMEDIATE" | "SKIP_FALSE_POSITIVE" | "REQUEST_APPROVAL",
        "severity": "HIGH",
        "resource_type": "AwsIamPolicy",
        "resource_arn": "arn:aws:...",
        "control_id": "IAM.1"
    }
    """
    logger.info("Triage event: %s", json.dumps(event, default=str)[:2000])

    parsed = parse_finding(event)

    is_false_positive = check_false_positive_registry(
        parsed["resource_arn"],
        parsed["control_id"],
    )

    decision = determine_decision(parsed["severity"], is_false_positive)

    result = {
        "decision": decision,
        "severity": parsed["severity"],
        "resource_type": parsed["resource_type"],
        "resource_arn": parsed["resource_arn"],
        "control_id": parsed["control_id"],
    }

    logger.info("Triage result: %s", json.dumps(result))
    return result
