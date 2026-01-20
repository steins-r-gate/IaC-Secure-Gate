# ==================================================================
# AWS Config Module Variables
# terraform/modules/config/variables.tf
# ==================================================================

# ==================================================================
# Environment and Naming
# ==================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming convention"
  type        = string
  default     = "iam-secure-gate"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all Config resources"
  type        = map(string)
  default     = {}
}

# ==================================================================
# S3 Bucket Configuration (from foundation module)
# ==================================================================

variable "config_bucket_name" {
  description = "Name of the S3 bucket for Config snapshots and history (from foundation module)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.config_bucket_name))
    error_message = "S3 bucket name must be valid: 3-63 chars, lowercase letters, numbers, hyphens."
  }
}

variable "config_bucket_arn" {
  description = "ARN of the S3 bucket for Config snapshots (from foundation module)"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.config_bucket_arn))
    error_message = "Must be a valid S3 bucket ARN."
  }
}

variable "config_bucket_kms_key_arn" {
  description = "ARN of the KMS key used for S3 bucket encryption (required if bucket uses SSE-KMS)"
  type        = string
  default     = null

  validation {
    condition     = var.config_bucket_kms_key_arn == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.config_bucket_kms_key_arn))
    error_message = "Must be a valid KMS key ARN or null."
  }
}

variable "s3_key_prefix" {
  description = "S3 key prefix for Config snapshots (enables multi-environment isolation in shared bucket)"
  type        = string
  default     = "AWSLogs"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_/]+$", var.s3_key_prefix)) && !startswith(var.s3_key_prefix, "/") && !endswith(var.s3_key_prefix, "/")
    error_message = "S3 key prefix must not start or end with '/' and contain only alphanumeric, hyphens, underscores, and forward slashes."
  }
}

# ==================================================================
# Multi-Region Configuration
# ==================================================================

variable "is_primary_region" {
  description = "Whether this is the primary region for global resource recording. Set to true in ONE region only to avoid duplicating IAM/global resources in Config."
  type        = bool
  default     = true
}

# ==================================================================
# Config Recorder Settings
# ==================================================================

variable "include_global_resource_types" {
  description = "Whether to record global resources (IAM, CloudFront, Route53, WAF). Should only be true in primary region. If null, uses is_primary_region value."
  type        = bool
  default     = null
}

variable "snapshot_delivery_frequency" {
  description = "Frequency of Config snapshot delivery to S3"
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains([
      "One_Hour",
      "Three_Hours",
      "Six_Hours",
      "Twelve_Hours",
      "TwentyFour_Hours"
    ], var.snapshot_delivery_frequency)
    error_message = "Must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}

# ==================================================================
# Config Rules Configuration
# ==================================================================

variable "enable_config_rules" {
  description = "Whether to deploy AWS Config managed rules for CIS compliance"
  type        = bool
  default     = true
}

variable "config_rules" {
  description = "Map of AWS Config managed rules to deploy. Key is rule name, value is rule configuration. Set to {} to disable all default rules."
  type = map(object({
    description       = string
    source_identifier = string
    input_parameters  = map(any)
  }))
  default = null
}

# ==================================================================
# Optional Features
# ==================================================================

variable "enable_sns_notifications" {
  description = "Whether to create an SNS topic for Config notifications"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "Existing SNS topic ARN for Config notifications (if enable_sns_notifications is false but you want to use an existing topic)"
  type        = string
  default     = null

  validation {
    condition     = var.sns_topic_arn == null || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9-_]+$", var.sns_topic_arn))
    error_message = "Must be a valid SNS topic ARN or null."
  }
}

# ==================================================================
# Deprecated Variables (for backward compatibility)
# ==================================================================

variable "region" {
  description = "DEPRECATED: AWS region is automatically detected via data source. This variable is ignored."
  type        = string
  default     = null
}

variable "account_id" {
  description = "DEPRECATED: AWS account ID is automatically detected via data source. This variable is ignored."
  type        = string
  default     = null
}
