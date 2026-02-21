# ==================================================================
# CIS Alarms Module Outputs
# terraform/modules/cis-alarms/outputs.tf
# ==================================================================

output "metric_filter_names" {
  description = "Names of the CIS metric filters created"
  value       = [for k, v in aws_cloudwatch_log_metric_filter.cis : v.name]
}

output "alarm_arns" {
  description = "ARNs of the CIS CloudWatch alarms created"
  value       = [for k, v in aws_cloudwatch_metric_alarm.cis : v.arn]
}

output "alarm_count" {
  description = "Number of CIS alarms created"
  value       = length(aws_cloudwatch_metric_alarm.cis)
}
