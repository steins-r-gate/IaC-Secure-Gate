"""
CI Gate Notifier Lambda
lambda/src/ci_gate_notifier.py

Called by GitHub Actions via `aws lambda invoke`. Sends Slack message
for CI gate override requests and writes PENDING status to DynamoDB.
"""

import json
import logging
import os
import time
import urllib.request
from datetime import datetime, timezone

import boto3

# ── Configuration ────────────────────────────────────────────────────

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
SLACK_CHANNEL_ID = os.environ.get("SLACK_CHANNEL_ID", "")
SLACK_BOT_TOKEN_PARAM = os.environ.get("SLACK_BOT_TOKEN_PARAM", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

ssm_client = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")

_bot_token_cache = None


def get_bot_token():
    """Retrieve Slack bot token from SSM Parameter Store (cached)."""
    global _bot_token_cache
    if _bot_token_cache is None:
        response = ssm_client.get_parameter(
            Name=SLACK_BOT_TOKEN_PARAM,
            WithDecryption=True,
        )
        _bot_token_cache = response["Parameter"]["Value"]
    return _bot_token_cache


def write_pending_approval(approval_id, pr_number, pr_url, violations):
    """Write PENDING approval to DynamoDB."""
    table = dynamodb.Table(DYNAMODB_TABLE)
    now = datetime.now(timezone.utc).isoformat()
    ttl = int(time.time()) + (24 * 60 * 60)  # 24h TTL

    table.put_item(
        Item={
            "violation_type": "CI_GATE_APPROVAL",
            "timestamp": now,
            "approval_id": approval_id,
            "status": "PENDING",
            "pr_number": str(pr_number),
            "pr_url": pr_url,
            "violations": violations,
            "environment": ENVIRONMENT,
            "expiration_time": ttl,
        }
    )

    logger.info("PENDING approval written: approval_id=%s, pr=#%s", approval_id, pr_number)
    return now


def send_slack_message(approval_id, pr_number, pr_url, violations, timestamp):
    """Send CI gate approval request to Slack."""
    bot_token = get_bot_token()

    violation_text = "\n".join(f"• {v}" for v in violations[:10])
    if len(violations) > 10:
        violation_text += f"\n_...and {len(violations) - 10} more_"

    approve_value = json.dumps({
        "action": "APPROVED",
        "type": "phase3",
        "approval_id": approval_id,
        "timestamp": timestamp,
    })
    reject_value = json.dumps({
        "action": "REJECTED",
        "type": "phase3",
        "approval_id": approval_id,
        "timestamp": timestamp,
    })

    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": ":shield: CI Gate Override Request",
            },
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*PR:*\n<{pr_url}|#{pr_number}>"},
                {"type": "mrkdwn", "text": f"*Violations:*\n{len(violations)}"},
                {"type": "mrkdwn", "text": f"*Environment:*\n{ENVIRONMENT}"},
                {"type": "mrkdwn", "text": f"*Approval ID:*\n`{approval_id[:8]}...`"},
            ],
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Flagged violations:*\n{violation_text}",
            },
        },
        {"type": "divider"},
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Override — Allow Merge"},
                    "style": "primary",
                    "action_id": "approve_remediation",
                    "value": approve_value,
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Reject — Keep Blocked"},
                    "style": "danger",
                    "action_id": "mark_false_positive",
                    "value": reject_value,
                },
            ],
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "IaC-Secure-Gate CI Gate | Timeout: 30 minutes",
                },
            ],
        },
    ]

    payload = json.dumps({
        "channel": SLACK_CHANNEL_ID,
        "text": f"CI gate override request for PR #{pr_number}",
        "blocks": blocks,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {bot_token}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req) as resp:
        body = json.loads(resp.read().decode("utf-8"))

    if not body.get("ok"):
        raise RuntimeError(f"Slack API error: {body.get('error', 'unknown')}")

    logger.info("CI gate Slack message sent: ts=%s", body.get("ts"))
    return body


def lambda_handler(event, context):
    """
    Entry point. Expected input (from GitHub Actions `aws lambda invoke`):
    {
        "approval_id": "<UUID>",
        "pr_number": 42,
        "pr_url": "https://github.com/owner/repo/pull/42",
        "violations": ["CKV_AWS_1: S3 bucket missing encryption", ...]
    }
    """
    logger.info("Received event: %s", json.dumps(event, default=str)[:2000])

    approval_id = event.get("approval_id", "")
    pr_number = event.get("pr_number", 0)
    pr_url = event.get("pr_url", "")
    violations = event.get("violations", [])

    if not approval_id:
        raise ValueError("Missing approval_id")
    if not pr_number:
        raise ValueError("Missing pr_number")

    # Write PENDING approval to DynamoDB
    timestamp = write_pending_approval(approval_id, pr_number, pr_url, violations)

    # Send Slack notification
    send_slack_message(approval_id, pr_number, pr_url, violations, timestamp)

    return {
        "statusCode": 200,
        "body": {
            "approval_id": approval_id,
            "status": "PENDING",
            "timestamp": timestamp,
        },
    }
