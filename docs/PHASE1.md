# Phase 1: AWS Detection Baseline

**Project:** IAM-Secure-Gate  
**Phase Duration:** Weeks 1-4  
**Status:** Planning → Implementation  
**Last Updated:** December 2025

---

## Table of Contents

1. [Phase Overview](#phase-overview)
2. [Objective & Acceptance Criteria](#objective--acceptance-criteria)
3. [Architecture](#architecture)
4. [Critical Decisions](#critical-decisions)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Cost Analysis](#cost-analysis)
8. [Risks & Mitigations](#risks--mitigations)
9. [Success Metrics](#success-metrics)

---

## Phase Overview

### Goal

Establish a **production-ready, AWS-native IAM misconfiguration detection pipeline** that continuously monitors IAM activity and surfaces security findings through a centralized dashboard, achieving sub-5-minute detection latency for critical violations.

### Scope (In Phase 1)

✅ **Included:**

- CloudTrail with encrypted S3 logging
- AWS Config with IAM-focused compliance rules
- IAM Access Analyzer for external access detection
- Security Hub as centralized findings aggregator
- EventBridge rules for sensitive IAM API call monitoring
- CloudWatch dashboard for real-time visibility
- Complete Terraform automation (local backend)
- Test scenarios demonstrating 5+ misconfiguration detections

❌ **Explicitly Out of Scope (Future Phases):**

- Lambda-based remediation (Phase 2)
- GitHub Actions PR security gate (Phase 3)
- Grafana dashboards and feedback loops (Phase 4)
- Advanced testing and documentation (Phase 5)

### Why This Matters

This phase establishes the **detection foundation** that all future phases depend on. Without reliable, fast detection, automated remediation (Phase 2) and preventive controls (Phase 3) cannot function effectively.

---

## Objective & Acceptance Criteria

### Primary Objective

Build and validate a multi-layered IAM misconfiguration detection system using AWS-native services, fully provisioned via Terraform, that detects critical security violations in under 5 minutes.

### Acceptance Criteria (MVP)

| **ID**  | **Criterion**              | **Measurement Method**                                       | **Target**         | **Priority** |
| ------- | -------------------------- | ------------------------------------------------------------ | ------------------ | ------------ |
| **AC1** | Detection Coverage         | Number of distinct IAM misconfiguration types detected       | ≥5 violation types | P0           |
| **AC2** | Mean Time to Detect (MTTD) | CloudWatch timestamp: IAM API call → Security Hub finding    | <5 minutes         | P0           |
| **AC3** | Infrastructure Deployment  | Terraform apply time with zero manual steps                  | <60 seconds        | P0           |
| **AC4** | Finding Aggregation        | Percentage of detection sources integrated into Security Hub | 100%               | P0           |
| **AC5** | Visibility                 | CloudWatch dashboard operational with real-time data         | Live updates       | P1           |
| **AC6** | Repeatability              | Successful clean teardown and redeploy cycles                | 3 consecutive      | P1           |
| **AC7** | Cost Compliance            | Monthly AWS spend for Phase 1 infrastructure                 | <$8/month          | P2           |

**Priority Levels:**

- **P0:** Must-have for MVP (blocks Phase 1 completion)
- **P1:** Should-have for production-ready (quality requirement)
- **P2:** Nice-to-have (can be adjusted if constraints require)

---

## Architecture

### High-Level Detection Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AWS Account (Single Region: eu-west-1)           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │                    IAM Activity Layer                      │       │
│  │  - User actions (console, CLI, SDK)                       │       │
│  │  - Service-to-service IAM operations                      │       │
│  │  - Policy modifications, access key lifecycle            │       │
│  └───────────────────────────┬──────────────────────────────┘       │
│                               ↓                                       │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │                    Detection Layer                         │       │
│  │                                                            │       │
│  │  ┌──────────────┐      ┌──────────────┐                  │       │
│  │  │  CloudTrail  │      │ EventBridge  │                  │       │
│  │  │  (All IAM    │──┬──→│   Rules      │                  │       │
│  │  │   API calls) │  │   │  (Sensitive  │                  │       │
│  │  └──────────────┘  │   │   patterns)  │                  │       │
│  │         ↓          │   └──────────────┘                  │       │
│  │  ┌──────────────┐  │          ↓                          │       │
│  │  │      S3      │  │   CloudWatch Logs                   │       │
│  │  │ (Encrypted)  │  │   (IAM API metrics)                 │       │
│  │  └──────────────┘  │                                      │       │
│  │                    │                                      │       │
│  │  ┌──────────────┐  │   ┌──────────────┐                  │       │
│  │  │ AWS Config   │  │   │ IAM Access   │                  │       │
│  │  │ - 3 IAM Rules│  │   │  Analyzer    │                  │       │
│  │  │ - Continuous │  │   │ (External    │                  │       │
│  │  │   compliance │  │   │  access)     │                  │       │
│  │  └──────────────┘  │   └──────────────┘                  │       │
│  │         ↓          │          ↓                          │       │
│  │  ┌──────────────┐  │   ┌──────────────┐                  │       │
│  │  │      S3      │  │   │   Findings   │                  │       │
│  │  │ (Snapshots)  │  │   │              │                  │       │
│  │  └──────────────┘  │   └──────────────┘                  │       │
│  └────────────────────┼──────────────────┼──────────────────┘       │
│                       ↓                  ↓                           │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │                  Aggregation Layer                       │        │
│  │                                                           │        │
│  │               ┌──────────────────────┐                   │        │
│  │               │   Security Hub       │                   │        │
│  │               │ ┌──────────────────┐ │                   │        │
│  │               │ │ Foundational     │ │                   │        │
│  │               │ │ Best Practices   │ │                   │        │
│  │               │ └──────────────────┘ │                   │        │
│  │               │ ┌──────────────────┐ │                   │        │
│  │               │ │ CIS Benchmark    │ │                   │        │
│  │               │ └──────────────────┘ │                   │        │
│  │               │                      │                   │        │
│  │               │ Normalized Findings  │                   │        │
│  │               │ (ASFF Format)        │                   │        │
│  │               └──────────────────────┘                   │        │
│  └─────────────────────────┬───────────────────────────────┘        │
│                             ↓                                         │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │                  Visualization Layer                     │        │
│  │                                                           │        │
│  │            CloudWatch Dashboard (4 Widgets)              │        │
│  │  ┌────────────────┐  ┌────────────────┐                 │        │
│  │  │ IAM API Call   │  │ Security Hub   │                 │        │
│  │  │ Volume         │  │ Findings by    │                 │        │
│  │  │                │  │ Severity       │                 │        │
│  │  └────────────────┘  └────────────────┘                 │        │
│  │  ┌────────────────┐  ┌────────────────┐                 │        │
│  │  │ Config Rule    │  │ Access Analyzer│                 │        │
│  │  │ Compliance     │  │ Active Findings│                 │        │
│  │  └────────────────┘  └────────────────┘                 │        │
│  └─────────────────────────────────────────────────────────┘        │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| **Component**           | **Role**                  | **Detection Method**              | **Latency**                        | **Output**                   |
| ----------------------- | ------------------------- | --------------------------------- | ---------------------------------- | ---------------------------- |
| **CloudTrail**          | Audit logging             | Records all IAM API calls         | ~5 seconds                         | S3 logs + EventBridge events |
| **AWS Config**          | Compliance checking       | Evaluates resources against rules | 1-15 minutes                       | Config findings              |
| **IAM Access Analyzer** | External access detection | Analyzes resource policies        | 1-30 minutes                       | Analyzer findings            |
| **EventBridge**         | Real-time routing         | Pattern matching on API calls     | <1 second                          | CloudWatch Logs/Metrics      |
| **Security Hub**        | Finding aggregation       | Ingests from all sources          | <1 minute (after source detection) | Normalized ASFF findings     |
| **CloudWatch**          | Metrics & visualization   | Displays aggregated data          | Real-time                          | Dashboard widgets            |

---

## Critical Decisions

### Decision Log

#### Decision 1: KMS Encryption Strategy

**Question:** Single KMS key or separate keys per service?

**Options:**

- **Option A:** Single KMS key for all logging/detection services
  - Pros: Simplified key management, lower cost ($1/key/month)
  - Cons: Broader access scope if key compromised
- **Option B:** Separate keys per service (CloudTrail, Config, S3)
  - Pros: Better isolation, granular access control
  - Cons: 3x key cost ($3/month), complex key policy management

**Decision:** ✅ **Option A - Single KMS Key**  
**Rationale:** For a student project with trusted single operator, complexity doesn't justify the benefit. Cost savings ($2/month) matter for budget constraints.

**Implementation:**

```hcl
resource "aws_kms_key" "detection_logs" {
  description             = "IAM-Secure-Gate Phase 1 Detection Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}
```

---

#### Decision 2: AWS Config Rules Selection

**Question:** Which 5 IAM rules, given budget constraint of ~$2/rule/month?

**Options:**

- **Option A:** 5 rules ($10/month) - Exceeds budget
- **Option B:** 3 rules ($6/month) - Fits budget
- **Option C:** 2 rules ($4/month) - Maximum safety margin

**Decision:** ✅ **Option B - 3 Core Rules**  
**Rationale:** Balance between coverage and cost. 3 rules detect the most critical IAM violations while staying near budget.

**Selected Rules:**

1. **`iam-root-access-key-check`**
   - Detects: Root account access keys (critical security violation)
   - Severity: CRITICAL
   - Remediation: Auto-delete in Phase 2
2. **`iam-user-mfa-enabled`**
   - Detects: IAM users without MFA for console access
   - Severity: HIGH
   - Remediation: SNS notification for manual fix
3. **`iam-policy-no-statements-with-admin-access`**
   - Detects: Policies granting `AdministratorAccess` or equivalent
   - Severity: HIGH
   - Remediation: Auto-replace with least-privilege policy in Phase 2

**Future Addition (if budget allows):** 4. `access-keys-rotated` (keys older than 90 days) 5. `iam-user-no-policies-check` (direct user policy attachments)

---

#### Decision 3: Config Snapshot Delivery Frequency

**Question:** How often should Config take configuration snapshots?

**Options:**

- **6 hours:** More frequent compliance checks, higher evaluation costs
- **12 hours:** Balanced approach
- **24 hours:** Lowest cost, still meets audit requirements

**Decision:** ✅ **24 Hours**  
**Rationale:** Phase 1 focuses on real-time detection via EventBridge/CloudTrail. Config snapshots are for compliance audit trail, not real-time detection. 24-hour frequency meets CIS benchmark requirements.

---

#### Decision 4: EventBridge Rule Patterns

**Question:** Which IAM API calls are "sensitive" enough to warrant real-time routing?

**Decision:** ✅ **3 High-Risk Pattern Categories**

**Pattern 1: Policy Modifications (Privilege Changes)**

```json
{
  "source": ["aws.iam"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": [
      "PutUserPolicy",
      "PutRolePolicy",
      "PutGroupPolicy",
      "AttachUserPolicy",
      "AttachRolePolicy",
      "AttachGroupPolicy",
      "DeleteUserPolicy",
      "DeleteRolePolicy",
      "DeleteGroupPolicy",
      "DetachUserPolicy",
      "DetachRolePolicy",
      "DetachGroupPolicy"
    ]
  }
}
```

**Pattern 2: Trust Relationship Changes (Lateral Movement Risk)**

```json
{
  "source": ["aws.iam"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": ["UpdateAssumeRolePolicy"]
  }
}
```

**Pattern 3: Root Account Activity (Critical Security Event)**

```json
{
  "source": ["aws.iam"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "userIdentity": {
      "type": ["Root"]
    }
  }
}
```

**Target for Phase 1:** CloudWatch Log Groups (for metrics extraction)  
**Target for Phase 2:** Lambda functions (for auto-remediation)

---

#### Decision 5: Security Hub Standards

**Question:** Which compliance standards to enable?

**Options:**

- AWS Foundational Security Best Practices only
- CIS AWS Foundations Benchmark only
- Both standards

**Decision:** ✅ **Both Standards**  
**Rationale:** Both are free, and they complement each other:

- **Foundational:** Broader coverage (100+ controls across services)
- **CIS:** IAM-specific depth (27 IAM-related controls)

**Cost:** $0 (standards are free, only pay $0.0010 per finding ingested)

---

#### Decision 6: CloudWatch Dashboard Widgets

**Question:** What metrics provide the most value for Phase 1 monitoring?

**Decision:** ✅ **4-Widget Dashboard**

| **Widget**                            | **Data Source**          | **Metric/Query**                                           | **Purpose**                          |
| ------------------------------------- | ------------------------ | ---------------------------------------------------------- | ------------------------------------ |
| **IAM API Call Volume**               | CloudWatch Logs Insights | `filter @message like /IAM/ \| stats count() by eventName` | Detect unusual spike in IAM activity |
| **Security Hub Findings by Severity** | Security Hub API         | `Severity.Label` aggregation                               | Prioritize remediation efforts       |
| **Config Compliance Status**          | AWS Config               | `ComplianceByConfigRule`                                   | Track rule compliance over time      |
| **Access Analyzer Active Findings**   | IAM Access Analyzer      | `FindingCount` by `Status=ACTIVE`                          | Monitor external access grants       |

**Update Frequency:** 1-minute refresh (CloudWatch default)

---

#### Decision 7: S3 Lifecycle Policies

**Question:** How long to retain logs before deletion/archival?

**Decision:** ✅ **Tiered Retention Strategy**

| **Log Type**         | **Hot Storage** | **Glacier** | **Deletion**   | **Rationale**                           |
| -------------------- | --------------- | ----------- | -------------- | --------------------------------------- |
| **CloudTrail**       | 30 days         | 31-90 days  | After 90 days  | CIS Benchmark requires 90-day retention |
| **Config Snapshots** | 90 days         | 91-365 days | After 365 days | Annual compliance audit requirement     |

**Cost Impact:**

- S3 Standard (30 days): ~$0.023/GB/month
- Glacier Flexible (60 days): ~$0.004/GB/month
- **Total for Phase 1:** ~$1-2/month (assuming <50GB logs)

---

#### Decision 8: Tagging Strategy

**Question:** What tags should be applied to all Phase 1 resources?

**Decision:** ✅ **7-Tag Standard Schema**

```hcl
locals {
  phase_1_tags = {
    Project     = "IAM-Secure-Gate"
    Phase       = "Phase-1-Detection"
    Environment = var.environment # dev/prod
    ManagedBy   = "Terraform"
    Owner       = "Steins"         # Your name
    CostCenter  = "University-FYP"
    Repository  = "github.com/yourusername/iam-secure-gate"
  }
}
```

**Benefits:**

- Cost allocation reports by Phase
- Resource filtering in AWS Console
- Compliance audit trail (ManagedBy=Terraform)
- Ownership tracking for multi-contributor projects

---

#### Decision 9: Region Selection

**Question:** Single region or multi-region deployment?

**Decision:** ✅ **Single Region: `eu-west-1` (Ireland)**  
**Rationale:**

- IAM is a global service (changes in any region are logged)
- CloudTrail can be configured as multi-region trail (logs from all regions)
- Cost optimization for student project
- eu-west-1 chosen as user's home region (Dublin, Ireland - low latency)
- Future phases can add regional aggregation

**Important IAM Console Note:**  
While we deploy detection infrastructure in eu-west-1, the AWS IAM console always defaults to showing "Global" or "us-east-1" in the region selector. This is normal behavior - IAM is a global service and your CloudTrail multi-region trail in eu-west-1 will capture all IAM API calls regardless of where they appear to originate in the console.

**Trade-off Accepted:** Regional AWS services (e.g., S3, Lambda in other regions) won't be monitored by Config rules, but IAM is global so no gap in IAM detection.

---

#### Decision 10: Terraform Backend

**Question:** Local state file or remote backend (S3 + DynamoDB)?

**Decision:** ✅ **Local Backend for Phase 1**  
**Rationale:**

- Single developer, no collaboration state conflicts
- Avoids bootstrap chicken-egg problem (need S3 before Terraform?)
- Zero backend infrastructure cost
- Can migrate to remote backend in Phase 4 if needed

**Security Measures:**

- ✅ `.gitignore` includes `*.tfstate*`, `.terraform/`
- ✅ State file encrypted at rest (Windows EFS/BitLocker)
- ✅ No state file committed to Git (verified in pre-commit hook)

---

## Implementation Plan

### Module Structure

```
terraform/
├── modules/
│   ├── foundation/           # KMS key + S3 buckets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── cloudtrail/           # CloudTrail configuration
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── config/               # AWS Config + Rules
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── access-analyzer/      # IAM Access Analyzer
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── security-hub/         # Security Hub + Standards
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── eventbridge/          # EventBridge Rules + Targets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── dashboard/            # CloudWatch Dashboard
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
└── environments/
    └── dev/
        ├── main.tf           # Root module (orchestrates all modules)
        ├── variables.tf      # Environment-specific variables
        ├── outputs.tf        # Outputs for verification
        ├── terraform.tfvars  # Variable values (gitignored)
        └── README.md         # Deployment instructions
```

### Build Order & Dependencies

#### **Step 1: Foundation Module** (Week 1, Days 1-2)

**Estimated Time:** 3 hours  
**Priority:** P0 (blocking all other modules)

**Resources:**

```hcl
# KMS Key for encryption
resource "aws_kms_key" "detection_logs"
resource "aws_kms_alias" "detection_logs"

# S3 Bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail_logs"
resource "aws_s3_bucket_versioning" "cloudtrail_logs"
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs"
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs"
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs"
resource "aws_s3_bucket_policy" "cloudtrail_logs"

# S3 Bucket for Config Snapshots
resource "aws_s3_bucket" "config_snapshots"
resource "aws_s3_bucket_versioning" "config_snapshots"
resource "aws_s3_bucket_lifecycle_configuration" "config_snapshots"
resource "aws_s3_bucket_server_side_encryption_configuration" "config_snapshots"
resource "aws_s3_bucket_public_access_block" "config_snapshots"
resource "aws_s3_bucket_policy" "config_snapshots"
```

**Outputs:**

- `kms_key_id`: For use by CloudTrail/Config
- `cloudtrail_bucket_name`: For CloudTrail module
- `config_bucket_name`: For Config module

**Acceptance Test:**

```bash
# Verify buckets exist and are encrypted
aws s3api get-bucket-encryption --bucket <cloudtrail-bucket-name>
aws s3api get-bucket-versioning --bucket <config-bucket-name>
```

---

#### **Step 2: CloudTrail Module** (Week 1, Days 3-4)

**Estimated Time:** 2 hours  
**Dependencies:** Foundation module  
**Priority:** P0

**Resources:**

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "iam-secure-gate-trail"
  s3_bucket_name                = var.cloudtrail_bucket_name
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_id

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}
```

**Acceptance Test:**

```bash
# Create test IAM user and verify CloudTrail logged it
aws iam create-user --user-name test-trail-user
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser
```

---

#### **Step 3: AWS Config Module** (Week 1-2, Days 5-7)

**Estimated Time:** 4 hours  
**Dependencies:** Foundation module  
**Priority:** P0

**Resources:**

```hcl
# IAM Role for Config
resource "aws_iam_role" "config"
resource "aws_iam_role_policy_attachment" "config"

# Configuration Recorder
resource "aws_config_configuration_recorder" "main"
resource "aws_config_delivery_channel" "main"
resource "aws_config_configuration_recorder_status" "main"

# 3 IAM Rules
resource "aws_config_config_rule" "iam_root_access_key_check"
resource "aws_config_config_rule" "iam_user_mfa_enabled"
resource "aws_config_config_rule" "iam_policy_no_admin_access"
```

**Acceptance Test:**

```bash
# Create IAM user without MFA, verify Config detects non-compliance
aws iam create-user --user-name test-no-mfa-user
aws iam create-login-profile --user-name test-no-mfa-user --password TempPass123!
# Wait 5-10 minutes for Config evaluation
aws configservice describe-compliance-by-config-rule --config-rule-names iam-user-mfa-enabled
```

---

#### **Step 4: IAM Access Analyzer Module** (Week 2, Day 1)

**Estimated Time:** 1 hour  
**Dependencies:** None  
**Priority:** P1

**Resources:**

```hcl
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "iam-secure-gate-analyzer"
  type          = "ACCOUNT"

  tags = local.phase_1_tags
}
```

**Acceptance Test:**

```bash
# Create IAM role with external trust, verify analyzer detects it
aws iam create-role --role-name test-external-trust \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "sts:AssumeRole"
    }]
  }'
# Wait 1-5 minutes
aws accessanalyzer list-findings --analyzer-arn <analyzer-arn>
```

---

#### **Step 5: Security Hub Module** (Week 2, Days 2-3)

**Estimated Time:** 2 hours  
**Dependencies:** CloudTrail, Config, Access Analyzer (for findings integration)  
**Priority:** P0

**Resources:**

```hcl
resource "aws_securityhub_account" "main"

resource "aws_securityhub_standards_subscription" "foundational" {
  standards_arn = "arn:aws:securityhub:eu-west-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:eu-west-1::standards/cis-aws-foundations-benchmark/v/1.2.0"
}
```

**Acceptance Test:**

```bash
# Verify Security Hub ingesting findings from Config and Access Analyzer
aws securityhub get-findings --filters '{"ProductName":[{"Value":"Config","Comparison":"EQUALS"}]}' --max-items 5
aws securityhub get-findings --filters '{"ProductName":[{"Value":"IAM Access Analyzer","Comparison":"EQUALS"}]}' --max-items 5
```

---

#### **Step 6: EventBridge Module** (Week 2, Days 4-5)

**Estimated Time:** 3 hours  
**Dependencies:** CloudTrail  
**Priority:** P1

**Resources:**

```hcl
# CloudWatch Log Groups for each pattern
resource "aws_cloudwatch_log_group" "iam_policy_changes"
resource "aws_cloudwatch_log_group" "trust_policy_changes"
resource "aws_cloudwatch_log_group" "root_account_activity"

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "iam_policy_changes"
resource "aws_cloudwatch_event_rule" "trust_policy_changes"
resource "aws_cloudwatch_event_rule" "root_account_activity"

# EventBridge Targets (CloudWatch Logs)
resource "aws_cloudwatch_event_target" "iam_policy_changes"
resource "aws_cloudwatch_event_target" "trust_policy_changes"
resource "aws_cloudwatch_event_target" "root_account_activity"
```

**Acceptance Test:**

```bash
# Attach policy to test user, verify EventBridge rule triggered
aws iam attach-user-policy --user-name test-user --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
# Check CloudWatch Logs
aws logs tail /aws/events/iam-policy-changes --follow
```

---

#### **Step 7: CloudWatch Dashboard Module** (Week 3, Days 1-3)

**Estimated Time:** 4 hours (JSON dashboard body is tedious)  
**Dependencies:** All detection services operational  
**Priority:** P1

**Resources:**

```hcl
resource "aws_cloudwatch_dashboard" "iam_security" {
  dashboard_name = "IAM-Security-Phase1"

  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: IAM API Call Volume
      # Widget 2: Security Hub Findings by Severity
      # Widget 3: Config Rule Compliance
      # Widget 4: Access Analyzer Active Findings
    ]
  })
}
```

**Acceptance Test:**

```bash
# Open dashboard in AWS Console, verify all 4 widgets displaying data
aws cloudwatch get-dashboard --dashboard-name IAM-Security-Phase1
```

---

#### **Step 8: Root Module Integration** (Week 3, Days 4-5)

**Estimated Time:** 2 hours  
**Priority:** P0

**File:** `terraform/environments/dev/main.tf`

```hcl
module "foundation" {
  source = "../../modules/foundation"
  # ... variables
}

