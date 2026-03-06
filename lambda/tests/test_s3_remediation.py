"""Unit tests for lambda/src/s3_remediation.py"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

# s3_remediation uses lazy boto3 init — safe to import directly.
import s3_remediation


# ── validate_bucket_name ──────────────────────────────────────────────

def test_validate_bucket_name_valid():
    assert s3_remediation.validate_bucket_name("my-test-bucket") is True
    assert s3_remediation.validate_bucket_name("bucket123") is True


def test_validate_bucket_name_invalid_ip():
    assert s3_remediation.validate_bucket_name("192.168.1.1") is False


def test_validate_bucket_name_too_short():
    assert s3_remediation.validate_bucket_name("ab") is False


# ── is_protected_bucket ───────────────────────────────────────────────

def test_is_protected_bucket_protected_tag():
    mock_s3 = MagicMock()
    mock_s3.get_bucket_tagging.return_value = {
        "TagSet": [{"Key": "ProtectedBucket", "Value": "true"}]
    }
    with patch("s3_remediation.get_s3_client", return_value=mock_s3):
        assert s3_remediation.is_protected_bucket("my-bucket") is True


def test_is_protected_bucket_purpose_tag_cloudtrail():
    mock_s3 = MagicMock()
    mock_s3.get_bucket_tagging.return_value = {
        "TagSet": [{"Key": "Purpose", "Value": "cloudtrail-logs"}]
    }
    with patch("s3_remediation.get_s3_client", return_value=mock_s3):
        assert s3_remediation.is_protected_bucket("ct-logs-bucket") is True


def test_is_protected_bucket_no_tags():
    mock_s3 = MagicMock()
    error = ClientError(
        {"Error": {"Code": "NoSuchTagSet", "Message": "No tag set"}},
        "GetBucketTagging",
    )
    mock_s3.get_bucket_tagging.side_effect = error
    with patch("s3_remediation.get_s3_client", return_value=mock_s3):
        assert s3_remediation.is_protected_bucket("my-bucket") is False


def test_is_protected_bucket_unexpected_error_fails_closed():
    """Fix 3: unexpected ClientError → treat as protected (fail-closed)."""
    mock_s3 = MagicMock()
    error = ClientError(
        {"Error": {"Code": "AccessDenied", "Message": "Access denied"}},
        "GetBucketTagging",
    )
    mock_s3.get_bucket_tagging.side_effect = error
    with patch("s3_remediation.get_s3_client", return_value=mock_s3):
        assert s3_remediation.is_protected_bucket("my-bucket") is True


def test_is_protected_bucket_unprotected():
    mock_s3 = MagicMock()
    mock_s3.get_bucket_tagging.return_value = {
        "TagSet": [{"Key": "Environment", "Value": "dev"}]
    }
    with patch("s3_remediation.get_s3_client", return_value=mock_s3):
        assert s3_remediation.is_protected_bucket("my-bucket") is False


# ── Remediation actions ───────────────────────────────────────────────

def test_block_public_access_applied():
    mock_s3 = MagicMock()
    with patch("s3_remediation.get_s3_client", return_value=mock_s3), \
         patch.object(s3_remediation, "DRY_RUN_MODE", False):
        result = s3_remediation.block_public_access("my-bucket")
    assert result["status"] == "applied"
    mock_s3.put_public_access_block.assert_called_once()
    call_kwargs = mock_s3.put_public_access_block.call_args[1]
    config = call_kwargs["PublicAccessBlockConfiguration"]
    assert config["BlockPublicAcls"] is True
    assert config["BlockPublicPolicy"] is True


def test_enable_encryption_applied():
    mock_s3 = MagicMock()
    with patch("s3_remediation.get_s3_client", return_value=mock_s3), \
         patch.object(s3_remediation, "DRY_RUN_MODE", False):
        result = s3_remediation.enable_encryption("my-bucket")
    assert result["status"] == "applied"
    mock_s3.put_bucket_encryption.assert_called_once()
    call_kwargs = mock_s3.put_bucket_encryption.call_args[1]
    rule = call_kwargs["ServerSideEncryptionConfiguration"]["Rules"][0]
    assert rule["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"] == "AES256"


def test_enable_versioning_applied():
    mock_s3 = MagicMock()
    with patch("s3_remediation.get_s3_client", return_value=mock_s3), \
         patch.object(s3_remediation, "DRY_RUN_MODE", False):
        result = s3_remediation.enable_versioning("my-bucket")
    assert result["status"] == "applied"
    mock_s3.put_bucket_versioning.assert_called_once_with(
        Bucket="my-bucket",
        VersioningConfiguration={"Status": "Enabled"},
    )


def test_remediate_bucket_dry_run():
    mock_s3 = MagicMock()
    with patch("s3_remediation.get_s3_client", return_value=mock_s3), \
         patch.object(s3_remediation, "DRY_RUN_MODE", True):
        actions = s3_remediation.remediate_bucket("my-bucket")
    assert all(a["status"] == "dry_run" for a in actions)
    mock_s3.put_public_access_block.assert_not_called()
    mock_s3.put_bucket_encryption.assert_not_called()
    mock_s3.put_bucket_versioning.assert_not_called()


# ── lambda_handler ────────────────────────────────────────────────────

def _make_s3_event(
    finding_id="arn:aws:securityhub:us-east-1:123456789012:finding/test123",
    bucket_name="my-test-bucket",
):
    return {
        "detail": {
            "findings": [
                {
                    "Id": finding_id,
                    "Resources": [
                        {
                            "Type": "AwsS3Bucket",
                            "Id": f"arn:aws:s3:::{bucket_name}",
                        }
                    ],
                }
            ]
        }
    }


def test_lambda_handler_protected_bucket_skipped():
    event = _make_s3_event()
    with patch("s3_remediation.is_protected_bucket", return_value=True), \
         patch("s3_remediation.get_s3_client", return_value=MagicMock()):
        result = s3_remediation.lambda_handler(event, None)
    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "SKIPPED"
    assert body["reason"] == "protected_bucket"


def test_lambda_handler_remediated():
    event = _make_s3_event()
    mock_s3 = MagicMock()
    # No tags → not protected
    mock_s3.get_bucket_tagging.side_effect = ClientError(
        {"Error": {"Code": "NoSuchTagSet", "Message": ""}}, "GetBucketTagging"
    )
    # Config capture returns sensible defaults
    mock_s3.get_public_access_block.side_effect = ClientError(
        {"Error": {"Code": "NoSuchPublicAccessBlockConfiguration", "Message": ""}},
        "GetPublicAccessBlock",
    )
    mock_s3.get_bucket_encryption.side_effect = ClientError(
        {"Error": {"Code": "ServerSideEncryptionConfigurationNotFoundError", "Message": ""}},
        "GetBucketEncryption",
    )
    mock_s3.get_bucket_versioning.return_value = {"Status": "Disabled"}
    mock_s3.get_bucket_acl.return_value = {"Grants": []}

    with patch("s3_remediation.get_s3_client", return_value=mock_s3), \
         patch.object(s3_remediation, "DRY_RUN_MODE", False), \
         patch("s3_remediation.log_remediation_to_dynamodb"), \
         patch("s3_remediation.send_notification"):
        result = s3_remediation.lambda_handler(event, None)

    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "REMEDIATED"
    assert len(body["actions"]) == 3
    mock_s3.put_public_access_block.assert_called_once()
    mock_s3.put_bucket_encryption.assert_called_once()
    mock_s3.put_bucket_versioning.assert_called_once()
