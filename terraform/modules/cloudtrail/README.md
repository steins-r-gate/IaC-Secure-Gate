# CloudTrail Module v2.0 - Production-Grade Edition

**Purpose:** Production-ready AWS CloudTrail configuration for comprehensive IAM activity logging and audit trail with optional CloudWatch Logs integration, SNS notifications, and CloudTrail Insights.

## What's New in v2.0

This is a **complete upgrade** from basic CloudTrail configuration to production-grade standards:

### Critical Fixes

✅ **Invalid depends_on Removed** - Removed `depends_on = [var.kms_key_id]` which caused errors (cannot depend on string variables)
✅ **Advanced Event Selectors** - Migrated from legacy `event_selector` to `advanced_event_selector` for better control and future-proofing
✅ **Variable Cleanup** - Removed unused `region` and `account_id` variables; auto-detect via data sources
✅ **Proper Dependency Handling** - Terraform automatically handles module output dependencies; no fake depends_on needed

### Production Features Added

✅ **CloudWatch Logs Integration** - Optional real-time log streaming to CloudWatch (default: off)
✅ **SNS Notifications** - Optional SNS topic for CloudTrail delivery notifications (default: off)
✅ **CloudTrail Insights** - Optional API call rate and error rate anomaly detection (default: off)
✅ **S3 Data Events** - Optional S3 object-level logging with bucket filtering (default: off)
✅ **Lambda Data Events** - Optional Lambda invocation logging (default: off)
✅ **Organization Trail Support** - Optional AWS Organizations multi-account trail (default: off)
✅ **Management Event Filtering** - Optional exclusion of noisy AWS services (e.g., KMS)

### Terraform Quality Improvements

✅ **Provider Version Constraints** - Added versions.tf with AWS provider >= 5.0.0
✅ **Data Sources** - Auto-detect account ID and region (no manual input needed)
✅ **Variable Validations** - 8+ validation rules for KMS ARN format, S3 bucket names, CloudWatch retention
✅ **Comprehensive Outputs** - 15+ outputs including CloudWatch logs, SNS topics, configuration summaries
✅ **Structured Outputs** - `cloudtrail_summary` and `event_configuration` for easy monitoring

## Quick Start

### Basic Usage (Minimal Configuration)

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "dev"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  common_tags = {
    Owner = "security-team@example.com"
  }
}
```

### Production Usage (with CloudWatch Logs)

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "prod"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Enable CloudWatch Logs for real-time analysis
  enable_cloudwatch_logs        = true
  cloudwatch_log_retention_days = 365 # 1 year

  # Enable SNS notifications
  enable_sns_notifications = true

  # CIS compliance defaults are already enabled:
  # - enable_log_file_validation = true (CIS 3.2)
  # - is_multi_region_trail = true (CIS 3.1)
  # - include_global_service_events = true (for IAM/STS)

  common_tags = {
    Owner       = "security-team@example.com"
    Environment = "prod"
    Compliance  = "CIS-AWS-Foundations"
  }
}
```

## Requirements

| Name      | Version   |
|-----------|-----------|
| terraform | >= 1.5.0  |
| aws       | >= 5.0.0  |

## Resources Created

### Default Resources (Minimal Configuration)

| Resource                 | Count | Purpose                                    |
|--------------------------|-------|--------------------------------------------|
| aws_cloudtrail           | 1     | Multi-region trail with log validation    |
| **Total**                | **1** | IAM activity logging enabled               |

### Optional Resources (When Enabled)

| Resource                        | Count | When Enabled                  | Purpose                           |
|---------------------------------|-------|-------------------------------|-----------------------------------|
| aws_cloudwatch_log_group        | 0-1   | enable_cloudwatch_logs = true | Real-time log streaming           |
| aws_iam_role                    | 0-1   | enable_cloudwatch_logs = true | CloudWatch Logs write permissions |
| aws_iam_role_policy             | 0-1   | enable_cloudwatch_logs = true | IAM policy for CloudWatch         |
| aws_sns_topic                   | 0-1   | enable_sns_notifications      | CloudTrail delivery notifications |
| aws_sns_topic_policy            | 0-1   | enable_sns_notifications      | SNS publish permissions           |
| **Total (with all features)**   | **6** |                               |                                   |

