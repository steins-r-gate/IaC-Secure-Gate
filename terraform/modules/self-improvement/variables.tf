# ==================================================================
# Self-Improvement Module - Input Variables
# terraform/modules/self-improvement/variables.tf
# ==================================================================

# ----------------------------------------------------------------------
# Required Variables
# ----------------------------------------------------------------------

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------
# SNS Configuration
# ----------------------------------------------------------------------

variable "enable_remediation_alerts" {
  description = "Enable SNS topic for immediate remediation alerts"
  type        = bool
  default     = true
}

variable "enable_analytics_reports" {
  description = "Enable SNS topic for daily analytics reports"
  type        = bool
  default     = true
}

variable "enable_manual_review_alerts" {
  description = "Enable SNS topic for failed remediations requiring manual review"
  type        = bool
  default     = true
}

variable "alert_email_subscriptions" {
  description = "List of email addresses to subscribe to alert topics"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.alert_email_subscriptions : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid email format."
  }
}

# ----------------------------------------------------------------------
# KMS Configuration
# ----------------------------------------------------------------------

variable "kms_key_arn" {
  description = "KMS key ARN for SNS encryption (null for AWS managed key)"
  type        = string
  default     = null
}

# ----------------------------------------------------------------------
# Analytics Configuration
# ----------------------------------------------------------------------

variable "enable_analytics_lambda" {
  description = "Enable analytics Lambda function"
  type        = bool
  default     = true
}

variable "analytics_schedule" {
  description = "CloudWatch Events schedule expression for analytics (cron or rate)"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
}

variable "analytics_lambda_timeout" {
  description = "Analytics Lambda timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.analytics_lambda_timeout >= 3 && var.analytics_lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "analytics_lambda_memory" {
  description = "Analytics Lambda memory in MB"
  type        = number
  default     = 256
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Log retention in days"
  type        = number
  default     = 30
}

# ----------------------------------------------------------------------
# DynamoDB Configuration (for analytics queries)
# ----------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "DynamoDB table name for remediation history"
  type        = string
  default     = ""
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for remediation history"
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------
# S3 Configuration (for analytics reports)
# ----------------------------------------------------------------------

variable "reports_bucket_name" {
  description = "S3 bucket name for storing analytics reports (optional)"
  type        = string
  default     = ""
}

variable "reports_bucket_arn" {
  description = "S3 bucket ARN for storing analytics reports (optional)"
  type        = string
  default     = ""
}
