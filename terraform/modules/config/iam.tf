# ==================================================================
# AWS Config Module - IAM Resources
# terraform/modules/config/iam.tf
# Purpose: Least-privilege IAM role and policies for AWS Config
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==================================================================
# IAM Role for AWS Config
# ==================================================================

data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "config" {
  name               = "${local.config_name}-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
  description        = "Service role for AWS Config recorder in ${var.environment} environment"

  tags = merge(local.config_tags, {
    Name = "${local.config_name}-role"
  })
}

# ==================================================================
# AWS Managed Policy - Read-only access to resources
# ==================================================================

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ==================================================================
# S3 Bucket Policy - Least-privilege write access
# ==================================================================

data "aws_iam_policy_document" "config_s3" {
  # Bucket-level permissions
  statement {
    sid    = "ConfigBucketPermissions"
    effect = "Allow"
    actions = [
      "s3:GetBucketVersioning",
      "s3:ListBucket"
    ]
    resources = [var.config_bucket_arn]
  }

  # Object-level permissions with prefix constraint
  statement {
    sid    = "ConfigObjectPermissions"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${var.config_bucket_arn}/${var.s3_key_prefix}/*"
    ]

    # Ensure Config writes with bucket-owner-full-control ACL
    # This prevents permission issues when bucket has BucketOwnerEnforced ownership
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_iam_role_policy" "config_s3" {
  name   = "${local.config_name}-s3-policy"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_s3.json
}

# ==================================================================
# KMS Key Policy - Decrypt and generate data keys for SSE-KMS
# ==================================================================

data "aws_iam_policy_document" "config_kms" {
  statement {
    sid    = "ConfigKMSPermissions"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [var.config_bucket_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "config_kms" {
  name   = "${local.config_name}-kms-policy"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_kms.json
}
