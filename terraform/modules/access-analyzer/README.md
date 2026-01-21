# IAM Access Analyzer Terraform Module

**Purpose:** Detect and report external access to AWS resources and identify unused IAM permissions across your AWS account.

**Version:** 2.0 (Phase 1)
**Status:** Production-Ready ✅

---

## Overview

This module deploys AWS IAM Access Analyzer to continuously monitor your AWS resources for external access and unused permissions. Access Analyzer uses provable security (automated reasoning) to identify resources that can be accessed from outside your AWS account, helping you maintain least-privilege access controls.

**What it does:**
- Analyzes resource-based policies (S3, IAM roles, KMS keys, Lambda, SQS, SNS, etc.)
- Identifies resources accessible from external AWS accounts
- Detects unused IAM permissions (future capability)
- Automatically integrates findings with AWS Security Hub
- Provides archive rules for managing resolved findings
- Optional SNS notifications for new findings

---

## Features

### Core Capabilities
- ✅ **Account-Level Analyzer** - Single account scope (Phase 1)
- ✅ **External Access Detection** - Identifies resources accessible outside your account
- ✅ **Automatic Archive Rules** - Archives resolved findings to reduce noise
- ✅ **Security Hub Integration** - Findings automatically sent to Security Hub
- ✅ **Zero Cost** - Completely free AWS service (no charges)

### Optional Features (Disabled by Default)
- 🔔 **SNS Notifications** - Real-time alerts for new findings via EventBridge
- 📧 **Email Subscriptions** - Configurable email notifications
- 🏢 **Organization Analyzer** - Multi-account analysis (future enhancement)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│          IAM Access Analyzer Module                     │
└─────────────────────────────────────────────────────────┘
                         │
                         ↓
         ┌───────────────────────────────┐
         │  aws_accessanalyzer_analyzer  │
         │  Type: ACCOUNT                │
         │  Status: ACTIVE               │
         └───────────────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          ↓                             ↓
┌────────────────────┐      ┌──────────────────────┐
│  Archive Rule      │      │  Optional: SNS       │
│  (Auto-archive     │      │  Notifications       │
│   resolved)        │      │  (EventBridge)       │
└────────────────────┘      └──────────────────────┘
          │
          ↓
┌─────────────────────────────────────┐
│  Findings Detection:                │
│  • S3 bucket policies               │
│  • IAM role trust relationships     │
│  • KMS key policies                 │
│  • Lambda function permissions      │
│  • SQS queue policies               │
│  • SNS topic policies               │
│  • Secrets Manager secrets          │
│  • ECS task execution roles         │
└─────────────────────────────────────┘
          │
          ↓ (Automatic)
┌─────────────────────────────────────┐
│      AWS Security Hub               │
│  (Centralized Findings Dashboard)   │
└─────────────────────────────────────┘
```

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws provider | ~> 5.0 |

### AWS Permissions Required

The IAM principal running Terraform must have:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "access-analyzer:CreateAnalyzer",
        "access-analyzer:DeleteAnalyzer",
        "access-analyzer:GetAnalyzer",
        "access-analyzer:ListAnalyzers",
        "access-analyzer:TagResource",
        "access-analyzer:UntagResource",
        "access-analyzer:CreateArchiveRule",
        "access-analyzer:DeleteArchiveRule",
        "access-analyzer:GetArchiveRule",
        "access-analyzer:ListArchiveRules"
      ],
      "Resource": "*"
    }
  ]
}
```

**Optional (for SNS notifications):**
```json
{
  "Effect": "Allow",
  "Action": [
    "sns:CreateTopic",
    "sns:DeleteTopic",
    "sns:Subscribe",
    "sns:Unsubscribe",
    "sns:SetTopicAttributes",
    "events:PutRule",
    "events:DeleteRule",
    "events:PutTargets",
    "events:RemoveTargets"
  ],
  "Resource": "*"
}
```

---

## Resources Created

This module creates the following AWS resources:

