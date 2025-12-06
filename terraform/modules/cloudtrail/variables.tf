# ==================================================================
# CloudTrail Module Variables
# terraform/modules/cloudtrail/variables.tf
# ==================================================================

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  
  validation {
    condition     = can(regex("^(dev|prod)$", var.environment))
    error_message = "Environment must be dev or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "iam-secure-gate"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-west-1"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Foundation module outputs (required)
variable "kms_key_id" {
  description = "KMS key ID from foundation module for log encryption"
  type        = string
}

variable "cloudtrail_bucket_name" {
  description = "S3 bucket name from foundation module for CloudTrail logs"
  type        = string
}

# CloudTrail configuration
variable "enable_log_file_validation" {
  description = "Enable log file integrity validation"
  type        = bool
  default     = true
}

variable "include_global_service_events" {
  description = "Include global service events (IAM, STS, etc.)"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Enable multi-region trail (captures events from all regions)"
  type        = bool
  default     = true
}