module "cloudtrail" {
  source              = "../../modules/cloudtrail"
  cloudtrail_bucket_name = module.foundation.cloudtrail_bucket_name
  kms_key_id          = module.foundation.kms_key_id
  depends_on          = [module.foundation]
}

module "config" {
  source            = "../../modules/config"
  config_bucket_name = module.foundation.config_bucket_name
  kms_key_id        = module.foundation.kms_key_id
  depends_on        = [module.foundation]
}

module "access_analyzer" {
  source = "../../modules/access-analyzer"
}

module "security_hub" {
  source     = "../../modules/security-hub"
  depends_on = [
    module.cloudtrail,
    module.config,
    module.access_analyzer
  ]
}

module "eventbridge" {
  source     = "../../modules/eventbridge"
  depends_on = [module.cloudtrail]
}

module "dashboard" {
  source     = "../../modules/dashboard"
  depends_on = [
    module.security_hub,
    module.config,
    module.access_analyzer,
    module.eventbridge
  ]
}
```

**Acceptance Test:**

```bash
# Full deployment from scratch
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
time terraform apply tfplan  # Should complete in <60 seconds (AC3)

# Full teardown
terraform destroy -auto-approve

# Redeploy to test repeatability (AC6)
terraform apply -auto-approve
```

---

### PowerShell Automation Scripts

#### **Deploy-Phase1.ps1** (Week 3, Day 5)

```powershell
# Automated deployment script
# 1. Source AWS credentials (Set-AWSEnvironment.ps1)
# 2. Terraform init/plan/apply
# 3. Run acceptance tests
# 4. Generate deployment report
```

#### **Test-Phase1.ps1** (Week 4, Days 1-3)

```powershell
# Test scenario orchestration
# 1. Create 5 IAM misconfigurations
# 2. Wait for detection (max 5 minutes)
# 3. Query Security Hub for findings
# 4. Calculate MTTD
# 5. Generate test report
```

#### **Cleanup-Phase1.ps1** (Week 4, Day 4)

```powershell
# Clean teardown
# 1. Terraform destroy
# 2. Verify all resources deleted
# 3. Check for orphaned resources (manual cleanup if needed)
```

---

## Testing Strategy

### Prerequisites for Testing

Before executing test scenarios, ensure your AWS CLI is configured for the correct region:

**Option 1: Set Default Region (Recommended)**

```bash
# Configure AWS CLI to default to eu-west-1
aws configure set region eu-west-1

