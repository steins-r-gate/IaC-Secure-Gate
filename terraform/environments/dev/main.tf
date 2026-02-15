# ==================================================================
# Phase 1 & 2 - Development Environment
# terraform/environments/dev/main.tf
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
  project_name = "iam-secure-gate" # Keep original name for backward compatibility

  common_tags = {
    Project     = "IaC-Secure-Gate"
    Phase       = "Phase-1-2"
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

  # Retention settings (configured via variables)
  cloudtrail_log_retention_days  = var.cloudtrail_log_retention_days
  config_snapshot_retention_days = var.config_snapshot_retention_days
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

# ==================================================================
# IAM Access Analyzer Module (External Access Detection)
# No dependencies - standalone service
# ==================================================================

module "access_analyzer" {
  source = "../../modules/access-analyzer"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Analyzer configuration
  analyzer_type = "ACCOUNT" # Single account scope for Phase 1

  # Archive rule (auto-archive old findings)
  enable_archive_rule              = true
  archive_findings_older_than_days = var.archive_findings_older_than_days

  # Optional: SNS notifications (disabled by default to save costs)
  enable_sns_notifications = false
  kms_key_arn              = module.foundation.kms_key_arn # If notifications enabled
  sns_email_subscriptions  = []                            # Add emails if notifications enabled

  # No dependencies - standalone service
}

# ==================================================================
# Security Hub Module (Centralized Security Findings)
# Depends on detection services being enabled for proper integration
# ==================================================================

module "security_hub" {
  source = "../../modules/security-hub"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Standards configuration
  enable_cis_standard           = true
  cis_standard_version          = var.cis_standard_version
  enable_foundational_standard  = false   # Disabled to reduce costs (~70% fewer Config rules)
  foundational_standard_version = "1.0.0" # 200+ controls (not deployed when disabled)

  # Product integrations
  enable_config_integration          = true
  enable_access_analyzer_integration = true

  # Multi-region aggregation (disabled for Phase 1 single-region)
  enable_finding_aggregation = false

  # Optional: Disable noisy controls in dev (empty set = all enabled)
  disabled_control_ids = [
    # Example: Uncomment to disable specific controls
    # "cis-aws-foundations-benchmark/v/1.4.0/1.1", # Root account MFA
  ]

  # Optional: SNS for critical findings (disabled to save costs)
  enable_critical_finding_notifications = false
  kms_key_arn                           = module.foundation.kms_key_arn
  sns_email_subscriptions               = []

  # CRITICAL: Depends on detection services being enabled
  # Security Hub integrations require these services to be active
  depends_on = [
    module.config,
    module.access_analyzer
  ]
}

# ==================================================================
# Phase 2 Modules
# ==================================================================

# Lambda Remediation Module (Automated Fixes)
# Triggered by EventBridge when Security Hub detects violations
module "lambda_remediation" {
  source = "../../modules/lambda-remediation"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Lambda configuration
  lambda_runtime            = "python3.12"
  lambda_timeout            = 30
  lambda_memory_size        = 256
  lambda_log_retention_days = 30

  # Feature flags - all enabled
  enable_iam_remediation   = true
  enable_s3_remediation    = true
  enable_sg_remediation    = true
  enable_dead_letter_queue = true

  # DRY RUN MODE: Set to true for safe testing (logs but doesn't modify)
  # IMPORTANT: Set to false for production remediation
  dry_run_mode = false

  # KMS encryption for Lambda environment variables
  # Note: Disabled because foundation KMS key policy blocks direct Lambda decrypt
  # Environment variables contain only config (no secrets), so this is acceptable
  kms_key_arn = null

  # DynamoDB for audit trail (configured via remediation_tracking module)
  enable_dynamodb_logging = true
  dynamodb_table_name     = module.remediation_tracking.table_name
  dynamodb_table_arn      = module.remediation_tracking.table_arn

  # SNS notifications for remediation events
  enable_sns_notifications = true
  sns_topic_arn            = module.self_improvement.remediation_alerts_topic_arn

  # Depends on Security Hub for findings
  depends_on = [
    module.security_hub
  ]
}

# EventBridge Remediation Module (Routes findings to Lambdas)
# Connects Security Hub findings to appropriate Lambda functions
module "eventbridge_remediation" {
  source = "../../modules/eventbridge-remediation"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # Lambda function ARNs from the remediation module
  iam_remediation_lambda_arn = module.lambda_remediation.iam_remediation_function_arn
  s3_remediation_lambda_arn  = module.lambda_remediation.s3_remediation_function_arn
  sg_remediation_lambda_arn  = module.lambda_remediation.sg_remediation_function_arn

  # Enable all rules
  enable_iam_rule = true
  enable_s3_rule  = true
  enable_sg_rule  = true

  # Retry configuration
  retry_attempts            = 2
  maximum_event_age_seconds = 3600 # 1 hour

  depends_on = [
    module.lambda_remediation
  ]
}

# Remediation Tracking Module (DynamoDB for audit trail)
# Stores all remediation actions for analytics and compliance
module "remediation_tracking" {
  source = "../../modules/remediation-tracking"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # DynamoDB configuration
  billing_mode                  = "PAY_PER_REQUEST" # Cost-effective for variable workloads
  enable_point_in_time_recovery = true              # Data protection
  enable_dynamodb_stream        = true              # For Phase 3 real-time processing

  # TTL for automatic cleanup (90 days)
  ttl_enabled = true
  ttl_days    = 90

  # Global Secondary Indexes for efficient queries
  enable_resource_index = true # Query by resource ARN
  enable_status_index   = true # Query by remediation status

  # Use AWS managed encryption (free)
  kms_key_arn = null
}

# Self-Improvement Module (SNS Notifications + Analytics)
# Provides alerting and daily analytics reports
module "self_improvement" {
  source = "../../modules/self-improvement"

  environment  = local.environment
  project_name = local.project_name
  common_tags  = local.common_tags

  # SNS Topics - all enabled
  enable_remediation_alerts   = true
  enable_analytics_reports    = true
  enable_manual_review_alerts = true

  # Email subscriptions (will require confirmation)
  alert_email_subscriptions = [var.owner_email]

  # Analytics Lambda configuration
  enable_analytics_lambda   = true
  analytics_schedule        = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
  analytics_lambda_timeout  = 60
  analytics_lambda_memory   = 256
  lambda_log_retention_days = 30

  # DynamoDB connection for analytics queries
  dynamodb_table_name = module.remediation_tracking.table_name
  dynamodb_table_arn  = module.remediation_tracking.table_arn

  # Use AWS managed encryption for SNS
  kms_key_arn = null

  depends_on = [
    module.remediation_tracking
  ]
}