## Module Structure

```
cloudtrail/
├── versions.tf          # Provider version constraints + data sources
├── main.tf              # CloudTrail trail + optional CloudWatch/SNS
├── variables.tf         # Input variables with validations
├── outputs.tf           # Comprehensive outputs
└── README.md            # This file
```

## Required Inputs

| Name                   | Description                                     | Type     |
|------------------------|-------------------------------------------------|----------|
| environment            | Environment name (dev, staging, prod)           | `string` |
| kms_key_arn            | KMS key ARN from foundation module              | `string` |
| cloudtrail_bucket_name | S3 bucket name from foundation module           | `string` |

## Optional Inputs

### Core CloudTrail Configuration

| Name                             | Description                                  | Type   | Default |
|----------------------------------|----------------------------------------------|--------|---------|
| project_name                     | Project name for resource naming             | string | `"iam-secure-gate"` |
| enable_log_file_validation       | Enable log file integrity validation (CIS 3.2) | bool   | `true`  |
| include_global_service_events    | Include IAM/STS events                       | bool   | `true`  |
| is_multi_region_trail            | Enable multi-region trail (CIS 3.1)          | bool   | `true`  |
| is_organization_trail            | Enable organization trail                    | bool   | `false` |

### CloudWatch Logs Integration

| Name                             | Description                                  | Type   | Default |
|----------------------------------|----------------------------------------------|--------|---------|
| enable_cloudwatch_logs           | Enable CloudWatch Logs integration           | bool   | `false` |
| cloudwatch_log_retention_days    | CloudWatch retention period (1-3653 days)    | number | `90`    |

### SNS Notifications

| Name                             | Description                                  | Type   | Default |
|----------------------------------|----------------------------------------------|--------|---------|
| enable_sns_notifications         | Enable SNS topic for notifications           | bool   | `false` |

### Event Selectors

| Name                             | Description                                   | Type          | Default |
|----------------------------------|-----------------------------------------------|---------------|---------|
| exclude_management_event_sources | Exclude noisy services (e.g., `["kms.amazonaws.com"]`) | list(string)  | `[]`    |
| enable_s3_data_events            | Enable S3 object-level events                 | bool          | `false` |
| s3_data_event_bucket_arns        | S3 buckets to monitor (empty = all)           | list(string)  | `[]`    |
| enable_lambda_data_events        | Enable Lambda invocation events               | bool          | `false` |

### CloudTrail Insights

| Name                             | Description                                  | Type   | Default |
|----------------------------------|----------------------------------------------|--------|---------|
| enable_insights                  | Enable API call rate anomaly detection       | bool   | `false` |
| enable_error_rate_insights       | Enable API error rate insights               | bool   | `false` |

## Key Outputs

### Core Outputs

```hcl
module.cloudtrail.trail_arn
module.cloudtrail.trail_name
module.cloudtrail.trail_home_region
module.cloudtrail.kms_key_id
```

### CloudWatch Logs Outputs (if enabled)

```hcl
module.cloudtrail.cloudwatch_logs_group_arn
module.cloudtrail.cloudwatch_logs_group_name
module.cloudtrail.cloudwatch_logs_role_arn
```

### SNS Outputs (if enabled)

```hcl
module.cloudtrail.sns_topic_arn
module.cloudtrail.sns_topic_name
```

### Structured Summaries

```hcl
module.cloudtrail.cloudtrail_summary      # Complete config summary
module.cloudtrail.event_configuration     # Event selector summary
```

## Usage Examples

### Example 1: Minimal Configuration (Default Secure Settings)

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "dev"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name
}

# This provides:
# ✅ Multi-region trail (captures all regions)
# ✅ Log file validation enabled (CIS 3.2)
# ✅ Global service events (IAM/STS)
# ✅ Management events (all AWS API calls)
# ✅ KMS encryption
```

### Example 2: Production with CloudWatch Logs

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "prod"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Real-time log analysis
  enable_cloudwatch_logs        = true
  cloudwatch_log_retention_days = 365

  # Notifications
  enable_sns_notifications = true

  common_tags = {
    Environment = "prod"
    Criticality = "high"
  }
}
```