# Verify configuration
aws configure get region
# Should output: eu-west-1
```

**Option 2: Use --region Flag**

```bash
# Add --region eu-west-1 to every AWS CLI command
aws iam create-user --user-name test-user --region eu-west-1
```

**Important Notes:**

- IAM commands work globally regardless of region setting, but other services (Config, Security Hub, Access Analyzer) are regional
- All test commands below assume your default region is set to `eu-west-1`
- If using PowerShell scripts, they should automatically use eu-west-1 via AWS credential configuration

---

### Test Scenarios (5 Required for AC1)

#### **Scenario 1: Root Account Access Key Creation**

**Violation Type:** Critical - Root credential exposure  
**Detection Method:** Config rule `iam-root-access-key-check`

**Test Steps:**

```bash
# 1. Attempt to create root access key (will fail in real environment, simulate in test account)
aws iam create-access-key --user-name root

# 2. Expected Detection Time: 1-5 minutes (Config evaluation period)

# 3. Verify Security Hub Finding:
aws securityhub get-findings \
  --filters '{
    "ProductName": [{"Value": "Config", "Comparison": "EQUALS"}],
    "ComplianceStatus": [{"Value": "FAILED", "Comparison": "EQUALS"}],
    "Title": [{"Value": "iam-root-access-key-check", "Comparison": "PREFIX"}]
  }'

