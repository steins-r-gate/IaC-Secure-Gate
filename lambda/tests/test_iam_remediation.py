"""Unit tests for lambda/src/iam_remediation.py"""

import json
import sys
import os
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch, call

# iam_remediation uses lazy boto3 init — safe to import directly.
import iam_remediation


# ── validate_arn ──────────────────────────────────────────────────────

def test_validate_arn_valid():
    assert iam_remediation.validate_arn("arn:aws:iam::123456789012:policy/MyPolicy") is True


def test_validate_arn_invalid():
    assert iam_remediation.validate_arn("not-an-arn") is False
    assert iam_remediation.validate_arn("") is False
    assert iam_remediation.validate_arn(None) is False


# ── is_dangerous_wildcard_action ──────────────────────────────────────

def test_is_dangerous_wildcard_action_star():
    stmt = {"Effect": "Allow", "Action": "*", "Resource": "*"}
    assert iam_remediation.is_dangerous_wildcard_action(stmt) is True


def test_is_dangerous_wildcard_action_iam_star():
    stmt = {"Effect": "Allow", "Action": "iam:*", "Resource": "*"}
    assert iam_remediation.is_dangerous_wildcard_action(stmt) is True


def test_is_dangerous_wildcard_action_safe():
    stmt = {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"}
    assert iam_remediation.is_dangerous_wildcard_action(stmt) is False


def test_is_dangerous_wildcard_action_deny():
    stmt = {"Effect": "Deny", "Action": "*", "Resource": "*"}
    assert iam_remediation.is_dangerous_wildcard_action(stmt) is False


# ── remediate_policy_document ─────────────────────────────────────────

def test_remediate_policy_document_removes_wildcard():
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "*", "Resource": "*"},
            {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"},
        ],
    }
    remediated, removed = iam_remediation.remediate_policy_document(policy)
    assert len(removed) == 1
    assert removed[0]["Action"] == "*"
    assert len(remediated["Statement"]) == 1
    assert remediated["Statement"][0]["Action"] == "s3:GetObject"


def test_remediate_policy_document_preserves_condition():
    """Fix 2: wildcard statement with Condition block is preserved, not removed."""
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "*",
                "Resource": "*",
                "Condition": {"StringEquals": {"aws:SourceVpc": "vpc-abc123"}},
            },
            {"Effect": "Allow", "Action": "ec2:DescribeInstances", "Resource": "*"},
        ],
    }
    remediated, removed = iam_remediation.remediate_policy_document(policy)
    assert removed == []
    assert len(remediated["Statement"]) == 2


def test_remediate_policy_document_all_removed_raises():
    """Fix 1: refuse to produce a zero-statement policy."""
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "*", "Resource": "*"},
        ],
    }
    with pytest.raises(ValueError, match="empty"):
        iam_remediation.remediate_policy_document(policy)


def test_remediate_policy_document_no_dangerous_returns_empty_removed():
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "ec2:DescribeInstances", "Resource": "*"},
        ],
    }
    remediated, removed = iam_remediation.remediate_policy_document(policy)
    assert removed == []
    assert len(remediated["Statement"]) == 1


# ── get_policy_document ───────────────────────────────────────────────

def test_get_policy_document_success():
    policy_arn = "arn:aws:iam::123456789012:policy/TestPolicy"
    doc = {"Version": "2012-10-17", "Statement": []}

    mock_iam = MagicMock()
    mock_iam.get_policy.return_value = {"Policy": {"DefaultVersionId": "v3"}}
    mock_iam.get_policy_version.return_value = {"PolicyVersion": {"Document": doc}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam):
        result_doc, version_id = iam_remediation.get_policy_document(policy_arn)

    assert version_id == "v3"
    assert result_doc == doc
    mock_iam.get_policy_version.assert_called_once_with(
        PolicyArn=policy_arn, VersionId="v3"
    )


# ── create_policy_version ─────────────────────────────────────────────

def test_create_policy_version_under_limit():
    policy_arn = "arn:aws:iam::123456789012:policy/TestPolicy"
    policy_doc = {"Version": "2012-10-17", "Statement": []}

    mock_iam = MagicMock()
    mock_iam.list_policy_versions.return_value = {
        "Versions": [
            {"VersionId": "v1", "IsDefaultVersion": True, "CreateDate": datetime(2024, 1, 1, tzinfo=timezone.utc)}
        ]
    }
    mock_iam.create_policy_version.return_value = {"PolicyVersion": {"VersionId": "v2"}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam):
        result = iam_remediation.create_policy_version(policy_arn, policy_doc)

    mock_iam.delete_policy_version.assert_not_called()
    assert result == "v2"


