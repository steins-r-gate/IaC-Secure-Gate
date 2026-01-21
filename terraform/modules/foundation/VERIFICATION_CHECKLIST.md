# Foundation Module v2.0 - Verification Checklist

## Pre-Deployment Validation

### 1. Terraform Code Quality

```bash
cd terraform/modules/foundation

# Format check
terraform fmt -check -recursive
# Expected: No output (all files formatted)

# Initialize providers
terraform init
# Expected: Successfully initialized

# Validate configuration
terraform validate
# Expected: Success! The configuration is valid.
```

**✅ Pass Criteria:** All three commands succeed without errors or warnings.

---

### 2. Variable Validation Testing

Test that variable validations work correctly:

```bash
# Test 1: Invalid environment (should fail)
echo 'environment = "invalid"' > test.tfvars
terraform plan -var-file=test.tfvars
# Expected: Error: Environment must be dev, staging, or prod.

# Test 2: Invalid retention (should fail)
echo 'cloudtrail_log_retention_days = 30' > test.tfvars
terraform plan -var environment=dev -var cloudtrail_log_retention_days=30
# Expected: Error: CloudTrail retention must be at least 90 days

# Test 3: Invalid lifecycle timing (should fail)
terraform plan -var environment=dev \
  -var cloudtrail_glacier_transition_days=100 \
  -var cloudtrail_log_retention_days=90
# Expected: Error: glacier_transition must be < retention

# Cleanup
rm test.tfvars
```

**✅ Pass Criteria:** All invalid inputs are rejected with clear error messages.

---

## Deployment Testing

### 3. Clean Environment Deploy

```bash
cd terraform/environments/dev

# Create minimal tfvars
cat > terraform.tfvars << EOF
owner_email = "test@example.com"
EOF

# Plan deployment
terraform plan -out=tfplan
# Expected: Plan: 17 to add, 0 to change, 0 to destroy

# Review plan output for:
#  ✅ 1 KMS key + 1 alias + 1 key policy
#  ✅ 2 S3 buckets (cloudtrail + config)
#  ✅ 2 versioning configs
#  ✅ 2 encryption configs
#  ✅ 2 public access blocks
#  ✅ 2 ownership controls
#  ✅ 2 lifecycle configs
#  ✅ 2 bucket policies
#  Total: 17 resources

# Apply changes
terraform apply tfplan
# Expected: Apply complete! Resources: 17 added, 0 changed, 0 destroyed.
```

**✅ Pass Criteria:**
- Plan shows exactly 17 resources
- Apply succeeds without errors
- No permission errors
- No timing/dependency errors

---

### 4. Idempotency Test

```bash
# Run plan again immediately
terraform plan
# Expected: No changes. Your infrastructure matches the configuration.
```

**✅ Pass Criteria:** Second plan shows zero changes (no drift).

---

## Post-Deployment Verification

### 5. KMS Key Verification

```bash
# Get KMS key ID
KMS_KEY_ID=$(terraform output -raw kms_key_id)

# Check key details
aws kms describe-key --key-id $KMS_KEY_ID

# Verify:
# ✅ KeyState: Enabled
# ✅ Origin: AWS_KMS
# ✅ KeyManager: CUSTOMER
# ✅ CustomerMasterKeySpec: SYMMETRIC_DEFAULT
```

```bash
# Check key rotation
aws kms get-key-rotation-status --key-id $KMS_KEY_ID

# Expected output:
# {
#     "KeyRotationEnabled": true
# }
```

```bash
# Get key policy
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default | jq .

# Verify policy contains:
# ✅ Statement with Sid: "Enable IAM User Permissions"
# ✅ Statement with Sid: "Allow CloudTrail to encrypt logs"
# ✅ Statement with Sid: "Allow Config to use the key"
# ✅ Condition with kms:EncryptionContext:aws:cloudtrail:arn
# ✅ Condition with kms:ViaService for cloudtrail
# ✅ Condition with kms:ViaService for config
```

**✅ Pass Criteria:** All checks pass, key rotation enabled, policy has correct conditions.

---

### 6. CloudTrail Bucket Verification

```bash
# Get bucket name
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket_name)

# Check versioning
aws s3api get-bucket-versioning --bucket $CLOUDTRAIL_BUCKET

# Expected output:
# {
#     "Status": "Enabled"
# }
```

```bash
# Check encryption
aws s3api get-bucket-encryption --bucket $CLOUDTRAIL_BUCKET | jq .

# Verify:
# ✅ SSEAlgorithm: "aws:kms"
# ✅ KMSMasterKeyID: matches your KMS key ARN
# ✅ BucketKeyEnabled: true
```

