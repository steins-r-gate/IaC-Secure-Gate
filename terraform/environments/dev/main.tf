terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend will be configured separately
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  project_name = "iam-security"
  environment  = "dev"
  
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
    CreatedDate = timestamp()
  }
}

# S3 Buckets
module "s3" {
  source = "../../modules/s3"

  environment = local.environment
  common_tags = local.common_tags
}
