# ==================================================================
# CloudTrail Module Outputs
# terraform/modules/cloudtrail/outputs.tf
# ==================================================================

# ==================================================================
# Core CloudTrail Outputs
# ==================================================================

output "trail_id" {
  description = "CloudTrail trail ID"
  value       = aws_cloudtrail.main.id
}

output "trail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.main.arn
}

output "trail_name" {
  description = "CloudTrail trail name"
  value       = aws_cloudtrail.main.name
}

output "trail_home_region" {
  description = "Region where the trail was created"
  value       = aws_cloudtrail.main.home_region
}

output "trail_s3_bucket_name" {
  description = "S3 bucket used for CloudTrail logs"
  value       = aws_cloudtrail.main.s3_bucket_name
}

# ==================================================================
# Security Configuration Outputs
# ==================================================================

output "log_file_validation_enabled" {
  description = "Whether log file validation is enabled (CIS 3.2)"
  value       = aws_cloudtrail.main.enable_log_file_validation
}

output "is_multi_region_trail" {
  description = "Whether this is a multi-region trail (CIS 3.1)"
  value       = aws_cloudtrail.main.is_multi_region_trail
}

output "is_organization_trail" {
  description = "Whether this is an organization trail"
  value       = aws_cloudtrail.main.is_organization_trail
}

output "include_global_service_events" {
  description = "Whether global service events (IAM/STS) are included"
  value       = aws_cloudtrail.main.include_global_service_events
}

output "kms_key_id" {
  description = "KMS key ID used for log encryption"
  value       = aws_cloudtrail.main.kms_key_id
}

# ==================================================================
# CloudWatch Logs Outputs (Optional)
# ==================================================================

output "cloudwatch_logs_group_arn" {
  description = "CloudWatch Logs group ARN (null if not enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

output "cloudwatch_logs_group_name" {
  description = "CloudWatch Logs group name (null if not enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudwatch_logs_role_arn" {
  description = "IAM role ARN for CloudWatch Logs integration (null if not enabled)"
  value       = var.enable_cloudwatch_logs ? aws_iam_role.cloudtrail_cloudwatch[0].arn : null
}

# ==================================================================
# SNS Outputs (Optional)
# ==================================================================

output "sns_topic_arn" {
  description = "SNS topic ARN for CloudTrail notifications (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.cloudtrail_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "SNS topic name for CloudTrail notifications (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.cloudtrail_notifications[0].name : null
}

# ==================================================================
# Insights Outputs
# ==================================================================

output "insights_enabled" {
  description = "Whether CloudTrail Insights are enabled"
  value       = var.enable_insights
}

# ==================================================================
# Configuration Summary (Structured Output)
# ==================================================================

output "cloudtrail_summary" {
  description = "Summary of CloudTrail configuration"
  value = {
    # Trail information
    trail_name        = aws_cloudtrail.main.name
    trail_arn         = aws_cloudtrail.main.arn
    trail_home_region = aws_cloudtrail.main.home_region
    s3_bucket_name    = aws_cloudtrail.main.s3_bucket_name

    # Security configuration
    log_file_validation_enabled   = aws_cloudtrail.main.enable_log_file_validation
    is_multi_region_trail         = aws_cloudtrail.main.is_multi_region_trail
    is_organization_trail         = aws_cloudtrail.main.is_organization_trail
    include_global_service_events = aws_cloudtrail.main.include_global_service_events
    kms_encryption_enabled        = true

    # Optional features
    cloudwatch_logs_enabled    = var.enable_cloudwatch_logs
    sns_notifications_enabled  = var.enable_sns_notifications
    insights_enabled           = var.enable_insights
    s3_data_events_enabled     = var.enable_s3_data_events
    lambda_data_events_enabled = var.enable_lambda_data_events

    # CIS compliance status
    cis_3_1_compliant = aws_cloudtrail.main.is_multi_region_trail      # Multi-region trail
    cis_3_2_compliant = aws_cloudtrail.main.enable_log_file_validation # Log validation
  }
}

# ==================================================================
# Event Selector Summary
# ==================================================================

output "event_configuration" {
  description = "Summary of event selector configuration"
  value = {
    management_events_enabled       = true
    excluded_management_sources     = var.exclude_management_event_sources
    s3_data_events_enabled          = var.enable_s3_data_events
    s3_data_event_bucket_count      = length(var.s3_data_event_bucket_arns)
    lambda_data_events_enabled      = var.enable_lambda_data_events
    api_call_rate_insights_enabled  = var.enable_insights
    api_error_rate_insights_enabled = var.enable_insights && var.enable_error_rate_insights
  }
}