```bash
# Check public access block
aws s3api get-public-access-block --bucket $CLOUDTRAIL_BUCKET

# Expected output:
# {
#     "PublicAccessBlockConfiguration": {
#         "BlockPublicAcls": true,
#         "IgnorePublicAcls": true,
#         "BlockPublicPolicy": true,
#         "RestrictPublicBuckets": true
#     }
# }
```

```bash
# Check ownership controls
aws s3api get-bucket-ownership-controls --bucket $CLOUDTRAIL_BUCKET

# Expected output:
# {
#     "OwnershipControls": {
#         "Rules": [
#             {
#                 "ObjectOwnership": "BucketOwnerEnforced"
#             }
#         ]
#     }
# }
```

```bash
# Check lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket $CLOUDTRAIL_BUCKET | jq .

# Verify rules exist for:
# ✅ Rule: "cloudtrail-current-version-lifecycle" (30d→Glacier, 90d→Delete)
# ✅ Rule: "cloudtrail-noncurrent-version-cleanup" (7d→Glacier, 30d→Delete)
# ✅ Rule: "cloudtrail-delete-marker-cleanup" (expired_object_delete_marker: true)
# ✅ Rule: "cloudtrail-abort-incomplete-uploads" (7 days)
```

```bash
# Check bucket policy
aws s3api get-bucket-policy --bucket $CLOUDTRAIL_BUCKET | jq -r .Policy | jq .

# Verify statements:
# ✅ Sid: "DenyInsecureTransport" (aws:SecureTransport = false → Deny)
# ✅ Sid: "DenyUnencryptedObjectUploads"
# ✅ Sid: "DenyIncorrectEncryptionHeader"
# ✅ Sid: "AWSCloudTrailAclCheck" (with aws:SourceAccount condition)
# ✅ Sid: "AWSCloudTrailWrite" (with aws:SourceAccount + aws:SourceArn conditions)
# ✅ Resource scoped to /AWSLogs/{account-id}/*
```

**✅ Pass Criteria:** All security settings match expected configuration.

---

### 7. Config Bucket Verification

```bash
# Get bucket name
CONFIG_BUCKET=$(terraform output -raw config_bucket_name)

# Run same checks as CloudTrail bucket (steps above)
# Verify lifecycle rules have different retention:
# ✅ Glacier transition: 90 days (vs. 30 for CloudTrail)
# ✅ Expiration: 365 days (vs. 90 for CloudTrail)
# ✅ Noncurrent version expiration: 90 days (vs. 30 for CloudTrail)

# Check bucket policy has Config-specific statements:
# ✅ Sid: "AWSConfigBucketPermissionsCheck"
# ✅ Sid: "AWSConfigBucketExistenceCheck" (s3:ListBucket permission)
# ✅ Sid: "AWSConfigWrite"
# ✅ Sid: "AWSConfigGetBucketLocation"
```

**✅ Pass Criteria:** All security settings match expected configuration, retention periods are longer than CloudTrail.

---

### 8. Terraform Outputs Verification

```bash
# Check structured outputs
terraform output foundation_summary

# Verify output contains:
# ✅ environment = "dev"
# ✅ region = "eu-west-1" (or your region)
# ✅ account_id = your 12-digit account ID
# ✅ kms_key_rotation = true
# ✅ cloudtrail_versioning_enabled = true
# ✅ cloudtrail_encryption_enabled = true
# ✅ cloudtrail_public_access_blocked = true
# ✅ config_versioning_enabled = true
# ✅ config_encryption_enabled = true
# ✅ config_public_access_blocked = true
# ✅ cis_compliant = true
```

```bash
# Check security status output
terraform output security_status

# Verify all flags are true:
# ✅ kms_rotation_enabled = true
# ✅ s3_versioning_enabled = true
# ✅ s3_encryption_enabled = true
# ✅ s3_public_access_blocked = true
# ✅ s3_ownership_enforced = true
# ✅ https_only_enforced = true
# ✅ kms_key_enforcement = true
# ✅ service_scoped_permissions = true
# ✅ source_account_validated = true
# ✅ noncurrent_version_managed = true
# ✅ delete_markers_cleaned = true
```

**✅ Pass Criteria:** All security flags show `true`, summary contains correct configuration.

---

## Security Penetration Tests

### 9. Try to Upload Without Encryption

```bash
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket_name)

# Create test file
echo "test" > /tmp/test.txt

# Try to upload without encryption
aws s3 cp /tmp/test.txt s3://$CLOUDTRAIL_BUCKET/test.txt

# Expected result: AccessDenied
# Expected error message contains: "encryption" or "Deny"
```

