# ==================================================================
# Phase 1 - Development Environment Outputs
# terraform/environments/dev/outputs.tf
# ==================================================================

# Foundation Module Outputs
output "kms_key_id" {
  description = "KMS key ID for log encryption"
  value       = module.foundation.kms_key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for log encryption"
  value       = module.foundation.kms_key_arn
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail logs S3 bucket name"
  value       = module.foundation.cloudtrail_bucket_name
}

output "config_bucket_name" {
  description = "Config snapshots S3 bucket name"
  value       = module.foundation.config_bucket_name
}

# CloudTrail Module Outputs
output "cloudtrail_trail_id" {
  description = "CloudTrail trail ID"
  value       = module.cloudtrail.trail_id
}

output "cloudtrail_trail_arn" {
  description = "CloudTrail trail ARN"
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_trail_name" {
  description = "CloudTrail trail name"
  value       = module.cloudtrail.trail_name
}

output "cloudtrail_home_region" {
  description = "CloudTrail trail home region"
  value       = module.cloudtrail.trail_home_region
}

# Account Information
output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}
