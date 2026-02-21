# ==================================================================
# Slack Integration Module - Variables
# terraform/modules/slack-integration/variables.tf
# ==================================================================

# ----------------------------------------------------------------------
# Core Configuration
# ----------------------------------------------------------------------

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
  default     = "iac-secure-gate"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------
# Slack Configuration
# ----------------------------------------------------------------------

variable "slack_bot_token" {
  description = "Slack Bot User OAuth Token (xoxb-...)"
  type        = string
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Slack app signing secret for request verification"
  type        = string
  sensitive   = true
}

variable "slack_channel_id" {
  description = "Slack channel ID to send notifications to"
  type        = string

  validation {
    condition     = can(regex("^C[A-Z0-9]+$", var.slack_channel_id))
    error_message = "Slack channel ID must start with C followed by alphanumeric characters."
  }
}

# ----------------------------------------------------------------------
# DynamoDB Configuration (for CI gate approvals)
# ----------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "Name of the remediation tracking DynamoDB table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the remediation tracking DynamoDB table"
  type        = string
}

# ----------------------------------------------------------------------
# Lambda Configuration
# ----------------------------------------------------------------------

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "lambda_source_path" {
  description = "Relative path to Lambda source files"
  type        = string
  default     = "../../../lambda/src"
}
