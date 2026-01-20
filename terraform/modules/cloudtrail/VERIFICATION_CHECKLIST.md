# CloudTrail Module v2.0 - Verification Checklist

## Pre-Deployment Validation

### 1. Terraform Code Quality

```bash
cd terraform/modules/cloudtrail

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

# Test 2: Invalid KMS ARN format (should fail)
terraform plan \
  -var environment=dev \
  -var kms_key_arn="not-an-arn" \
  -var cloudtrail_bucket_name="valid-bucket-name"
# Expected: Error: KMS key ARN must be a valid AWS KMS key ARN.

# Test 3: Invalid S3 bucket name (should fail)
terraform plan \
  -var environment=dev \
  -var kms_key_arn="arn:aws:kms:us-east-1:123456789012:key/abc123" \
  -var cloudtrail_bucket_name="Invalid_Bucket_Name"
# Expected: Error: S3 bucket name must be 3-63 characters, lowercase...

# Test 4: Invalid CloudWatch retention (should fail)
terraform plan \
  -var environment=dev \
  -var kms_key_arn="arn:aws:kms:us-east-1:123456789012:key/abc123" \
  -var cloudtrail_bucket_name="valid-bucket-name" \
  -var cloudwatch_log_retention_days=42
# Expected: Error: CloudWatch log retention must be a valid retention period...

# Cleanup
rm test.tfvars
```

**✅ Pass Criteria:** All invalid inputs are rejected with clear error messages.

---

## Deployment Testing

### 3. Clean Environment Deploy (Minimal Configuration)

```bash
cd terraform/environments/dev

# Verify foundation module is deployed
terraform output foundation_summary
# Should show KMS key and S3 bucket outputs

# Plan CloudTrail deployment
terraform plan -target=module.cloudtrail
# Expected: Plan: 1 to add, 0 to change, 0 to destroy

# Review plan output for:
#  ✅ 1 CloudTrail trail resource
#  ✅ Using foundation KMS key ARN
#  ✅ Using foundation S3 bucket name
#  ✅ enable_log_file_validation = true
#  ✅ is_multi_region_trail = true
#  ✅ include_global_service_events = true

# Apply changes
terraform apply -target=module.cloudtrail
# Expected: Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**✅ Pass Criteria:**
- Plan shows exactly 1 resource (CloudTrail trail)
- Apply succeeds without errors
- No permission errors
- No timing/dependency errors

---

### 4. Deployment with CloudWatch Logs

```bash
cd terraform/environments/dev

# Update config to enable CloudWatch Logs
cat >> terraform.tfvars << EOF

# CloudWatch Logs integration
enable_cloudwatch_logs        = true
cloudwatch_log_retention_days = 90
EOF

# Plan deployment
terraform plan
# Expected: Plan: 3 to add, 1 to change, 0 to destroy
# Adding: CloudWatch log group, IAM role, IAM role policy
# Changing: CloudTrail trail (add CloudWatch config)

# Apply changes
terraform apply
# Expected: Apply complete! Resources: 3 added, 1 changed, 0 destroyed.
```

**✅ Pass Criteria:**
- CloudWatch log group created
- IAM role created with correct assume role policy
- IAM role policy grants CreateLogStream and PutLogEvents
- CloudTrail updated to reference CloudWatch log group

---

### 5. Idempotency Test

```bash
# Run plan again immediately
terraform plan
# Expected: No changes. Your infrastructure matches the configuration.
```

**✅ Pass Criteria:** Second plan shows zero changes (no drift).

---

## Post-Deployment Verification

### 6. CloudTrail Trail Verification

```bash
# Get trail name
TRAIL_NAME=$(terraform output -raw cloudtrail_trail_name)

# Check trail details
aws cloudtrail describe-trails --trail-name-list $TRAIL_NAME

# Verify:
# ✅ IsMultiRegionTrail: true
# ✅ IncludeGlobalServiceEvents: true
# ✅ LogFileValidationEnabled: true
# ✅ S3BucketName: matches foundation bucket
# ✅ KmsKeyId: matches foundation KMS key ARN
```

```bash
# Check trail status
aws cloudtrail get-trail-status --name $TRAIL_NAME