# 4. Expected Result:
# - Finding with Severity: CRITICAL
# - Recommendation: "Remove root access keys"
```

**Success Criteria:**

- Finding appears in Security Hub within 5 minutes
- Severity correctly set to CRITICAL
- CloudWatch dashboard "Config Compliance" widget shows non-compliant resource

---

#### **Scenario 2: IAM User Without MFA**

**Violation Type:** High - Weak authentication  
**Detection Method:** Config rule `iam-user-mfa-enabled`

**Test Steps:**

```bash
# 1. Create IAM user with console access but no MFA
aws iam create-user --user-name test-no-mfa-user
aws iam create-login-profile \
  --user-name test-no-mfa-user \
  --password 'TempPassword123!' \
  --password-reset-required

# 2. Expected Detection Time: 1-5 minutes

# 3. Verify Finding:
aws securityhub get-findings \
  --filters '{
    "ResourceId": [{"Value": "test-no-mfa-user", "Comparison": "PREFIX"}],
    "ComplianceStatus": [{"Value": "FAILED", "Comparison": "EQUALS"}]
  }'

# 4. Cleanup:
aws iam delete-login-profile --user-name test-no-mfa-user
aws iam delete-user --user-name test-no-mfa-user
```

**Success Criteria:**

- Detection latency <5 minutes
- Finding includes resource ID (username)
- Remediation recommendation provided

---

#### **Scenario 3: AdministratorAccess Policy Attachment**

**Violation Type:** High - Excessive permissions  
**Detection Method:** Config rule `iam-policy-no-statements-with-admin-access`

**Test Steps:**

```bash
# 1. Create test user and attach admin policy
aws iam create-user --user-name test-admin-user
aws iam attach-user-policy \
  --user-name test-admin-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 2. Verify EventBridge captures the API call immediately
