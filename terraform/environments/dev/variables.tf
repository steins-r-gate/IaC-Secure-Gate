# ==================================================================
# Phase 1 - Development Environment Variables
# terraform/environments/dev/variables.tf
# ==================================================================

variable "aws_region" {
  description = "AWS region for Phase 1 deployment"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "Phase 1 is configured for eu-west-1 only."
  }
}

variable "owner_email" {
  description = "Email address of the project owner (for tagging)"
  type        = string
  # No default - requires explicit value in terraform.tfvars

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Must be a valid email address."
  }
}

variable "cloudtrail_log_retention_days" {
  description = "CloudTrail log retention in days (minimum 90 for CIS compliance)"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_log_retention_days >= 90 && var.cloudtrail_log_retention_days <= 2555
    error_message = "Retention must be between 90 days (CIS minimum) and 2555 days (7 years)."
  }
}

variable "config_snapshot_retention_days" {
  description = "Config snapshot retention in days"
  type        = number
  default     = 365

  validation {
    condition     = var.config_snapshot_retention_days >= 365 && var.config_snapshot_retention_days <= 2555
    error_message = "Retention must be between 365 days and 2555 days (7 years)."
  }
}

variable "archive_findings_older_than_days" {
  description = "Auto-archive Access Analyzer findings older than N days"
  type        = number
  default     = 90

  validation {
    condition     = var.archive_findings_older_than_days >= 30 && var.archive_findings_older_than_days <= 365
    error_message = "Archive threshold must be 30-365 days."
  }
}

variable "cis_standard_version" {
  description = "CIS AWS Foundations Benchmark version for Security Hub"
  type        = string
  default     = "1.4.0"

  validation {
    condition     = contains(["1.2.0", "1.4.0", "3.0.0"], var.cis_standard_version)
    error_message = "CIS standard version must be one of: 1.2.0, 1.4.0, 3.0.0."
  }
}
