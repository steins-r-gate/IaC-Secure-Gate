"""Unit tests for lambda/src/finding_triage.py"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

# finding_triage has a module-level `dynamodb = boto3.resource("dynamodb")`.
# Patch boto3.resource before importing so no real AWS call is made.
with patch("boto3.resource", return_value=MagicMock()):
    import finding_triage


# ── Helpers ───────────────────────────────────────────────────────────

def _make_event(
    severity="HIGH",
    control_id="IAM.1",
    resource_arn="arn:aws:iam::123456789012:policy/TestPolicy",
    resource_type="AwsIamPolicy",
):
    return {
        "detail": {
            "findings": [
                {
                    "Compliance": {"SecurityControlId": control_id},
                    "Severity": {"Label": severity},
                    "Title": "Test finding",
                    "Resources": [{"Id": resource_arn, "Type": resource_type}],
                }
            ]
        }
    }


# ── determine_decision ────────────────────────────────────────────────

def test_determine_decision_auto_remediate_critical():
    with patch.object(finding_triage, "AUTO_REMEDIATE_SEVERITY", "HIGH"):
        assert finding_triage.determine_decision("CRITICAL", False) == "AUTO_REMEDIATE"


def test_determine_decision_auto_remediate_high():
    with patch.object(finding_triage, "AUTO_REMEDIATE_SEVERITY", "HIGH"):
        assert finding_triage.determine_decision("HIGH", False) == "AUTO_REMEDIATE"


def test_determine_decision_request_approval_medium():
    with patch.object(finding_triage, "AUTO_REMEDIATE_SEVERITY", "HIGH"):
        assert finding_triage.determine_decision("MEDIUM", False) == "REQUEST_APPROVAL"


def test_determine_decision_false_positive_overrides_severity():
    with patch.object(finding_triage, "AUTO_REMEDIATE_SEVERITY", "HIGH"):
        assert finding_triage.determine_decision("HIGH", True) == "SKIP_FALSE_POSITIVE"


# ── parse_finding ─────────────────────────────────────────────────────

def test_parse_finding_valid_event():
    result = finding_triage.parse_finding(_make_event())
    assert result["control_id"] == "IAM.1"
    assert result["severity"] == "HIGH"
    assert result["resource_arn"] == "arn:aws:iam::123456789012:policy/TestPolicy"
    assert result["resource_type"] == "AwsIamPolicy"


def test_parse_finding_missing_findings_raises():
    with pytest.raises(ValueError, match="No findings"):
        finding_triage.parse_finding({"detail": {"findings": []}})


# ── check_false_positive_registry ────────────────────────────────────

def test_check_false_positive_registry_found():
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": [{"violation_type": "FALSE_POSITIVE"}]}
    with patch.object(finding_triage, "DYNAMODB_TABLE", "test-table"), \
         patch.object(finding_triage, "dynamodb") as mock_dynamo:
        mock_dynamo.Table.return_value = mock_table
        result = finding_triage.check_false_positive_registry("arn:aws:s3:::bucket", "S3.2")
    assert result is True


def test_check_false_positive_registry_not_found():
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": []}
    with patch.object(finding_triage, "DYNAMODB_TABLE", "test-table"), \
         patch.object(finding_triage, "dynamodb") as mock_dynamo:
        mock_dynamo.Table.return_value = mock_table
        result = finding_triage.check_false_positive_registry("arn:aws:s3:::bucket", "S3.2")
    assert result is False


def test_check_false_positive_registry_dynamo_error():
    """ClientError is caught and returns False — not fail-open (Fix 8)."""
    mock_table = MagicMock()
    error = ClientError(
        {"Error": {"Code": "ResourceNotFoundException", "Message": "Table not found"}},
        "Query",
    )
    mock_table.query.side_effect = error
    with patch.object(finding_triage, "DYNAMODB_TABLE", "test-table"), \
         patch.object(finding_triage, "dynamodb") as mock_dynamo:
        mock_dynamo.Table.return_value = mock_table
        result = finding_triage.check_false_positive_registry("arn:aws:s3:::bucket", "S3.2")
    assert result is False


def test_check_false_positive_registry_no_table():
    with patch.object(finding_triage, "DYNAMODB_TABLE", ""):
        result = finding_triage.check_false_positive_registry("arn:aws:s3:::bucket", "S3.2")
    assert result is False


# ── lambda_handler integration ────────────────────────────────────────

def test_lambda_handler_auto_remediate():
    event = _make_event(severity="HIGH")
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": []}
    with patch.object(finding_triage, "DYNAMODB_TABLE", "test-table"), \
         patch.object(finding_triage, "AUTO_REMEDIATE_SEVERITY", "HIGH"), \
         patch.object(finding_triage, "dynamodb") as mock_dynamo:
        mock_dynamo.Table.return_value = mock_table
        result = finding_triage.lambda_handler(event, None)
    assert result["decision"] == "AUTO_REMEDIATE"
    assert result["severity"] == "HIGH"
    assert result["control_id"] == "IAM.1"


def test_lambda_handler_skip_false_positive():
    event = _make_event(severity="HIGH")
    mock_table = MagicMock()
    mock_table.query.return_value = {"Items": [{"violation_type": "FALSE_POSITIVE"}]}
    with patch.object(finding_triage, "DYNAMODB_TABLE", "test-table"), \
         patch.object(finding_triage, "dynamodb") as mock_dynamo:
        mock_dynamo.Table.return_value = mock_table
        result = finding_triage.lambda_handler(event, None)
    assert result["decision"] == "SKIP_FALSE_POSITIVE"


def test_lambda_handler_missing_findings_raises():
    with pytest.raises(ValueError, match="No findings"):
        finding_triage.lambda_handler({"detail": {"findings": []}}, None)
