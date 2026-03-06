"""
Slack Callback Lambda
lambda/src/slack_callback.py

Receives Slack interactive message callbacks via API Gateway.
Validates HMAC-SHA256 signature, then:
- Phase 2: calls sfn:SendTaskSuccess to resume Step Functions
- Phase 3: writes CI gate approval to DynamoDB

After processing, uses chat.update to edit the original message in-place
(removes action buttons, shows who took the action).
"""

import hashlib
import hmac
import json
import logging
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3

# ── Configuration ────────────────────────────────────────────────────

ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "iac-secure-gate")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "")
SLACK_SIGNING_SECRET_PARAM = os.environ.get("SLACK_SIGNING_SECRET_PARAM", "")
SLACK_BOT_TOKEN_PARAM = os.environ.get("SLACK_BOT_TOKEN_PARAM", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

ssm_client = boto3.client("ssm")
sfn_client = boto3.client("stepfunctions")
dynamodb = boto3.resource("dynamodb")

_signing_secret_cache = None
_bot_token_cache = None


def get_signing_secret():
    global _signing_secret_cache
    if _signing_secret_cache is None:
        _signing_secret_cache = ssm_client.get_parameter(
            Name=SLACK_SIGNING_SECRET_PARAM, WithDecryption=True
        )["Parameter"]["Value"]
    return _signing_secret_cache


def get_bot_token():
    global _bot_token_cache
    if _bot_token_cache is None:
        _bot_token_cache = ssm_client.get_parameter(
            Name=SLACK_BOT_TOKEN_PARAM, WithDecryption=True
        )["Parameter"]["Value"]
    return _bot_token_cache


# ── Signature verification ────────────────────────────────────────────

def verify_slack_signature(headers, body):
    signing_secret = get_signing_secret()
    timestamp = headers.get("X-Slack-Request-Timestamp", headers.get("x-slack-request-timestamp", ""))
    signature = headers.get("X-Slack-Signature", headers.get("x-slack-signature", ""))

    if not timestamp or not signature:
        raise ValueError("Missing Slack signature headers")

    if abs(time.time() - int(timestamp)) > 300:
        raise ValueError("Request timestamp too old — possible replay attack")

    sig_basestring = f"v0:{timestamp}:{body}"
    computed = "v0=" + hmac.new(
        signing_secret.encode("utf-8"),
        sig_basestring.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(computed, signature):
        raise ValueError("Invalid Slack signature")


# ── Slack message update ──────────────────────────────────────────────

def update_original_message(channel_id, message_ts, action, user_info):
    """
    Edit the original Slack message in-place using chat.update.
    Replaces action buttons with a plain confirmation line.
    """
    username = user_info.get("username", "someone")

    labels = {
        "APPROVED":       (":white_check_mark:", f"Remediation *approved* by @{username} — executing now."),
        "FALSE_POSITIVE": (":no_entry_sign:",    f"Marked as *false positive* by @{username} — added to registry."),
        "REJECTED":       (":x:",                f"Override *rejected* by @{username} — PR remains blocked."),
    }
    icon, text = labels.get(action, (":grey_question:", f"Action `{action}` recorded by @{username}."))
    full_text = f"{icon} {text}"

    payload = json.dumps({
        "channel": channel_id,
        "ts": message_ts,
        "text": full_text,
        "blocks": [
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": full_text},
            }
        ],
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://slack.com/api/chat.update",
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {get_bot_token()}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode("utf-8"))

    if not body.get("ok"):
        logger.warning("chat.update failed: %s", body.get("error"))
    else:
        logger.info("Original Slack message updated (buttons removed)")


# ── Business logic ────────────────────────────────────────────────────

def register_false_positive(resource_arn, control_id, username):
    """Write a false positive entry to DynamoDB so future findings are auto-skipped."""
    if not DYNAMODB_TABLE or not resource_arn or not control_id:
        return
    now = datetime.now(timezone.utc)
    ttl_seconds = 90 * 24 * 60 * 60  # 90 days
    table = dynamodb.Table(DYNAMODB_TABLE)
    table.put_item(Item={
        "violation_type": "FALSE_POSITIVE",
        "timestamp": now.isoformat(),
        "resource_arn": resource_arn,
        "control_id": control_id,
        "marked_by": username,
        "environment": ENVIRONMENT,
        "expiration_time": int(now.timestamp()) + ttl_seconds,
    })
    logger.info("False positive registered: resource=%s, control=%s", resource_arn, control_id)


def handle_phase2_callback(action_data, user_info):
    task_token = action_data.get("task_token", "")
    action = action_data.get("action", "")

    if not task_token:
        raise ValueError("Missing task_token in action data")

    if action == "FALSE_POSITIVE":
        register_false_positive(
            resource_arn=action_data.get("resource_arn", ""),
            control_id=action_data.get("control_id", ""),
            username=user_info.get("username", "unknown"),
        )

    sfn_client.send_task_success(
        taskToken=task_token,
        output=json.dumps({
            "decision": action,
            "approved_by": user_info.get("username", "unknown"),
            "approved_at": datetime.now(timezone.utc).isoformat(),
            "resource_arn": action_data.get("resource_arn", ""),
            "control_id": action_data.get("control_id", ""),
        }),
    )
    logger.info("SFN task success sent: action=%s, user=%s", action, user_info.get("username"))
    return action


def handle_phase3_callback(action_data, user_info):
    approval_id = action_data.get("approval_id", "")
    action = action_data.get("action", "")

    if not approval_id:
        raise ValueError("Missing approval_id in action data")

    table = dynamodb.Table(DYNAMODB_TABLE)
    now = datetime.now(timezone.utc).isoformat()

    table.update_item(
        Key={
            "violation_type": "CI_GATE_APPROVAL",
            "timestamp": action_data.get("timestamp", now),
        },
        UpdateExpression="SET #s = :status, approved_by = :user, approved_at = :at, approval_id = :aid",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":status": "APPROVED" if action == "APPROVED" else "REJECTED",
            ":user": user_info.get("username", "unknown"),
            ":at": now,
            ":aid": approval_id,
        },
    )
    logger.info("CI gate approval written: approval_id=%s, action=%s", approval_id, action)
    return action


# ── Entry point ───────────────────────────────────────────────────────

def lambda_handler(event, context):
    headers = event.get("headers", {})
    body = event.get("body", "")

    try:
        verify_slack_signature(headers, body)
    except ValueError as e:
        logger.warning("Signature verification failed: %s", e)
        return {"statusCode": 401, "body": json.dumps({"error": str(e)})}

    parsed = urllib.parse.parse_qs(body)
    payload_str = parsed.get("payload", [""])[0]
    if not payload_str:
        return {"statusCode": 400, "body": json.dumps({"error": "Missing payload"})}

    # Fix 4: Guard against malformed payloads — a JSONDecodeError here would
    # return 500, causing Slack to retry and potentially flood the endpoint.
    try:
        payload = json.loads(payload_str)
    except json.JSONDecodeError as e:
        logger.warning("Failed to parse Slack payload JSON: %s", e)
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid payload JSON"})}

    user_info = payload.get("user", {})
    channel_id = payload.get("channel", {}).get("id", "")
    message_ts = payload.get("message", {}).get("ts", "")
    actions = payload.get("actions", [])

    if not actions:
        return {"statusCode": 400, "body": json.dumps({"error": "No actions in payload"})}

    try:
        action_value = json.loads(actions[0].get("value", "{}"))
    except json.JSONDecodeError as e:
        logger.warning("Failed to parse action value JSON: %s", e)
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid action value JSON"})}
    callback_type = action_value.get("type", "")

    try:
        if callback_type == "phase2":
            taken_action = handle_phase2_callback(action_value, user_info)
        elif callback_type == "phase3":
            taken_action = handle_phase3_callback(action_value, user_info)
        else:
            return {"statusCode": 400, "body": json.dumps({"error": f"Unknown type: {callback_type}"})}
    except Exception as e:
        logger.error("Callback processing failed: %s", e, exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": "Internal processing error"})}

    # Edit the original message in-place — removes buttons
    if channel_id and message_ts:
        try:
            update_original_message(channel_id, message_ts, taken_action, user_info)
        except Exception as e:
            logger.warning("Failed to update Slack message: %s", e)

    return {"statusCode": 200, "body": ""}
