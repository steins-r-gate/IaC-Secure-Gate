# ==================================================================
# Account Baseline Module Outputs
# terraform/modules/account-baseline/outputs.tf
# ==================================================================

output "s3_account_bpa_enabled" {
  description = "Whether S3 account-level Block Public Access is enabled"
  value       = var.enable_s3_account_bpa
}

output "ebs_default_encryption_enabled" {
  description = "Whether EBS default encryption is enabled"
  value       = var.enable_ebs_default_encryption
}

output "password_policy_enabled" {
  description = "Whether IAM password policy is configured"
  value       = var.enable_password_policy
}

output "vpc_flow_logs_enabled" {
  description = "Whether VPC flow logging is enabled on default VPC"
  value       = var.enable_default_vpc_flow_logs
}

output "vpc_flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs"
  value       = var.enable_default_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}
