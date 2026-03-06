"""Unit tests for lambda/src/sg_remediation.py"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

# sg_remediation uses lazy boto3 init — safe to import directly.
import sg_remediation


# ── validate_security_group_id ────────────────────────────────────────

def test_validate_security_group_id_valid():
    assert sg_remediation.validate_security_group_id("sg-12345678") is True
    assert sg_remediation.validate_security_group_id("sg-0a1b2c3d4e5f67890") is True


def test_validate_sg_id_invalid():
    assert sg_remediation.validate_security_group_id("i-12345678") is False
    assert sg_remediation.validate_security_group_id("") is False
    assert sg_remediation.validate_security_group_id(None) is False


# ── is_overly_permissive_rule ─────────────────────────────────────────

def _tcp_rule(from_port, to_port, cidr="0.0.0.0/0"):
    return {
        "IpProtocol": "tcp",
        "FromPort": from_port,
        "ToPort": to_port,
        "IpRanges": [{"CidrIp": cidr}] if cidr else [],
        "Ipv6Ranges": [],
    }


def test_is_overly_permissive_rule_all_traffic():
    rule = {
        "IpProtocol": "-1",
        "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
        "Ipv6Ranges": [],
    }
    assert sg_remediation.is_overly_permissive_rule(rule, allow_web_traffic=False) is True


def test_is_overly_permissive_rule_ssh_public():
    assert sg_remediation.is_overly_permissive_rule(_tcp_rule(22, 22), allow_web_traffic=False) is True


def test_is_overly_permissive_rule_https_with_web_tag():
    rule = _tcp_rule(443, 443)
    assert sg_remediation.is_overly_permissive_rule(rule, allow_web_traffic=True) is False


def test_is_overly_permissive_rule_private_cidr():
    rule = _tcp_rule(22, 22, cidr="10.0.0.0/8")
    assert sg_remediation.is_overly_permissive_rule(rule, allow_web_traffic=False) is False


def test_is_overly_permissive_rule_wide_range():
    # Port range 0-1024 has width 1024 > 100
    rule = _tcp_rule(0, 1024)
    assert sg_remediation.is_overly_permissive_rule(rule, allow_web_traffic=False) is True


# ── allows_public_web_traffic ─────────────────────────────────────────

def test_allows_public_web_traffic_tagged():
    sg = {"Tags": [{"Key": "AllowPublicWeb", "Value": "true"}]}
    assert sg_remediation.allows_public_web_traffic(sg) is True


def test_allows_public_web_traffic_untagged():
    sg = {"Tags": [{"Key": "Environment", "Value": "prod"}]}
    assert sg_remediation.allows_public_web_traffic(sg) is False


# ── is_protected_security_group ───────────────────────────────────────

def test_is_protected_sg_default_name():
    sg = {"GroupName": "default", "Tags": []}
    is_protected, reason = sg_remediation.is_protected_security_group(sg)
    assert is_protected is True
    assert reason == "default_security_group"


def test_is_protected_sg_protected_tag():
    sg = {
        "GroupName": "my-sg",
        "Tags": [{"Key": "ProtectedSecurityGroup", "Value": "true"}],
    }
    is_protected, reason = sg_remediation.is_protected_security_group(sg)
    assert is_protected is True
    assert reason == "protected_tag"


def test_is_protected_sg_unprotected():
    sg = {"GroupName": "web-server", "Tags": []}
    is_protected, reason = sg_remediation.is_protected_security_group(sg)
    assert is_protected is False
    assert reason == ""


# ── find_rules_to_remove ──────────────────────────────────────────────

def test_find_rules_to_remove():
    sg = {
        "GroupName": "web-server",
        "Tags": [],
        "IpPermissions": [
            _tcp_rule(22, 22),               # dangerous — SSH, public, in dangerous_ports
            _tcp_rule(443, 443),             # safe — 443 not in dangerous_ports, range not wide
            _tcp_rule(80, 80, cidr="10.0.0.0/8"),  # safe — private CIDR, no public source
            _tcp_rule(3306, 3306),           # dangerous — MySQL in dangerous_ports
        ],
    }
    rules = sg_remediation.find_rules_to_remove(sg)
    # Only SSH (22) and MySQL (3306) are flagged — 443 is not in dangerous_ports
    assert len(rules) == 2
    ports = {r["FromPort"] for r in rules}
    assert 22 in ports
    assert 3306 in ports


# ── remove_ingress_rules ──────────────────────────────────────────────

def test_remove_ingress_rules_success():
    rules = [_tcp_rule(22, 22)]
    mock_ec2 = MagicMock()
    with patch("sg_remediation.get_ec2_client", return_value=mock_ec2), \
         patch.object(sg_remediation, "DRY_RUN_MODE", False):
        result = sg_remediation.remove_ingress_rules("sg-12345678", rules)
    assert result["status"] == "applied"
    assert result["count"] == 1
    mock_ec2.revoke_security_group_ingress.assert_called_once_with(
        GroupId="sg-12345678", IpPermissions=rules
    )


def test_remove_ingress_rules_empty():
    mock_ec2 = MagicMock()
    with patch("sg_remediation.get_ec2_client", return_value=mock_ec2):
        result = sg_remediation.remove_ingress_rules("sg-12345678", [])
    assert result["status"] == "no_action"
    assert result["count"] == 0
    mock_ec2.revoke_security_group_ingress.assert_not_called()


# ── lambda_handler ────────────────────────────────────────────────────

def _make_sg_event(sg_id="sg-12345678"):
    return {
        "detail": {
            "findings": [
                {
                    "Id": "arn:aws:securityhub:us-east-1:123456789012:finding/test123",
                    "Resources": [
                        {
                            "Type": "AwsEc2SecurityGroup",
                            "Id": f"arn:aws:ec2:us-east-1:123456789012:security-group/{sg_id}",
                        }
                    ],
                }
            ]
        }
    }


def test_lambda_handler_protected_sg_skipped():
    event = _make_sg_event()
    mock_ec2 = MagicMock()
    mock_ec2.describe_security_groups.return_value = {
        "SecurityGroups": [
            {"GroupId": "sg-12345678", "GroupName": "default", "Tags": [], "IpPermissions": []}
        ]
    }
    with patch("sg_remediation.get_ec2_client", return_value=mock_ec2), \
         patch("sg_remediation.log_remediation_to_dynamodb"), \
         patch("sg_remediation.send_notification"):
        result = sg_remediation.lambda_handler(event, None)
    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "SKIPPED"
    assert body["reason"] == "default_security_group"


def test_lambda_handler_remediated():
    event = _make_sg_event()
    mock_ec2 = MagicMock()
    mock_ec2.describe_security_groups.return_value = {
        "SecurityGroups": [
            {
                "GroupId": "sg-12345678",
                "GroupName": "web-server",
                "Tags": [],
                "IpPermissions": [_tcp_rule(22, 22)],
            }
        ]
    }
    with patch("sg_remediation.get_ec2_client", return_value=mock_ec2), \
         patch.object(sg_remediation, "DRY_RUN_MODE", False), \
         patch("sg_remediation.log_remediation_to_dynamodb"), \
         patch("sg_remediation.send_notification"):
        result = sg_remediation.lambda_handler(event, None)
    body = json.loads(result["body"])
    assert result["statusCode"] == 200
    assert body["status"] == "REMEDIATED"
    assert body["rules_removed"] == 1
    mock_ec2.revoke_security_group_ingress.assert_called_once()
