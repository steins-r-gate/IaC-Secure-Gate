# Phase 1 Dev Environment - Verification Checklist

This checklist provides step-by-step commands to verify the Phase 1 dev environment is correctly configured and successfully deployed.

---

## Pre-Deployment Validation

### 1. Terraform Formatting
```bash
cd terraform/environments/dev
terraform fmt -check -recursive
```
**Expected**: No output (all files already formatted)

---

### 2. Terraform Initialization
```bash
cd terraform/environments/dev
terraform init
```
**Expected**:
```
Initializing modules...
- cloudtrail in ../../modules/cloudtrail
- config in ../../modules/config
- foundation in ../../modules/foundation

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

---

### 3. Terraform Validation
```bash
cd terraform/environments/dev
terraform validate
```
**Expected**:
```
Success! The configuration is valid.
```

---

### 4. Configuration Review
```bash
cd terraform/environments/dev
terraform plan
```
**Expected Resources** (approximate counts):
- **Foundation Module**: ~25 resources
  - KMS key + alias + policy
  - 2 S3 buckets (CloudTrail, Config)
  - Bucket encryption, versioning, lifecycle, logging, policies, public access blocks
- **CloudTrail Module**: ~2 resources
  - CloudTrail trail
  - (No CloudWatch/SNS since disabled in dev)
- **Config Module**: ~20 resources
  - Config recorder + delivery channel + recorder status
  - IAM role + policies (managed policy attachment + inline S3/KMS policies)
  - 8 Config rules (CIS compliance)

**Total**: ~45-50 resources

---

## Deployment Testing

### 5. Clean Deployment (First Apply)
```bash
cd terraform/environments/dev
terraform apply
```

**What to Monitor**:
1. Foundation module creates all resources first
2. CloudTrail module waits for foundation completion
3. Config module waits for foundation completion
4. No "Access Denied" errors (dependencies working)
5. All resources reach "Creation complete"

**Expected Duration**: 2-3 minutes

**Success Indicators**:
```
Apply complete! Resources: 45-50 added, 0 changed, 0 destroyed.

Outputs:

deployment_summary = {
  phase_1_ready = true
  cloudtrail_cis_3_1_compliant = true
  cloudtrail_cis_3_2_compliant = true
  config_recorder_enabled = true
  config_rules_deployed = 8
  foundation_cis_compliant = true
}
```

---

### 6. Idempotency Test (Second Apply)
```bash
cd terraform/environments/dev
terraform apply
```

**Expected**:
```
No changes. Your infrastructure matches the configuration.
```

**Why This Matters**: Proves configuration is deterministic and doesn't have flaky attributes or eventual consistency issues.

---

## Post-Deployment Verification

### 7. Review Deployment Summary
```bash
cd terraform/environments/dev
terraform output deployment_summary
```

**Expected Output**:
```json
{
  "account_id" = "123456789012"
  "cloudtrail_cis_3_1_compliant" = true
  "cloudtrail_cis_3_2_compliant" = true
  "cloudtrail_global_service_events" = true
  "cloudtrail_log_validation" = true
  "cloudtrail_multi_region" = true
  "cloudtrail_name" = "iam-secure-gate-dev-trail"
  "config_bucket" = "iam-secure-gate-dev-config-123456789012"
  "config_global_resources" = true
  "config_primary_region" = true
  "config_recorder_enabled" = true
  "config_recorder_name" = "iam-secure-gate-dev-config-recorder"
  "config_rules_deployed" = 8
  "cloudtrail_bucket" = "iam-secure-gate-dev-cloudtrail-123456789012"
  "environment" = "dev"
  "foundation_cis_compliant" = true
  "kms_key_arn" = "arn:aws:kms:eu-west-1:123456789012:key/GUID"
  "phase_1_ready" = true
  "project" = "iam-secure-gate"
  "region" = "eu-west-1"
}
```

**Verify**:
- ✅ `phase_1_ready = true`
- ✅ `cloudtrail_cis_3_1_compliant = true` (multi-region)
- ✅ `cloudtrail_cis_3_2_compliant = true` (log validation)
- ✅ `config_recorder_enabled = true`
- ✅ `config_rules_deployed = 8`
- ✅ `foundation_cis_compliant = true`

---

### 8. Verify Foundation Resources

#### KMS Key
```bash
# Get KMS key ARN
KMS_KEY_ARN=$(terraform output -raw kms_key_arn)

# Verify key exists and rotation is enabled
aws kms describe-key --key-id "$KMS_KEY_ARN" --region eu-west-1 --query 'KeyMetadata.{KeyId:KeyId,State:KeyState,Enabled:Enabled}' --output table

