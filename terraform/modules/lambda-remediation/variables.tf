# ==================================================================
# Lambda Remediation Module - Variables
# terraform/modules/lambda-remediation/variables.tf
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
  default     = "iac-secure-gate"

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
# Lambda Configuration
# ==================================================================

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.12"

  validation {
    condition     = can(regex("^python3\\.(9|10|11|12)$", var.lambda_runtime))
    error_message = "Lambda runtime must be python3.9, python3.10, python3.11, or python3.12."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Log retention in days for Lambda logs"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention value."
  }
}

# ==================================================================
# DynamoDB Configuration (State Tracking)
# ==================================================================

variable "dynamodb_table_name" {
  description = "DynamoDB table name for remediation tracking"
  type        = string
  default     = ""
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for remediation tracking"
  type        = string
  default     = ""

  validation {
    condition     = var.dynamodb_table_arn == "" || can(regex("^arn:aws:dynamodb:[a-z0-9-]+:[0-9]{12}:table/[a-zA-Z0-9_.-]+$", var.dynamodb_table_arn))
    error_message = "Must be a valid DynamoDB table ARN or empty string."
  }
}

# ==================================================================
# SNS Configuration (Notifications)
# ==================================================================

variable "sns_topic_arn" {
  description = "SNS topic ARN for remediation notifications"
  type        = string
  default     = ""

  validation {
    condition     = var.sns_topic_arn == "" || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]+$", var.sns_topic_arn))
    error_message = "Must be a valid SNS topic ARN or empty string."
  }
}

# ==================================================================
# KMS Configuration
# ==================================================================

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Lambda environment variables"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "Must be a valid KMS key ARN or null."
  }
}

# ==================================================================
# Lambda Source Path
# ==================================================================

variable "lambda_source_path" {
  description = "Path to Lambda source code directory"
  type        = string
  default     = "../../../lambda/src"
}

# ==================================================================
# Feature Flags
# ==================================================================

variable "enable_iam_remediation" {
  description = "Enable IAM policy wildcard remediation Lambda"
  type        = bool
  default     = true
}

variable "enable_s3_remediation" {
  description = "Enable S3 public access remediation Lambda"
  type        = bool
  default     = true
}

variable "enable_sg_remediation" {
  description = "Enable Security Group remediation Lambda"
  type        = bool
  default     = true
}

variable "enable_dead_letter_queue" {
  description = "Enable SQS Dead Letter Queue for failed Lambda invocations"
  type        = bool
  default     = true
}

# ==================================================================
# Dry Run Mode (Safety)
# ==================================================================

variable "dry_run_mode" {
  description = "When true, Lambdas will log actions but not make changes (safe testing)"
  type        = bool
  default     = false
}
