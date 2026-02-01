# ==================================================================
# EventBridge Remediation Module - Provider Configuration
# terraform/modules/eventbridge-remediation/versions.tf
# ==================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ==================================================================
# Data Sources
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