aws kms get-key-rotation-status --key-id "$KMS_KEY_ARN" --region eu-west-1
```

**Expected**:
```
KeyId: GUID
State: Enabled
Enabled: true

KeyRotationEnabled: true
```

---

#### S3 Buckets
```bash
# Get bucket names
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket_name)
CONFIG_BUCKET=$(terraform output -raw config_bucket_name)

# Verify buckets exist
aws s3api head-bucket --bucket "$CLOUDTRAIL_BUCKET" --region eu-west-1
aws s3api head-bucket --bucket "$CONFIG_BUCKET" --region eu-west-1

# Verify encryption (should use KMS)
aws s3api get-bucket-encryption --bucket "$CLOUDTRAIL_BUCKET" --region eu-west-1
aws s3api get-bucket-encryption --bucket "$CONFIG_BUCKET" --region eu-west-1

# Verify versioning (should be Enabled)
aws s3api get-bucket-versioning --bucket "$CLOUDTRAIL_BUCKET" --region eu-west-1
aws s3api get-bucket-versioning --bucket "$CONFIG_BUCKET" --region eu-west-1

# Verify public access block (all should be true)
aws s3api get-public-access-block --bucket "$CLOUDTRAIL_BUCKET" --region eu-west-1
aws s3api get-public-access-block --bucket "$CONFIG_BUCKET" --region eu-west-1
```

**Expected Encryption**:
```json
{
  "ServerSideEncryptionConfiguration": {
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "arn:aws:kms:eu-west-1:ACCOUNT:key/GUID"
        }
      }
    ]
  }
}
```

**Expected Versioning**:
```json
{
  "Status": "Enabled"
}
```

**Expected Public Access Block**:
```json
{
  "PublicAccessBlockConfiguration": {
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }
}
```

---

### 9. Verify CloudTrail

#### Trail Status
```bash
TRAIL_NAME=$(terraform output -raw cloudtrail_trail_name)

# Get trail details
aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" --region eu-west-1 --query 'trailList[0]' --output json
```

**Expected**:
```json
{
  "Name": "iam-secure-gate-dev-trail",
  "S3BucketName": "iam-secure-gate-dev-cloudtrail-123456789012",
  "IncludeGlobalServiceEvents": true,
  "IsMultiRegionTrail": true,
  "HomeRegion": "eu-west-1",
  "LogFileValidationEnabled": true,
  "HasCustomEventSelectors": false,
  "HasInsightSelectors": false,
  "IsOrganizationTrail": false,
  "KmsKeyId": "arn:aws:kms:eu-west-1:ACCOUNT:key/GUID"
}
```

**Verify**:
- ✅ `IncludeGlobalServiceEvents: true` (IAM events captured)
- ✅ `IsMultiRegionTrail: true` (CIS 3.1)
- ✅ `LogFileValidationEnabled: true` (CIS 3.2)
- ✅ `KmsKeyId` present (encryption enabled)

---

#### Trail Logging Status
```bash
aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region eu-west-1 --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}' --output table
```

**Expected**:
```
IsLogging: true
LatestDeliveryTime: (recent timestamp)
```

---

#### Trail Event Selectors
```bash
aws cloudtrail get-event-selectors --trail-name "$TRAIL_NAME" --region eu-west-1
```

**Expected** (advanced event selectors):
```json
{
  "AdvancedEventSelectors": [
    {
      "Name": "Management events selector",
      "FieldSelectors": [
        {
          "Field": "eventCategory",
          "Equals": ["Management"]
        }
      ]
    }
  ]
}
```

---

#### Test CloudTrail Recording
```bash
# Perform an API action (create a test IAM policy)
aws iam create-policy \
  --policy-name test-cloudtrail-$(date +%s) \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}' \
  --region eu-west-1

# Wait 2-3 minutes for event delivery

# Search CloudTrail for the event
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreatePolicy \
  --region eu-west-1 \
  --max-results 1 \
  --query 'Events[0].{EventTime:EventTime,EventName:EventName,Username:Username}' \
  --output table
```

**Expected**: Should show recent CreatePolicy event

---

### 10. Verify AWS Config

#### Recorder Status
```bash
RECORDER_NAME=$(terraform output -raw config_recorder_name)

# Get recorder configuration
aws configservice describe-configuration-recorders \
  --configuration-recorder-names "$RECORDER_NAME" \
  --region eu-west-1 \
  --query 'ConfigurationRecorders[0]' \
  --output json
