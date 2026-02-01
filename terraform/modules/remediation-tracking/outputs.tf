# ==================================================================
# Remediation Tracking Module - Outputs
# terraform/modules/remediation-tracking/outputs.tf
# ==================================================================

# ----------------------------------------------------------------------
# DynamoDB Table Outputs
# ----------------------------------------------------------------------

output "table_name" {
  description = "Name of the DynamoDB remediation history table"
  value       = aws_dynamodb_table.remediation_history.name
}

output "table_arn" {
  description = "ARN of the DynamoDB remediation history table"
  value       = aws_dynamodb_table.remediation_history.arn
}

output "table_id" {
  description = "ID of the DynamoDB remediation history table"
  value       = aws_dynamodb_table.remediation_history.id
}

output "table_stream_arn" {
  description = "ARN of the DynamoDB stream (for Phase 3)"
  value       = var.enable_dynamodb_stream ? aws_dynamodb_table.remediation_history.stream_arn : null
}

output "table_stream_label" {
  description = "Label of the DynamoDB stream"
  value       = var.enable_dynamodb_stream ? aws_dynamodb_table.remediation_history.stream_label : null
}

# ----------------------------------------------------------------------
# IAM Policy Outputs
# ----------------------------------------------------------------------

output "dynamodb_access_policy_arn" {
  description = "ARN of the IAM policy for DynamoDB access"
  value       = aws_iam_policy.dynamodb_access.arn
}

output "dynamodb_access_policy_name" {
  description = "Name of the IAM policy for DynamoDB access"
  value       = aws_iam_policy.dynamodb_access.name
}

# ----------------------------------------------------------------------
# Index Names (for Lambda code)
# ----------------------------------------------------------------------

output "resource_arn_index_name" {
  description = "Name of the GSI for querying by resource ARN"
  value       = var.enable_resource_index ? "resource-arn-index" : null
}

output "status_index_name" {
  description = "Name of the GSI for querying by status"
  value       = var.enable_status_index ? "status-index" : null
}

# ----------------------------------------------------------------------
# CloudWatch Alarm Outputs
# ----------------------------------------------------------------------

output "throttle_alarm_arn" {
  description = "ARN of the throttled requests CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.throttled_requests.arn
}

output "error_alarm_arn" {
  description = "ARN of the system errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.system_errors.arn
}

# ----------------------------------------------------------------------
# Configuration Outputs (for reference)
# ----------------------------------------------------------------------

output "ttl_attribute_name" {
  description = "Name of the TTL attribute for item expiration"
  value       = var.ttl_enabled ? var.ttl_attribute_name : null
}

output "ttl_days" {
  description = "Number of days before items expire"
  value       = var.ttl_enabled ? var.ttl_days : null
}
