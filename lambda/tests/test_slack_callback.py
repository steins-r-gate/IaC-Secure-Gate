"""Unit tests for lambda/src/slack_callback.py"""

import hashlib
import hmac as hmac_module
import json
import sys
import os
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch

# slack_callback has module-level boto3 calls — patch before importing.
with patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.resource", return_value=MagicMock()):
    import slack_callback


# ── Helpers ───────────────────────────────────────────────────────────

def _compute_signature(secret, timestamp, body):
    sig_base = f"v0:{timestamp}:{body}"
    return "v0=" + hmac_module.new(
        secret.encode("utf-8"), sig_base.encode("utf-8"), hashlib.sha256
    ).hexdigest()


# ── verify_slack_signature ────────────────────────────────────────────

def test_verify_slack_signature_valid():
    secret = "test_signing_secret"
    ts = str(int(time.time()))
    body = "key=value"
    sig = _compute_signature(secret, ts, body)
    headers = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": sig}
    with patch.object(slack_callback, "get_signing_secret", return_value=secret):
        slack_callback.verify_slack_signature(headers, body)  # must not raise


def test_verify_slack_signature_invalid_hmac():
    ts = str(int(time.time()))
    headers = {"X-Slack-Request-Timestamp": ts, "X-Slack-Signature": "v0=badsignature"}
    with patch.object(slack_callback, "get_signing_secret", return_value="secret"):
        with pytest.raises(ValueError, match="Invalid Slack signature"):
            slack_callback.verify_slack_signature(headers, "body")


def test_verify_slack_signature_expired_timestamp():
    old_ts = str(int(time.time()) - 400)  # 400 s > 300 s limit
    headers = {
        "X-Slack-Request-Timestamp": old_ts,
        "X-Slack-Signature": "v0=irrelevant",
    }
    with patch.object(slack_callback, "get_signing_secret", return_value="secret"):
        with pytest.raises(ValueError, match="timestamp too old"):
            slack_callback.verify_slack_signature(headers, "body")


def test_verify_slack_signature_missing_headers():
    with patch.object(slack_callback, "get_signing_secret", return_value="secret"):
        with pytest.raises(ValueError, match="Missing"):
            slack_callback.verify_slack_signature({}, "body")


# ── lambda_handler: malformed payload (Fix 4) ─────────────────────────

def test_lambda_handler_malformed_payload_json_returns_400():
    body = urllib.parse.urlencode({"payload": "NOT_VALID_JSON"})
    event = {"headers": {}, "body": body}
    with patch.object(slack_callback, "verify_slack_signature"):
        result = slack_callback.lambda_handler(event, None)
    assert result["statusCode"] == 400
    assert "Invalid payload JSON" in result["body"]


def test_lambda_handler_malformed_action_value_json_returns_400():
    inner_payload = json.dumps({
        "user": {"username": "alice"},
        "channel": {"id": "C123"},
        "message": {"ts": "1234.5678"},
        "actions": [{"value": "NOT_VALID_JSON"}],
    })
    body = urllib.parse.urlencode({"payload": inner_payload})
    event = {"headers": {}, "body": body}
    with patch.object(slack_callback, "verify_slack_signature"):
        result = slack_callback.lambda_handler(event, None)
    assert result["statusCode"] == 400
    assert "Invalid action value JSON" in result["body"]


# ── lambda_handler: routing ───────────────────────────────────────────

def test_lambda_handler_invalid_signature_returns_401():
    event = {"headers": {}, "body": "payload=test"}
    with patch.object(
        slack_callback, "verify_slack_signature", side_effect=ValueError("Invalid Slack signature")
    ):
        result = slack_callback.lambda_handler(event, None)
    assert result["statusCode"] == 401


def test_lambda_handler_unknown_callback_type_returns_400():
    action_value = json.dumps({"type": "unknown_phase", "action": "APPROVED"})
    inner_payload = json.dumps({
        "user": {"username": "alice"},
        "channel": {"id": "C123"},
        "message": {"ts": "1234.5678"},
        "actions": [{"value": action_value}],
    })
    body = urllib.parse.urlencode({"payload": inner_payload})
    event = {"headers": {}, "body": body}
    with patch.object(slack_callback, "verify_slack_signature"):
        result = slack_callback.lambda_handler(event, None)
    assert result["statusCode"] == 400


