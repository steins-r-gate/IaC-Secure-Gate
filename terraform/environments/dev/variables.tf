# ==================================================================
# Terraform variables for the development environment
# terraform/environments/dev/variables.tf
# ==================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

variable "owner_email" {
  description = "Email address of the project owner"
  type        = string
  default     = "demo@example.com" # Default for easy demo

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Must be a valid email address."
  }
}
