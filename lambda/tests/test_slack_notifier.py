"""Unit tests for lambda/src/slack_notifier.py"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch, ANY

# slack_notifier has module-level boto3 calls — patch before importing.
with patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.resource", return_value=MagicMock()):
    import slack_notifier


# ── build_approval_message ────────────────────────────────────────────

def _make_finding_detail(severity="HIGH", control_id="IAM.1", resource_id="arn:aws:iam::123:policy/P"):
    return {
        "findings": [
            {
                "Compliance": {"SecurityControlId": control_id},
                "Severity": {"Label": severity},
                "Title": "IAM policy allows full admin",
                "Resources": [{"Id": resource_id}],
            }
        ]
    }


def test_build_approval_message_structure():
    finding_detail = _make_finding_detail()
    blocks = slack_notifier.build_approval_message(finding_detail, task_token="tok-abc")
    # Should have header, section (fields), section (title), divider, actions, context
    block_types = [b["type"] for b in blocks]
    assert "header" in block_types
    assert "actions" in block_types
    assert "divider" in block_types

    # Section block should contain control_id and severity in fields
    section_with_fields = next(b for b in blocks if b["type"] == "section" and "fields" in b)
    field_texts = [f["text"] for f in section_with_fields["fields"]]
    assert any("IAM.1" in t for t in field_texts)
    assert any("HIGH" in t for t in field_texts)


def test_build_approval_message_embeds_task_token():
    finding_detail = _make_finding_detail()
    task_token = "sfn-token-xyz-12345"
    blocks = slack_notifier.build_approval_message(finding_detail, task_token=task_token)

    # Task token must be embedded in at least one button value
    actions_block = next(b for b in blocks if b["type"] == "actions")
    button_values = [json.loads(e["value"]) for e in actions_block["elements"]]
    token_found = any(v.get("task_token") == task_token for v in button_values)
    assert token_found, "task_token not found in any button value"


# ── send_slack_message ────────────────────────────────────────────────

def _mock_urlopen(response_body: dict):
    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps(response_body).encode("utf-8")
    mock_urlopen = MagicMock()
    mock_urlopen.return_value.__enter__ = lambda s: mock_resp
    mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)
    return mock_urlopen


def test_send_slack_message_success():
    mock_urlopen = _mock_urlopen({"ok": True, "ts": "1234.5678", "channel": "C123"})
    with patch.object(slack_notifier, "get_bot_token", return_value="xoxb-test-token"), \
         patch("urllib.request.urlopen", mock_urlopen):
        result = slack_notifier.send_slack_message([], "fallback text")
    assert result["ok"] is True
    # Verify timeout=10 was passed (Fix 7)
    mock_urlopen.assert_called_once_with(ANY, timeout=10)


def test_send_slack_message_api_error():
    mock_urlopen = _mock_urlopen({"ok": False, "error": "channel_not_found"})
    with patch.object(slack_notifier, "get_bot_token", return_value="xoxb-test-token"), \
         patch("urllib.request.urlopen", mock_urlopen):
        with pytest.raises(RuntimeError, match="Slack API error"):
            slack_notifier.send_slack_message([], "fallback text")
