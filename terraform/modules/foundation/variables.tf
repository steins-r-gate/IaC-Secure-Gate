# ==================================================================
# Foundation Module Variables
# terraform/modules/foundation/variables.tf
# ==================================================================

# ==================================================================
# Core Configuration
# ==================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming (lowercase, alphanumeric, hyphens only)"
  type        = string
  default     = "iam-secure-gate"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==================================================================
# KMS Configuration
# ==================================================================

variable "kms_deletion_window_days" {
  description = "KMS key deletion waiting period in days (7-30). Lower = faster recovery, higher = more safety"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# ==================================================================
# CloudTrail Bucket Configuration
# ==================================================================

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in S3 before deletion (minimum 90 for CIS compliance)"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_log_retention_days >= 90
    error_message = "CloudTrail retention must be at least 90 days for CIS AWS Foundations compliance."
  }
}

variable "cloudtrail_glacier_transition_days" {
  description = "Number of days before transitioning CloudTrail logs to Glacier storage (must be less than retention)"
  type        = number
  default     = 30

  validation {
    condition     = var.cloudtrail_glacier_transition_days >= 30
    error_message = "Glacier transition must be at least 30 days (S3 minimum for Glacier transition)."
  }
}

variable "cloudtrail_noncurrent_version_retention_days" {
  description = "Number of days to retain noncurrent (old) versions of CloudTrail logs before deletion"
  type        = number
  default     = 30

  validation {
    condition     = var.cloudtrail_noncurrent_version_retention_days >= 1
    error_message = "Noncurrent version retention must be at least 1 day."
  }
}

# ==================================================================
# Config Bucket Configuration
# ==================================================================

variable "config_snapshot_retention_days" {
  description = "Number of days to retain Config snapshots in S3 before deletion (recommend 365 for annual audits)"
  type        = number
  default     = 365

  validation {
    condition     = var.config_snapshot_retention_days >= 90
    error_message = "Config retention should be at least 90 days for compliance audits."
  }
}

variable "config_glacier_transition_days" {
  description = "Number of days before transitioning Config snapshots to Glacier storage (must be less than retention)"
  type        = number
  default     = 90

  validation {
    condition     = var.config_glacier_transition_days >= 30
    error_message = "Glacier transition must be at least 30 days (S3 minimum for Glacier transition)."
  }
}

variable "config_noncurrent_version_retention_days" {
  description = "Number of days to retain noncurrent (old) versions of Config snapshots before deletion"
  type        = number
  default     = 90

  validation {
    condition     = var.config_noncurrent_version_retention_days >= 1
    error_message = "Noncurrent version retention must be at least 1 day."
  }
}

# ==================================================================
# Optional Features
# ==================================================================

variable "enable_bucket_logging" {
  description = "Enable S3 access logging for audit buckets (requires separate log bucket)"
  type        = bool
  default     = false
}

variable "bucket_logging_target_bucket" {
  description = "Target S3 bucket for access logs (required if enable_bucket_logging = true)"
  type        = string
  default     = null

  validation {
    condition     = var.bucket_logging_target_bucket == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_logging_target_bucket))
    error_message = "bucket_logging_target_bucket must be a valid S3 bucket name if provided."
  }
}

variable "bucket_logging_target_prefix" {
  description = "Prefix for access logs in target bucket"
  type        = string
  default     = "foundation-access-logs/"
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock (WORM) for immutable logs (WARNING: Cannot be disabled after creation)"
  type        = bool
  default     = false
}

variable "object_lock_retention_days" {
  description = "Number of days to retain objects in Object Lock (WORM) mode"
  type        = number
  default     = 90

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "Object Lock retention must be at least 1 day."
  }
}

# ==================================================================
# Cross-validation
# ==================================================================

locals {
  # Validate CloudTrail lifecycle timing
  validate_cloudtrail_lifecycle = var.cloudtrail_glacier_transition_days < var.cloudtrail_log_retention_days ? true : tobool("ERROR: cloudtrail_glacier_transition_days must be less than cloudtrail_log_retention_days")

  # Validate Config lifecycle timing
  validate_config_lifecycle = var.config_glacier_transition_days < var.config_snapshot_retention_days ? true : tobool("ERROR: config_glacier_transition_days must be less than config_snapshot_retention_days")
}
