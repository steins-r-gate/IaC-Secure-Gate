# ==================================================================
# Lambda Remediation Module - Provider Configuration
# terraform/modules/lambda-remediation/versions.tf
# ==================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# ==================================================================
# Data Sources (Auto-detect account and region)
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
