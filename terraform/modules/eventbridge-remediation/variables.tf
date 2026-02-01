# ==================================================================
# EventBridge Remediation Module - Variables
# terraform/modules/eventbridge-remediation/variables.tf
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
# Lambda Target ARNs
# ==================================================================

variable "iam_remediation_lambda_arn" {
  description = "ARN of the IAM remediation Lambda function"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:.+$", var.iam_remediation_lambda_arn))
    error_message = "Must be a valid Lambda function ARN."
  }
}

variable "s3_remediation_lambda_arn" {
  description = "ARN of the S3 remediation Lambda function"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:.+$", var.s3_remediation_lambda_arn))
    error_message = "Must be a valid Lambda function ARN."
  }
}

variable "sg_remediation_lambda_arn" {
  description = "ARN of the Security Group remediation Lambda function"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:.+$", var.sg_remediation_lambda_arn))
    error_message = "Must be a valid Lambda function ARN."
  }
}

# ==================================================================
# Feature Flags
# ==================================================================

variable "enable_iam_rule" {
  description = "Enable EventBridge rule for IAM wildcard findings"
  type        = bool
  default     = true
}

variable "enable_s3_rule" {
  description = "Enable EventBridge rule for S3 public bucket findings"
  type        = bool
  default     = true
}

variable "enable_sg_rule" {
  description = "Enable EventBridge rule for Security Group findings"
  type        = bool
  default     = true
}

# ==================================================================
# Retry Configuration
# ==================================================================

variable "retry_attempts" {
  description = "Number of retry attempts for failed Lambda invocations"
  type        = number
  default     = 2

  validation {
    condition     = var.retry_attempts >= 0 && var.retry_attempts <= 185
    error_message = "Retry attempts must be between 0 and 185."
  }
}

variable "maximum_event_age_seconds" {
  description = "Maximum age of event before discarding (seconds)"
  type        = number
  default     = 3600 # 1 hour

  validation {
    condition     = var.maximum_event_age_seconds >= 60 && var.maximum_event_age_seconds <= 86400
    error_message = "Maximum event age must be between 60 and 86400 seconds."
  }
}
