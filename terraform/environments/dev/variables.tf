# ==================================================================
# Phase 1 - Development Environment Variables
# terraform/environments/dev/variables.tf
# ==================================================================

variable "aws_region" {
  description = "AWS region for Phase 1 deployment"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "Phase 1 is configured for eu-west-1 only."
  }
}

variable "owner_email" {
  description = "Email address of the project owner (for tagging)"
  type        = string
  default     = "demo@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Must be a valid email address."
  }
}
