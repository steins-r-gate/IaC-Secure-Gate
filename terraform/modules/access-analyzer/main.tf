# ==================================================================
# IAM Access Analyzer Module - Main Configuration
# terraform/modules/access-analyzer/main.tf
# ==================================================================

# ==================================================================
# Local Variables
# ==================================================================

locals {
  analyzer_name = "${var.project_name}-${var.environment}-analyzer"

  analyzer_tags = merge(var.common_tags, {
    Module  = "access-analyzer"
    Service = "IAM-Access-Analyzer"
    Phase   = "Phase-1-Detection"
  })
}

# ==================================================================
# IAM Access Analyzer
# ==================================================================

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = local.analyzer_name
  type          = var.analyzer_type

  tags = merge(local.analyzer_tags, {
    Name = local.analyzer_name
  })
}

# ==================================================================
# Archive Rule (Optional) - DISABLED
# ==================================================================
# AWS Access Analyzer doesn't support filtering by "status" criteria
# Archive rules can only filter by:
# - isPublic
# - resourceType
# - principalType
# - principalOrgID
#
# Users should manually archive resolved findings in AWS Console
# Or create resource-specific archive rules if needed
# ==================================================================

# resource "aws_accessanalyzer_archive_rule" "auto_archive_resolved" {
#   count = var.enable_archive_rule ? 1 : 0
#
#   analyzer_name = aws_accessanalyzer_analyzer.account.analyzer_name
#   rule_name     = "${local.analyzer_name}-auto-archive-resolved"
#
#   # Archive resolved findings (status = RESOLVED)
#   filter {
#     criteria = "status"
#     eq       = ["RESOLVED"]
#   }
# }

# ==================================================================
# Optional: EventBridge Rule for New Findings → SNS
# ==================================================================

resource "aws_cloudwatch_event_rule" "analyzer_findings" {
  count = var.enable_sns_notifications ? 1 : 0

  name        = "${local.analyzer_name}-findings"
  description = "Route Access Analyzer findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.access-analyzer"]
    detail-type = ["Access Analyzer Finding"]
    detail = {
      status = ["ACTIVE"] # Only new/active findings
    }
  })

  tags = merge(local.analyzer_tags, {
    Name = "${local.analyzer_name}-findings-rule"
  })
}

resource "aws_cloudwatch_event_target" "analyzer_sns" {
  count = var.enable_sns_notifications ? 1 : 0

  rule      = aws_cloudwatch_event_rule.analyzer_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.analyzer_notifications[0].arn
}

# ==================================================================
# SNS Topic for Findings Notifications
# ==================================================================

resource "aws_sns_topic" "analyzer_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  name              = "${local.analyzer_name}-notifications"
  display_name      = "IAM Access Analyzer Findings"
  kms_master_key_id = var.kms_key_arn

  tags = merge(local.analyzer_tags, {
    Name = "${local.analyzer_name}-notifications"
  })
}

resource "aws_sns_topic_policy" "analyzer_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  arn = aws_sns_topic.analyzer_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.analyzer_notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscriptions (optional)
resource "aws_sns_topic_subscription" "analyzer_email" {
  for_each = var.enable_sns_notifications ? toset(var.sns_email_subscriptions) : []

  topic_arn = aws_sns_topic.analyzer_notifications[0].arn
  protocol  = "email"
  endpoint  = each.value
}
