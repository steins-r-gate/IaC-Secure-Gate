# ==================================================================
# Phase 1 - Development Environment
# terraform/environments/dev/main.tf
# ==================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Configure AWS Provider for eu-west-1
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ==================================================================
# Data Sources
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==================================================================
# Local Variables
# ==================================================================

locals {
  environment  = "dev"
  project_name = "iam-secure-gate"

  common_tags = {
    Project     = "IAM-Secure-Gate"
    Phase       = "Phase-1-Detection"
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
    Region      = var.aws_region
  }
}

# ==================================================================
# Phase 1 Modules
# ==================================================================

# Foundation Module (KMS + S3 Buckets)
module "foundation" {
  source = "../../modules/foundation"

  environment  = local.environment
  project_name = local.project_name
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  common_tags  = local.common_tags

  # Retention settings (can override defaults)
  cloudtrail_log_retention_days  = 90  # CIS requirement
  config_snapshot_retention_days = 365 # Annual compliance
}
