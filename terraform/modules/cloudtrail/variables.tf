# ==================================================================
# CloudTrail Module Variables
# terraform/modules/cloudtrail/variables.tf
# ==================================================================

# ==================================================================
# Required Variables
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

# Foundation module outputs (required)
variable "kms_key_arn" {
  description = "KMS key ARN from foundation module for log encryption"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "KMS key ARN must be a valid AWS KMS key ARN."
  }
}

variable "cloudtrail_bucket_name" {
  description = "S3 bucket name from foundation module for CloudTrail logs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.cloudtrail_bucket_name))
    error_message = "S3 bucket name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# ==================================================================
# Optional Variables - Common Tags
# ==================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==================================================================
# CloudTrail Core Configuration
# ==================================================================

variable "enable_log_file_validation" {
  description = "Enable log file integrity validation (CIS 3.2)"
  type        = bool
  default     = true
}

variable "include_global_service_events" {
  description = "Include global service events (IAM, STS, etc.) - Required for IAM logging"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Enable multi-region trail (CIS 3.1) - Captures events from all regions"
  type        = bool
  default     = true
}

variable "is_organization_trail" {
  description = "Enable organization trail (requires AWS Organizations)"
  type        = bool
  default     = false
}

# ==================================================================
# CloudWatch Logs Integration (Optional)
# ==================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs integration for real-time analysis"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 90

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period (1, 3, 5, 7, 14, 30, 60, 90, etc.)."
  }
}

# ==================================================================
# SNS Notifications (Optional)
# ==================================================================

variable "enable_sns_notifications" {
  description = "Enable SNS topic for CloudTrail notifications"
  type        = bool
  default     = false
}

# ==================================================================
# Advanced Event Selectors
# ==================================================================

variable "exclude_management_event_sources" {
  description = "List of AWS service event sources to exclude from management events (e.g., ['kms.amazonaws.com'])"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for source in var.exclude_management_event_sources :
      can(regex("^[a-z0-9-]+\\.amazonaws\\.com$", source))
    ])
    error_message = "Event sources must be valid AWS service domains (e.g., 'kms.amazonaws.com')."
  }
}

# ==================================================================
# Data Events (Optional - Increases Costs)
# ==================================================================

variable "enable_s3_data_events" {
  description = "Enable S3 object-level data events (GetObject, PutObject, DeleteObject)"
  type        = bool
  default     = false
}

variable "s3_data_event_bucket_arns" {
  description = "List of S3 bucket ARNs to monitor for data events (empty = all buckets)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.s3_data_event_bucket_arns :
      can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", arn))
    ])
    error_message = "S3 bucket ARNs must be valid (format: arn:aws:s3:::bucket-name)."
  }
}

variable "enable_lambda_data_events" {
  description = "Enable Lambda function invocation data events"
  type        = bool
  default     = false
}

# ==================================================================
# CloudTrail Insights (Optional - Additional Costs)
# ==================================================================

variable "enable_insights" {
  description = "Enable CloudTrail Insights for API call rate anomaly detection"
  type        = bool
  default     = false
}

variable "enable_error_rate_insights" {
  description = "Enable API error rate insights (requires enable_insights = true)"
  type        = bool
  default     = false
}