### Example 3: Cost Optimization (Exclude Noisy Services)

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "dev"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Reduce log volume by excluding KMS read-only events
  exclude_management_event_sources = [
    "kms.amazonaws.com"
  ]
}
```

### Example 4: S3 Data Events for Specific Buckets

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "prod"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Enable S3 object-level logging for sensitive buckets only
  enable_s3_data_events = true
  s3_data_event_bucket_arns = [
    "arn:aws:s3:::my-sensitive-data-bucket",
    "arn:aws:s3:::my-financial-records"
  ]

  common_tags = {
    Purpose = "S3-Audit-Logging"
  }
}
```

### Example 5: CloudTrail Insights for Anomaly Detection

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "prod"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Enable anomaly detection (additional cost)
  enable_insights            = true
  enable_error_rate_insights = true

  # CloudWatch for insights analysis
  enable_cloudwatch_logs        = true
  cloudwatch_log_retention_days = 90
}
```

### Example 6: Organization Trail (Multi-Account)

```hcl
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "prod"
  kms_key_arn            = module.foundation.kms_key_arn
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name

  # Organization trail (run from management account)
  is_organization_trail = true

  common_tags = {
    Scope = "AWS-Organization"
  }
}
```

## Integration with Foundation Module

The CloudTrail module **requires** the Foundation module outputs:

```hcl
# terraform/environments/dev/main.tf

# Foundation module creates KMS key and S3 bucket
module "foundation" {
  source = "../../modules/foundation"
  environment = "dev"
}

# CloudTrail module uses foundation outputs
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "dev"
  kms_key_arn            = module.foundation.kms_key_arn  # ← Use ARN, not ID
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name
}
```

**IMPORTANT:** Use `kms_key_arn` (not `kms_key_id`) from the foundation module. The CloudTrail resource requires the full ARN.

## CIS AWS Foundations Benchmark Compliance

| Control | Requirement                              | Status                  |
|---------|------------------------------------------|-------------------------|
| 3.1     | Multi-region trail enabled               | ✅ Enabled by default   |
| 3.2     | Log file validation enabled              | ✅ Enabled by default   |
| 3.3     | CloudTrail bucket not public             | ✅ Foundation module    |
| 3.4     | CloudTrail integrated with CloudWatch    | ⚙️  Optional feature    |
| 3.5     | AWS Config enabled                       | ⚙️  Separate module     |
| 3.6     | CloudTrail logs encrypted at rest        | ✅ KMS encryption       |
| 3.7     | CloudTrail logs have versioning enabled  | ✅ Foundation module    |

## Cost Considerations

### Default Configuration (Minimal Cost)

- **CloudTrail Trail**: First trail in each region is free
- **Management Events**: Included in free tier (first copy)
- **S3 Storage**: ~$0.50/month for logs (varies by activity)
- **KMS Encryption**: Minimal cost with S3 bucket keys
- **Total**: ~$0.50-$1.00/month for dev environment

### Optional Features (Additional Costs)

| Feature                  | Estimated Cost                 | When to Use                          |
|--------------------------|--------------------------------|--------------------------------------|
| CloudWatch Logs          | ~$0.50/GB ingested + storage   | Real-time analysis, alerting         |
| SNS Notifications        | ~$0.50/million notifications   | Delivery monitoring                  |
| S3 Data Events           | $0.10/100,000 events           | Sensitive bucket monitoring          |
| Lambda Data Events       | $0.10/100,000 events           | Function invocation tracking         |
| CloudTrail Insights      | $0.35/100,000 write events     | Anomaly detection, security analysis |

**Recommendation**: Start with default configuration, add CloudWatch Logs in production for alerting.

## Deployment

### Step 1: Initialize Terraform

```bash
cd terraform/modules/cloudtrail
terraform init
```

### Step 2: Validate Configuration

```bash
terraform validate
# Expected: Success! The configuration is valid.
```

### Step 3: Deploy from Environment

```bash
cd terraform/environments/dev

# Plan deployment
terraform plan

