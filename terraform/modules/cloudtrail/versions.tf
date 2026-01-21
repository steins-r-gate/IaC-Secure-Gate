# ==================================================================
# CloudTrail Module - Version Constraints
# terraform/modules/cloudtrail/versions.tf
# ==================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# Data sources for auto-detection (no variables needed)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
