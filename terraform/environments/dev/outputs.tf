# ==================================================================
# Phase 1 - Development Environment Outputs
# terraform/environments/dev/outputs.tf
# ==================================================================

# ==================================================================
# Foundation Module Outputs
# ==================================================================

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

output "cloudtrail_bucket_arn" {
  description = "CloudTrail logs S3 bucket ARN"
  value       = module.foundation.cloudtrail_bucket_arn
}

output "config_bucket_name" {
  description = "Config snapshots S3 bucket name"
  value       = module.foundation.config_bucket_name
}

output "config_bucket_arn" {
  description = "Config snapshots S3 bucket ARN"
  value       = module.foundation.config_bucket_arn
}

# ==================================================================
# CloudTrail Module Outputs
# ==================================================================

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

output "cloudtrail_log_file_validation_enabled" {
  description = "Whether CloudTrail log file validation is enabled (CIS 3.2)"
  value       = module.cloudtrail.log_file_validation_enabled
}

output "cloudtrail_is_multi_region_trail" {
  description = "Whether CloudTrail is a multi-region trail (CIS 3.1)"
  value       = module.cloudtrail.is_multi_region_trail
}

# ==================================================================
# AWS Config Module Outputs
# ==================================================================

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = module.config.config_recorder_name
}

output "config_recorder_arn" {
  description = "AWS Config recorder ARN"
  value       = module.config.config_recorder_arn
}

output "config_recorder_enabled" {
  description = "Whether the Config recorder is enabled"
  value       = module.config.recorder_status_enabled
}

output "config_delivery_channel_name" {
  description = "Config delivery channel name"
  value       = module.config.delivery_channel_name
}

output "config_role_arn" {
  description = "IAM role ARN used by AWS Config"
  value       = module.config.config_role_arn
}

output "config_rules_deployed" {
  description = "List of deployed Config rule names"
  value       = module.config.config_rule_names
}

output "config_rules_count" {
  description = "Number of Config rules deployed"
  value       = module.config.config_rules_count
}

# ==================================================================
# Access Analyzer Module Outputs
# ==================================================================

output "access_analyzer_id" {
  description = "Access Analyzer ID"
  value       = module.access_analyzer.analyzer_id
}

output "access_analyzer_arn" {
  description = "Access Analyzer ARN"
  value       = module.access_analyzer.analyzer_arn
}

output "access_analyzer_name" {
  description = "Access Analyzer name"
  value       = module.access_analyzer.analyzer_name
}

output "access_analyzer_type" {
  description = "Analyzer type (ACCOUNT or ORGANIZATION)"
  value       = module.access_analyzer.analyzer_type
}

output "access_analyzer_summary" {
  description = "Access Analyzer configuration summary"
  value       = module.access_analyzer.analyzer_summary
}

# ==================================================================
# Security Hub Module Outputs
# ==================================================================

output "security_hub_account_arn" {
  description = "Security Hub account ARN"
  value       = module.security_hub.securityhub_account_arn
}

output "security_hub_enabled_standards" {
  description = "List of enabled Security Hub standards"
  value       = module.security_hub.enabled_standards
}

output "security_hub_control_count" {
  description = "Total Security Hub controls available"
  value       = try(module.security_hub.control_configuration.total_controls_available, 0)
}

output "security_hub_summary" {
  description = "Security Hub configuration summary"
  value       = module.security_hub.securityhub_summary
}

# ==================================================================
# Environment Information
# ==================================================================

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "environment" {
  description = "Environment name"
  value       = local.environment
}

output "project_name" {
  description = "Project name"
  value       = local.project_name
}

# ==================================================================
# Deployment Summary
# ==================================================================

output "deployment_summary" {
  description = "Summary of Phase 1 dev environment deployment"
  value = {
    # Environment
    environment = local.environment
    region      = data.aws_region.current.name
    account_id  = data.aws_caller_identity.current.account_id
    project     = local.project_name

    # Foundation
    kms_key_arn              = module.foundation.kms_key_arn
    cloudtrail_bucket        = module.foundation.cloudtrail_bucket_name
    config_bucket            = module.foundation.config_bucket_name
    foundation_cis_compliant = try(module.foundation.foundation_summary.cis_compliant, false)

    # CloudTrail
    cloudtrail_name                  = module.cloudtrail.trail_name
    cloudtrail_multi_region          = module.cloudtrail.is_multi_region_trail
    cloudtrail_log_validation        = module.cloudtrail.log_file_validation_enabled
    cloudtrail_global_service_events = module.cloudtrail.include_global_service_events
    cloudtrail_cis_3_1_compliant     = try(module.cloudtrail.cloudtrail_summary.cis_3_1_compliant, false)
    cloudtrail_cis_3_2_compliant     = try(module.cloudtrail.cloudtrail_summary.cis_3_2_compliant, false)

    # Config
    config_recorder_name    = module.config.config_recorder_name
    config_recorder_enabled = module.config.recorder_status_enabled
    config_rules_deployed   = module.config.config_rules_count
    config_primary_region   = try(module.config.configuration_summary.is_primary_region, true)
    config_global_resources = try(module.config.configuration_summary.include_global_resource_types, false)

    # Access Analyzer
    access_analyzer_enabled = true
    access_analyzer_name    = module.access_analyzer.analyzer_name
    access_analyzer_type    = module.access_analyzer.analyzer_type

    # Security Hub
    security_hub_enabled       = true
    security_hub_standards     = module.security_hub.enabled_standards
    security_hub_control_count = try(module.security_hub.control_configuration.total_controls_available, 0)

    # Compliance Status
    phase_1_ready    = true
    phase_1_complete = true # All 5 modules deployed
  }
}