# Verify:
# ✅ IsLogging: true
# ✅ LatestDeliveryTime: recent timestamp (within last hour)
# ✅ StartLoggingTime: present
```

```bash
# Check event selectors
aws cloudtrail get-event-selectors --trail-name $TRAIL_NAME | jq .

# Verify:
# ✅ AdvancedEventSelectors present (not EventSelectors)
# ✅ Selector name: "Management events selector"
# ✅ Field: "eventCategory", Equals: ["Management"]
```

**✅ Pass Criteria:** All checks pass, trail is logging, advanced event selectors configured.

---

### 7. S3 Bucket Integration Verification

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw cloudtrail_trail_s3_bucket_name)

# Wait 15 minutes for first log delivery, then check
aws s3 ls s3://$BUCKET_NAME/AWSLogs/ --recursive | head -5

# Expected output:
# AWSLogs/123456789012/CloudTrail/eu-west-1/2026/01/20/...json.gz

# Download and verify a log file
LOG_FILE=$(aws s3 ls s3://$BUCKET_NAME/AWSLogs/ --recursive | head -1 | awk '{print $4}')
aws s3 cp s3://$BUCKET_NAME/$LOG_FILE - | gunzip | jq .Records[0]

# Verify JSON structure:
# ✅ eventVersion, eventTime, eventSource present
# ✅ userIdentity contains AWS account info
# ✅ requestParameters, responseElements present
```

**✅ Pass Criteria:** CloudTrail logs are being delivered to S3 bucket, logs are valid JSON.

---

### 8. Log File Validation Verification

```bash
# Check if digest files are being created
aws s3 ls s3://$BUCKET_NAME/AWSLogs/${ACCOUNT_ID}/CloudTrail-Digest/ --recursive | head -5

# Expected output:
# CloudTrail-Digest/eu-west-1/2026/01/20/...json.gz

# Validate log file integrity
aws cloudtrail validate-logs \
  --trail-arn $(terraform output -raw cloudtrail_trail_arn) \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S')

# Expected output:
# Results requested for 2026-01-20T...
# Results found for 1 trail.
# 100% of logs valid
```

**✅ Pass Criteria:** Digest files exist, log validation succeeds 100%.

---

### 9. CloudWatch Logs Verification (if enabled)

```bash
# Get log group name
LOG_GROUP=$(terraform output -raw cloudtrail_cloudwatch_logs_group_name)

# Check log group details
aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP

# Verify:
# ✅ logGroupName: /aws/cloudtrail/iam-secure-gate-dev-trail
# ✅ retentionInDays: 90 (or configured value)
# ✅ kmsKeyId: matches foundation KMS key ARN
```

```bash
# Wait 5-10 minutes, then check for log streams
aws logs describe-log-streams --log-group-name $LOG_GROUP --max-items 5

# Expected output:
# logStreams array with entries
# Each stream represents events from different resources
```

```bash
# Get recent CloudTrail events from CloudWatch Logs
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --limit 5 \
  --query 'events[].message' \
  --output text | jq .

# Expected output:
# CloudTrail events in JSON format
# Should match S3 log file contents
```

**✅ Pass Criteria:** Log group exists, retention set correctly, events flowing to CloudWatch.

---

### 10. IAM Role Verification (if CloudWatch enabled)

```bash
# Get IAM role ARN
ROLE_ARN=$(terraform output -raw cloudtrail_cloudwatch_logs_role_arn)
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')

# Check assume role policy
aws iam get-role --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument' | jq .

# Verify:
# ✅ Principal.Service: "cloudtrail.amazonaws.com"
# ✅ Action: "sts:AssumeRole"
```

```bash
# Check inline policy
aws iam list-role-policies --role-name $ROLE_NAME

# Get policy document
POLICY_NAME=$(aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames[0]' --output text)
aws iam get-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --query 'PolicyDocument' | jq .

# Verify:
# ✅ Actions: ["logs:CreateLogStream", "logs:PutLogEvents"]
# ✅ Resource: specific log group ARN (not wildcard)
```

**✅ Pass Criteria:** IAM role has correct trust policy and least-privilege permissions.

---

### 11. SNS Topic Verification (if enabled)