| Resource | Type | Count | Purpose |
|----------|------|-------|---------|
| `aws_accessanalyzer_analyzer` | Core | 1 | Account-level analyzer |
| `aws_accessanalyzer_archive_rule` | Optional | 0-1 | Auto-archives resolved findings |
| `aws_cloudwatch_event_rule` | Optional | 0-1 | EventBridge rule for findings |
| `aws_cloudwatch_event_target` | Optional | 0-1 | Route findings to SNS |
| `aws_sns_topic` | Optional | 0-1 | Notification topic |
| `aws_sns_topic_policy` | Optional | 0-1 | Allow EventBridge to publish |
| `aws_sns_topic_subscription` | Optional | 0-N | Email subscriptions |

**Total Resources (Base Configuration):** 2 (analyzer + archive rule)
**Total Resources (With SNS):** 5+ (adds 3 + N email subscriptions)

---

## Usage

### Basic Usage (Recommended for Phase 1)

```hcl
module "access_analyzer" {
  source = "../../modules/access-analyzer"

  environment  = "dev"
  project_name = "my-project"
  common_tags = {
    Project     = "MyProject"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  # Analyzer configuration
  analyzer_type = "ACCOUNT"

  # Archive resolved findings
  enable_archive_rule              = true
  archive_findings_older_than_days = 90

  # SNS notifications disabled (cost optimization)
  enable_sns_notifications = false
}
```

### With SNS Notifications

```hcl
module "access_analyzer" {
  source = "../../modules/access-analyzer"

  environment  = "dev"
  project_name = "my-project"
  common_tags  = local.common_tags

  analyzer_type = "ACCOUNT"

  # Archive settings
  enable_archive_rule              = true
  archive_findings_older_than_days = 90

  # Enable SNS notifications
  enable_sns_notifications = true
  kms_key_arn              = module.foundation.kms_key_arn
  sns_email_subscriptions = [
    "security-team@example.com",
    "compliance@example.com"
  ]
}
```

### Production Configuration

```hcl
module "access_analyzer" {
  source = "../../modules/access-analyzer"

  environment  = "prod"
  project_name = "my-project"
  common_tags  = local.common_tags

  analyzer_type = "ACCOUNT"

  # Longer archive threshold for production
  enable_archive_rule              = true
  archive_findings_older_than_days = 365

  # Production alerting enabled
  enable_sns_notifications = true
  kms_key_arn              = module.kms.key_arn
  sns_email_subscriptions = [
    "security-alerts@example.com"
  ]
}
```

---

## Input Variables

### Required Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `environment` | Environment name (dev, staging, prod) | `string` | - |
| `project_name` | Project name for resource naming | `string` | `"iam-secure-gate"` |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `common_tags` | Common tags to apply to all resources | `map(string)` | `{}` |
| `analyzer_type` | Analyzer type (ACCOUNT or ORGANIZATION) | `string` | `"ACCOUNT"` |
| `enable_archive_rule` | Create archive rule for resolved findings | `bool` | `true` |
| `archive_findings_older_than_days` | Archive threshold (30-365 days) | `number` | `90` |
| `enable_sns_notifications` | Enable SNS notifications for new findings | `bool` | `false` |
| `kms_key_arn` | KMS key ARN for SNS encryption | `string` | `null` |
| `sns_email_subscriptions` | List of email addresses for notifications | `list(string)` | `[]` |

### Variable Validation

- `environment`: Must be `dev`, `staging`, or `prod`
- `project_name`: Only lowercase letters, numbers, and hyphens
- `analyzer_type`: Must be `ACCOUNT` or `ORGANIZATION`
- `archive_findings_older_than_days`: Between 30 and 365 days
- `kms_key_arn`: Must be valid KMS key ARN or null
- `sns_email_subscriptions`: All entries must be valid email addresses

---

## Outputs

### Core Outputs

| Name | Description |
|------|-------------|
| `analyzer_id` | Access Analyzer ID |
| `analyzer_arn` | Access Analyzer ARN |
| `analyzer_name` | Access Analyzer name |
| `analyzer_type` | Analyzer type (ACCOUNT or ORGANIZATION) |

### Archive Rule Outputs

| Name | Description |
|------|-------------|
| `archive_rule_name` | Archive rule name (null if disabled) |
| `archive_threshold_days` | Days after which findings are archived |

### SNS Outputs

