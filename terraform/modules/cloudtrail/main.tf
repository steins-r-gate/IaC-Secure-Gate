# ==================================================================
# CloudTrail Module - Main Resources
# terraform/modules/cloudtrail/main.tf
# Purpose: Create CloudTrail trail for IAM activity logging
# ==================================================================

locals {
  trail_name = "${var.project_name}-${var.environment}-trail"

  # Common tags for all CloudTrail resources
  cloudtrail_tags = merge(var.common_tags, {
    Module  = "cloudtrail"
    Service = "CloudTrail"
    Phase   = "Phase-1-Detection"
  })
}

# ==================================================================
# CloudWatch Logs (Optional)
# ==================================================================

# CloudWatch log group for CloudTrail logs (optional)
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.cloudtrail_tags, {
    Name = "${local.trail_name}-logs"
  })
}

# IAM role for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${local.trail_name}-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.cloudtrail_tags, {
    Name = "${local.trail_name}-cloudwatch-role"
  })
}

# IAM policy for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name = "${local.trail_name}-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateLogStream"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

# ==================================================================
# SNS Topic for CloudTrail Notifications (Optional)
# ==================================================================

resource "aws_sns_topic" "cloudtrail_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  name              = "${local.trail_name}-notifications"
  kms_master_key_id = var.kms_key_arn

  tags = merge(local.cloudtrail_tags, {
    Name = "${local.trail_name}-notifications"
  })
}

# SNS topic policy to allow CloudTrail to publish
resource "aws_sns_topic_policy" "cloudtrail_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  arn = aws_sns_topic.cloudtrail_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cloudtrail_notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      }
    ]
  })
}

# ==================================================================
# CloudTrail Trail
# ==================================================================

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = var.cloudtrail_bucket_name
  kms_key_id     = var.kms_key_arn

  # Security settings (CIS AWS Foundations Benchmark)
  enable_log_file_validation    = var.enable_log_file_validation    # CIS 3.2
  is_multi_region_trail         = var.is_multi_region_trail         # CIS 3.1
  include_global_service_events = var.include_global_service_events # Required for IAM/STS

  # Organization trail support (optional)
  is_organization_trail = var.is_organization_trail

  # CloudWatch Logs integration (optional)
  cloud_watch_logs_group_arn = var.enable_cloudwatch_logs ? "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.enable_cloudwatch_logs ? aws_iam_role.cloudtrail_cloudwatch[0].arn : null

  # SNS notifications (optional)
  sns_topic_name = var.enable_sns_notifications ? aws_sns_topic.cloudtrail_notifications[0].name : null

  # Advanced event selectors (recommended over legacy event_selector)
  # Management events capture IAM API calls
  advanced_event_selector {
    name = "Management events selector"

    # Include all management events (read + write)
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }

    # Exclude specific read-only events to reduce cost (optional)
    dynamic "field_selector" {
      for_each = var.exclude_management_event_sources
      content {
        field      = "eventSource"
        not_equals = var.exclude_management_event_sources
      }
    }
  }

  # Data events selector (optional, default off)
  dynamic "advanced_event_selector" {
    for_each = var.enable_s3_data_events ? [1] : []
    content {
      name = "S3 data events selector"

      # S3 object-level events
      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }

      # Restrict to specific buckets if provided
      dynamic "field_selector" {
        for_each = length(var.s3_data_event_bucket_arns) > 0 ? [1] : []
        content {
          field       = "resources.ARN"
          starts_with = var.s3_data_event_bucket_arns
        }
      }
    }
  }

  # Lambda data events (optional, default off)
  dynamic "advanced_event_selector" {
    for_each = var.enable_lambda_data_events ? [1] : []
    content {
      name = "Lambda data events selector"

      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = ["AWS::Lambda::Function"]
      }
    }
  }

  # Insight selectors for anomaly detection (optional)
  dynamic "insight_selector" {
    for_each = var.enable_insights ? [1] : []
    content {
      insight_type = "ApiCallRateInsight"
    }
  }

  dynamic "insight_selector" {
    for_each = var.enable_insights && var.enable_error_rate_insights ? [1] : []
    content {
      insight_type = "ApiErrorRateInsight"
    }
  }

  tags = merge(local.cloudtrail_tags, {
    Name = local.trail_name
  })

  # CRITICAL: Ensure foundation resources are ready
  # The bucket policy must allow CloudTrail writes, and KMS key must allow CloudTrail encryption
  # We depend on the bucket name and KMS ARN being ready (module outputs are available when resources exist)
  # No explicit depends_on needed here - Terraform handles module output dependencies automatically
  # If you need explicit dependency passing from root module, use a lifecycle hook or depends_on at root level
}