```bash
# Get SNS topic ARN
SNS_TOPIC=$(terraform output -raw cloudtrail_sns_topic_arn)

# Check SNS topic attributes
aws sns get-topic-attributes --topic-arn $SNS_TOPIC

# Verify:
# ✅ KmsMasterKeyId: matches foundation KMS key ARN
# ✅ DisplayName or TopicArn contains "cloudtrail-notifications"
```

```bash
# Check SNS topic policy
aws sns get-topic-attributes --topic-arn $SNS_TOPIC \
  --query 'Attributes.Policy' --output text | jq .

# Verify policy contains:
# ✅ Statement with Principal.Service: "cloudtrail.amazonaws.com"
# ✅ Action: "SNS:Publish"
# ✅ Condition with aws:SourceAccount
# ✅ Condition with aws:SourceArn (CloudTrail trail ARN pattern)
```

**✅ Pass Criteria:** SNS topic exists, encrypted with KMS, policy has SourceAccount conditions.

---

### 12. Terraform Outputs Verification

```bash
# Check structured outputs
terraform output cloudtrail_summary

# Verify output contains:
# ✅ trail_name
# ✅ trail_arn
# ✅ trail_home_region
# ✅ s3_bucket_name
# ✅ log_file_validation_enabled = true
# ✅ is_multi_region_trail = true
# ✅ is_organization_trail = false (unless enabled)
# ✅ include_global_service_events = true
# ✅ kms_encryption_enabled = true
# ✅ cis_3_1_compliant = true
# ✅ cis_3_2_compliant = true
```

```bash
# Check event configuration output
terraform output event_configuration

# Verify output contains:
# ✅ management_events_enabled = true
# ✅ excluded_management_sources = [] (or configured list)
# ✅ s3_data_events_enabled = false (unless enabled)
# ✅ lambda_data_events_enabled = false (unless enabled)
# ✅ api_call_rate_insights_enabled = false (unless enabled)
```

**✅ Pass Criteria:** All outputs present, security flags show `true`, CIS compliance confirmed.

---

## Security Testing

### 13. Verify Management Events Captured

```bash
# Trigger a management event (e.g., list S3 buckets)
aws s3 ls

# Wait 5-15 minutes, then search CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ListBuckets \
  --max-results 1

# Expected output:
# Events array with your ListBuckets call
# CloudTrailEvent JSON shows:
#   - eventSource: s3.amazonaws.com
#   - eventName: ListBuckets
#   - userIdentity: your IAM identity
```

**✅ Pass Criteria:** Management events (AWS API calls) are captured.

---

### 14. Verify Global Service Events (IAM)

```bash
# Trigger IAM event (list users)
aws iam list-users --max-items 1

# Wait 5-15 minutes, then search CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ListUsers \
  --max-results 1

# Expected output:
# Event captured even though IAM is global service
# awsRegion: us-east-1 (IAM events route to us-east-1)
```

**✅ Pass Criteria:** IAM/STS events captured (proves include_global_service_events works).

---

### 15. Verify Multi-Region Coverage

```bash
# Make API call in different region
aws ec2 describe-instances --region us-west-2 --max-results 1

# Wait 5-15 minutes, then search CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DescribeInstances \
  --max-results 1

# Expected output:
# Event captured from us-west-2
# S3 logs stored in: AWSLogs/123456789012/CloudTrail/us-west-2/...
```

**✅ Pass Criteria:** Events from all regions captured (proves is_multi_region_trail works).

---

### 16. Test S3 Data Events (if enabled)

```bash
# Only if enable_s3_data_events = true

# Upload object to monitored bucket
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://your-monitored-bucket/test.txt

# Wait 5-15 minutes, then search CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject \
  --max-results 1 \
  --region $(terraform output -raw trail_home_region)

# Expected output:
# PutObject event captured
# requestParameters.bucketName: your-monitored-bucket
# requestParameters.key: test.txt
```

**✅ Pass Criteria:** S3 object-level events captured for configured buckets.

---

## Cost Verification

### 17. Check AWS Cost Explorer

After 24-48 hours of deployment:

```
AWS Console → Cost Explorer → Cost & Usage Reports

Filter by:
- Service: CloudTrail
- Tag: Module = cloudtrail

Expected costs (default config):
- CloudTrail Trail: $0 (first trail free)
- S3 Storage: $0.50-$2.00/month (varies by activity)
- If CloudWatch Logs: +$0.50-$5.00/month (varies by volume)
- If SNS: +$0.01-$0.10/month
- If Insights: +$3.50/month per 100k write events
```

