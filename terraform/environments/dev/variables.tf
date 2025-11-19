variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

variable "owner_email" {
  description = "Email address of the project owner"
  type        = string
}

variable "alert_email" {
  description = "Email address for security alerts"
  type        = string
}