aws logs tail /aws/events/iam-policy-changes --since 1m

# 3. Wait for Config evaluation (1-5 minutes)

# 4. Verify Security Hub Finding:
aws securityhub get-findings \
  --filters '{
    "ResourceId": [{"Value": "test-admin-user", "Comparison": "PREFIX"}],
    "Title": [{"Value": "Administrator access", "Comparison": "PREFIX"}]
  }'

# 5. Calculate MTTD:
# MTTD = (Security Hub Finding CreatedAt) - (CloudTrail Event Time)

# 6. Cleanup:
aws iam detach-user-policy \
  --user-name test-admin-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-user --user-name test-admin-user
```

**Success Criteria:**

- EventBridge logs API call within 1 second
- Security Hub finding within 5 minutes
- MTTD calculation documented in test report

---

#### **Scenario 4: External IAM Role Trust Relationship**

**Violation Type:** Medium - Potential lateral movement  
**Detection Method:** IAM Access Analyzer

**Test Steps:**

```bash
# 1. Create IAM role with external AWS account trust
aws iam create-role \
  --role-name test-external-trust-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "sts:AssumeRole"
    }]
  }'

# 2. Expected Detection Time: 1-30 minutes (Access Analyzer analysis period)

# 3. Verify Access Analyzer Finding:
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:eu-west-1:YOUR_ACCOUNT_ID:analyzer/iam-secure-gate-analyzer \
  --filter '{"resource": {"contains": ["test-external-trust-role"]}}'

