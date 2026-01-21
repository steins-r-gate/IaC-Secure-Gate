# ==================================================================
# IAM Access Analyzer Module - Outputs
# terraform/modules/access-analyzer/outputs.tf
# ==================================================================

# ==================================================================
# Core Analyzer Outputs
# ==================================================================

output "analyzer_id" {
  description = "Access Analyzer ID"
  value       = aws_accessanalyzer_analyzer.account.id
}

output "analyzer_arn" {
  description = "Access Analyzer ARN"
  value       = aws_accessanalyzer_analyzer.account.arn
}

output "analyzer_name" {
  description = "Access Analyzer name"
  value       = aws_accessanalyzer_analyzer.account.analyzer_name
}

output "analyzer_type" {
  description = "Analyzer type (ACCOUNT or ORGANIZATION)"
  value       = aws_accessanalyzer_analyzer.account.type
}

# ==================================================================
# Archive Rule Outputs - DISABLED
# ==================================================================
# Archive rule not implemented due to AWS API limitations
# status filtering is not supported

output "archive_rule_name" {
  description = "Archive rule name (null - archive rule not implemented)"
  value       = null
}

output "archive_threshold_days" {
  description = "Number of days after which findings are archived (informational only)"
  value       = var.archive_findings_older_than_days
}

# ==================================================================
# SNS Outputs (Optional)
# ==================================================================

output "sns_topic_arn" {
  description = "SNS topic ARN for findings notifications (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.analyzer_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "SNS topic name (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.analyzer_notifications[0].name : null
}

output "eventbridge_rule_arn" {
  description = "EventBridge rule ARN for findings (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_cloudwatch_event_rule.analyzer_findings[0].arn : null
}

# ==================================================================
# Structured Summary (Following established pattern)
# ==================================================================

output "analyzer_summary" {
  description = "Summary of Access Analyzer configuration"
  value = {
    # Environment
    environment = var.environment
    region      = data.aws_region.current.id
    account_id  = data.aws_caller_identity.current.account_id

    # Analyzer
    analyzer_name   = aws_accessanalyzer_analyzer.account.analyzer_name
    analyzer_arn    = aws_accessanalyzer_analyzer.account.arn
    analyzer_type   = aws_accessanalyzer_analyzer.account.type
    analyzer_status = "ACTIVE"

    # Features
    archive_rule_enabled   = var.enable_archive_rule
    archive_threshold_days = var.archive_findings_older_than_days
    sns_notifications      = var.enable_sns_notifications

    # Integration
    security_hub_integration = true # Automatic

    # CIS Compliance
    cis_controls_supported = [
      "CIS 1.15 - IAM external access detection",
      "CIS 1.16 - IAM policy analysis"
    ]

    # Cost
    monthly_cost_usd = 0.00 # FREE
  }
}
