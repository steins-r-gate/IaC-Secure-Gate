# ==================================================================
# AWS Config Module - IAM Resources
# terraform/modules/config/iam.tf
# Purpose: Least-privilege IAM role and policies for AWS Config
#          Supports service-linked role (CIS Config.1) or custom role
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==================================================================
# Role ARN Resolution
# ==================================================================

locals {
  # When using SLR, reference the well-known AWS service-linked role ARN
  # When using custom role, reference the role we create below
  config_role_arn = var.use_service_linked_role ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" : aws_iam_role.config[0].arn
}

# ==================================================================
# IAM Role for AWS Config (skipped when using SLR)
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
  count = var.use_service_linked_role ? 0 : 1

  name               = "${local.config_name}-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
  description        = "Service role for AWS Config recorder in ${var.environment} environment"

  tags = merge(local.config_tags, {
    Name = "${local.config_name}-role"
  })
}

# ==================================================================
# AWS Managed Policy - Read-only access to resources (skipped when using SLR)
# ==================================================================

resource "aws_iam_role_policy_attachment" "config" {
  count = var.use_service_linked_role ? 0 : 1

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ==================================================================
# S3 Bucket Policy - Least-privilege write access (skipped when using SLR)
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
  count = var.use_service_linked_role ? 0 : 1

  name   = "${local.config_name}-s3-policy"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_s3.json
}

# ==================================================================
# KMS Key Policy - Decrypt and generate data keys for SSE-KMS (skipped when using SLR)
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
  count = var.use_service_linked_role ? 0 : 1

  name   = "${local.config_name}-kms-policy"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_kms.json
}
