# ==================================================================
# Main Terraform configuration for the dev environment
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

  # Local backend (state stored in current directory)
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Configure the AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Data sources to get current AWS account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  project_name = "IAM-Secure-Gate"
  environment  = "dev"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner_email
  }
}

# S3 Module
module "s3" {
  source = "../../modules/s3"

  environment = local.environment
  common_tags = local.common_tags
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
}
