# ==================================================================
# CloudTrail Module Outputs
# terraform/modules/cloudtrail/outputs.tf
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

output "log_file_validation_enabled" {
  description = "Whether log file validation is enabled"
  value       = aws_cloudtrail.main.enable_log_file_validation
}
