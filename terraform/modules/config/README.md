# AWS Config Terraform Module (v2.0)

Production-grade AWS Config module with least-privilege IAM, correct dependency ordering, and multi-region support.

> **Upgrade Note:** This is v2.0 with significant security and correctness improvements. See [UPGRADE_GUIDE.md](UPGRADE_GUIDE.md) for migration from v1.0.

## Features

- **Secure by Default**: Least-privilege IAM policies, S3 encryption support, SNS encryption
- **Deterministic**: Correct resource ordering prevents flaky applies and startup failures
- **Multi-Region Ready**: Conditional global resource recording prevents duplication
- **CIS Compliant**: 8 default Config rules for CIS AWS Foundations Benchmark
- **Maintainable**: for_each pattern for rules, modular file structure, variable validations
- **Flexible**: Customizable rules, optional SNS notifications, configurable delivery frequency

## Quick Start

```hcl
module "config" {
  source = "../../modules/config"

  environment  = "prod"
  project_name = "my-project"

  # S3 bucket for Config snapshots (from foundation module)
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn  # Required if bucket uses KMS

  # Multi-environment isolation
  s3_key_prefix = "AWSLogs/prod"

  # Multi-region setup
  is_primary_region = true  # Set to false in secondary regions

  common_tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Resources Created

| Resource Type | Count | Purpose |
|---------------|-------|---------|
| IAM Role | 1 | Config service role |
| IAM Policies | 2-3 | S3 + optional KMS permissions |
| Config Recorder | 1 | Captures resource configurations |
| Delivery Channel | 1 | Sends snapshots to S3 |
| Recorder Status | 1 | Starts the recorder |
| Config Rules | 8 (default) | CIS compliance checks |
| SNS Topic | 0-1 | Optional notifications |
| **Total** | **14-15** | **All free tier eligible** |

## Default CIS Config Rules

The module deploys 8 CIS AWS Foundations Benchmark rules by default:

1. **root-account-mfa-enabled** (CIS 1.5) - Root account MFA verification
2. **iam-password-policy** (CIS 1.8-1.11) - Password policy compliance (14 chars, complexity, rotation)
3. **access-keys-rotated** (CIS 1.14) - Access key rotation check (90 days)
4. **iam-user-mfa-enabled** (CIS 1.10) - IAM user MFA for console access
5. **cloudtrail-enabled** (CIS 3.1) - CloudTrail enabled in all regions
6. **cloudtrail-log-file-validation-enabled** (CIS 3.2) - CloudTrail log file validation
7. **s3-bucket-public-read-prohibited** (CIS 2.3.1) - S3 public read access blocked
8. **s3-bucket-public-write-prohibited** (CIS 2.3.1) - S3 public write access blocked

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| environment | Environment name (dev, staging, prod) | `string` |
| config_bucket_name | S3 bucket name for Config snapshots | `string` |
| config_bucket_arn | S3 bucket ARN for Config snapshots | `string` |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| project_name | Project name for resource naming | `string` | `"iam-secure-gate"` |
| config_bucket_kms_key_arn | KMS key ARN for S3 encryption (**required if bucket uses SSE-KMS**) | `string` | `null` |
| s3_key_prefix | S3 key prefix for Config snapshots | `string` | `"AWSLogs"` |
| is_primary_region | Whether this is the primary region for global resources | `bool` | `true` |
| include_global_resource_types | Override for global resource recording (null = use is_primary_region) | `bool` | `null` |
| snapshot_delivery_frequency | Frequency of Config snapshots (One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours) | `string` | `"TwentyFour_Hours"` |
| enable_config_rules | Whether to deploy Config rules | `bool` | `true` |
| config_rules | Custom Config rules map (null = use defaults) | `map(object)` | `null` |
| enable_sns_notifications | Whether to create SNS topic for notifications | `bool` | `false` |
| sns_topic_arn | Existing SNS topic ARN for notifications | `string` | `null` |
| common_tags | Tags to apply to all resources | `map(string)` | `{}` |

## Outputs

### Core Outputs

| Name | Description |
|------|-------------|
| config_recorder_id | Config recorder ID |
| config_recorder_name | Config recorder name |
| config_recorder_arn | Config recorder ARN |
| delivery_channel_id | Delivery channel ID |
| recorder_status_enabled | Whether recorder is enabled |
| config_role_arn | IAM role ARN |
| config_rules | Map of deployed rules (name, id, arn) |
| config_rules_count | Number of rules deployed |

### Advanced Outputs

| Name | Description |
|------|-------------|
| configuration_summary | Complete deployment summary object |
| recorder_status_id | For depends_on in other modules |
| sns_topic_arn | SNS topic ARN (if enabled) |
| sns_topic_name | SNS topic name (if enabled) |

## Usage Examples

### Basic Usage (Single Region)

```hcl
module "config" {
  source = "../../modules/config"

