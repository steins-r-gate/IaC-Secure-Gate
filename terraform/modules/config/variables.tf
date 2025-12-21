# ==================================================================
# AWS Config Module Variables
# terraform/modules/config/variables.tf
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
variable "config_bucket_name" {
  description = "S3 bucket name from foundation module for Config snapshots"
  type        = string
}

variable "config_bucket_arn" {
  description = "S3 bucket ARN from foundation module for Config snapshots"
  type        = string
}