**✅ Pass Criteria:** Upload is DENIED.

---

### 10. Try to Upload with Wrong KMS Key

```bash
# Create a different KMS key
WRONG_KEY=$(aws kms create-key --query 'KeyMetadata.KeyId' --output text)

# Try to upload with wrong key
aws s3 cp /tmp/test.txt s3://$CLOUDTRAIL_BUCKET/test.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id $WRONG_KEY

# Expected result: AccessDenied
# Expected error message: Bucket policy violation

# Cleanup
aws kms schedule-key-deletion --key-id $WRONG_KEY --pending-window-in-days 7
```

**✅ Pass Criteria:** Upload is DENIED.

---

### 11. Try HTTP Connection (Non-TLS)

```bash
# Try to make HTTP (not HTTPS) request
aws s3api list-objects-v2 \
  --bucket $CLOUDTRAIL_BUCKET \
  --endpoint-url http://s3.amazonaws.com

# Expected result: Connection refused or SSL error
# S3 API only accepts HTTPS by default, HTTP attempts will fail at transport layer
```

**✅ Pass Criteria:** HTTP connection fails.

---

### 12. Try Cross-Account Access

```bash
# From a DIFFERENT AWS account:
# 1. Create an IAM user in account B
# 2. Try to write to account A's CloudTrail bucket

# Expected result: AccessDenied
# Reason: aws:SourceAccount condition restricts to your account only
```

**✅ Pass Criteria:** Cross-account access is DENIED.

---

## Cost Verification

### 13. Check AWS Cost Explorer

After 24 hours of deployment:

```
AWS Console → Cost Explorer → Cost & Usage Reports

Filter by:
- Tag: Project = IAM-Secure-Gate
- Tag: Module = foundation

Expected costs:
- KMS Key: ~$1.00/month ($0.03/day)
- S3 Storage: ~$0.50/month ($0.02/day) - increases over time
- Total: ~$1.50-2.00/month initially
```

**✅ Pass Criteria:** Costs match expectations, no unexpected charges.

---

## Compliance Verification

### 14. CIS AWS Foundations Benchmark

| Control | Requirement | Verification | Status |
|---------|-------------|--------------|--------|
| 2.1.5 | S3 public access blocked | `get-public-access-block` shows all true | ✅ |
| 2.1.5.1 | S3 uses bucket policies not ACLs | `get-bucket-ownership-controls` shows BucketOwnerEnforced | ✅ |
| 3.6 | CloudTrail logs encrypted | `get-bucket-encryption` shows aws:kms | ✅ |
| 3.7 | CloudTrail versioning enabled | `get-bucket-versioning` shows Enabled | ✅ |
| 3.10 | KMS rotation enabled | `get-key-rotation-status` shows true | ✅ |

**✅ Pass Criteria:** All CIS controls pass verification.

---

## Cleanup (After Testing)

```bash
# If this was a test deployment, clean up
cd terraform/environments/dev

# Destroy all resources
terraform destroy

# Expected: Plan: 0 to add, 0 to change, 17 to destroy.
```

**Note:** S3 buckets must be empty before destruction. If buckets contain objects:

```bash
# Empty CloudTrail bucket
aws s3 rm s3://$(terraform output -raw cloudtrail_bucket_name) --recursive

# Empty Config bucket
aws s3 rm s3://$(terraform output -raw config_bucket_name) --recursive

# Then run terraform destroy again
terraform destroy
```

---

## Summary Checklist

- [ ] **Pre-deployment:** Code validation passes
- [ ] **Pre-deployment:** Variable validations work
- [ ] **Deployment:** 17 resources created successfully
- [ ] **Post-deployment:** Idempotency test passes (no drift)
- [ ] **KMS:** Key rotation enabled, policy has conditions
- [ ] **CloudTrail Bucket:** All security settings configured
- [ ] **CloudTrail Bucket:** Lifecycle rules include noncurrent versions
- [ ] **Config Bucket:** All security settings configured
- [ ] **Config Bucket:** Lifecycle rules have longer retention
- [ ] **Outputs:** foundation_summary shows correct config
- [ ] **Outputs:** security_status shows all true
- [ ] **Security:** Unencrypted uploads denied
- [ ] **Security:** Wrong KMS key uploads denied
- [ ] **Security:** HTTP connections fail
- [ ] **Security:** Cross-account access denied
- [ ] **Cost:** Monthly costs match expectations (~$1.50-2.00)
- [ ] **Compliance:** All CIS controls pass

---

**Verification Complete:** All checks pass ✅

**Date:** _____________
**Verified By:** _____________
**Environment:** dev / staging / prod
**Version:** 2.0
