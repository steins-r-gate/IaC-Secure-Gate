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
  common_tags  = local.common_tags

  # Retention settings (can override defaults)
  cloudtrail_log_retention_days  = 90  # CIS requirement
  config_snapshot_retention_days = 365 # Annual compliance
}

# CloudTrail Module (Audit Logging)
# Depends on foundation S3 bucket policy and KMS key policy being ready
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Foundation module outputs (corrected identifiers)
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # CloudTrail configuration (CIS AWS Foundations Benchmark)
  enable_log_file_validation    = true # CIS 3.2
  is_multi_region_trail         = true # CIS 3.1
  include_global_service_events = true # Capture IAM events in home region

  # Optional features (disabled by default to minimize costs in dev)
  enable_cloudwatch_logs    = false
  enable_sns_notifications  = false
  enable_insights           = false
  enable_s3_data_events     = false
  enable_lambda_data_events = false

  # Explicit dependency: CloudTrail requires foundation bucket policy ready
  # Module outputs automatically create implicit dependencies, but adding
  # explicit dependency on bucket policy for determinism
  depends_on = [
    module.foundation
  ]
}

# AWS Config Module (Configuration Compliance)
# Depends on foundation S3 bucket policy and KMS key policy being ready
module "config" {
  source = "../../modules/config"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Foundation module outputs
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn

  # Config recorder settings
  is_primary_region             = true # Record global resources (IAM, etc.) in this region
  include_global_resource_types = true # Explicitly record IAM, CloudFront, Route53, etc.
  snapshot_delivery_frequency   = "TwentyFour_Hours"

  # Config rules (CIS AWS Foundations Benchmark)
  enable_config_rules = true # Deploy 8 managed rules for CIS compliance

  # Optional features (disabled by default to minimize costs in dev)
  enable_sns_notifications = false

  # Explicit dependency: Config requires foundation bucket policy + KMS policy ready
  depends_on = [
    module.foundation
  ]
}
