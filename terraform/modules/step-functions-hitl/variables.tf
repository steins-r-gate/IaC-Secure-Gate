# ==================================================================
# Step Functions HITL Module - Variables
# terraform/modules/step-functions-hitl/variables.tf
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
# Remediation Lambda ARNs (existing Phase 2 functions)
# ----------------------------------------------------------------------

variable "iam_remediation_lambda_arn" {
  description = "ARN of the IAM remediation Lambda function"
  type        = string
}

variable "s3_remediation_lambda_arn" {
  description = "ARN of the S3 remediation Lambda function"
  type        = string
}

variable "sg_remediation_lambda_arn" {
  description = "ARN of the Security Group remediation Lambda function"
  type        = string
}

# ----------------------------------------------------------------------
# Slack Notifier
# ----------------------------------------------------------------------

variable "slack_notifier_lambda_arn" {
  description = "ARN of the Slack notifier Lambda function"
  type        = string
}

# ----------------------------------------------------------------------
# DynamoDB
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
# HITL Configuration
# ----------------------------------------------------------------------

variable "approval_timeout_seconds" {
  description = "Timeout for Slack approval before auto-remediating (seconds)"
  type        = number
  default     = 14400 # 4 hours

  validation {
    condition     = var.approval_timeout_seconds >= 60 && var.approval_timeout_seconds <= 86400
    error_message = "Approval timeout must be between 60 and 86400 seconds."
  }
}

variable "auto_remediate_severity" {
  description = "Minimum severity to auto-remediate without approval (CRITICAL, HIGH, MEDIUM, LOW)"
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["CRITICAL", "HIGH", "MEDIUM", "LOW"], var.auto_remediate_severity)
    error_message = "Auto-remediate severity must be CRITICAL, HIGH, MEDIUM, or LOW."
  }
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
