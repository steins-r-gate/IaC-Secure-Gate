# s3/variables.tf

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Optional Lifecycle Configuration
# ============================================================================
variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs before deletion"
  type        = number
  default     = 365
}

variable "config_log_retention_days" {
  description = "Number of days to retain Config logs before deletion"
  type        = number
  default     = 365
}

variable "access_log_retention_days" {
  description = "Number of days to retain S3 access logs before deletion"
  type        = number
  default     = 365
}

variable "transition_to_ia_days" {
  description = "Number of days before transitioning to STANDARD_IA storage class"
  type        = number
  default     = 90
}

variable "transition_to_glacier_days" {
  description = "Number of days before transitioning to GLACIER storage class"
  type        = number
  default     = 180
}

# ============================================================================
# KMS Configuration
# ============================================================================
variable "kms_deletion_window_days" {
  description = "Number of days before KMS key is deleted after destruction"
  type        = number
  default     = 10

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}
