"""Unit tests for lambda/src/ci_gate_notifier.py"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch, ANY

# ci_gate_notifier has module-level boto3 calls — patch before importing.
with patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.resource", return_value=MagicMock()):
    import ci_gate_notifier


# ── get_bot_token ─────────────────────────────────────────────────────

def test_get_bot_token_ssm_missing_raises_runtime_error():
    """Fix 6: SSM failure raises RuntimeError with parameter name in message."""
    ci_gate_notifier._bot_token_cache = None  # reset cache
    mock_ssm = MagicMock()
    mock_ssm.get_parameter.side_effect = Exception("ParameterNotFound")
    with patch.object(ci_gate_notifier, "ssm_client", mock_ssm), \
         patch.object(ci_gate_notifier, "SLACK_BOT_TOKEN_PARAM", "/slack/bot-token"):
        with pytest.raises(RuntimeError, match="Failed to retrieve Slack bot token"):
            ci_gate_notifier.get_bot_token()


# ── write_pending_approval ────────────────────────────────────────────

def test_write_pending_approval_writes_dynamo():
    mock_table = MagicMock()
    mock_dynamo = MagicMock()
    mock_dynamo.Table.return_value = mock_table
    with patch.object(ci_gate_notifier, "dynamodb", mock_dynamo), \
         patch.object(ci_gate_notifier, "DYNAMODB_TABLE", "test-table"):
        ci_gate_notifier.write_pending_approval(
            approval_id="uuid-abc",
            pr_number=42,
            pr_url="https://github.com/owner/repo/pull/42",
            violations=["CKV_AWS_1: missing encryption"],
        )
    mock_table.put_item.assert_called_once()
    item = mock_table.put_item.call_args[1]["Item"]
    assert item["violation_type"] == "CI_GATE_APPROVAL"
    assert item["approval_id"] == "uuid-abc"
    assert item["status"] == "PENDING"
    assert item["pr_number"] == "42"


# ── send_slack_message ────────────────────────────────────────────────

def _mock_urlopen(response_body: dict):
    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps(response_body).encode("utf-8")
    mock_urlopen = MagicMock()
    mock_urlopen.return_value.__enter__ = lambda s: mock_resp
    mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)
    return mock_urlopen


def test_send_slack_message_success():
    mock_urlopen = _mock_urlopen({"ok": True, "ts": "1234.5678"})
    with patch.object(ci_gate_notifier, "get_bot_token", return_value="xoxb-test"), \
         patch("urllib.request.urlopen", mock_urlopen):
        ci_gate_notifier.send_slack_message(
            approval_id="uuid-abc",
            pr_number=42,
            pr_url="https://github.com/owner/repo/pull/42",
            violations=["CKV_AWS_1: missing encryption"],
            timestamp="2024-01-01T12:00:00+00:00",
        )
    # Verify timeout=10 was passed (Fix 7)
    mock_urlopen.assert_called_once_with(ANY, timeout=10)


# ── lambda_handler ────────────────────────────────────────────────────

def test_lambda_handler_missing_approval_id_raises():
    event = {"pr_number": 42, "pr_url": "https://github.com/owner/repo/pull/42", "violations": []}
    with pytest.raises(ValueError, match="Missing approval_id"):
        ci_gate_notifier.lambda_handler(event, None)


def test_lambda_handler_success():
    event = {
        "approval_id": "uuid-abc-123",
        "pr_number": 42,
        "pr_url": "https://github.com/owner/repo/pull/42",
        "violations": ["CKV_AWS_1: S3 bucket missing encryption"],
    }
    mock_table = MagicMock()
    mock_dynamo = MagicMock()
    mock_dynamo.Table.return_value = mock_table
    mock_urlopen = _mock_urlopen({"ok": True, "ts": "9999.0000"})

    with patch.object(ci_gate_notifier, "dynamodb", mock_dynamo), \
         patch.object(ci_gate_notifier, "DYNAMODB_TABLE", "test-table"), \
         patch.object(ci_gate_notifier, "get_bot_token", return_value="xoxb-test"), \
         patch("urllib.request.urlopen", mock_urlopen):
        result = ci_gate_notifier.lambda_handler(event, None)

    assert result["statusCode"] == 200
    assert result["body"]["approval_id"] == "uuid-abc-123"
    assert result["body"]["status"] == "PENDING"
    mock_table.put_item.assert_called_once()
    mock_urlopen.assert_called_once_with(ANY, timeout=10)