# Expected output:
# Plan: 1 to add (or 6 if CloudWatch/SNS enabled)

# Apply changes
terraform apply
```

### Step 4: Verify Trail Status

```bash
# Get trail ARN
TRAIL_ARN=$(terraform output -raw cloudtrail.trail_arn)

# Check trail status
aws cloudtrail get-trail-status --name $TRAIL_ARN

# Expected output:
# {
#     "IsLogging": true,
#     "LatestDeliveryTime": <timestamp>
# }
```

## Troubleshooting

### Issue: CloudTrail cannot write to S3 bucket

**Symptoms**: Trail shows delivery errors in AWS console

**Cause**: S3 bucket policy doesn't allow CloudTrail writes

**Solution**: Ensure foundation module bucket policy includes CloudTrail permissions (v2.0 includes this automatically)

### Issue: KMS encryption errors

**Symptoms**: Trail creation fails with KMS permission errors

**Cause**: KMS key policy doesn't allow CloudTrail usage

**Solution**: Ensure foundation module KMS policy includes CloudTrail encryption permissions (v2.0 includes encryption context validation)

### Issue: Cannot depend on foundation resources

**Symptoms**: "depends_on cannot reference string variable" error

**Solution**: Remove explicit depends_on - Terraform automatically handles module output dependencies. When you pass `module.foundation.kms_key_arn` to CloudTrail, Terraform knows to wait for foundation resources.

### Issue: CloudWatch Logs not receiving events

**Symptoms**: CloudWatch log group is empty

**Cause**: IAM role doesn't have permissions or trust relationship incorrect

**Solution**: Check that `enable_cloudwatch_logs = true` is set. The module automatically creates the IAM role and policy.

## Migration from v1.0

### Breaking Changes

1. **Variable Rename**: `kms_key_id` → `kms_key_arn` (CloudTrail requires full ARN)
2. **Removed Variables**: `region` and `account_id` (auto-detected via data sources)
3. **Event Selector**: Legacy `event_selector` → `advanced_event_selector` (CloudTrail best practice)
4. **Environment Validation**: Now accepts `dev`, `staging`, or `prod` (was `dev` or `prod`)

### Migration Steps

```hcl
# OLD (v1.0)
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment  = "dev"
  region       = "eu-west-1"        # ← REMOVE (auto-detected)
  account_id   = "123456789012"     # ← REMOVE (auto-detected)
  kms_key_id   = module.foundation.kms_key_id  # ← CHANGE to kms_key_arn
  # ...
}

# NEW (v2.0)
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  environment            = "dev"
  kms_key_arn            = module.foundation.kms_key_arn  # ← Use ARN
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name
  # ...
}
```

### Terraform State Migration

```bash
# No state migration needed - resources will be updated in-place
terraform plan  # Review changes
terraform apply # Apply updates (no recreation)
```

## Advanced Configuration

### Exclude High-Volume Services

```hcl
# Reduce costs by excluding read-heavy services
exclude_management_event_sources = [
  "kms.amazonaws.com",
  "s3.amazonaws.com"
]
```

### Lambda + S3 Data Events

```hcl
enable_lambda_data_events = true
enable_s3_data_events     = true

s3_data_event_bucket_arns = [
  "arn:aws:s3:::my-lambda-deployment-bucket"
]
```

## Security Best Practices

1. **Always enable log file validation** (default: enabled)
2. **Use multi-region trails** (default: enabled) - Captures all regions from single trail
3. **Enable CloudWatch Logs in production** - Real-time monitoring and alerting
4. **Encrypt logs with KMS** (default: enabled via foundation module)
5. **Monitor SNS notifications** - Detect delivery failures
6. **Use CloudTrail Insights** - Detect unusual API activity patterns
7. **Restrict S3 data events** - Only monitor sensitive buckets to control costs

## License

Part of the IaC-Secure-Gate project.

## Authors

- **v2.0 Production Upgrade** - Claude Sonnet 4.5 (2026-01-20)
- **v1.0 Initial Implementation** - IaC-Secure-Gate Contributors

## Support

For issues or questions, review the troubleshooting section or check the project documentation at `/docs/PHASE1.md`.
