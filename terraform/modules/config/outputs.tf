# ==================================================================
# AWS Config Module Outputs
# terraform/modules/config/outputs.tf
# ==================================================================

# ==================================================================
# Core Config Resources
# ==================================================================

output "config_recorder_id" {
  description = "AWS Config recorder ID"
  value       = aws_config_configuration_recorder.main.id
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = aws_config_configuration_recorder.main.name
}

output "config_recorder_arn" {
  description = "ARN of the Config recorder"
  value       = "arn:aws:config:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:config-recorder/${aws_config_configuration_recorder.main.name}"
}

output "delivery_channel_id" {
  description = "Config delivery channel ID"
  value       = aws_config_delivery_channel.main.id
}

output "delivery_channel_name" {
  description = "Config delivery channel name"
  value       = aws_config_delivery_channel.main.name
}

output "recorder_status_enabled" {
  description = "Whether the Config recorder is enabled"
  value       = aws_config_configuration_recorder_status.main.is_enabled
}

# ==================================================================
# IAM Role
# ==================================================================

output "config_role_arn" {
  description = "IAM role ARN used by AWS Config"
  value       = aws_iam_role.config.arn
}

output "config_role_name" {
  description = "IAM role name used by AWS Config"
  value       = aws_iam_role.config.name
}

output "config_role_id" {
  description = "IAM role ID used by AWS Config"
  value       = aws_iam_role.config.id
}

# ==================================================================
# Config Rules
# ==================================================================

output "config_rules" {
  description = "Map of deployed Config rule names and their ARNs"
  value = {
    for rule_name, rule in aws_config_config_rule.rules : rule_name => {
      name = rule.name
      id   = rule.id
      arn  = rule.arn
    }
  }
}

output "config_rule_names" {
  description = "List of deployed Config rule names"
  value       = [for rule in aws_config_config_rule.rules : rule.name]
}

output "config_rules_count" {
  description = "Number of Config rules deployed"
  value       = length(aws_config_config_rule.rules)
}

# ==================================================================
# SNS Topic (Optional)
# ==================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Config notifications (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.config[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for Config notifications (null if not enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.config[0].name : null
}

# ==================================================================
# Configuration Summary
# ==================================================================

output "configuration_summary" {
  description = "Summary of AWS Config module deployment"
  value = {
    environment                   = var.environment
    region                        = data.aws_region.current.id
    account_id                    = data.aws_caller_identity.current.account_id
    recorder_name                 = aws_config_configuration_recorder.main.name
    recorder_enabled              = aws_config_configuration_recorder_status.main.is_enabled
    include_global_resource_types = local.include_global_resources
    is_primary_region             = var.is_primary_region
    delivery_bucket               = var.config_bucket_name
    s3_key_prefix                 = var.s3_key_prefix
    snapshot_frequency            = var.snapshot_delivery_frequency
    rules_deployed                = length(aws_config_config_rule.rules)
    sns_notifications_enabled     = var.enable_sns_notifications
  }
}

# ==================================================================
# Dependency Management
# ==================================================================

output "recorder_status_id" {
  description = "Config recorder status ID - use this in depends_on when other resources need Config to be fully operational"
  value       = aws_config_configuration_recorder_status.main.id
}
