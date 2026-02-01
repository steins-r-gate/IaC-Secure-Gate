# ==================================================================
# Self-Improvement Module - SNS Topics
# terraform/modules/self-improvement/sns-topics.tf
#
# Purpose: Notification infrastructure for remediation events
# Topics:
#   - Remediation Alerts: Immediate notifications for each remediation
#   - Analytics Reports: Daily summary reports
#   - Manual Review: Failed remediations requiring human intervention
# ==================================================================

# ----------------------------------------------------------------------
# Data Sources
# ----------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------------------
# SNS Topic: Remediation Alerts (Immediate Notifications)
# ----------------------------------------------------------------------

resource "aws_sns_topic" "remediation_alerts" {
  count = var.enable_remediation_alerts ? 1 : 0

  name         = local.remediation_alerts_topic_name
  display_name = "IaC Secure Gate - Remediation Alerts"

  # Encryption at rest (AWS managed key if kms_key_arn is null)
  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

  tags = merge(local.module_tags, {
    Name        = local.remediation_alerts_topic_name
    Description = "Immediate alerts for security remediation events"
    AlertType   = "Immediate"
  })
}

# Topic policy for remediation alerts
resource "aws_sns_topic_policy" "remediation_alerts" {
  count = var.enable_remediation_alerts ? 1 : 0

  arn = aws_sns_topic.remediation_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "RemediationAlertsPolicy"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.remediation_alerts[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowAccountManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.remediation_alerts[0].arn
      }
    ]
  })
}

# Email subscriptions for remediation alerts
resource "aws_sns_topic_subscription" "remediation_alerts_email" {
  count = var.enable_remediation_alerts ? length(var.alert_email_subscriptions) : 0

  topic_arn = aws_sns_topic.remediation_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email_subscriptions[count.index]
}

# ----------------------------------------------------------------------
# SNS Topic: Analytics Reports (Daily Summaries)
# ----------------------------------------------------------------------

resource "aws_sns_topic" "analytics_reports" {
  count = var.enable_analytics_reports ? 1 : 0

  name         = local.analytics_reports_topic_name
  display_name = "IaC Secure Gate - Analytics Reports"

  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

  tags = merge(local.module_tags, {
    Name        = local.analytics_reports_topic_name
    Description = "Daily analytics and summary reports"
    AlertType   = "Scheduled"
  })
}

# Topic policy for analytics reports
resource "aws_sns_topic_policy" "analytics_reports" {
  count = var.enable_analytics_reports ? 1 : 0

  arn = aws_sns_topic.analytics_reports[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AnalyticsReportsPolicy"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.analytics_reports[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowAccountManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.analytics_reports[0].arn
      }
    ]
  })
}

# Email subscriptions for analytics reports
resource "aws_sns_topic_subscription" "analytics_reports_email" {
  count = var.enable_analytics_reports ? length(var.alert_email_subscriptions) : 0

  topic_arn = aws_sns_topic.analytics_reports[0].arn
  protocol  = "email"
  endpoint  = var.alert_email_subscriptions[count.index]
}

# ----------------------------------------------------------------------
# SNS Topic: Manual Review (Failed Remediations)
# ----------------------------------------------------------------------

resource "aws_sns_topic" "manual_review" {
  count = var.enable_manual_review_alerts ? 1 : 0

  name         = local.manual_review_topic_name
  display_name = "IaC Secure Gate - Manual Review Required"

  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

  tags = merge(local.module_tags, {
    Name        = local.manual_review_topic_name
    Description = "Alerts for failed remediations requiring manual intervention"
    AlertType   = "Critical"
    Priority    = "High"
  })
}

# Topic policy for manual review
resource "aws_sns_topic_policy" "manual_review" {
  count = var.enable_manual_review_alerts ? 1 : 0

  arn = aws_sns_topic.manual_review[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ManualReviewPolicy"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.manual_review[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowAccountManagement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish"
        ]
        Resource = aws_sns_topic.manual_review[0].arn
      }
    ]
  })
}

# Email subscriptions for manual review
resource "aws_sns_topic_subscription" "manual_review_email" {
  count = var.enable_manual_review_alerts ? length(var.alert_email_subscriptions) : 0

  topic_arn = aws_sns_topic.manual_review[0].arn
  protocol  = "email"
  endpoint  = var.alert_email_subscriptions[count.index]
}