```

**Expected**:
```json
{
  "name": "iam-secure-gate-dev-config-recorder",
  "roleARN": "arn:aws:iam::ACCOUNT:role/iam-secure-gate-dev-config-role",
  "recordingGroup": {
    "allSupported": true,
    "includeGlobalResourceTypes": true,
    "resourceTypes": []
  }
}
```

**Verify**:
- ✅ `allSupported: true` (recording all resource types)
- ✅ `includeGlobalResourceTypes: true` (recording IAM, global resources)

---

#### Recorder Running Status
```bash
aws configservice describe-configuration-recorder-status \
  --configuration-recorder-names "$RECORDER_NAME" \
  --region eu-west-1 \
  --query 'ConfigurationRecordersStatus[0]' \
  --output json
```

**Expected**:
```json
{
  "name": "iam-secure-gate-dev-config-recorder",
  "lastStartTime": "(recent timestamp)",
  "recording": true,
  "lastStatus": "SUCCESS",
  "lastStatusChangeTime": "(recent timestamp)"
}
```

**Verify**:
- ✅ `recording: true`
- ✅ `lastStatus: SUCCESS`

---

#### Delivery Channel
```bash
CHANNEL_NAME=$(terraform output -raw config_delivery_channel_name)

aws configservice describe-delivery-channels \
  --delivery-channel-names "$CHANNEL_NAME" \
  --region eu-west-1 \
  --query 'DeliveryChannels[0]' \
  --output json
```

**Expected**:
```json
{
  "name": "iam-secure-gate-dev-config-delivery",
  "s3BucketName": "iam-secure-gate-dev-config-123456789012",
  "s3KeyPrefix": "AWSLogs",
  "configSnapshotDeliveryProperties": {
    "deliveryFrequency": "TwentyFour_Hours"
  }
}
```

---

#### Config Rules Status
```bash
# List all deployed rules
aws configservice describe-config-rules --region eu-west-1 --query 'ConfigRules[?starts_with(ConfigRuleName, `iam-secure-gate-dev`)].{Name:ConfigRuleName,State:ConfigRuleState}' --output table

# Get compliance status for all rules
aws configservice describe-compliance-by-config-rule --region eu-west-1 --query 'ComplianceByConfigRules[?starts_with(ConfigRuleName, `iam-secure-gate-dev`)].{Rule:ConfigRuleName,Compliance:Compliance.ComplianceType}' --output table
```

**Expected**: 8 rules deployed with ACTIVE state

**Rule Names Should Include**:
1. `iam-secure-gate-dev-cloudtrail-enabled`
2. `iam-secure-gate-dev-multi-region-cloudtrail-enabled`
3. `iam-secure-gate-dev-s3-bucket-public-read-prohibited`
4. `iam-secure-gate-dev-s3-bucket-public-write-prohibited`
5. `iam-secure-gate-dev-s3-bucket-server-side-encryption-enabled`
6. `iam-secure-gate-dev-iam-password-policy`
7. `iam-secure-gate-dev-root-account-mfa-enabled`
8. `iam-secure-gate-dev-iam-user-mfa-enabled`

---

### 11. Verify IAM Roles

#### Config IAM Role
```bash
CONFIG_ROLE_ARN=$(terraform output -raw config_role_arn)

# Verify role exists and has correct trust policy
aws iam get-role --role-name iam-secure-gate-dev-config-role --query 'Role.{RoleName:RoleName,Arn:Arn}' --output table

# List attached policies
aws iam list-attached-role-policies --role-name iam-secure-gate-dev-config-role --output table

# List inline policies
aws iam list-role-policies --role-name iam-secure-gate-dev-config-role --output table
```

**Expected Attached Policies**:
- `AWS_ConfigRole` (AWS managed policy)

**Expected Inline Policies**:
- `iam-secure-gate-dev-config-s3-policy` (S3 write permissions)
- `iam-secure-gate-dev-config-kms-policy` (KMS encrypt permissions)

---

### 12. Cost Verification

```bash
# Check CloudTrail costs (management events only, no data events)
aws cloudtrail get-event-selectors --trail-name "$TRAIL_NAME" --region eu-west-1 | grep -i data

# Verify no CloudWatch Logs integration (would add costs)
aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" --region eu-west-1 --query 'trailList[0].CloudWatchLogsLogGroupArn'

