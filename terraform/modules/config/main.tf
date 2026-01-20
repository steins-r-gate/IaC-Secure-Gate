# ==================================================================
# AWS Config Module - Main Resources
# terraform/modules/config/main.tf
# Purpose: Enable AWS Config for continuous compliance monitoring
# ==================================================================

locals {
  config_name = "${var.project_name}-${var.environment}-config"

  # Determine whether to include global resource types
  # If explicitly set via variable, use that; otherwise use is_primary_region
  include_global_resources = coalesce(var.include_global_resource_types, var.is_primary_region)

  # Common tags for all Config resources
  config_tags = merge(var.common_tags, {
    Module  = "config"
    Service = "AWS-Config"
  })

  # SNS topic for delivery channel (if enabled)
  sns_topic_arn = var.enable_sns_notifications ? aws_sns_topic.config[0].arn : var.sns_topic_arn
}

# ==================================================================
# AWS Config Recorder
# ==================================================================

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.config_name}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
    # Only record global resources (IAM, etc.) in primary region to avoid duplication
    include_global_resource_types = local.include_global_resources
  }

  # Ensure IAM role and all policies are attached before creating recorder
  depends_on = [
    aws_iam_role_policy_attachment.config,
    aws_iam_role_policy.config_s3,
    aws_iam_role_policy.config_kms
  ]
}

# ==================================================================
# Config Delivery Channel
# ==================================================================

resource "aws_config_delivery_channel" "main" {
  name           = "${local.config_name}-delivery"
  s3_bucket_name = var.config_bucket_name
  s3_key_prefix  = var.s3_key_prefix
  sns_topic_arn  = local.sns_topic_arn

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  # CRITICAL: Delivery channel does NOT depend on recorder
  # The recorder resource must exist, but should not be in depends_on
  # AWS requires delivery channel to exist BEFORE starting the recorder
  depends_on = [aws_config_configuration_recorder.main]
}

# ==================================================================
# Start Config Recorder
# ==================================================================

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  # CRITICAL: Recorder can only start after:
  # 1. Delivery channel is created
  # 2. IAM role has all permissions attached
  # 3. S3 bucket is configured (handled by foundation module)
  depends_on = [
    aws_config_delivery_channel.main,
    aws_iam_role_policy_attachment.config,
    aws_iam_role_policy.config_s3,
    aws_iam_role_policy.config_kms
  ]
}

# ==================================================================
# Optional: SNS Topic for Config Notifications
# ==================================================================

resource "aws_sns_topic" "config" {
  count = var.enable_sns_notifications ? 1 : 0

  name              = "${local.config_name}-notifications"
  display_name      = "AWS Config notifications for ${var.environment}"
  kms_master_key_id = var.config_bucket_kms_key_arn

  tags = merge(local.config_tags, {
    Name = "${local.config_name}-notifications"
  })
}

resource "aws_sns_topic_policy" "config" {
  count = var.enable_sns_notifications ? 1 : 0

  arn    = aws_sns_topic.config[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy[0].json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = var.enable_sns_notifications ? 1 : 0

  statement {
    sid    = "ConfigPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [aws_sns_topic.config[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
