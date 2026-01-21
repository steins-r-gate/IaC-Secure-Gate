# AWS Security Hub Terraform Module

**Purpose:** Centralized security findings aggregation, compliance dashboards, and automated security posture monitoring across AWS services.

**Version:** 2.0 (Phase 1)
**Status:** Production-Ready ✅

---

## Overview

This module deploys AWS Security Hub to provide a comprehensive view of your security state across AWS accounts and services. Security Hub aggregates, organizes, and prioritizes security findings from multiple AWS services (Config, Access Analyzer, GuardDuty, etc.) and provides automated compliance checks against industry standards.

**What it does:**
- Aggregates findings from AWS Config, IAM Access Analyzer, and other security services
- Enables CIS AWS Foundations Benchmark automated compliance checks
- Enables AWS Foundational Security Best Practices automated checks
- Provides centralized security dashboard with severity ratings
- Supports custom control suppression for environment-specific needs
- Optional SNS notifications for critical/high severity findings
- Optional cross-region finding aggregation

---

## Features

### Core Capabilities
- ✅ **CIS AWS Foundations Benchmark** - Automated compliance checks (25 controls in v1.4.0)
- ✅ **AWS Foundational Security Best Practices** - Automated security checks (200+ controls)
- ✅ **Multi-Service Integration** - Auto-ingests findings from Config, Access Analyzer
- ✅ **Centralized Dashboard** - Single pane of glass for all security findings
- ✅ **Severity Scoring** - CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL ratings
- ✅ **Compliance Reporting** - Track compliance scores over time

### Optional Features (Configurable)
- 🔔 **SNS Notifications** - Alerts for critical/high severity findings
- 📧 **Email Subscriptions** - Configurable email notifications
- 🌍 **Finding Aggregation** - Multi-region aggregation (for multi-region deployments)
- 🎯 **Control Suppression** - Disable specific controls not applicable to your environment

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              AWS Security Hub Module                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ↓
         ┌─────────────────────────────────┐
         │  aws_securityhub_account        │
         │  (Hub Enabled)                  │
         └─────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ↓                ↓                ↓
┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐
│  CIS Standard    │  │ Foundational │  │  Product         │
│  v1.4.0          │  │ Standard     │  │  Integrations    │
│  (25 controls)   │  │ v1.0.0       │  │  • Config        │
│                  │  │ (200+ ctrls) │  │  • Access        │
│                  │  │              │  │    Analyzer      │
└──────────────────┘  └──────────────┘  └──────────────────┘
                           │
          ┌────────────────┴────────────────┐
          ↓                                 ↓
┌──────────────────────┐        ┌────────────────────┐
│  Findings Ingestion  │        │  Optional: SNS     │
│  • Config rules      │        │  Notifications     │
│  • Access Analyzer   │        │  (Critical/High)   │
│  • CloudTrail (via   │        └────────────────────┘
│    Config)           │
└──────────────────────┘
          │
          ↓
┌─────────────────────────────────────┐
│  Security Hub Dashboard             │
│  • Findings by severity             │
│  • Compliance score                 │
│  • Resource-level insights          │
│  • Remediation guidance             │
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
        "securityhub:EnableSecurityHub",
        "securityhub:DisableSecurityHub",
        "securityhub:GetEnabledStandards",
        "securityhub:BatchEnableStandards",
        "securityhub:BatchDisableStandards",
        "securityhub:DescribeStandards",
        "securityhub:GetFindings",
        "securityhub:EnableImportFindingsForProduct",
        "securityhub:DisableImportFindingsForProduct",
        "securityhub:UpdateStandardsControl"
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
    "sns:SetTopicAttributes",
    "events:PutRule",
    "events:DeleteRule",
    "events:PutTargets"
  ],
  "Resource": "*"
}
```

---

## Resources Created

This module creates the following AWS resources:

| Resource | Type | Count | Purpose |
|----------|------|-------|---------|
| `aws_securityhub_account` | Core | 1 | Enable Security Hub |
| `aws_securityhub_standards_subscription` | Standards | 0-2 | CIS + Foundational standards |
| `aws_securityhub_product_subscription` | Integration | 0-2 | Config + Access Analyzer |
| `aws_securityhub_finding_aggregator` | Optional | 0-1 | Multi-region aggregation |
| `aws_securityhub_standards_control` | Optional | 0-N | Control suppression |
| `aws_cloudwatch_event_rule` | Optional | 0-1 | EventBridge rule for findings |
| `aws_cloudwatch_event_target` | Optional | 0-1 | Route findings to SNS |
| `aws_sns_topic` | Optional | 0-1 | Notification topic |
| `aws_sns_topic_policy` | Optional | 0-1 | Allow EventBridge to publish |
| `aws_sns_topic_subscription` | Optional | 0-N | Email subscriptions |

**Total Resources (Base Configuration):** 5 (account + 2 standards + 2 integrations)
**Total Resources (With SNS):** 9+ (adds 4 + N email subscriptions)

---

## Usage

### Basic Usage (Recommended for Phase 1)

```hcl
module "security_hub" {
  source = "../../modules/security-hub"

