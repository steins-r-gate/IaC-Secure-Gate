# Foundation Module v2.0 - Production-Grade Edition

**Purpose:** Secure encryption and storage infrastructure for AWS CloudTrail and Config logs with CIS AWS Foundations Benchmark compliance.

## What's New in v2.0

This is a **complete security and correctness refactor** of the foundation module. All major security gaps, policy misconfigurations, and Terraform anti-patterns have been fixed.

### Critical Security Fixes

✅ **KMS Key Policy** - Added encryption context validation, ViaService conditions, and cross-account protection
✅ **S3 Bucket Policies** - Added SourceAccount/SourceArn conditions, denied unencrypted uploads, enforced correct KMS key
✅ **ACL Compatibility** - Removed conflicting ACL conditions (BucketOwnerEnforced disables ACLs)
✅ **Lifecycle Management** - Added noncurrent version cleanup and delete marker removal (prevents unbounded costs)
✅ **Resource Dependencies** - Fixed encryption config timing issues and policy application order

### Architecture Improvements

✅ **Modular File Structure** - Split into 7 logical files (vs. 1 monolithic 349-line file)
✅ **No Hardcoding** - Uses data sources for account_id/region (removes variables)
✅ **Policy Documents** - Uses `aws_iam_policy_document` to prevent JSON drift
✅ **Variable Validations** - 15+ validation rules with cross-checks
✅ **Comprehensive Outputs** - Added structured outputs with security status

## Quick Start

```hcl
module "foundation" {
  source = "../../modules/foundation"

  environment  = "dev"
  project_name = "iam-secure-gate"

  common_tags = {
    Owner     = "security-team@example.com"
    ManagedBy = "Terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Resources Created

| Resource | Count | Purpose |
|----------|-------|---------|
| KMS Key + Alias + Policy | 3 | Customer-managed encryption key with rotation |
| CloudTrail S3 Bucket + Config | 7-9 | Versioned, encrypted, lifecycle-managed storage |
| Config S3 Bucket + Config | 7-9 | Versioned, encrypted, lifecycle-managed storage |
| **Total** | **17-21** | Depends on optional features |

## Module Structure

```
foundation/
├── versions.tf          # Terraform/provider version constraints
├── locals.tf            # Data sources + computed values
├── kms.tf               # KMS key with least-privilege policy
├── s3_cloudtrail.tf     # CloudTrail bucket (secure by default)
├── s3_config.tf         # Config bucket (secure by default)
├── variables.tf         # Input variables with validations
├── outputs.tf           # Comprehensive outputs
└── README.md            # This file
```

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| environment | Environment name (dev, staging, prod) | `string` |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| project_name | Project name for resource naming | `string` | `"iam-secure-gate"` |
| kms_deletion_window_days | KMS key deletion window (7-30 days) | `number` | `7` |
| cloudtrail_log_retention_days | CloudTrail log retention (min 90 for CIS) | `number` | `90` |
| cloudtrail_glacier_transition_days | Days before Glacier transition | `number` | `30` |
| cloudtrail_noncurrent_version_retention_days | Old version retention | `number` | `30` |
| config_snapshot_retention_days | Config snapshot retention | `number` | `365` |
| config_glacier_transition_days | Days before Glacier transition | `number` | `90` |
| config_noncurrent_version_retention_days | Old version retention | `number` | `90` |
| enable_object_lock | Enable WORM (immutable logs) | `bool` | `false` |
| enable_bucket_logging | Enable S3 access logging | `bool` | `false` |
| common_tags | Tags for all resources | `map(string)` | `{}` |

## Key Outputs

```hcl
# Core outputs for other modules
module.foundation.kms_key_arn
module.foundation.cloudtrail_bucket_name
module.foundation.config_bucket_name

