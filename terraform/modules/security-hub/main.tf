# ==================================================================
# Security Hub Module - Main Configuration
# terraform/modules/security-hub/main.tf
# ==================================================================

# ==================================================================
# Local Variables
# ==================================================================

locals {
  securityhub_name = "${var.project_name}-${var.environment}-securityhub"

  securityhub_tags = merge(var.common_tags, {
    Module  = "security-hub"
    Service = "AWS-Security-Hub"
    Phase   = "Phase-1-Detection"
  })

  # CIS standard ARN
  cis_standard_arn = "arn:aws:securityhub:${data.aws_region.current.id}::standards/cis-aws-foundations-benchmark/v/${var.cis_standard_version}"

  # Foundational standard ARN
  foundational_standard_arn = "arn:aws:securityhub:${data.aws_region.current.id}::standards/aws-foundational-security-best-practices/v/${var.foundational_standard_version}"
}

# ==================================================================
# Enable Security Hub
# ==================================================================

resource "aws_securityhub_account" "main" {}

# ==================================================================
# Enable Security Standards
# ==================================================================

# CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_cis_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = local.cis_standard_arn
}

# AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "foundational" {
  count = var.enable_foundational_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = local.foundational_standard_arn
}

# ==================================================================
# Product Integrations
# ==================================================================

# AWS Config Integration
resource "aws_securityhub_product_subscription" "config" {
  count = var.enable_config_integration ? 1 : 0

  depends_on  = [aws_securityhub_account.main]
  product_arn = "arn:aws:securityhub:${data.aws_region.current.id}::product/aws/config"
}

# IAM Access Analyzer Integration
resource "aws_securityhub_product_subscription" "access_analyzer" {
  count = var.enable_access_analyzer_integration ? 1 : 0

  depends_on  = [aws_securityhub_account.main]
  product_arn = "arn:aws:securityhub:${data.aws_region.current.id}::product/aws/access-analyzer"
}

# ==================================================================
# Finding Aggregation (Multi-Region, Optional)
# ==================================================================

resource "aws_securityhub_finding_aggregator" "main" {
  count = var.enable_finding_aggregation ? 1 : 0

  linking_mode = var.finding_aggregation_linking_mode

  # Only used with SPECIFIED_REGIONS linking mode
  specified_regions = var.finding_aggregation_linking_mode == "SPECIFIED_REGIONS" ? var.finding_aggregation_regions : null
}

# ==================================================================
# Control Suppression (Disable specific controls)
# ==================================================================

resource "aws_securityhub_standards_control" "suppressed_controls" {
  for_each = var.disabled_control_ids

  standards_control_arn = "arn:aws:securityhub:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:control/${each.value}"
  control_status        = "DISABLED"
  disabled_reason       = "Not applicable to ${var.environment} environment"

  depends_on = [
    aws_securityhub_standards_subscription.cis,
    aws_securityhub_standards_subscription.foundational
  ]
}

# ==================================================================
# Optional: EventBridge Rule for Critical Findings → SNS
# ==================================================================

resource "aws_cloudwatch_event_rule" "critical_findings" {
  count = var.enable_critical_finding_notifications ? 1 : 0

  name        = "${local.securityhub_name}-critical-findings"
  description = "Route critical/high Security Hub findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })

  tags = merge(local.securityhub_tags, {
    Name = "${local.securityhub_name}-critical-findings-rule"
  })
}

resource "aws_cloudwatch_event_target" "critical_findings_sns" {
  count = var.enable_critical_finding_notifications ? 1 : 0

  rule      = aws_cloudwatch_event_rule.critical_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.critical_findings[0].arn
}

# ==================================================================
# SNS Topic for Critical Findings
# ==================================================================

resource "aws_sns_topic" "critical_findings" {
  count = var.enable_critical_finding_notifications ? 1 : 0

  name              = "${local.securityhub_name}-critical-findings"
  display_name      = "Security Hub Critical Findings"
  kms_master_key_id = var.kms_key_arn

  tags = merge(local.securityhub_tags, {
    Name = "${local.securityhub_name}-critical-findings"
  })
}

resource "aws_sns_topic_policy" "critical_findings" {
  count = var.enable_critical_finding_notifications ? 1 : 0

  arn = aws_sns_topic.critical_findings[0].arn

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
        Resource = aws_sns_topic.critical_findings[0].arn
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
resource "aws_sns_topic_subscription" "critical_findings_email" {
  for_each = var.enable_critical_finding_notifications ? toset(var.sns_email_subscriptions) : []

  topic_arn = aws_sns_topic.critical_findings[0].arn
  protocol  = "email"
  endpoint  = each.value
}
