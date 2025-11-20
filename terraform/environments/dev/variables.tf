# ==================================================================
# Terraform variables for the development environment
# ==================================================================

# AWS region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

# Owner email address
variable "owner_email" {
  description = "Email address of the project owner"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Must be a valid email address."
  }
}

# Alert email address
variable "alert_email" {
  description = "Email address for security alerts"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Must be a valid email address."
  }
}