  environment  = "dev"
  project_name = "my-project"
  common_tags = {
    Project     = "MyProject"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  # Enable both standards
  enable_cis_standard          = true
  cis_standard_version         = "1.4.0"
  enable_foundational_standard = true
  foundational_standard_version = "1.0.0"

  # Enable integrations
  enable_config_integration          = true
  enable_access_analyzer_integration = true

  # Single region (no aggregation)
  enable_finding_aggregation = false

  # No control suppression
  disabled_control_ids = []

  # SNS disabled (cost optimization)
  enable_critical_finding_notifications = false

  # Ensure detection services are active
  depends_on = [
    module.config,
    module.access_analyzer
  ]
}
```

### With Critical Finding Notifications

```hcl
module "security_hub" {
  source = "../../modules/security-hub"

  environment  = "prod"
  project_name = "my-project"
  common_tags  = local.common_tags

  # Standards
  enable_cis_standard          = true
  cis_standard_version         = "1.4.0"
  enable_foundational_standard = true

  # Integrations
  enable_config_integration          = true
  enable_access_analyzer_integration = true

  # Multi-region aggregation
  enable_finding_aggregation = false

  # Enable SNS for critical findings
  enable_critical_finding_notifications = true
  kms_key_arn                           = module.foundation.kms_key_arn
  sns_email_subscriptions = [
    "security-team@example.com",
    "soc@example.com"
  ]

  depends_on = [module.config, module.access_analyzer]
}
```

### With Control Suppression

```hcl
module "security_hub" {
  source = "../../modules/security-hub"

  environment  = "dev"
  project_name = "my-project"
  common_tags  = local.common_tags

  # Standards
  enable_cis_standard          = true
  cis_standard_version         = "1.4.0"
  enable_foundational_standard = true

  # Integrations
  enable_config_integration          = true
  enable_access_analyzer_integration = true

  # Disable controls not applicable to dev
  disabled_control_ids = [
    "cis-aws-foundations-benchmark/v/1.4.0/1.1",  # Root MFA (root not used)
    "cis-aws-foundations-benchmark/v/1.4.0/1.14", # Access key rotation
  ]

  enable_critical_finding_notifications = false

  depends_on = [module.config, module.access_analyzer]
}
```

### Multi-Region Aggregation

```hcl
module "security_hub" {
  source = "../../modules/security-hub"

  environment  = "prod"
  project_name = "my-project"
  common_tags  = local.common_tags

  # Standards
  enable_cis_standard = true
  cis_standard_version = "1.4.0"
  enable_foundational_standard = true

  # Integrations
  enable_config_integration          = true
  enable_access_analyzer_integration = true

  # Enable multi-region aggregation
  enable_finding_aggregation       = true
  finding_aggregation_linking_mode = "ALL_REGIONS"  # Aggregate from all regions

  enable_critical_finding_notifications = true
  kms_key_arn                           = module.foundation.kms_key_arn
  sns_email_subscriptions               = ["security@example.com"]