**✅ Pass Criteria:** Costs match expectations, no unexpected charges.

---

## Compliance Verification

### 18. CIS AWS Foundations Benchmark

| Control | Requirement                              | Verification Command                                   | Status |
|---------|------------------------------------------|--------------------------------------------------------|--------|
| 3.1     | Multi-region trail enabled               | `aws cloudtrail describe-trails` → IsMultiRegionTrail | ✅      |
| 3.2     | Log file validation enabled              | `aws cloudtrail describe-trails` → LogFileValidationEnabled | ✅      |
| 3.3     | CloudTrail bucket not publicly accessible| Foundation module verification                         | ✅      |
| 3.4     | CloudTrail integrated with CloudWatch    | `terraform output cloudwatch_logs_group_arn` (optional)| ⚙️      |
| 3.6     | CloudTrail logs encrypted at rest        | `aws cloudtrail describe-trails` → KmsKeyId            | ✅      |
| 3.7     | CloudTrail logs have versioning enabled  | Foundation module S3 bucket versioning                 | ✅      |

**✅ Pass Criteria:** All CIS controls pass verification (3.4 optional).

---

## Cleanup (After Testing)

```bash
# If this was a test deployment, clean up
cd terraform/environments/dev

# Disable trail first (stops log delivery)
TRAIL_ARN=$(terraform output -raw cloudtrail_trail_arn)
aws cloudtrail stop-logging --name $TRAIL_ARN

# Destroy CloudTrail resources
terraform destroy -target=module.cloudtrail

# Expected: Plan: 0 to add, 0 to change, 1-6 to destroy
# (depending on optional features enabled)
```

**Note:** S3 logs remain in foundation bucket after CloudTrail deletion (intended for audit retention).

---

## Summary Checklist

### Pre-Deployment
- [ ] **Code validation:** terraform validate passes
- [ ] **Variable validations:** Invalid inputs rejected
- [ ] **No invalid depends_on:** Module loads without errors

### Deployment
- [ ] **Minimal config:** 1 resource created (CloudTrail trail)
- [ ] **CloudWatch config:** +3 resources if enabled
- [ ] **Idempotency:** No drift after initial apply

### CloudTrail Verification
- [ ] **Trail status:** IsLogging = true
- [ ] **Multi-region:** IsMultiRegionTrail = true
- [ ] **Log validation:** LogFileValidationEnabled = true
- [ ] **Event selectors:** AdvancedEventSelectors present
- [ ] **S3 integration:** Logs delivered to bucket
- [ ] **Digest files:** Log validation files created

### CloudWatch Logs (if enabled)
- [ ] **Log group:** Created with correct retention
- [ ] **IAM role:** Assume role policy allows CloudTrail
- [ ] **IAM policy:** Scoped to specific log group ARN
- [ ] **Events flowing:** Log streams created, events visible

### SNS (if enabled)
- [ ] **Topic created:** With KMS encryption
- [ ] **Topic policy:** SourceAccount and SourceArn conditions

### Outputs
- [ ] **cloudtrail_summary:** Shows complete config
- [ ] **CIS compliance:** cis_3_1_compliant and cis_3_2_compliant = true
- [ ] **event_configuration:** Shows management events enabled

### Security Testing
- [ ] **Management events:** AWS API calls captured
- [ ] **Global service events:** IAM/STS calls captured
- [ ] **Multi-region:** Events from all regions captured
- [ ] **S3 data events:** Object operations captured (if enabled)

### Cost
- [ ] **CloudTrail:** First trail free
- [ ] **S3:** Minimal storage costs
- [ ] **CloudWatch:** Controlled retention costs (if enabled)
- [ ] **No surprise charges:** All costs expected

### Compliance
- [ ] **CIS 3.1:** Multi-region trail ✅
- [ ] **CIS 3.2:** Log file validation ✅
- [ ] **CIS 3.6:** KMS encryption ✅
- [ ] **CIS 3.7:** S3 versioning ✅ (foundation)

---

**Verification Complete:** All checks pass ✅

**Date:** _____________
**Verified By:** _____________
**Environment:** dev / staging / prod
**Version:** 2.0
