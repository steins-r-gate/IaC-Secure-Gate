# ==================================================================
# Remediation Tracking Module - Input Variables
# terraform/modules/remediation-tracking/variables.tf
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
# DynamoDB Configuration
# ----------------------------------------------------------------------

variable "table_name_suffix" {
  description = "Suffix for the DynamoDB table name"
  type        = string
  default     = "remediation-history"
}

variable "billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.billing_mode)
    error_message = "Billing mode must be PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "read_capacity" {
  description = "Read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "enable_point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_dynamodb_stream" {
  description = "Enable DynamoDB Streams for Phase 3 integration"
  type        = bool
  default     = true
}

variable "stream_view_type" {
  description = "DynamoDB Stream view type"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"

  validation {
    condition     = contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "Stream view type must be one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "ttl_enabled" {
  description = "Enable TTL for automatic item expiration"
  type        = bool
  default     = true
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute"
  type        = string
  default     = "expiration_time"
}

variable "ttl_days" {
  description = "Number of days before items expire (TTL)"
  type        = number
  default     = 90

  validation {
    condition     = var.ttl_days >= 1 && var.ttl_days <= 365
    error_message = "TTL days must be between 1 and 365."
  }
}

# ----------------------------------------------------------------------
# KMS Encryption
# ----------------------------------------------------------------------

variable "kms_key_arn" {
  description = "KMS key ARN for DynamoDB encryption (null for AWS managed key)"
  type        = string
  default     = null
}

# ----------------------------------------------------------------------
# Global Secondary Indexes
# ----------------------------------------------------------------------

variable "enable_resource_index" {
  description = "Enable GSI for querying by resource ARN"
  type        = bool
  default     = true
}

variable "enable_status_index" {
  description = "Enable GSI for querying by remediation status"
  type        = bool
  default     = true
}
