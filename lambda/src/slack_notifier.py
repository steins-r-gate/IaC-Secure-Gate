"""
Slack Notifier Lambda
lambda/src/slack_notifier.py

Sends interactive Block Kit messages to Slack for HITL approval workflows.
Called by Step Functions with a task token embedded in button values.
"""

import json
import logging
import os
import time
import urllib.request
import urllib.error

import boto3

# ── Configuration ────────────────────────────────────────────────────

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
SLACK_CHANNEL_ID = os.environ.get("SLACK_CHANNEL_ID", "")
SLACK_BOT_TOKEN_PARAM = os.environ.get("SLACK_BOT_TOKEN_PARAM", "")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

ssm_client = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")

# Cache the bot token across invocations
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


def build_approval_message(finding_detail, task_token):
    """Build a Slack Block Kit message for finding approval."""
    finding = finding_detail.get("findings", [{}])[0] if "findings" in finding_detail else finding_detail

    control_id = (
        finding.get("Compliance", {}).get("SecurityControlId", "Unknown")
        if isinstance(finding.get("Compliance"), dict)
        else "Unknown"
    )
    severity = finding.get("Severity", {}).get("Label", "UNKNOWN")
    title = finding.get("Title", "Security Hub Finding")
    resource_id = "Unknown"
    resources = finding.get("Resources", [])
    if resources:
        resource_id = resources[0].get("Id", "Unknown")

    # Encode task token and metadata in button values
    approve_value = json.dumps({
        "action": "APPROVED",
        "task_token": task_token,
        "type": "phase2",
    })
    false_positive_value = json.dumps({
        "action": "FALSE_POSITIVE",
        "task_token": task_token,
        "type": "phase2",
        "resource_arn": resource_id,
        "control_id": control_id,
    })

    severity_emoji = {
        "CRITICAL": ":rotating_light:",
        "HIGH": ":warning:",
        "MEDIUM": ":large_orange_diamond:",
        "LOW": ":information_source:",
    }.get(severity, ":question:")

    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"{severity_emoji} Security Finding — Approval Required",
            },
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Control:*\n{control_id}"},
                {"type": "mrkdwn", "text": f"*Severity:*\n{severity}"},
                {"type": "mrkdwn", "text": f"*Resource:*\n`{resource_id}`"},
                {"type": "mrkdwn", "text": f"*Environment:*\n{ENVIRONMENT}"},
            ],
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Finding:* {title}",
            },
        },
        {"type": "divider"},
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Approve Remediation"},
                    "style": "primary",
                    "action_id": "approve_remediation",
                    "value": approve_value,
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Mark False Positive"},
                    "style": "danger",
                    "action_id": "mark_false_positive",
                    "value": false_positive_value,
                },
            ],
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": f"IaC-Secure-Gate HITL | Auto-remediates on timeout (4h)",
                },
            ],
        },
    ]

    return blocks


def send_slack_message(blocks, text_fallback):
    """Send a message to Slack using the chat.postMessage API."""
    bot_token = get_bot_token()

    payload = json.dumps({
        "channel": SLACK_CHANNEL_ID,
        "text": text_fallback,
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

    logger.info("Slack message sent: ts=%s, channel=%s", body.get("ts"), body.get("channel"))
    return body


def update_slack_message(channel_id, message_ts, blocks, text_fallback):
    """Update an existing Slack message in-place using chat.update."""
    bot_token = get_bot_token()

    payload = json.dumps({
        "channel": channel_id,
        "ts": message_ts,
        "text": text_fallback,
        "blocks": blocks,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://slack.com/api/chat.update",
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
        raise RuntimeError(f"Slack chat.update error: {body.get('error', 'unknown')}")

    logger.info("Slack message updated: ts=%s, channel=%s", message_ts, channel_id)
    return body


def send_timeout_notification(control_id, resource_arn, severity, execution_id=None):
    """
    Notify Slack that approval timed out and auto-remediation was triggered.

    When execution_id is provided, looks up the original approval message in
    DynamoDB and replaces its buttons in-place with the timeout text. Falls back
    to posting a new message if the record is not found.
    """
    severity_emoji = {
        "CRITICAL": ":rotating_light:",
        "HIGH": ":warning:",
        "MEDIUM": ":large_orange_diamond:",
        "LOW": ":information_source:",
    }.get(severity, ":question:")

    text = (
        f":alarm_clock: *Approval timed out — auto-remediating*\n"
        f"{severity_emoji} *Control:* {control_id}\n"
        f"*Resource:* `{resource_arn}`\n"
        f"No response within the approval window. Remediation has been triggered automatically."
    )
    blocks = [
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": text},
        }
    ]

    # Try to update the original approval message in-place
    if execution_id and DYNAMODB_TABLE:
        try:
            table = dynamodb.Table(DYNAMODB_TABLE)
            item = table.get_item(
                Key={"violation_type": "PENDING_APPROVAL", "timestamp": execution_id}
            ).get("Item")
            if item:
                update_slack_message(item["channel_id"], item["message_ts"], blocks, text)
                logger.info("Updated original approval message for execution %s", execution_id)
                return
            else:
                logger.warning("No DynamoDB record for execution_id=%s; posting new message", execution_id)
        except Exception as exc:  # noqa: BLE001
            logger.error("Failed to update original message: %s", exc)

    send_slack_message(blocks, text)


def lambda_handler(event, context):
    """
    Entry point. Handles two message types:

    Approval request (Phase 2 HITL):
    {
        "task_token": "<SFN task token>",
        "finding": { ...Security Hub finding detail... }
    }

    Timeout notification:
    {
        "message_type": "timeout_notification",
        "control_id": "S3.2",
        "resource_arn": "arn:aws:s3:::bucket",
        "severity": "MEDIUM"
    }
    """
    logger.info("Received event: %s", json.dumps(event, default=str)[:2000])

    if event.get("message_type") == "timeout_notification":
        send_timeout_notification(
            control_id=event.get("control_id", "Unknown"),
            resource_arn=event.get("resource_arn", "Unknown"),
            severity=event.get("severity", "UNKNOWN"),
            execution_id=event.get("execution_id"),
        )
        return {"statusCode": 200, "body": {"message": "Timeout notification sent"}}

    task_token = event.get("task_token", "")
    finding_detail = event.get("finding", {})
    execution_id = event.get("execution_id", "")

    if not task_token:
        raise ValueError("Missing task_token in event")

    blocks = build_approval_message(finding_detail, task_token)
    text_fallback = "Security finding requires approval — check the Slack message for details."

    result = send_slack_message(blocks, text_fallback)

    # Persist channel + ts so the timeout handler can update this message in-place
    if execution_id and DYNAMODB_TABLE:
        try:
            table = dynamodb.Table(DYNAMODB_TABLE)
            table.put_item(Item={
                "violation_type": "PENDING_APPROVAL",
                "timestamp": execution_id,
                "channel_id": result["channel"],
                "message_ts": result["ts"],
                "expiration_time": int(time.time()) + 86400,  # 24 h TTL
            })
            logger.info("Stored message ts for execution_id=%s", execution_id)
        except Exception as exc:  # noqa: BLE001
            logger.error("Failed to store message ts in DynamoDB: %s", exc)

    return {
        "statusCode": 200,
        "body": {
            "message": "Slack notification sent",
            "slack_ts": result.get("ts"),
        },
    }