# 4. Verify Security Hub Ingestion:
aws securityhub get-findings \
  --filters '{
    "ProductName": [{"Value": "IAM Access Analyzer", "Comparison": "EQUALS"}],
    "ResourceId": [{"Value": "test-external-trust-role", "Comparison": "PREFIX"}]
  }'

# 5. Cleanup:
aws iam delete-role --role-name test-external-trust-role
```

**Success Criteria:**

- Access Analyzer detects external access grant
- Finding severity: MEDIUM or HIGH
- Security Hub displays finding with "External Access" category

---

#### **Scenario 5: Root Account Console Login**

**Violation Type:** Critical - Violation of least privilege  
**Detection Method:** EventBridge rule for Root activity + CIS Benchmark control

**Test Steps:**

```bash
# 1. Simulate root login (use CloudTrail event injection if real root login not feasible)
# Alternative: Review existing CloudTrail logs for any root activity

# 2. Verify EventBridge Rule Trigger:
aws logs filter-log-events \
  --log-group-name /aws/events/root-account-activity \
  --filter-pattern "Root" \
  --start-time $(date -u -d '5 minutes ago' +%s)000

# 3. Verify Security Hub CIS Control:
aws securityhub get-findings \
  --filters '{
    "GeneratorId": [{"Value": "cis-aws-foundations-benchmark/v/1.2.0/1.1", "Comparison": "PREFIX"}]
  }'

# 4. Expected Results:
# - EventBridge logs root activity within seconds
# - Security Hub CIS finding with Severity: CRITICAL
# - Dashboard widget "Security Hub Findings by Severity" shows CRITICAL alert
```

**Success Criteria:**

- Real-time detection (<1 minute) via EventBridge
- CIS Benchmark control flagged in Security Hub
- CloudWatch dashboard updates with critical finding

---

### Test Execution Plan (Week 4, Days 1-3)

**Day 1: Infrastructure Validation**

- Deploy Phase 1 from scratch (repeatability test)
- Verify all 7 modules deployed successfully
- Check CloudWatch dashboard displays baseline (no findings yet)

**Day 2: Violation Injection**

- Execute 5 test scenarios sequentially (15-minute spacing)
- Monitor CloudWatch Logs for EventBridge triggers
- Record timestamps for MTTD calculation

**Day 3: Finding Analysis**

- Query Security Hub for all findings
- Calculate MTTD for each scenario
- Generate test report with pass/fail criteria
- Screenshot dashboard showing findings

**Test Report Template:**

```markdown
# Phase 1 Test Report

## Test Execution Summary

- Date: [Date]
- Duration: 3 hours
- Scenarios Executed: 5
- Pass Rate: X/5 (XX%)

## MTTD Analysis

| Scenario        | IAM API Call Time | Security Hub Finding Time | MTTD  | Target | Pass/Fail |
| --------------- | ----------------- | ------------------------- | ----- | ------ | --------- |
| Root Access Key | HH:MM:SS          | HH:MM:SS                  | X min | <5 min | ✅/❌     |
| User No MFA     | HH:MM:SS          | HH:MM:SS                  | X min | <5 min | ✅/❌     |
| Admin Policy    | HH:MM:SS          | HH:MM:SS                  | X min | <5 min | ✅/❌     |
| External Trust  | HH:MM:SS          | HH:MM:SS                  | X min | <5 min | ✅/❌     |
| Root Login      | HH:MM:SS          | HH:MM:SS                  | X min | <5 min | ✅/❌     |

**Average MTTD:** X.X minutes

## Findings Analysis

[Screenshot of Security Hub findings]
[Screenshot of CloudWatch dashboard]

## Issues Identified

- [Any false positives]
- [Any missed detections]
- [Performance bottlenecks]

## Recommendations for Phase 2

