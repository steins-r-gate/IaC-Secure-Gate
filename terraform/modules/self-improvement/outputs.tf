# ==================================================================
# Self-Improvement Module - Outputs
# terraform/modules/self-improvement/outputs.tf
# ==================================================================

# ----------------------------------------------------------------------
# SNS Topic Outputs - Remediation Alerts
# ----------------------------------------------------------------------

output "remediation_alerts_topic_arn" {
  description = "ARN of the remediation alerts SNS topic"
  value       = var.enable_remediation_alerts ? aws_sns_topic.remediation_alerts[0].arn : null
}

output "remediation_alerts_topic_name" {
  description = "Name of the remediation alerts SNS topic"
  value       = var.enable_remediation_alerts ? aws_sns_topic.remediation_alerts[0].name : null
}

# ----------------------------------------------------------------------
# SNS Topic Outputs - Analytics Reports
# ----------------------------------------------------------------------

output "analytics_reports_topic_arn" {
  description = "ARN of the analytics reports SNS topic"
  value       = var.enable_analytics_reports ? aws_sns_topic.analytics_reports[0].arn : null
}

output "analytics_reports_topic_name" {
  description = "Name of the analytics reports SNS topic"
  value       = var.enable_analytics_reports ? aws_sns_topic.analytics_reports[0].name : null
}

# ----------------------------------------------------------------------
# SNS Topic Outputs - Manual Review
# ----------------------------------------------------------------------

output "manual_review_topic_arn" {
  description = "ARN of the manual review SNS topic"
  value       = var.enable_manual_review_alerts ? aws_sns_topic.manual_review[0].arn : null
}

output "manual_review_topic_name" {
  description = "Name of the manual review SNS topic"
  value       = var.enable_manual_review_alerts ? aws_sns_topic.manual_review[0].name : null
}

# ----------------------------------------------------------------------
# Analytics Lambda Outputs
# ----------------------------------------------------------------------

output "analytics_lambda_arn" {
  description = "ARN of the analytics Lambda function"
  value       = var.enable_analytics_lambda ? aws_lambda_function.analytics[0].arn : null
}

output "analytics_lambda_name" {
  description = "Name of the analytics Lambda function"
  value       = var.enable_analytics_lambda ? aws_lambda_function.analytics[0].function_name : null
}

output "analytics_schedule_rule_arn" {
  description = "ARN of the CloudWatch Events rule for analytics schedule"
  value       = var.enable_analytics_lambda ? aws_cloudwatch_event_rule.analytics_schedule[0].arn : null
}

# ----------------------------------------------------------------------
# Summary Output
# ----------------------------------------------------------------------

output "module_summary" {
  description = "Summary of self-improvement module configuration"
  value = {
    environment = var.environment
    region      = data.aws_region.current.name

    sns_topics = {
      remediation_alerts = var.enable_remediation_alerts ? {
        arn  = aws_sns_topic.remediation_alerts[0].arn
        name = aws_sns_topic.remediation_alerts[0].name
      } : null

      analytics_reports = var.enable_analytics_reports ? {
        arn  = aws_sns_topic.analytics_reports[0].arn
        name = aws_sns_topic.analytics_reports[0].name
      } : null

      manual_review = var.enable_manual_review_alerts ? {
        arn  = aws_sns_topic.manual_review[0].arn
        name = aws_sns_topic.manual_review[0].name
      } : null
    }

    email_subscriptions = length(var.alert_email_subscriptions)

    analytics_lambda = var.enable_analytics_lambda ? {
      name     = aws_lambda_function.analytics[0].function_name
      schedule = var.analytics_schedule
    } : null
  }
}