| Name | Description |
|------|-------------|
| `sns_topic_arn` | SNS topic ARN (null if disabled) |
| `sns_topic_name` | SNS topic name (null if disabled) |
| `eventbridge_rule_arn` | EventBridge rule ARN (null if disabled) |

### Structured Summary

| Name | Description |
|------|-------------|
| `analyzer_summary` | Comprehensive configuration summary object |

**Summary Object Structure:**
```hcl
{
  environment              = "dev"
  region                   = "eu-west-1"
  account_id               = "123456789012"
  analyzer_name            = "my-project-dev-analyzer"
  analyzer_arn             = "arn:aws:access-analyzer:..."
  analyzer_type            = "ACCOUNT"
  analyzer_status          = "ACTIVE"
  archive_rule_enabled     = true
  archive_threshold_days   = 90
  sns_notifications        = false
  security_hub_integration = true
  cis_controls_supported   = [
    "CIS 1.15 - IAM external access detection",
    "CIS 1.16 - IAM policy analysis"
  ]
  monthly_cost_usd = 0.00
}
```

---

## CIS AWS Foundations Benchmark Compliance

This module helps achieve compliance with the following CIS controls:

| CIS Control | Requirement | Implementation |
|-------------|-------------|----------------|
| **CIS 1.15** | Ensure IAM users receive permissions only through groups | Detects IAM roles with external trust relationships |
| **CIS 1.16** | Ensure IAM policies are attached only to groups or roles | Analyzes IAM policies for external access |
| **CIS 3.x** | IAM Policy Analysis | Identifies overly permissive resource-based policies |

**Note:** Access Analyzer complements (but does not replace) other CIS controls. It focuses on **external access detection** rather than general IAM best practices.

---

## What Access Analyzer Detects

### Supported Resource Types

Access Analyzer scans the following AWS resources:

1. **S3 Buckets**
   - Bucket policies allowing external access
   - Public read/write permissions
   - Cross-account bucket sharing

2. **IAM Roles**
   - Trust policies allowing external principals
   - Cross-account role assumptions
   - Third-party service access

3. **KMS Keys**
   - Key policies granting external access
   - Cross-account key usage permissions

4. **Lambda Functions**
   - Function policies allowing external invocation
   - Cross-account Lambda permissions

5. **SQS Queues**
   - Queue policies allowing external access
   - Cross-account message sending/receiving

6. **SNS Topics**
   - Topic policies allowing external subscriptions
   - Cross-account publish permissions

7. **Secrets Manager**
   - Secret policies granting external access
   - Cross-account secret sharing

8. **ECS Tasks**
   - Task execution role trust policies
   - External service access

### Finding Types

Access Analyzer generates findings for:
- ✅ **External Access** - Resource accessible from outside your account
- ✅ **Public Access** - Resource accessible from the internet
- ✅ **Cross-Account Access** - Resource shared with specific AWS accounts
- ✅ **Service Access** - Resource accessible by AWS services

---

## Cost

**Monthly Cost:** $0.00 (FREE)

AWS IAM Access Analyzer is a **completely free service** with no charges for:
- Analyzer creation
- Findings generation
- Archive rules
- API calls

**Optional Costs:**
- **SNS Topic:** $0.00 (first 1,000 email notifications free, then $0.50/million)
- **EventBridge Rule:** $1.00 per million events (unlikely to exceed free tier)
- **KMS Encryption:** Included in your existing KMS key cost

**Estimated Monthly Cost (with SNS):** < $0.50 for most workloads

---

## Verification

### Post-Deployment Verification

```bash
# 1. List analyzers
aws accessanalyzer list-analyzers --region eu-west-1

# Expected output:
# {
#   "analyzers": [{
#     "name": "my-project-dev-analyzer",
#     "type": "ACCOUNT",
#     "status": "ACTIVE",
#     "arn": "arn:aws:access-analyzer:eu-west-1:123456789012:analyzer/..."
#   }]
# }

# 2. Check analyzer status
ANALYZER_ARN=$(terraform output -raw access_analyzer_arn)
aws accessanalyzer get-analyzer --analyzer-name $ANALYZER_ARN --region eu-west-1

# 3. List findings
aws accessanalyzer list-findings \
  --analyzer-arn $ANALYZER_ARN \
  --region eu-west-1

# 4. List archive rules
aws accessanalyzer list-archive-rules \
  --analyzer-name "my-project-dev-analyzer" \
  --region eu-west-1
```