- [Findings that should be auto-remediated]
- [Findings that require human approval]
```

---

## Cost Analysis

### Monthly Cost Breakdown (Phase 1)

| **Service**             | **Resource**                | **Quantity** | **Unit Cost**   | **Monthly Cost** | **Notes**                 |
| ----------------------- | --------------------------- | ------------ | --------------- | ---------------- | ------------------------- |
| **KMS**                 | Customer-managed key        | 1            | $1.00/key       | $1.00            | Includes key rotation     |
| **S3**                  | CloudTrail logs (Standard)  | ~10 GB       | $0.023/GB       | $0.23            | 30-day hot storage        |
| **S3**                  | CloudTrail logs (Glacier)   | ~20 GB       | $0.004/GB       | $0.08            | 31-90 day archive         |
| **S3**                  | Config snapshots (Standard) | ~5 GB        | $0.023/GB       | $0.12            | 90-day hot storage        |
| **S3**                  | Config snapshots (Glacier)  | ~40 GB       | $0.004/GB       | $0.16            | 91-365 day archive        |
| **CloudTrail**          | Multi-region trail          | 1            | $0.00           | $0.00            | First trail free          |
| **AWS Config**          | Configuration recorder      | 1            | $0.00           | $0.00            | Included with rules       |
| **AWS Config**          | Config rules                | 3            | $2.00/rule      | $6.00            | ⚠️ Largest cost           |
| **IAM Access Analyzer** | Account analyzer            | 1            | $0.00           | $0.00            | No charge                 |
| **Security Hub**        | Findings ingestion          | ~100/day     | $0.0010/finding | $3.00            | After free tier           |
| **EventBridge**         | Rule evaluations            | ~1M/month    | $0.00           | $0.00            | First 1M free             |
| **CloudWatch**          | Dashboard                   | 1            | $3.00/dashboard | $3.00            | Custom dashboards         |
| **CloudWatch**          | Log storage                 | ~2 GB        | $0.50/GB        | $1.00            | EventBridge targets       |
| **Data Transfer**       | S3 → Services               | ~5 GB        | $0.00           | $0.00            | Same-region transfer free |
|                         |                             |              | **Total**       | **$14.59/month** | ⚠️ Exceeds $5 target      |

### Cost Optimization Strategies

#### **Option A: Reduce Config Rules (Recommended)**

- **Action:** Deploy only 2 rules instead of 3
- **Savings:** $2.00/month
- **New Total:** $12.59/month
- **Trade-off:** Reduced detection coverage (remove `iam-policy-no-admin-access`)

#### **Option B: Disable Security Hub (Not Recommended)**

- **Action:** Remove Security Hub module
- **Savings:** $3.00/month
- **New Total:** $11.59/month
- **Trade-off:** Lose centralized findings aggregation (breaks AC4)

#### **Option C: Remove CloudWatch Dashboard**

- **Action:** Use AWS Console native dashboards instead
- **Savings:** $3.00/month
- **New Total:** $11.59/month
- **Trade-off:** Manual dashboard access, no custom widgets

#### **Option D: Aggressive S3 Lifecycle (Recommended)**

- **Action:** Reduce CloudTrail retention to 30 days (delete after), Config to 180 days
- **Savings:** $0.24/month (minimal)
- **New Total:** $14.35/month
- **Trade-off:** Shorter audit trail (still meets most compliance requirements)

#### **✅ Recommended Combination: A + D**

- Deploy 2 Config rules + Aggressive S3 lifecycle
- **Final Cost:** $12.35/month
- **Exceeds Budget By:** $7.35/month

**Budget Reality Check:**
Given the scope of Phase 1, **$5/month is not realistic** if you want:

- ✅ AWS Config rules (mandatory for AC1)
- ✅ Security Hub (mandatory for AC4)
- ✅ CloudWatch Dashboard (mandatory for AC5)

**Recommended Budget:** $12-15/month for Phase 1  
**Alternative:** Request AWS Educate credits from university (typically $100-200 for students)

---

## Risks & Mitigations

### Technical Risks

#### **Risk 1: AWS Config Rule Evaluation Latency**

**Description:** Config rules evaluate every 1-24 hours (configurable), which may exceed <5 minute MTTD target.

**Likelihood:** High  
**Impact:** High (blocks AC2)

**Mitigation:**

- Configure Config rules for "Configuration changes" trigger (near real-time)
- Use EventBridge as primary detection method (sub-second latency)
- Config serves as backup detection layer and compliance record

**Contingency:**

- If Config latency consistently exceeds 5 minutes, rely on EventBridge for MTTD measurement
- Use Config findings for compliance reporting only

---

#### **Risk 2: IAM Access Analyzer Analysis Delay**

**Description:** Access Analyzer can take 1-30 minutes to analyze new resources.

**Likelihood:** Medium  
**Impact:** Medium (affects AC2 for Scenario 4)

**Mitigation:**

- Document expected latency range in test report
- Use Access Analyzer for external access patterns, not real-time alerting
- EventBridge + CloudTrail provide immediate detection of trust policy changes

**Contingency:**

- If Access Analyzer consistently >30 minutes, escalate to AWS Support
- Consider custom Lambda function to parse CloudTrail for external principals

---

#### **Risk 3: Terraform State File Corruption**

**Description:** Local state file could be corrupted during apply/destroy, causing deployment failures.

**Likelihood:** Low  
**Impact:** High (blocks AC6)

**Mitigation:**

- Enable S3 versioning on all buckets (state snapshots)
- Pre-commit hook to backup state file before each apply
- Keep manual backup of last-known-good state in `terraform/backups/`

**Contingency:**

- Restore from backup state file
- If state unrecoverable, use `terraform import` to rebuild state from existing resources
- Worst case: Destroy all resources via AWS Console, redeploy from scratch

---

#### **Risk 4: CloudTrail Log Delivery Delay**

**Description:** CloudTrail typically delivers logs within 5-15 minutes, not real-time.

**Likelihood:** Certain  
**Impact:** Medium (affects MTTD measurement)

**Mitigation:**

- Use EventBridge for real-time event capture (CloudTrail events are available immediately via EventBridge)
- CloudTrail S3 logs are for audit trail, not primary detection

**Contingency:**

- If EventBridge unavailable, accept higher MTTD (15 minutes) and document in limitations

---

#### **Risk 5: Security Hub Finding Ingestion Failure**

**Description:** Security Hub may fail to ingest findings from Config/Access Analyzer due to integration issues.

**Likelihood:** Low  
**Impact:** High (blocks AC4)

**Mitigation:**

- Enable Security Hub integrations explicitly in Terraform:
  ```hcl
  resource "aws_securityhub_product_subscription" "config" {
    product_arn = "arn:aws:securityhub:eu-west-1::product/aws/config"
  }
  ```
- Test finding ingestion during module development, not just at the end

**Contingency:**

- Manually enable integrations in AWS Console if Terraform fails
- Create custom EventBridge rule to route Config/Analyzer findings directly to CloudWatch

---

### Project Management Risks

#### **Risk 6: Scope Creep (Phase 2 Features Bleeding into Phase 1)**

**Description:** Temptation to add remediation logic or advanced features during Phase 1 development.

**Likelihood:** Medium  
**Impact:** High (delays Phase 1 completion)

**Mitigation:**

- Strict adherence to Phase 1 acceptance criteria (detection only, no remediation)
- Code review checklist: "Does this code belong in Phase 2?"
- Use Git branches: `phase-1-detection` (current), `phase-2-remediation` (future)

**Contingency:**

- If already implemented Phase 2 code, move to separate module and comment out in root `main.tf`

---

#### **Risk 7: Time Underestimation for CloudWatch Dashboard**

**Description:** Dashboard JSON body is complex and time-consuming to debug.

**Likelihood:** High  
**Impact:** Low (dashboard is P1, not P0)

**Mitigation:**

- Build dashboard widgets incrementally (1 widget per hour)
- Use AWS Console to prototype widget, then export JSON
- Accept simplified dashboard if time-constrained (2 widgets instead of 4)

**Contingency:**

- Remove dashboard from Phase 1 MVP (defer to Phase 4)
- Use AWS CloudWatch Insights queries manually for demos

---

## Success Metrics

### Phase 1 Completion Checklist

#### **Infrastructure (AC3, AC6)**

- [ ] All 7 Terraform modules deployed successfully
- [ ] Zero manual steps required for deployment
- [ ] Deployment time <60 seconds (measured with `time terraform apply`)
- [ ] Clean teardown and redeploy successful (3 cycles)
- [ ] No orphaned resources after `terraform destroy`

#### **Detection (AC1, AC2)**

- [ ] 5 distinct IAM misconfiguration types detected
- [ ] Average MTTD <5 minutes across all scenarios
- [ ] Security Hub displays findings from all sources (Config, Access Analyzer, EventBridge)
- [ ] CloudWatch dashboard shows real-time updates

#### **Integration (AC4)**

- [ ] CloudTrail logs visible in S3 bucket
- [ ] Config rules evaluating resources (compliance status displayed)
- [ ] IAM Access Analyzer generating findings for external access
- [ ] Security Hub ingesting findings from all 3 sources (100% integration)
- [ ] EventBridge rules triggering CloudWatch Logs

#### **Documentation (Deliverable)**

- [ ] Architecture diagram (completed)
- [ ] Module README files (7 modules)
- [ ] Deployment guide (step-by-step instructions)
- [ ] Test report (5 scenarios with MTTD calculations)
- [ ] Cost analysis (actual spend vs. projected)

#### **Code Quality**

- [ ] No hardcoded credentials or sensitive data in code
- [ ] All resources tagged with `phase_1_tags`
- [ ] Terraform code passes `terraform validate`
- [ ] Terraform code formatted with `terraform fmt`
- [ ] `.gitignore` excludes state files, credentials, logs

---

### Deliverables Checklist

| **Deliverable**          | **Format**         | **Location**                  | **Due Date** | **Status**     |
| ------------------------ | ------------------ | ----------------------------- | ------------ | -------------- |
| **Terraform Modules**    | `.tf` files        | `terraform/modules/`          | Week 3       | 🟡 In Progress |
| **Root Module**          | `main.tf`          | `terraform/environments/dev/` | Week 3       | 🟡 In Progress |
| **Architecture Diagram** | `.png` / `.drawio` | `docs/architecture/`          | Week 2       | ⬜ Not Started |
| **Module READMEs**       | `.md` files        | Each module directory         | Week 3       | ⬜ Not Started |
| **Deployment Guide**     | `.md` file         | `docs/deployment/`            | Week 4       | ⬜ Not Started |
| **Test Scenarios**       | PowerShell script  | `scripts/Test-Phase1.ps1`     | Week 4       | ⬜ Not Started |
| **Test Report**          | `.md` file         | `docs/testing/`               | Week 4       | ⬜ Not Started |
| **Cost Analysis**        | `.xlsx` / `.md`    | `docs/cost-analysis/`         | Week 4       | ⬜ Not Started |
| **CloudWatch Dashboard** | JSON export        | `config/dashboards/`          | Week 3       | ⬜ Not Started |

---

## Next Steps

### Week 1 Priorities (Foundation + Core Detection)

1. **Finalize Critical Decisions:**

   - Confirm budget tolerance ($12-15/month vs. $5/month)
   - AWS region: `eu-west-1` (Ireland - your home region)
   - Approve 3-rule Config setup (vs. 5-rule original plan)

2. **Build Foundation Module:**

   - KMS key with rotation
   - 2 S3 buckets (CloudTrail, Config)
   - Bucket policies and encryption
   - Test: Verify bucket encryption and versioning

3. **Build CloudTrail Module:**

   - Multi-region trail configuration
   - S3 integration with foundation module
   - Test: Create IAM user, verify logged in S3

4. **Build AWS Config Module:**
   - Configuration recorder + delivery channel
   - 3 IAM rules deployment
   - Test: Create non-compliant resource, verify Config detects

### Week 2 Priorities (Integration + Aggregation)

1. **Build IAM Access Analyzer Module:**

   - ACCOUNT-type analyzer
   - Test: Create external trust role, verify finding

2. **Build Security Hub Module:**

   - Enable Foundational + CIS standards
   - Integrate Config and Access Analyzer
   - Test: Verify findings from all sources appear

3. **Build EventBridge Module:**
   - 3 rule patterns (policy changes, trust changes, root activity)
   - CloudWatch Logs targets
   - Test: Attach policy, verify EventBridge logs

### Week 3 Priorities (Dashboard + Root Integration)

1. **Build CloudWatch Dashboard Module:**

   - 4 widgets (IAM API calls, Security Hub findings, Config compliance, Access Analyzer)
   - Test: Verify all widgets displaying data

2. **Root Module Integration:**

   - Wire all 7 modules together
   - Dependency management
   - Test: Full deployment <60 seconds

3. **Documentation:**
   - Architecture diagram
   - Module READMEs
   - Deployment guide

### Week 4 Priorities (Testing + Validation)

1. **Test Execution:**

   - Run 5 violation scenarios
   - Calculate MTTD for each
   - Generate test report with screenshots

2. **Repeatability Testing:**

   - 3 cycles of deploy → test → destroy
   - Verify AC6 (clean teardown)

3. **Final Documentation:**
   - Cost analysis (actual vs. projected)
   - Lessons learned
   - Phase 2 recommendations

---

## Questions for Supervisor

1. **Budget Approval:**

   - Phase 1 realistic cost is $12-15/month (not $5/month as initially estimated)
   - Can we adjust budget or request AWS Educate credits?

2. **Config Rules Trade-off:**

   - Should we deploy 2 rules (budget-friendly) or 3 rules (better coverage)?
   - If 3 rules, accept $7/month over-budget?

3. **Dashboard Priority:**

   - Is CloudWatch dashboard mandatory for Phase 1 MVP (adds $3/month)?
   - Alternative: Use AWS Console native views for demo?

4. **Test Scenario 4 (Old Access Keys):**

   - Access key rotation rule requires 90-day wait to trigger
   - Should we replace with different test scenario, or accept as "manual validation only"?

5. **Multi-Region Consideration:**
   - Phase 1 is single-region (eu-west-1 Ireland)
   - Should Phase 4/5 add multi-region support, or is single-region acceptable for FYP?

---

## References

1. [AWS CloudTrail Documentation](https://docs.aws.amazon.com/cloudtrail/)
2. [AWS Config Developer Guide](https://docs.aws.amazon.com/config/)
3. [IAM Access Analyzer Documentation](https://docs.aws.amazon.com/access-analyzer/)
4. [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/)
5. CIS AWS Foundations Benchmark v1.2.0
6. [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

**Document Version:** 1.0  
**Last Updated:** December 2025  
**Status:** Planning Complete → Ready for Implementation
