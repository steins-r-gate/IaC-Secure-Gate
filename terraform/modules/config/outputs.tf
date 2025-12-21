# ==================================================================
# AWS Config Module Outputs
# terraform/modules/config/outputs.tf
# ==================================================================

output "config_recorder_id" {
  description = "AWS Config recorder ID"
  value       = aws_config_configuration_recorder.main.id
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = aws_config_configuration_recorder.main.name
}

output "config_role_arn" {
  description = "IAM role ARN used by AWS Config"
  value       = aws_iam_role.config.arn
}

output "config_role_name" {
  description = "IAM role name used by AWS Config"
  value       = aws_iam_role.config.name
}

output "delivery_channel_id" {
  description = "Config delivery channel ID"
  value       = aws_config_delivery_channel.main.id
}

output "config_rules" {
  description = "List of deployed Config rule names"
  value = [
    aws_config_config_rule.root_mfa_enabled.name,
    aws_config_config_rule.iam_password_policy.name,
    aws_config_config_rule.access_keys_rotated.name,
    aws_config_config_rule.iam_user_mfa_enabled.name,
    aws_config_config_rule.cloudtrail_enabled.name,
    aws_config_config_rule.cloudtrail_log_file_validation.name,
    aws_config_config_rule.s3_bucket_public_read_prohibited.name,
    aws_config_config_rule.s3_bucket_public_write_prohibited.name,
  ]
}

output "config_rules_count" {
  description = "Number of Config rules deployed"
  value       = 8
}