  environment               = "dev"
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn
}
```

### Multi-Region Deployment

```hcl
# Primary region (us-east-1) - records global resources
module "config_primary" {
  source = "../../modules/config"
  providers = { aws = aws.us_east_1 }

  environment               = "prod"
  is_primary_region         = true  # Records IAM, CloudFront, etc.
  s3_key_prefix             = "AWSLogs/us-east-1"
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn
}

# Secondary region (eu-west-1) - skips global resources
module "config_secondary" {
  source = "../../modules/config"
  providers = { aws = aws.eu_west_1 }

  environment               = "prod"
  is_primary_region         = false  # Only regional resources
  s3_key_prefix             = "AWSLogs/eu-west-1"
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn
}
```

### Custom Config Rules

```hcl
module "config" {
  source = "../../modules/config"

  environment               = "prod"
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn

  # Override default rules with custom set
  config_rules = {
    root-account-mfa-enabled = {
      description       = "Checks whether MFA is enabled for root user"
      source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
      input_parameters  = {}
    }
    encrypted-volumes = {
      description       = "Checks whether EBS volumes are encrypted"
      source_identifier = "ENCRYPTED_VOLUMES"
      input_parameters  = {}
    }
  }
}
```

### With SNS Notifications

```hcl
module "config" {
  source = "../../modules/config"

  environment               = "prod"
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn

  # Enable SNS notifications
  enable_sns_notifications = true
}

# Subscribe to notifications
resource "aws_sns_topic_subscription" "config_email" {
  topic_arn = module.config.sns_topic_arn
  protocol  = "email"
  endpoint  = "security-team@example.com"
}
```

## Security Features

### Least-Privilege IAM

- **Separated permissions**: Bucket-level (`s3:GetBucketVersioning`, `s3:ListBucket`) and object-level (`s3:PutObject`) actions in separate statements
- **S3 prefix scoping**: PutObject restricted to `s3_key_prefix` path only
- **Removed unnecessary permissions**: No `s3:GetObject` (Config only writes, never reads)
- **ACL enforcement**: Requires `bucket-owner-full-control` ACL on PutObject to prevent permission issues

### KMS Encryption Support

- **Automatic KMS permissions**: When `config_bucket_kms_key_arn` is provided
- **Required permissions**: `kms:Decrypt` and `kms:GenerateDataKey` for SSE-KMS buckets
- **SNS encryption**: Optional SNS topic uses same KMS key

### Multi-Environment Isolation

- **S3 key prefix**: Each environment writes to separate path (e.g., `AWSLogs/dev`, `AWSLogs/prod`)
- **Resource naming**: Environment-scoped names prevent collisions
- **Tag isolation**: Environment tags on all resources for cost allocation

## Dependency Ordering

The module ensures correct AWS Config startup sequence:

```
1. IAM Role + All Policies attached
   ↓
2. Config Recorder created (with role)
   ↓
3. Delivery Channel created (references recorder)
   ↓
4. Recorder Status enabled (starts recording) ← depends on delivery channel + all IAM policies
   ↓
5. Config Rules deployed ← depend on recorder status (enabled state)
```

**Critical Fix from v1.0:** Delivery channel must exist BEFORE starting recorder (was inverted in v1.0).

## Multi-Region Considerations

### Global Resource Duplication

AWS Config can record global resources (IAM, CloudFront, Route53, WAF) in any region. Deploying to multiple regions with `include_global_resource_types = true` causes:

- Duplicate recording of same global resources
- Increased costs (counted multiple times)
- Potential Config service conflicts

### Solution

Set `is_primary_region = true` in **ONE region only**:

```hcl
# Primary region - records everything
module "config_us_east_1" {
  is_primary_region = true  # IAM + regional resources
}

# Secondary regions - skip global resources
module "config_eu_west_1" {
  is_primary_region = false  # Regional resources only
}
```

## Cost Estimate

**AWS Config Free Tier:**
- First 1,000 configuration items recorded per month: **FREE**
- First 100,000 rule evaluations per month: **FREE**

**Typical Phase 1 usage:**
- ~50-100 configuration items (IAM users, roles, S3 buckets, CloudTrail)
- ~8 rules × ~50 resources = ~400 evaluations/month
- **Monthly cost: €0.00** (well within free tier)

**Beyond free tier:**
- Additional configuration items: $0.003 each
- Additional rule evaluations: $0.001 per 10 evaluations

## Deployment Steps

### 1. Update Foundation Module

Add KMS key ARN output to foundation module (if not already present):

```hcl
# terraform/modules/foundation/outputs.tf

