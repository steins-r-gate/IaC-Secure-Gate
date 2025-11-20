# S3 Module - IAM-Secure-Gate

## Overview

This module creates secure S3 buckets for CloudTrail and AWS Config logging with enterprise-grade security controls.

## Features

### Security Controls

- ✅ **KMS Encryption**: All buckets encrypted with customer-managed KMS keys
- ✅ **Key Rotation**: Automatic KMS key rotation enabled
- ✅ **Versioning**: Object versioning enabled on all buckets
- ✅ **Access Logging**: All bucket access logged to dedicated logs bucket
- ✅ **Public Access Block**: All public access completely blocked
- ✅ **Secure Transport**: HTTPS-only access enforced via bucket policies
- ✅ **Ownership Controls**: Bucket owner enforcement enabled

### Cost Optimization

- 📊 **Lifecycle Policies**: Automatic archival and deletion
  - Day 0-90: Standard storage
  - Day 90-180: Standard-IA (30% cheaper)
  - Day 180-365: Glacier (70% cheaper)
  - Day 365+: Automatic deletion

## Resources Created

### 1. KMS Key

- Customer-managed key for S3 encryption
- Automatic key rotation enabled
- 10-day deletion window for safety

### 2. Logs Bucket (`iam-security-{env}-logs-{account_id}`)

- Stores access logs for CloudTrail and Config buckets
- Enables audit trail of bucket access
- Same security controls as primary buckets

### 3. CloudTrail Bucket (`iam-security-{env}-cloudtrail-{account_id}`)

- Stores AWS CloudTrail logs
- Bucket policy allows CloudTrail service access
- Access logging to logs bucket

### 4. Config Bucket (`iam-security-{env}-config-{account_id}`)

- Stores AWS Config snapshots and history
- Bucket policy allows Config service access
- Access logging to logs bucket

## Usage

```hcl
module "s3" {
  source = "../../modules/s3"

  environment = "dev"
  common_tags = {
    Project     = "IAM-Secure-Gate"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  # Optional: Override default retention periods
  cloudtrail_log_retention_days = 730  # 2 years
  config_log_retention_days     = 365  # 1 year
  access_log_retention_days     = 180  # 6 months
}
```

## Inputs

| Name                          | Description                         | Type        | Default | Required |
| ----------------------------- | ----------------------------------- | ----------- | ------- | -------- |
| environment                   | Environment name (dev/staging/prod) | string      | -       | yes      |
| common_tags                   | Tags to apply to all resources      | map(string) | {}      | no       |
| cloudtrail_log_retention_days | CloudTrail log retention            | number      | 365     | no       |
| config_log_retention_days     | Config log retention                | number      | 365     | no       |
| access_log_retention_days     | Access log retention                | number      | 365     | no       |
| transition_to_ia_days         | Days before moving to Standard-IA   | number      | 90      | no       |
| transition_to_glacier_days    | Days before moving to Glacier       | number      | 180     | no       |
| kms_deletion_window_days      | KMS key deletion window             | number      | 10      | no       |

## Outputs

| Name                   | Description             |
| ---------------------- | ----------------------- |
| cloudtrail_bucket_name | CloudTrail bucket name  |
| cloudtrail_bucket_arn  | CloudTrail bucket ARN   |
| config_bucket_name     | Config bucket name      |
| config_bucket_arn      | Config bucket ARN       |
| logs_bucket_name       | Access logs bucket name |
| logs_bucket_arn        | Access logs bucket ARN  |
| kms_key_id             | KMS key ID              |
| kms_key_arn            | KMS key ARN             |
| kms_key_alias          | KMS key alias           |

## Security Compliance

This module implements the following security best practices:

- **CIS AWS Foundations Benchmark**: Section 3 (Logging)
- **AWS Security Best Practices**: S3 encryption and access controls
- **GDPR**: Data at rest encryption
- **SOC 2**: Audit logging and access controls

## Cost Estimation

### Example Monthly Cost (1 TB of logs):

- **Standard (0-90 days)**: ~$23/month
- **Standard-IA (90-180 days)**: ~$12.50/month
- **Glacier (180-365 days)**: ~$4/month
- **KMS Key**: ~$1/month
- **Total**: ~$40.50/month for 1 TB with lifecycle policies

Without lifecycle policies: ~$92/month for same 1 TB (56% savings!)

## Notes

1. **Bucket Names**: Include AWS account ID to prevent naming conflicts
2. **KMS Keys**: Separate key per environment recommended for prod
3. **Lifecycle Rules**: Adjust retention based on compliance requirements
4. **Access Logs**: Logs bucket has its own lifecycle policy
5. **Deletion**: Buckets must be empty before Terraform can destroy them

## Troubleshooting

### Error: "AccessDenied" when CloudTrail/Config tries to write

**Solution**: Ensure the bucket policy is applied after bucket creation. Dependencies are handled automatically.

### Error: "BucketAlreadyExists"

**Solution**: Bucket names include account ID. If still occurring, check for orphaned buckets.

### High S3 Costs

**Solution**: Review lifecycle policies. Consider shorter retention periods if compliance allows.

## Future Enhancements

- [ ] Cross-region replication for disaster recovery
- [ ] MFA delete protection for production
- [ ] S3 Object Lock for immutable logs
- [ ] Integration with AWS Macie for data discovery
