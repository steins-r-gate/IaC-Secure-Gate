# ==================================================================
# CIS Alarms Module Variables
# terraform/modules/cis-alarms/variables.tf
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
# CloudTrail Log Group (required)
# ==================================================================

variable "cloudtrail_log_group_name" {
  description = "Name of the CloudTrail CloudWatch Logs group to create metric filters on"
  type        = string
}

# ==================================================================
# Feature Flags and Configuration
# ==================================================================

variable "enable_cis_alarms" {
  description = "Enable CIS CloudWatch metric filters and alarms"
  type        = bool
  default     = true
}

variable "metric_namespace" {
  description = "CloudWatch metric namespace for CIS alarms"
  type        = string
  default     = "CISBenchmark"
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}