# Structured summary
module.foundation.foundation_summary
module.foundation.security_status
```

## Security Features

### 1. KMS Key Protection

- **Automatic key rotation** enabled (every 365 days)
- **Encryption context validation** for CloudTrail (prevents cross-account misuse)
- **ViaService conditions** ensure only CloudTrail/Config services can use key
- **Separate permissions** for encrypt (GenerateDataKey) vs. decrypt
- **Account admin access** preserved for key management

### 2. S3 Bucket Security

#### Defense in Depth (7 Layers)

1. **Public Access Block** - 4-layer protection (block + ignore ACLs/policies)
2. **Bucket Ownership Enforced** - Disables ACLs, bucket owner owns all objects
3. **Versioning Enabled** - Protects against accidental/malicious deletion
4. **KMS Encryption** - Server-side encryption with customer-managed key
5. **Bucket Policies** - Least-privilege, service-scoped with conditions
6. **HTTPS Enforcement** - Denies all non-TLS traffic
7. **KMS Key Enforcement** - Denies uploads with wrong/no encryption key

#### Bucket Policy Conditions

```hcl
# CloudTrail bucket policy includes:
✅ aws:SourceAccount = your-account-id
✅ aws:SourceArn = arn:aws:cloudtrail:region:account:trail/*
✅ aws:SecureTransport = true (deny if false)
✅ s3:x-amz-server-side-encryption = aws:kms
✅ s3:x-amz-server-side-encryption-aws-kms-key-id = your-kms-key-arn
✅ Resource scoped to /AWSLogs/{account-id}/* only
```

### 3. Lifecycle Management

#### Current Version Lifecycle
- CloudTrail: 30 days Standard → Glacier → Delete at 90 days
- Config: 90 days Standard → Glacier → Delete at 365 days

#### Noncurrent Version Lifecycle (NEW in v2.0)
- Transition old versions to Glacier after 7/30 days
- Delete old versions after 30/90 days
- **Prevents unbounded storage costs** from versioning

#### Delete Marker Cleanup (NEW in v2.0)
- Removes delete markers when all versions expired
- **Keeps bucket clean** and prevents confusion

#### Abort Incomplete Uploads (NEW in v2.0)
- Cleans up failed multipart uploads after 7 days
- **Prevents hidden storage costs**

### 4. Resource Dependencies

Correct dependency ordering prevents apply-time failures:

```
1. KMS Key + Policy created
   ↓
2. S3 Buckets created
   ↓
3. Public Access Block + Ownership Controls applied
   ↓
4. Encryption configuration applied (depends on KMS)
   ↓
5. Bucket policies applied (depends on ownership controls)
```

## Cost Estimate

**Monthly cost for dev environment:**

| Component | Cost |
|-----------|------|
| KMS Key | $1.00/month |
| KMS API Requests (with bucket keys) | ~$0.003/month |
| S3 Standard Storage (CloudTrail 30 days) | ~$0.23/month |
| S3 Glacier Storage (CloudTrail 60 days) | ~$0.08/month |
| S3 Standard Storage (Config 90 days) | ~$0.12/month |
| S3 Glacier Storage (Config 275 days) | ~$0.06/month |
| Lifecycle Transitions | ~$0.10/month |
| **Total** | **~$1.62/month** |

## Usage Examples

### Basic Usage

```hcl
module "foundation" {
  source = "../../modules/foundation"

  environment = "dev"
  common_tags = {
    Owner = "security@example.com"
  }
}
```

### Custom Retention Periods

```hcl
module "foundation" {
  source = "../../modules/foundation"

  environment = "prod"

  # Longer retention for production
  cloudtrail_log_retention_days  = 365  # 1 year
  config_snapshot_retention_days = 2555 # 7 years

  # Faster Glacier transition for cost savings
  cloudtrail_glacier_transition_days = 30
  config_glacier_transition_days     = 180

  common_tags = {
    Environment = "prod"
    Owner       = "security@example.com"
    CostCenter  = "12345"
  }
}
```

### With Object Lock (Immutable Logs)

```hcl
module "foundation" {
  source = "../../modules/foundation"

  environment = "prod"

  # WORM compliance mode - logs cannot be deleted or modified
  enable_object_lock         = true
  object_lock_retention_days = 2555  # 7 years

  common_tags = {
    Environment = "prod"
    Compliance  = "SEC-Rule-17a-4"  # Example: Financial services
  }
}
```

**WARNING:** Object Lock cannot be disabled after bucket creation. Use with caution.

### With S3 Access Logging

```hcl
# First create a logging bucket
resource "aws_s3_bucket" "logs" {
  bucket = "my-s3-access-logs-${data.aws_caller_identity.current.account_id}"
}

module "foundation" {
  source = "../../modules/foundation"

  environment = "dev"

  # Enable access logging
  enable_bucket_logging        = true
  bucket_logging_target_bucket = aws_s3_bucket.logs.id
  bucket_logging_target_prefix = "foundation/"
}
```

## CIS AWS Foundations Benchmark Compliance

| Control | Description | Status |
|---------|-------------|--------|
| 2.1.5 | S3 buckets should have public access blocked | ✅ 4-layer protection |
| 2.1.5.1 | S3 buckets should use bucket policies, not ACLs | ✅ BucketOwnerEnforced |
| 3.6 | CloudTrail logs encrypted at rest | ✅ KMS encryption |
| 3.7 | CloudTrail logs have versioning enabled | ✅ Versioning enabled |
| 3.10 | KMS key rotation enabled | ✅ Automatic rotation |

## Deployment

### 1. Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

### 2. Validate Configuration

```bash
terraform validate
```

### 3. Plan Deployment

```bash
terraform plan
```

Expected output: **17-21 resources to add**

### 4. Apply Changes

```bash
terraform apply
```

### 5. Verify Outputs

```bash
terraform output foundation_summary
```

## Troubleshooting

### Issue: KMS encryption configuration timeout

**Cause:** S3 tries to use KMS key before policy is ready

**Solution:** This is handled automatically by `depends_on`. If it persists, run `terraform apply` again.

### Issue: Bucket policy rejected

**Cause:** Policy applied before ownership controls

**Solution:** This is handled automatically by `depends_on`. Module ensures correct ordering.

### Issue: Terraform fmt shows changes

**Cause:** Auto-formatting applied

**Solution:** Run `terraform fmt -recursive` before committing

### Issue: Bucket already exists

**Cause:** Previous deployment or bucket name collision

**Solution:**
- Check if this is a redeploy: `terraform destroy` then `terraform apply`
- Bucket names include account ID for uniqueness, so collisions are rare

## Migration from v1.0

See [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) for detailed migration instructions.

**Summary of breaking changes:**
- Removed `account_id` and `region` variables (now auto-detected)
- Bucket policies changed (removed ACL condition, added SourceAccount/SourceArn)
- Lifecycle rules updated (added noncurrent version management)
- File structure changed (split into multiple files)

**To upgrade:**
1. Remove `account_id` and `region` from module calls
2. Run `terraform plan` to review changes
3. Apply changes (in-place update, no recreation needed for most resources)

## Maintenance

### Adding Custom Lifecycle Rules

Edit `s3_cloudtrail.tf` or `s3_config.tf` lifecycle configuration blocks.

### Changing Retention Periods

Update variables in your environment configuration:

```hcl
cloudtrail_log_retention_days = 180  # 6 months
```

### Rotating KMS Key Manually

```bash
aws kms enable-key-rotation --key-id $(terraform output -raw kms_key_id)
```

(Key rotation is enabled by default and happens automatically every 365 days)

## License

Part of the IaC-Secure-Gate project.

## Authors

- **v2.0 Production Refactor** - Claude Sonnet 4.5 (2026-01-20)
- **v1.0 Initial Implementation** - IaC-Secure-Gate Contributors

## Support

For issues or questions, review the troubleshooting section or check the project documentation at `/docs/PHASE1.md`.
