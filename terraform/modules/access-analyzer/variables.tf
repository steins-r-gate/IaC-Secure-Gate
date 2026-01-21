# ==================================================================
# IAM Access Analyzer Module - Variables
# terraform/modules/access-analyzer/variables.tf
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
  description = "Project name for resource naming"
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
# Analyzer Configuration
# ==================================================================

variable "analyzer_type" {
  description = "Analyzer type: ACCOUNT (single account) or ORGANIZATION (multi-account)"
  type        = string
  default     = "ACCOUNT"

  validation {
    condition     = contains(["ACCOUNT", "ORGANIZATION"], var.analyzer_type)
    error_message = "Analyzer type must be ACCOUNT or ORGANIZATION."
  }
}

# ==================================================================
# Archive Rule Configuration
# ==================================================================

variable "enable_archive_rule" {
  description = "Whether to create archive rule for old findings"
  type        = bool
  default     = true
}

variable "archive_findings_older_than_days" {
  description = "Archive findings older than N days (90 for dev, 365 for prod)"
  type        = number
  default     = 90

  validation {
    condition     = var.archive_findings_older_than_days >= 30 && var.archive_findings_older_than_days <= 365
    error_message = "Archive threshold must be between 30 and 365 days."
  }
}

# ==================================================================
# Optional SNS Notifications
# ==================================================================

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for new findings"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS encryption (from foundation module)"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "Must be a valid KMS key ARN or null."
  }
}

variable "sns_email_subscriptions" {
  description = "List of email addresses to subscribe to SNS notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.sns_email_subscriptions : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid."
  }
}
