# ==================================================================
# terraform/modules/s3/variables.tf
# ==================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

# ============================================================================
# Optional Configuration (for future expansion)
# ============================================================================

# Uncomment when expanding beyond demo:

# variable "cloudtrail_log_retention_days" {
#   description = "Number of days to retain CloudTrail logs"
#   type        = number
#   default     = 365
# }
# 
# variable "enable_kms_encryption" {
#   description = "Use KMS encryption instead of AES256"
#   type        = bool
#   default     = false
# }
