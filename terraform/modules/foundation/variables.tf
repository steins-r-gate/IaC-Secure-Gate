# ==================================================================
# Foundation Module Variables
# terraform/modules/foundation/variables.tf
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

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-west-1"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# CloudTrail retention settings
variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in S3"
  type        = number
  default     = 90
}

# Config retention settings
variable "config_snapshot_retention_days" {
  description = "Number of days to retain Config snapshots in S3"
  type        = number
  default     = 365
}