def test_lambda_handler_phase2_approved():
    task_token = "sfn-task-token-abc"
    action_value = json.dumps({
        "type": "phase2",
        "action": "APPROVED",
        "task_token": task_token,
        "resource_arn": "arn:aws:s3:::my-bucket",
        "control_id": "S3.2",
    })
    inner_payload = json.dumps({
        "user": {"username": "alice", "id": "U123"},
        "channel": {"id": "C123"},
        "message": {"ts": "1234.5678"},
        "actions": [{"value": action_value}],
    })
    body = urllib.parse.urlencode({"payload": inner_payload})
    event = {"headers": {}, "body": body}

    mock_sfn = MagicMock()
    with patch.object(slack_callback, "verify_slack_signature"), \
         patch.object(slack_callback, "sfn_client", mock_sfn), \
         patch.object(slack_callback, "update_original_message"):
        result = slack_callback.lambda_handler(event, None)

    assert result["statusCode"] == 200
    mock_sfn.send_task_success.assert_called_once()
    call_kwargs = mock_sfn.send_task_success.call_args[1]
    assert call_kwargs["taskToken"] == task_token
    output = json.loads(call_kwargs["output"])
    assert output["decision"] == "APPROVED"


def test_lambda_handler_phase2_false_positive():
    task_token = "sfn-task-token-xyz"
    action_value = json.dumps({
        "type": "phase2",
        "action": "FALSE_POSITIVE",
        "task_token": task_token,
        "resource_arn": "arn:aws:iam::123456789012:policy/MyPolicy",
        "control_id": "IAM.1",
    })
    inner_payload = json.dumps({
        "user": {"username": "bob", "id": "U456"},
        "channel": {"id": "C123"},
        "message": {"ts": "9999.0000"},
        "actions": [{"value": action_value}],
    })
    body = urllib.parse.urlencode({"payload": inner_payload})
    event = {"headers": {}, "body": body}

    mock_sfn = MagicMock()
    mock_table = MagicMock()
    mock_dynamo = MagicMock()
    mock_dynamo.Table.return_value = mock_table

    with patch.object(slack_callback, "verify_slack_signature"), \
         patch.object(slack_callback, "sfn_client", mock_sfn), \
         patch.object(slack_callback, "dynamodb", mock_dynamo), \
         patch.object(slack_callback, "DYNAMODB_TABLE", "test-table"), \
         patch.object(slack_callback, "update_original_message"):
        result = slack_callback.lambda_handler(event, None)

    assert result["statusCode"] == 200
    mock_sfn.send_task_success.assert_called_once()
    mock_table.put_item.assert_called_once()  # false positive registered in DynamoDB


def test_lambda_handler_phase3_approved():
    approval_id = "approval-uuid-123"
    timestamp = "2024-01-01T12:00:00+00:00"
    action_value = json.dumps({
        "type": "phase3",
        "action": "APPROVED",
        "approval_id": approval_id,
        "timestamp": timestamp,
    })
    inner_payload = json.dumps({
        "user": {"username": "carol", "id": "U789"},
        "channel": {"id": "C999"},
        "message": {"ts": "5555.6666"},
        "actions": [{"value": action_value}],
    })
    body = urllib.parse.urlencode({"payload": inner_payload})
    event = {"headers": {}, "body": body}

    mock_table = MagicMock()
    mock_dynamo = MagicMock()
    mock_dynamo.Table.return_value = mock_table

    with patch.object(slack_callback, "verify_slack_signature"), \
         patch.object(slack_callback, "dynamodb", mock_dynamo), \
         patch.object(slack_callback, "DYNAMODB_TABLE", "test-table"), \
         patch.object(slack_callback, "update_original_message"):
        result = slack_callback.lambda_handler(event, None)

    assert result["statusCode"] == 200
    mock_table.update_item.assert_called_once()
    update_kwargs = mock_table.update_item.call_args[1]
    assert update_kwargs["Key"]["violation_type"] == "CI_GATE_APPROVAL"
    assert ":status" in update_kwargs["ExpressionAttributeValues"]
    assert update_kwargs["ExpressionAttributeValues"][":status"] == "APPROVED"