  depends_on = [module.config, module.access_analyzer]
}
```

---

## Input Variables

### Required Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `environment` | Environment name (dev, staging, prod) | `string` | - |
| `project_name` | Project name for resource naming | `string` | `"iam-secure-gate"` |

### Standards Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_cis_standard` | Enable CIS AWS Foundations Benchmark | `bool` | `true` |
| `cis_standard_version` | CIS version (1.2.0, 1.4.0, 3.0.0) | `string` | `"1.4.0"` |
| `enable_foundational_standard` | Enable AWS Foundational Security Best Practices | `bool` | `true` |
| `foundational_standard_version` | Foundational version | `string` | `"1.0.0"` |

### Integration Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_config_integration` | Enable AWS Config integration | `bool` | `true` |
| `enable_access_analyzer_integration` | Enable IAM Access Analyzer integration | `bool` | `true` |

### Finding Aggregation

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_finding_aggregation` | Enable cross-region aggregation | `bool` | `false` |
| `finding_aggregation_linking_mode` | Linking mode (ALL_REGIONS, SPECIFIED_REGIONS, ALL_REGIONS_EXCEPT_SPECIFIED) | `string` | `"ALL_REGIONS"` |
| `finding_aggregation_regions` | List of regions for SPECIFIED_REGIONS mode | `list(string)` | `[]` |

### Control Suppression

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `disabled_control_ids` | Set of control IDs to disable | `set(string)` | `[]` |

### Notifications

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_critical_finding_notifications` | Enable SNS for critical/high findings | `bool` | `false` |
| `kms_key_arn` | KMS key ARN for SNS encryption | `string` | `null` |
| `sns_email_subscriptions` | List of email addresses | `list(string)` | `[]` |

### Other

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `common_tags` | Common tags to apply to all resources | `map(string)` | `{}` |

---

## Outputs

### Core Outputs

| Name | Description |
|------|-------------|
| `securityhub_account_id` | Security Hub account ID |
| `securityhub_account_arn` | Security Hub account ARN |

### Standards Outputs

| Name | Description |
|------|-------------|
| `cis_standard_arn` | CIS standard subscription ARN (null if disabled) |
| `foundational_standard_arn` | Foundational standard ARN (null if disabled) |
| `enabled_standards` | List of enabled standard names |

### Integration Outputs

| Name | Description |
|------|-------------|
| `config_integration_arn` | Config product integration ARN (null if disabled) |
| `access_analyzer_integration_arn` | Access Analyzer integration ARN (null if disabled) |

### Aggregation Outputs

| Name | Description |
|------|-------------|
| `finding_aggregator_arn` | Finding aggregator ID (null if disabled) |

### Notification Outputs

| Name | Description |
|------|-------------|
| `critical_findings_sns_topic_arn` | SNS topic ARN (null if disabled) |
| `eventbridge_rule_arn` | EventBridge rule ARN (null if disabled) |

### Structured Outputs

| Name | Description |
|------|-------------|
| `control_configuration` | Control counts and configuration summary |
| `securityhub_summary` | Comprehensive configuration summary object |

**Summary Object Structure:**
```hcl
{
  environment                         = "dev"
  region                              = "eu-west-1"
  account_id                          = "123456789012"
  securityhub_enabled                 = true
  securityhub_arn                     = "arn:aws:securityhub:..."
  cis_standard_enabled                = true
  cis_standard_version                = "1.4.0"
  foundational_standard_enabled       = true
  foundational_standard_version       = "1.0.0"
  total_standards_enabled             = 2
  config_integration_enabled          = true
  access_analyzer_integration_enabled = true
  cloudtrail_integration_enabled      = true
  finding_aggregation_enabled         = false
  critical_finding_notifications      = false
  disabled_control_count              = 0
  total_controls_available            = 225
  cis_controls_supported              = [
    "CIS 1.x - IAM controls (14 controls)",
    "CIS 2.x - Storage controls (8 controls)",
    "CIS 3.x - Logging controls (3 controls)"
  ]
  monthly_cost_usd_min = 0.00
  monthly_cost_usd_max = 5.00
}
```

---

## CIS AWS Foundations Benchmark

### CIS Controls by Version

#### CIS v1.4.0 (25 Controls) - Recommended

| Section | Controls | Description |
|---------|----------|-------------|
| **1.x IAM** | 14 | Password policy, MFA, access keys, root account |
| **2.x Storage** | 8 | S3 bucket security, logging, encryption |
| **3.x Logging** | 3 | CloudTrail configuration |

**Key Controls:**
- 1.1: Avoid root account use
- 1.5: Root account MFA enabled
- 1.8-1.11: IAM password policy
- 1.14: Access keys rotated within 90 days
- 2.1.5: S3 bucket logging enabled
- 3.1: CloudTrail enabled in all regions
- 3.2: CloudTrail log file validation enabled

#### CIS v1.2.0 (14 Controls) - Legacy

Older version with fewer controls. Use v1.4.0 for comprehensive coverage.

#### CIS v3.0.0 (28 Controls) - Latest

Newest version with additional controls. May have breaking changes from v1.4.0.

### AWS Foundational Security Best Practices (200+ Controls)

Comprehensive security checks across 30+ AWS services:
- IAM (15+ controls)
- EC2 (20+ controls)
- S3 (10+ controls)
- RDS (15+ controls)
- Lambda (10+ controls)
- VPC (10+ controls)
- ELB (5+ controls)
- And many more...

---

## Control Suppression

### When to Suppress Controls

Suppress controls that:
- Are not applicable to your environment (e.g., root MFA if root is never used)
- Generate excessive false positives
- Conflict with your organization's security policy
- Are managed through alternative means

### How to Suppress Controls

```hcl
disabled_control_ids = [
  "cis-aws-foundations-benchmark/v/1.4.0/1.1",  # Root account use
  "aws-foundational-security-best-practices/v/1.0.0/IAM.6",  # Hardware MFA
]
```

### Finding Control IDs

```bash
# List all controls for CIS standard
aws securityhub describe-standards-controls \
  --standards-subscription-arn "arn:aws:securityhub:eu-west-1:123456789012:subscription/cis-aws-foundations-benchmark/v/1.4.0" \
  --region eu-west-1

# List all controls for Foundational standard
aws securityhub describe-standards-controls \
  --standards-subscription-arn "arn:aws:securityhub:eu-west-1:123456789012:subscription/aws-foundational-security-best-practices/v/1.0.0" \
  --region eu-west-1
```

---

## Cost

### Base Cost

**Monthly Cost:** $0.00 - $5.00

| Component | Cost | Notes |
|-----------|------|-------|
| Security Hub | $0.00 | First 10,000 findings free |
| Finding ingestion | $0.00 - $5.00 | $0.0012 per finding after 10k |
| Standards checks | $0.00 | Included |
| Product integrations | $0.00 | Included |

**Typical Dev Environment:** $0.00 - $1.00/month (usually within free tier)
**Typical Prod Environment:** $3.00 - $5.00/month

### Optional Costs

| Feature | Cost |
|---------|------|
| SNS Topic | $0.00 - $0.50/month (first 1000 emails free) |
| EventBridge Rule | $1.00 per million events (unlikely to exceed) |
| KMS Encryption | Included in existing KMS key cost |

**Total Estimated Cost (Dev):** $3-5/month
**Total Estimated Cost (Prod):** $5-10/month

---

## Verification

### Post-Deployment Verification

```bash
# 1. Check Security Hub is enabled
aws securityhub describe-hub --region eu-west-1

# Expected output:
# {
#   "HubArn": "arn:aws:securityhub:eu-west-1:123456789012:hub/default",
#   "SubscribedAt": "2026-01-20T..."
# }

# 2. List enabled standards
aws securityhub get-enabled-standards --region eu-west-1

# Expected: 2 standards (CIS + Foundational)

# 3. Check control status
aws securityhub describe-standards-controls \
  --standards-subscription-arn "arn:aws:securityhub:eu-west-1:123456789012:subscription/cis-aws-foundations-benchmark/v/1.4.0" \
  --region eu-west-1 \
  --query 'Controls[*].[ControlId, ControlStatus]' \
  --output table

# 4. Check product integrations
aws securityhub list-enabled-products-for-import --region eu-west-1

# Expected: Config and Access Analyzer products

# 5. Get findings count
aws securityhub get-findings \
  --region eu-west-1 \
  --query 'length(Findings)'

# 6. Get critical findings
aws securityhub get-findings \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}' \
  --region eu-west-1
```

### Check Compliance Score

```bash
# Get compliance summary for CIS standard
aws securityhub get-compliance-summary \
  --standards-subscription-arns "arn:aws:securityhub:eu-west-1:123456789012:subscription/cis-aws-foundations-benchmark/v/1.4.0" \
  --region eu-west-1

# Expected output shows pass/fail counts
```

### Verify Config Integration

```bash
# Check Config findings in Security Hub
aws securityhub get-findings \
  --filters '{"ProductName":[{"Value":"Config","Comparison":"EQUALS"}]}' \
  --max-items 10 \
  --region eu-west-1

# Should show Config rule compliance findings
```

### Verify Access Analyzer Integration

```bash
# Check Access Analyzer findings in Security Hub
aws securityhub get-findings \
  --filters '{"ProductName":[{"Value":"IAM Access Analyzer","Comparison":"EQUALS"}]}' \
  --max-items 10 \
  --region eu-west-1

# Should show external access findings
```

---

## Integration Testing

### Test End-to-End Flow

```bash
# 1. Create non-compliant resource
aws iam create-user --user-name test-integration-user

# 2. Wait for Config evaluation (5 minutes)
sleep 300

# 3. Check Config detected it
aws configservice describe-compliance-by-config-rule \
  --config-rule-names iam-user-mfa-enabled \
  --region eu-west-1

# Expected: NON_COMPLIANT

# 4. Check Security Hub received finding
aws securityhub get-findings \
  --filters '{
    "ProductName":[{"Value":"Config","Comparison":"EQUALS"}],
    "ResourceId":[{"Value":"test-integration-user","Comparison":"PREFIX"}]
  }' \
  --region eu-west-1

# Expected: Finding with Severity HIGH, Workflow Status NEW

# 5. Cleanup
aws iam delete-user --user-name test-integration-user
```

---

## Troubleshooting

### Issue: No Findings Appearing

**Possible Causes:**
1. Detection services not enabled (Config, Access Analyzer)
2. Standards still evaluating (wait 15-30 minutes after deployment)
3. All resources are compliant (good!)

**Solution:**
```bash
# Check product integrations
aws securityhub list-enabled-products-for-import --region eu-west-1

# Check standards status
aws securityhub get-enabled-standards --region eu-west-1

# Create test non-compliant resource (see integration testing)
```

### Issue: Too Many Findings

**Possible Causes:**
1. Initial deployment showing all non-compliant resources
2. False positives from controls not applicable to your environment

**Solution:**
```bash
# Suppress irrelevant controls via disabled_control_ids variable

# Or manually suppress in console/API
aws securityhub update-standards-control \
  --standards-control-arn "arn:aws:securityhub:eu-west-1:123456789012:control/cis-aws-foundations-benchmark/v/1.4.0/1.1" \
  --control-status DISABLED \
  --disabled-reason "Root account not used" \
  --region eu-west-1
```

### Issue: SNS Notifications Not Received

**Solution:**
```bash
# Check SNS subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw critical_findings_sns_topic_arn)

# Confirm email subscription (check inbox for confirmation email)

# Test SNS manually
aws sns publish \
  --topic-arn $(terraform output -raw critical_findings_sns_topic_arn) \
  --message "Test notification"
```

---

## Module Dependencies

### Upstream Dependencies (Recommended)
- **Config Module**: Provides configuration compliance findings
- **Access Analyzer Module**: Provides external access findings

### Downstream Dependencies
- None

### Integration Pattern

```hcl
# Typical module orchestration
module "config" {
  source = "../../modules/config"
  # ...
}

module "access_analyzer" {
  source = "../../modules/access-analyzer"
  # ...
}

module "security_hub" {
  source = "../../modules/security-hub"
  # ...
  depends_on = [
    module.config,
    module.access_analyzer
  ]
}
```

**Why `depends_on` is critical:**
- Security Hub product subscriptions require services to be active
- Ensures findings start flowing immediately after deployment
- Prevents "product not found" errors

---

## Best Practices

### 1. Start with CIS v1.4.0
- Most stable and widely adopted version
- Good balance of controls (25) vs maintenance overhead
- Well-documented remediation guidance

### 2. Enable Both Standards
- CIS: Industry compliance
- Foundational: AWS best practices
- Together provide comprehensive coverage

### 3. Suppress Deliberately
- Don't suppress controls to "look good"
- Document why each control is suppressed
- Review suppressed controls quarterly

### 4. Use SNS Selectively
- Only for CRITICAL/HIGH in production
- Avoid alert fatigue
- Consider integrating with ticketing systems (Jira, ServiceNow)

### 5. Monitor Compliance Score
- Track score over time
- Set goals (e.g., >80% pass rate)
- Celebrate improvements

---

## Changelog

### Version 2.0 (January 2026) - Phase 1 Complete
- ✅ Production-ready module
- ✅ CIS AWS Foundations Benchmark v1.4.0 support
- ✅ AWS Foundational Security Best Practices support
- ✅ Automatic Config and Access Analyzer integration
- ✅ Optional multi-region finding aggregation
- ✅ Control suppression support
- ✅ Optional SNS notifications for critical findings
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