# Verify no Insights enabled (would add $0.35 per 100k events)
aws cloudtrail get-insight-selectors --trail-name "$TRAIL_NAME" --region eu-west-1 2>&1
```

**Expected Costs for Dev Environment**:
- **CloudTrail**: $2.00/month (first trail free, multi-region counts as one)
- **Config**: ~$2.00/month (first 1000 config items free, then $0.003/item)
- **Config Rules**: ~$1.60/month ($0.20 per rule × 8 rules)
- **S3 Storage**: <$1.00/month (minimal logs in dev)
- **KMS**: $1.00/month (1 CMK)

**Total**: ~$6-7/month for complete Phase 1 detection baseline in dev

---

## Compliance Verification

### 13. CIS AWS Foundations Benchmark Compliance

```bash
# Check all CIS-related outputs
terraform output | grep -i cis
```

**Expected**:
```
cloudtrail_cis_3_1_compliant = true
cloudtrail_cis_3_2_compliant = true
foundation_cis_compliant = true
```

**Manual Verification**:

#### CIS 3.1: Multi-Region Trail
```bash
aws cloudtrail describe-trails --region eu-west-1 --query 'trailList[?IsMultiRegionTrail==`true`].Name' --output table
```
**Expected**: Your trail should appear in the list

---

#### CIS 3.2: Log File Validation
```bash
aws cloudtrail describe-trails --region eu-west-1 --query 'trailList[?LogFileValidationEnabled==`true`].Name' --output table
```
**Expected**: Your trail should appear in the list

---

#### CIS 3.3: CloudTrail Log Encryption (KMS)
```bash
aws cloudtrail describe-trails --region eu-west-1 --query 'trailList[?KmsKeyId!=`null`].{Name:Name,KmsKeyId:KmsKeyId}' --output table
```
**Expected**: Your trail should appear with KMS key ARN

---

#### CIS 3.4: CloudTrail Integration with CloudWatch Logs
**Note**: This is optional and disabled in dev to reduce costs. Can be enabled via:
```hcl
module "cloudtrail" {
  enable_cloudwatch_logs = true
}
```

---

## Cleanup (Optional)

If you want to tear down the environment:

```bash
cd terraform/environments/dev

# Preview destruction
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Note**: S3 buckets have retention policies and versioning. You may need to:
1. Empty buckets before destroy: `aws s3 rm s3://BUCKET_NAME --recursive`
2. Delete all object versions: `aws s3api delete-objects --bucket BUCKET_NAME --delete ...`

---

## Summary Checklist

Use this quick checklist to verify deployment success:

- [ ] ✅ `terraform validate` passes
- [ ] ✅ `terraform apply` succeeds with ~45-50 resources
- [ ] ✅ Second apply shows "No changes" (idempotency)
- [ ] ✅ `deployment_summary` shows `phase_1_ready = true`
- [ ] ✅ KMS key exists and rotation enabled
- [ ] ✅ CloudTrail bucket encrypted with KMS
- [ ] ✅ Config bucket encrypted with KMS
- [ ] ✅ CloudTrail trail logging and multi-region
- [ ] ✅ CloudTrail log validation enabled
- [ ] ✅ CloudTrail includes global service events
- [ ] ✅ Config recorder running
- [ ] ✅ Config 8 rules deployed and ACTIVE
- [ ] ✅ All CIS compliance flags = true
- [ ] ✅ Test IAM API call recorded in CloudTrail (2-3 min delay)
- [ ] ✅ Estimated monthly cost < $10 for dev

---

## Troubleshooting

### Issue: "Access Denied" during apply

**Cause**: S3 bucket policy not yet propagated (eventual consistency)

**Solution**:
```bash
# Wait 30 seconds and retry
sleep 30
terraform apply
```

This should NOT happen with correct `depends_on` in place, but if it does, it indicates a timing issue.

---

### Issue: Config recorder not starting

**Cause**: IAM role permissions not yet propagated

**Solution**:
```bash
# Manually stop and start recorder
aws configservice stop-configuration-recorder --configuration-recorder-name "$RECORDER_NAME" --region eu-west-1
sleep 10
aws configservice start-configuration-recorder --configuration-recorder-name "$RECORDER_NAME" --region eu-west-1
```

---

### Issue: Config rules show "No Resources in Scope"

**Cause**: Config needs time to discover resources (5-15 minutes after first deployment)

**Solution**: Wait 15 minutes and re-check compliance status

---

### Issue: CloudTrail not logging

**Symptoms**:
```bash
aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region eu-west-1
# Shows IsLogging: false
```

**Solution**:
```bash
# Manually start logging
aws cloudtrail start-logging --name "$TRAIL_NAME" --region eu-west-1
```

This should NOT be necessary with correct configuration.

---

## Next Steps

After verification:
1. Document any custom configurations in your team wiki
2. Plan staging/prod environment deployments (copy dev, adjust costs/features)
3. Set up monitoring/alerting based on CloudTrail + Config events
4. Review Config rule compliance and remediate any findings
5. Plan Phase 2 modules (GuardDuty, Security Hub, IAM Access Analyzer, etc.)