def test_create_policy_version_at_limit_deletes_oldest():
    policy_arn = "arn:aws:iam::123456789012:policy/TestPolicy"
    policy_doc = {"Version": "2012-10-17", "Statement": []}

    versions = [
        {
            "VersionId": f"v{i}",
            "IsDefaultVersion": i == 5,
            "CreateDate": datetime(2024, 1, i, tzinfo=timezone.utc),
        }
        for i in range(1, 6)
    ]
    mock_iam = MagicMock()
    mock_iam.list_policy_versions.return_value = {"Versions": versions}
    mock_iam.create_policy_version.return_value = {"PolicyVersion": {"VersionId": "v6"}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam):
        result = iam_remediation.create_policy_version(policy_arn, policy_doc)

    # Oldest non-default version is v1
    mock_iam.delete_policy_version.assert_called_once_with(
        PolicyArn=policy_arn, VersionId="v1"
    )
    assert result == "v6"


# ── lambda_handler ────────────────────────────────────────────────────

def _make_iam_event(
    finding_id="arn:aws:securityhub:us-east-1:123456789012:finding/test123",
    policy_arn="arn:aws:iam::123456789012:policy/DangerousPolicy",
):
    return {
        "detail": {
            "findings": [
                {
                    "Id": finding_id,
                    "Resources": [
                        {"Type": "AwsIamPolicy", "Id": policy_arn}
                    ],
                }
            ]
        }
    }


def test_lambda_handler_success():
    event = _make_iam_event()
    original_doc = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "*", "Resource": "*"},
            {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"},
        ],
    }
    mock_iam = MagicMock()
    mock_iam.get_policy.return_value = {"Policy": {"DefaultVersionId": "v1"}}
    mock_iam.get_policy_version.return_value = {"PolicyVersion": {"Document": original_doc}}
    mock_iam.list_policy_versions.return_value = {
        "Versions": [{"VersionId": "v1", "IsDefaultVersion": True, "CreateDate": datetime(2024, 1, 1, tzinfo=timezone.utc)}]
    }
    mock_iam.create_policy_version.return_value = {"PolicyVersion": {"VersionId": "v2"}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam), \
         patch("iam_remediation.DRY_RUN_MODE", False), \
         patch("iam_remediation.log_remediation_to_dynamodb"), \
         patch("iam_remediation.send_notification"):
        result = iam_remediation.lambda_handler(event, None)

    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "REMEDIATED"
    assert body["statements_removed"] == 1
    assert body["dry_run"] is False


def test_lambda_handler_no_action_needed():
    event = _make_iam_event()
    clean_doc = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "s3:ListBucket", "Resource": "*"},
        ],
    }
    mock_iam = MagicMock()
    mock_iam.get_policy.return_value = {"Policy": {"DefaultVersionId": "v1"}}
    mock_iam.get_policy_version.return_value = {"PolicyVersion": {"Document": clean_doc}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam), \
         patch("iam_remediation.log_remediation_to_dynamodb"), \
         patch("iam_remediation.send_notification"):
        result = iam_remediation.lambda_handler(event, None)

    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "NO_ACTION_NEEDED"
    mock_iam.create_policy_version.assert_not_called()


def test_lambda_handler_dry_run():
    event = _make_iam_event()
    original_doc = {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": "*", "Resource": "*"},
            {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"},
        ],
    }
    mock_iam = MagicMock()
    mock_iam.get_policy.return_value = {"Policy": {"DefaultVersionId": "v1"}}
    mock_iam.get_policy_version.return_value = {"PolicyVersion": {"Document": original_doc}}

    with patch("iam_remediation.get_iam_client", return_value=mock_iam), \
         patch("iam_remediation.DRY_RUN_MODE", True), \
         patch("iam_remediation.log_remediation_to_dynamodb"), \
         patch("iam_remediation.send_notification"):
        result = iam_remediation.lambda_handler(event, None)

    body = json.loads(result["body"])
    assert body["status"] == "REMEDIATED"
    assert body["dry_run"] is True
    assert body["new_version_id"] == "DRY_RUN"
    mock_iam.create_policy_version.assert_not_called()
