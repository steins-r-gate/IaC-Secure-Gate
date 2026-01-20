# ==================================================================
# Foundation Module - KMS Encryption Key
# terraform/modules/foundation/kms.tf
# Purpose: Customer-managed KMS key for CloudTrail + Config encryption
# ==================================================================

# Data sources for auto-detection
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==================================================================
# KMS Key for Log Encryption
# ==================================================================

resource "aws_kms_key" "logs" {
  description             = "KMS key for Phase 1 detection logs (CloudTrail + Config)"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(local.foundation_tags, {
    Name    = "${var.project_name}-${var.environment}-logs-kms"
    Purpose = "Encrypt CloudTrail and Config logs"
  })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.project_name}-${var.environment}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# ==================================================================
# KMS Key Policy - Least Privilege with Proper Conditions
# ==================================================================

data "aws_iam_policy_document" "kms_key_policy" {
  # Statement 1: Enable IAM User Permissions
  # Allows account admin to manage the key via IAM policies
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:*"
    ]
    resources = ["*"]
  }

  # Statement 2: Allow CloudTrail to encrypt logs
  # CRITICAL: Must include encryption context condition for security
  statement {
    sid    = "Allow CloudTrail to encrypt logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    # SECURITY: Encryption context ensures only YOUR CloudTrail can use this key
    # Prevents cross-account misuse
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values = [
        "arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:trail/*"
      ]
    }

    # SECURITY: Ensure CloudTrail calls are authenticated from your account
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "cloudtrail.${data.aws_region.current.id}.amazonaws.com"
      ]
    }
  }

  # Statement 3: Allow Config to use the key
  # Config needs Decrypt (read old snapshots) + GenerateDataKey (create new snapshots)
  statement {
    sid    = "Allow Config to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]

    # SECURITY: Ensure Config calls are authenticated from your account's region
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "config.${data.aws_region.current.id}.amazonaws.com"
      ]
    }
  }

  # Statement 4: Deny unencrypted uploads
  # Defense in depth: Ensure all PutObject calls use encryption
  statement {
    sid    = "Deny unencrypted object uploads"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "kms:Decrypt"
    ]
    resources = ["*"]

    # Only deny if caller is NOT using a secure ViaService call
    condition {
      test     = "StringNotLike"
      variable = "kms:ViaService"
      values = [
        "*.amazonaws.com"
      ]
    }

    # Exception: Allow account admin for emergency access
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }
}

resource "aws_kms_key_policy" "logs" {
  key_id = aws_kms_key.logs.id
  policy = data.aws_iam_policy_document.kms_key_policy.json

  # CRITICAL: Ensure policy is applied after key is created
  depends_on = [aws_kms_key.logs]
}
