# ==================================================================
# Foundation Module Outputs
# terraform/modules/foundation/outputs.tf
# ==================================================================

# ==================================================================
# Environment Information
# ==================================================================

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.id
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ==================================================================
# KMS Key Outputs
# ==================================================================

output "kms_key_id" {
  description = "ID of the KMS key for log encryption"
  value       = aws_kms_key.logs.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for log encryption"
  value       = aws_kms_key.logs.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.logs.name
}

output "kms_key_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.logs.arn
}

# ==================================================================
# CloudTrail Bucket Outputs
# ==================================================================

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail logs bucket"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail logs bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudtrail_bucket_domain_name" {
  description = "Domain name of the CloudTrail bucket"
  value       = aws_s3_bucket.cloudtrail.bucket_domain_name
}

output "cloudtrail_bucket_region" {
  description = "Region of the CloudTrail bucket"
  value       = aws_s3_bucket.cloudtrail.region
}

# ==================================================================
# Config Bucket Outputs
# ==================================================================

output "config_bucket_name" {
  description = "Name of the Config snapshots bucket"
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN of the Config snapshots bucket"
  value       = aws_s3_bucket.config.arn
}

output "config_bucket_domain_name" {
  description = "Domain name of the Config bucket"
  value       = aws_s3_bucket.config.bucket_domain_name
}

output "config_bucket_region" {
  description = "Region of the Config bucket"
  value       = aws_s3_bucket.config.region
}

# ==================================================================
# Configuration Summary (Structured Output)
# ==================================================================

output "foundation_summary" {
  description = "Summary of foundation module deployment"
  value = {
    # Environment
    environment = var.environment
    region      = data.aws_region.current.id
    account_id  = data.aws_caller_identity.current.account_id

    # KMS
    kms_key_id          = aws_kms_key.logs.id
    kms_key_arn         = aws_kms_key.logs.arn
    kms_key_rotation    = aws_kms_key.logs.enable_key_rotation
    kms_deletion_window = var.kms_deletion_window_days

    # CloudTrail Bucket
    cloudtrail_bucket_name             = aws_s3_bucket.cloudtrail.id
    cloudtrail_retention_days          = var.cloudtrail_log_retention_days
    cloudtrail_glacier_transition_days = var.cloudtrail_glacier_transition_days
    cloudtrail_versioning_enabled      = true
    cloudtrail_encryption_enabled      = true
    cloudtrail_public_access_blocked   = true

    # Config Bucket
    config_bucket_name             = aws_s3_bucket.config.id
    config_retention_days          = var.config_snapshot_retention_days
    config_glacier_transition_days = var.config_glacier_transition_days
    config_versioning_enabled      = true
    config_encryption_enabled      = true
    config_public_access_blocked   = true

    # Security Features
    object_lock_enabled    = var.enable_object_lock
    bucket_logging_enabled = var.enable_bucket_logging

    # Compliance
    cis_compliant = true
  }
}

# ==================================================================
# Bucket Policy ARNs (for reference)
# ==================================================================

output "cloudtrail_bucket_policy_id" {
  description = "ID of the CloudTrail bucket policy"
  value       = aws_s3_bucket_policy.cloudtrail.id
}

output "config_bucket_policy_id" {
  description = "ID of the Config bucket policy"
  value       = aws_s3_bucket_policy.config.id
}

# ==================================================================
# Lifecycle Configuration References
# ==================================================================

output "cloudtrail_lifecycle_rules" {
  description = "CloudTrail lifecycle configuration summary"
  value = {
    current_version_retention    = var.cloudtrail_log_retention_days
    glacier_transition_days      = var.cloudtrail_glacier_transition_days
    noncurrent_version_retention = var.cloudtrail_noncurrent_version_retention_days
    abort_incomplete_uploads     = true
  }
}

output "config_lifecycle_rules" {
  description = "Config lifecycle configuration summary"
  value = {
    current_version_retention    = var.config_snapshot_retention_days
    glacier_transition_days      = var.config_glacier_transition_days
    noncurrent_version_retention = var.config_noncurrent_version_retention_days
    abort_incomplete_uploads     = true
  }
}

# ==================================================================
# Security Status
# ==================================================================

output "security_status" {
  description = "Security configuration status"
  value = {
    kms_rotation_enabled       = true
    s3_versioning_enabled      = true
    s3_encryption_enabled      = true
    s3_public_access_blocked   = true
    s3_ownership_enforced      = true
    https_only_enforced        = true
    kms_key_enforcement        = true
    service_scoped_permissions = true
    source_account_validated   = true
    noncurrent_version_managed = true
    delete_markers_cleaned     = true
  }
}
