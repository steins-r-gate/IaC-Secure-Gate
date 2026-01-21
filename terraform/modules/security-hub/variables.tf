# ==================================================================
# Security Hub Module - Variables
# terraform/modules/security-hub/variables.tf
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
# Standards Configuration
# ==================================================================

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark standard"
  type        = bool
  default     = true
}

variable "cis_standard_version" {
  description = "CIS AWS Foundations Benchmark version"
  type        = string
  default     = "1.4.0"

  validation {
    condition     = contains(["1.2.0", "1.4.0", "3.0.0"], var.cis_standard_version)
    error_message = "CIS version must be 1.2.0, 1.4.0, or 3.0.0."
  }
}

variable "enable_foundational_standard" {
  description = "Enable AWS Foundational Security Best Practices standard"
  type        = bool
  default     = true
}

variable "foundational_standard_version" {
  description = "AWS Foundational Security Best Practices version"
  type        = string
  default     = "1.0.0"
}

# ==================================================================
# Product Integrations
# ==================================================================

variable "enable_config_integration" {
  description = "Enable AWS Config integration"
  type        = bool
  default     = true
}

variable "enable_access_analyzer_integration" {
  description = "Enable IAM Access Analyzer integration"
  type        = bool
  default     = true
}

# ==================================================================
# Finding Aggregation (Multi-Region)
# ==================================================================

variable "enable_finding_aggregation" {
  description = "Enable cross-region finding aggregation"
  type        = bool
  default     = false
}

variable "finding_aggregation_linking_mode" {
  description = "Linking mode for finding aggregation"
  type        = string
  default     = "ALL_REGIONS"

  validation {
    condition     = contains(["ALL_REGIONS", "SPECIFIED_REGIONS", "ALL_REGIONS_EXCEPT_SPECIFIED"], var.finding_aggregation_linking_mode)
    error_message = "Must be ALL_REGIONS, SPECIFIED_REGIONS, or ALL_REGIONS_EXCEPT_SPECIFIED."
  }
}

variable "finding_aggregation_regions" {
  description = "List of regions for finding aggregation (used with SPECIFIED_REGIONS linking mode)"
  type        = list(string)
  default     = []
}

# ==================================================================
# Control Suppression
# ==================================================================

variable "disabled_control_ids" {
  description = "Set of control IDs to disable (e.g., ['cis-aws-foundations-benchmark/v/1.4.0/1.1'])"
  type        = set(string)
  default     = []
}

# ==================================================================
# Optional Notifications
# ==================================================================

variable "enable_critical_finding_notifications" {
  description = "Enable SNS notifications for critical/high severity findings"
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
  description = "List of email addresses to subscribe to critical finding notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.sns_email_subscriptions : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid."
  }
}