output "kms_key_arn" {
  description = "ARN of the KMS key for log encryption"
  value       = aws_kms_key.logs.arn
}
```

### 2. Add Config Module to Environment

```hcl
# terraform/environments/dev/main.tf

module "config" {
  source = "../../modules/config"

  environment               = local.environment
  project_name              = local.project_name
  config_bucket_name        = module.foundation.config_bucket_name
  config_bucket_arn         = module.foundation.config_bucket_arn
  config_bucket_kms_key_arn = module.foundation.kms_key_arn  # NEW - required
  common_tags               = local.common_tags

  # Optional: Environment-specific S3 prefix
  s3_key_prefix = "AWSLogs/${local.environment}"
}
```

### 3. Validate and Deploy

```bash
cd terraform/environments/dev

# Initialize and validate
terraform init
terraform validate

# Plan changes
terraform plan -out=tfplan

# Review plan (should show ~14-15 resources to add)
# Apply changes
terraform apply tfplan
```

### 4. Verify Deployment

```bash
# Check recorder status
aws configservice describe-configuration-recorder-status \
  --configuration-recorder-names $(terraform output -raw config_recorder_name)

# List Config rules
aws configservice describe-config-rules \
  --query 'ConfigRules[].ConfigRuleName' \
  --output table

# Check S3 bucket for snapshots (after 15 minutes)
aws s3 ls s3://$(terraform output -raw config_bucket_name)/AWSLogs/ --recursive
```

## Troubleshooting

### "InsufficientDeliveryPolicyException"

**Cause:** S3 bucket policy doesn't allow Config to write.

**Fix:** Ensure foundation module's S3 bucket policy includes Config service permissions (statement with `config.amazonaws.com` principal).

### "AccessDenied" on S3 PutObject

**Cause:** Missing KMS permissions.

**Fix:** Provide `config_bucket_kms_key_arn` variable if bucket uses SSE-KMS encryption.

### Rules show "No configuration recorder available"

**Cause:** Rules created before recorder started (old v1.0 behavior).

**Fix:** Module now ensures rules depend on `recorder_status` (not just recorder resource). This is fixed in v2.0.

### Duplicate global resource recording

**Cause:** `include_global_resource_types = true` in multiple regions.

**Fix:** Set `is_primary_region = false` in secondary regions.

### Rules show "Evaluating..." for extended period

**Cause:** Normal behavior. Initial rule evaluation takes 10-15 minutes after recorder starts.

**Fix:** Wait 15-20 minutes, then check compliance status again.

## File Structure

```
terraform/modules/config/
├── versions.tf          # Provider version constraints
├── variables.tf         # Input variables with validations (226 lines)
├── iam.tf              # IAM role and policies (115 lines)
├── main.tf             # Recorder, delivery channel, SNS (134 lines)
├── rules.tf            # Config rules with for_each (90 lines)
├── outputs.tf          # Module outputs (128 lines)
├── README.md           # This file
└── UPGRADE_GUIDE.md    # Detailed v1.0 → v2.0 migration guide
```

## Version History

- **v2.0.0** (2026-01-19) - Production-grade refactor
  - Fixed critical dependency ordering bug (delivery channel)
  - Added least-privilege IAM with KMS support
  - Added multi-region global resource controls
  - Refactored rules to use for_each pattern
  - Added variable validations and enhanced outputs
  - Added optional SNS notifications
  - Modularized file structure (6 files)

- **v1.0.0** (Previous) - Initial implementation
  - Basic Config recorder and delivery channel
  - 8 hardcoded CIS compliance rules
  - Single-file structure (240 lines)
  - Missing KMS permissions
  - Inverted delivery channel dependency

## Upgrade from v1.0

See [UPGRADE_GUIDE.md](UPGRADE_GUIDE.md) for comprehensive migration instructions.

**Quick summary:**
1. Add `config_bucket_kms_key_arn` variable (required for KMS-encrypted buckets)
2. Optionally add `s3_key_prefix` for multi-environment isolation
3. Remove deprecated `account_id` and `region` variables (auto-detected)
4. Run `terraform plan` to review changes (rules will be recreated due to for_each)
5. Apply changes

## License

Part of the IaC-Secure-Gate project.

## Authors

- Production-grade refactoring: Claude Sonnet 4.5 (2026-01-19)
- Original implementation: IaC-Secure-Gate contributors
