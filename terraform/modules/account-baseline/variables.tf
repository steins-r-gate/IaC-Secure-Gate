# ==================================================================
# Account Baseline Module Variables
# terraform/modules/account-baseline/variables.tf
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
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==================================================================
# Feature Flags
# ==================================================================

variable "enable_s3_account_bpa" {
  description = "Enable account-level S3 Block Public Access (CIS S3.1)"
  type        = bool
  default     = true
}

variable "enable_ebs_default_encryption" {
  description = "Enable EBS default encryption (CIS EC2.7)"
  type        = bool
  default     = true
}

variable "enable_password_policy" {
  description = "Enable IAM account password policy (CIS IAM.15)"
  type        = bool
  default     = true
}

variable "enable_default_vpc_flow_logs" {
  description = "Enable VPC flow logging on default VPC (CIS EC2.6)"
  type        = bool
  default     = true
}

# ==================================================================
# Password Policy Settings
# ==================================================================

variable "password_minimum_length" {
  description = "Minimum password length for IAM users"
  type        = number
  default     = 14

  validation {
    condition     = var.password_minimum_length >= 14
    error_message = "Password minimum length must be at least 14 for CIS compliance."
  }
}

variable "password_max_age_days" {
  description = "Maximum password age in days before requiring rotation"
  type        = number
  default     = 90

  validation {
    condition     = var.password_max_age_days >= 1 && var.password_max_age_days <= 365
    error_message = "Password max age must be between 1 and 365 days."
  }
}

variable "password_reuse_prevention" {
  description = "Number of previous passwords to prevent reuse"
  type        = number
  default     = 24

  validation {
    condition     = var.password_reuse_prevention >= 1 && var.password_reuse_prevention <= 24
    error_message = "Password reuse prevention must be between 1 and 24."
  }
}

# ==================================================================
# VPC Flow Logs Settings
# ==================================================================

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC flow logs in CloudWatch"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention must be a valid CloudWatch Logs retention period."
  }
}