### Test External Access Detection

```bash
# Create test IAM role with external trust
aws iam create-role \
  --role-name test-external-trust \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Wait 1-5 minutes for analysis
sleep 300

# Check for finding
aws accessanalyzer list-findings \
  --analyzer-arn $(terraform output -raw access_analyzer_arn) \
  --filter '{"resourceType":{"eq":["AWS::IAM::Role"]}}' \
  --region eu-west-1

# Expected: Finding showing external access to test-external-trust role

# Cleanup
aws iam delete-role --role-name test-external-trust
```

### Verify Security Hub Integration

```bash
# Check Access Analyzer findings in Security Hub
aws securityhub get-findings \
  --filters '{"ProductName":[{"Value":"IAM Access Analyzer","Comparison":"EQUALS"}]}' \
  --region eu-west-1
```

---

## Security Considerations

### Archive Rule Behavior

**Important:** The default archive rule archives findings with `status = RESOLVED`. This means:
- ✅ Resolved findings are automatically archived (reduces noise)
- ✅ Active findings remain visible
- ⚠️ If you resolve a finding manually, it will be archived
- ⚠️ Archived findings are not deleted, just hidden from default views

**To view archived findings:**
```bash
aws accessanalyzer list-findings \
  --analyzer-arn $(terraform output -raw access_analyzer_arn) \
  --filter '{"status":{"eq":["RESOLVED"]}}' \
  --region eu-west-1
```

### False Positives

Access Analyzer may generate findings for intentional cross-account access:
- Intentional resource sharing with partner accounts
- AWS service access (e.g., CloudTrail → S3, Config → S3)
- Intentional public buckets (e.g., static website hosting)

**Recommendation:** Review findings and archive intentional access patterns using custom archive rules.

---

## Troubleshooting

### Issue: No Findings Generated

**Possible Causes:**
1. No resources with external access exist (good!)
2. Analyzer still analyzing resources (wait 5-10 minutes after creation)
3. Analyzer in wrong region

**Solution:**
```bash
# Check analyzer status
aws accessanalyzer get-analyzer \
  --analyzer-name "my-project-dev-analyzer" \
  --region eu-west-1

# Create test resource with external access (see verification section)
```

### Issue: SNS Notifications Not Received

**Possible Causes:**
1. Email subscription not confirmed
2. EventBridge rule not triggering
3. SNS topic policy incorrect

**Solution:**
```bash
# Check SNS subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --region eu-west-1

# Check EventBridge rule
aws events describe-rule \
  --name "my-project-dev-analyzer-findings" \
  --region eu-west-1

# Test SNS manually
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --message "Test notification" \
  --region eu-west-1
```

---

## Module Dependencies

### Upstream Dependencies (Required)
- None - This module is standalone

### Downstream Dependencies (Optional)
- **Security Hub Module**: Access Analyzer findings automatically sent to Security Hub when both are enabled
- **Foundation Module**: Can use foundation KMS key for SNS encryption (optional)

### Integration Pattern

```hcl
# Typical integration in environment
module "foundation" {
  source = "../../modules/foundation"
  # ...
}

module "access_analyzer" {
  source = "../../modules/access-analyzer"
  # ...
  kms_key_arn = module.foundation.kms_key_arn  # Optional
}

module "security_hub" {
  source = "../../modules/security-hub"
  # ...
  depends_on = [module.access_analyzer]  # Ensures integration
}
```

---

## Changelog

### Version 2.0 (January 2026) - Phase 1 Complete
- ✅ Production-ready module
- ✅ Archive rule for resolved findings
- ✅ Optional SNS notifications via EventBridge
- ✅ Email subscription support
- ✅ Automatic Security Hub integration
- ✅ Comprehensive documentation

---

## License

This module is part of the IaC-Secure-Gate project.

---

## Authors

**IaC-Secure-Gate Project**
Phase 1: Detection Baseline

---

## Support

For issues, questions, or contributions, please refer to the main project documentation.
