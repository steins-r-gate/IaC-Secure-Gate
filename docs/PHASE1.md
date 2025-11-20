# Phase 1: AWS Detection Baseline - IAM-Secure-Gate

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Cost Analysis](#cost-analysis)
- [Security Features](#security-features)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

---

## 🎯 Overview

**Phase 1 Goal:** Establish core IAM detection capabilities using AWS-native services.

**Timeline:** Weeks 1-4  
**Status:** Foundation Complete - Ready for Deployment  
**Estimated Monthly Cost:** $2-5 (well within free tier limits)

### What Phase 1 Delivers

Phase 1 creates the **foundation** for real-time IAM misconfiguration detection by deploying:

1. **Secure Storage Infrastructure** (S3 + KMS)

   - CloudTrail logs storage
   - AWS Config snapshots storage
   - Access logs for audit trail

2. **Logging & Monitoring** (Ready for Phase 1 Completion)

   - CloudTrail for API activity
   - AWS Config for resource changes
   - IAM Access Analyzer for permission analysis

3. **Centralized Security** (Ready for Phase 1 Completion)

   - Security Hub for findings aggregation
   - EventBridge for event routing
   - CloudWatch for metrics visualization

4. **Automation Infrastructure**
   - Deployment scripts
   - Verification suite
   - Testing framework

---

## 🏗️ Architecture

### Current Implementation (S3 Foundation)

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Account (eu-west-1)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────── ───┐  │
│  │                 KMS Customer Key                      │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ • Automatic Rotation Enabled               │       │  │
│  │  │ • CloudTrail Service Access                │       │  │
│  │  │ • Config Service Access                    │       │  │
│  │  │ • S3 Service Access                        │       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  └──────────────────────────────────────────────────── ──┘  │
│                           │                                 │
│                           │ (encrypts)                      │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────── ───┐  │
│  │              S3 Storage Infrastructure                │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ CloudTrail Bucket                          │       │  │
│  │  │ • Versioning Enabled                       │       │  │
│  │  │ • KMS Encrypted                            │       │  │
│  │  │ • Public Access: BLOCKED                   │       │  │
│  │  │ • HTTPS Only                               │       │  │
│  │  │ • Access Logged → Logs Bucket              │       │  │
│  │  │ • Lifecycle: 90d→IA, 180d→Glacier, 365d→Del│       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  │                                                       │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ Config Bucket                              │       │  │
│  │  │ • Versioning Enabled                       │       │  │
│  │  │ • KMS Encrypted                            │       │  │
│  │  │ • Public Access: BLOCKED                   │       │  │
│  │  │ • HTTPS Only                               │       │  │
│  │  │ • Access Logged → Logs Bucket              │       │  │
│  │  │ • Lifecycle: 90d→IA, 180d→Glacier, 365d→Del│       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  │                                                       │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ Access Logs Bucket                         │       │  │
│  │  │ • Versioning Enabled                       │       │  │
│  │  │ • KMS Encrypted                            │       │  │
│  │  │ • Public Access: BLOCKED                   │       │  │
│  │  │ • Lifecycle: 90d→IA, 365d→Delete           │       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  └──────────────────────────────────────────────────── ──┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────── ──┐  │
│  │         Terraform Remote State (Optional)             │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ S3: iam-security-terraform-state-{account} │       │  │
│  │  │ • Versioning: 90-day retention             │       │  │
│  │  │ • Encryption: AES256                       │       │  │
│  │  │ • Public Access: BLOCKED                   │       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  │                                                       │  │
│  │  ┌────────────────────────────────────────────┐       │  │
│  │  │ DynamoDB: iam-security-terraform-locks     │       │  │
│  │  │ • Billing: Pay-per-request                 │       │  │
│  │  │ • Point-in-time recovery enabled           │       │  │
│  │  └────────────────────────────────────────────┘       │  │
│  └──────────────────────────────────────────────────── ──┘  │
└─────────────────────────────────────────────────────────────┘
```

### Complete Phase 1 Architecture (To Be Built)

```
┌───────────────────────────────────────────────────────────────────┐
│                         IAM Activity                              │
│                    (API Calls, Changes, Events)                   │
└───────────────────────┬───────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
   ┌─────────┐   ┌───────────┐   ┌──────────────┐
   │CloudTrail│  │AWS Config │   │IAM Access    │
   │         │   │           │   │Analyzer      │
   │• All IAM│   │• Resource │   │• External    │
   │  API    │   │  Changes  │   │  Access      │
   │  Calls  │   │• Rule Eval│   │• Policy      │
   │• Multi  │   │• Snapshots│   │  Validation  │
   │  Region │   │           │   │              │
   └────┬────┘   └─────┬─────┘   └──────┬───────┘
        │              │                │
        │              │                │
        │              └────────┬───────┘
        │                       │
        └───────────────────────┼─────────────────┐
                                ▼                 │
                        ┌──────────────┐          │
                        │Security Hub  │          │
                        │              │          │
                        │• Aggregates  │          │
                        │  Findings    │          │
                        │• Normalizes  │          │
                        │  Severity    │          │
                        │• CIS         │          │
                        │  Benchmark   │          │
                        └──────┬───────┘          │
                               │                  │
                               ▼                  │
                        ┌──────────────┐          │
                        │EventBridge   │          │
                        │              │          │
                        │• IAM Events  │          │
                        │• Route by    │          │
                        │  Severity    │          │
                        └──────┬───────┘          │
                               │                  │
                ┌──────────────┼──────────────┐   │
                │              │              │   │
                ▼              ▼              ▼   ▼
         ┌──────────┐  ┌──────────┐  ┌──────────────┐
         │CloudWatch│  │SNS       │  │S3 (Logs)     │
         │Dashboard │  │Alerts    │  │              │
         │          │  │          │  │• CloudTrail  │
         │• MTTD    │  │• Email   │  │• Config      │
         │• Findings│  │• Approval│  │• Access Logs │
         │• Trends  │  │          │  │              │
         └──────────┘  └──────────┘  └──────────────┘
```

---

## 🔧 Components

### Currently Deployed: S3 Foundation

#### 1. S3 Buckets (3 buckets)

**CloudTrail Bucket** (`iam-security-dev-cloudtrail-{account-id}`)

- **Purpose:** Store CloudTrail API activity logs
- **Retention:** 365 days with lifecycle transitions
- **Security:**
  - KMS encryption
  - Versioning enabled
  - Public access blocked (all 4 controls)
  - HTTPS-only policy
  - Access logging enabled

**Config Bucket** (`iam-security-dev-config-{account-id}`)

- **Purpose:** Store AWS Config snapshots and history
- **Retention:** 365 days with lifecycle transitions
- **Security:** Same as CloudTrail bucket

**Logs Bucket** (`iam-security-dev-logs-{account-id}`)

- **Purpose:** Store S3 access logs for audit trail
- **Retention:** 365 days
- **Security:** Same as above (except no self-logging)

**Lifecycle Policy (All Buckets):**

```
Day 0-90:    Standard Storage (hot access)
Day 90-180:  Standard-IA (30% cheaper, infrequent access)
Day 180-365: Glacier (70% cheaper, archive)
Day 365+:    Automatic deletion
```

#### 2. KMS Key

**S3 Encryption Key** (`iam-security-dev-s3-kms`)

- **Type:** Customer-managed key (CMK)
- **Rotation:** Automatic (yearly)
- **Permissions:** CloudTrail, Config, S3 services
- **Cost:** $1/month
- **Alias:** `alias/iam-security-dev-s3`

**Why KMS over AES256?**

- Audit trail of encryption/decryption
- Centralized key management
- Compliance requirements (GDPR, SOC 2)
- Key rotation capability

#### 3. Terraform Backend (Optional)

**State Bucket** (`iam-security-terraform-state-{account-id}`)

- **Purpose:** Store Terraform state remotely
- **Benefits:**
  - Team collaboration
  - State locking (prevents concurrent changes)
  - Version history
  - Secure storage

**Lock Table** (`iam-security-terraform-locks`)

- **Type:** DynamoDB table
- **Billing:** Pay-per-request (no minimum cost)
- **Purpose:** Prevent concurrent Terraform operations

### To Be Deployed (Phase 1 Completion)

#### 4. CloudTrail

**Trail Configuration:**

- **Name:** `iam-security-audit-trail`
- **Type:** Multi-region trail
- **Events:**
  - Management events (all IAM API calls)
  - Global service events (IAM, STS, CloudFront)
- **Destination:** CloudTrail S3 bucket
- **Encryption:** KMS key
- **Cost:** FREE (first trail per account)

**What It Captures:**

```json
{
  "eventName": "AttachUserPolicy",
  "userIdentity": {
    "type": "IAMUser",
    "userName": "admin"
  },
  "requestParameters": {
    "userName": "developer",
    "policyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
  }
}
```

#### 5. AWS Config

**Configuration Recorder:**

- **Resources:** IAM (Policy, Role, User, Group)
- **Delivery:** Config S3 bucket
- **Cost:** FREE for first 20,000 rule evaluations/month

**Config Rules (5 rules):**

1. `iam-policy-no-statements-with-admin-access`

   - Detects policies with `Action: "*"`
   - Severity: HIGH

2. `iam-root-access-key-check`

   - Ensures root account has no access keys
   - Severity: CRITICAL

3. `mfa-enabled-for-iam-console-access`

   - Checks MFA on console users
   - Severity: MEDIUM

4. `iam-user-no-policies-check`

   - Ensures no policies attached directly to users
   - Severity: LOW

5. `iam-password-policy`
   - Validates password complexity requirements
   - Severity: MEDIUM

#### 6. IAM Access Analyzer

**Analyzer Type:** ACCOUNT

- **Purpose:** Detect resources shared outside account
- **Checks:** Trust policies, resource policies
- **Cost:** FREE
- **Integration:** Sends findings to Security Hub

#### 7. Security Hub

**Purpose:** Centralized security findings dashboard

**Enabled Standards:**

- AWS Foundational Security Best Practices
- CIS AWS Foundations Benchmark v1.4.0

**Cost:**

- 30-day free trial
- Then $0.0010 per finding-check/month
- Estimated: $0.10-0.50/month for dev

#### 8. EventBridge Rules

**IAM Event Rules (3 rules):**

1. `iam-high-severity-findings`

   - **Trigger:** Security Hub finding (HIGH/CRITICAL)
   - **Filter:** IAM resources only
   - **Action:** SNS notification + CloudWatch log

2. `iam-policy-changes`

   - **Trigger:** CloudTrail API calls
   - **Filter:** CreatePolicy, AttachUserPolicy, etc.
   - **Action:** Log to CloudWatch

3. `iam-trust-policy-changes`
   - **Trigger:** UpdateAssumeRolePolicy
   - **Action:** SNS notification

**Cost:** FREE (first 1M events/month)

#### 9. CloudWatch Dashboard

**Metrics Displayed:**

- IAM findings per day
- Security Hub compliance score
- Config rule compliance
- CloudTrail event volume

**Cost:** $0.30/month per dashboard

---

## 💰 Cost Analysis

### Current Deployment (S3 Only)

| Resource              | Quantity | Unit Cost   | Monthly Cost     |
| --------------------- | -------- | ----------- | ---------------- |
| S3 Storage (Standard) | ~0.5 GB  | $0.023/GB   | $0.01            |
| S3 Storage (IA)       | ~0.2 GB  | $0.0125/GB  | $0.003           |
| S3 Storage (Glacier)  | ~0.3 GB  | $0.004/GB   | $0.001           |
| KMS Key               | 1 key    | $1.00/month | $1.00            |
| S3 Requests           | ~1,000   | $0.005/1000 | $0.005           |
| **TOTAL (S3 Only)**   |          |             | **~$1.02/month** |

### Full Phase 1 Deployment

| Resource                 | Quantity        | Unit Cost           | Monthly Cost          |
| ------------------------ | --------------- | ------------------- | --------------------- |
| S3 Storage (all tiers)   | 1 GB            | Various             | $0.02                 |
| KMS Key                  | 1 key           | $1.00/month         | $1.00                 |
| CloudTrail               | 1 trail         | FREE                | $0.00                 |
| AWS Config               | 5 rules         | FREE (under 20k/mo) | $0.00                 |
| IAM Access Analyzer      | 1 analyzer      | FREE                | $0.00                 |
| Security Hub             | Est. findings   | $0.001/check        | $0.20                 |
| EventBridge              | <10k events     | FREE                | $0.00                 |
| CloudWatch Dashboard     | 1 dashboard     | $0.30/month         | $0.30                 |
| DynamoDB (optional)      | Pay-per-request | FREE tier           | $0.00                 |
| **TOTAL (Full Phase 1)** |                 |                     | **~$1.52-2.00/month** |

### Cost Optimization Features

1. **Lifecycle Policies:** 56% storage cost reduction
2. **Free Tier Services:** CloudTrail, Config, Access Analyzer, EventBridge
3. **Pay-per-request:** DynamoDB (no idle costs)
4. **Bucket Keys:** Reduced KMS API costs
5. **Automatic Cleanup:** Old logs deleted after 365 days

### Annual Cost Projection

```
Monthly: $2.00
Annual:  $24.00

vs. Security Breach Cost: $100,000+ (average for SMB)
ROI: 4,166x
```

---

## 🔒 Security Features

### Defense in Depth (7 Layers)

#### Layer 1: Encryption at Rest

- **KMS CMK:** Customer-managed encryption keys
- **Automatic Rotation:** Yearly key rotation
- **Audit Trail:** CloudTrail logs all KMS operations

#### Layer 2: Encryption in Transit

- **HTTPS Only:** Bucket policy denies HTTP requests
- **TLS 1.2+:** Modern encryption standards
- **Condition:** `aws:SecureTransport = false` → DENY

#### Layer 3: Access Control

- **Public Access Block:** All 4 controls enabled
  - BlockPublicAcls: true
  - IgnorePublicAcls: true
  - BlockPublicPolicy: true
  - RestrictPublicBuckets: true
- **Bucket Ownership:** Enforced (prevents ACL confusion)
- **Service Principals:** Scoped to CloudTrail/Config

#### Layer 4: Audit Logging

- **Access Logs:** All S3 operations logged
- **CloudTrail:** All IAM API calls logged
- **Config:** All resource changes logged
- **Retention:** 365 days for compliance

#### Layer 5: Data Lifecycle

- **Versioning:** Enabled (protects against deletion)
- **Lifecycle Rules:** Automatic archival
- **90-day Retention:** Old state versions deleted
- **Point-in-time Recovery:** DynamoDB backups

#### Layer 6: Monitoring & Alerting

- **Security Hub:** Centralized findings
- **EventBridge:** Real-time event routing
- **CloudWatch:** Metrics and dashboards
- **SNS:** Email/SMS notifications

#### Layer 7: Compliance & Governance

- **Resource Tagging:** Project, Environment, Owner
- **CIS Benchmark:** Alignment with industry standards
- **GDPR:** Data encryption, audit logs
- **SOC 2:** Access controls, monitoring

### Bucket Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::bucket-name", "arn:aws:s3:::bucket-name/*"],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::bucket-name/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    }
  ]
}
```

---

## 📋 Prerequisites

### Required Tools

1. **Terraform** >= 1.5.0

   ```powershell
   # Install with Chocolatey
   choco install terraform

   # Or download from
   https://www.terraform.io/downloads
   ```

2. **AWS CLI** >= 2.0

   ```powershell
   # Install with winget
   winget install Amazon.AWSCLI

   # Or download from
   https://aws.amazon.com/cli/
   ```

3. **PowerShell** >= 5.1 (included in Windows 10/11)

4. **Git** (for version control)
   ```powershell
   winget install Git.Git
   ```

### AWS Account Setup

1. **IAM User with Permissions:**

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:*",
           "kms:*",
           "dynamodb:*",
           "cloudtrail:*",
           "config:*",
           "access-analyzer:*",
           "securityhub:*",
           "events:*",
           "cloudwatch:*",
           "sns:*",
           "iam:CreateServiceLinkedRole"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. **Access Keys Generated:**

   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY

3. **AWS CLI Configured:**
   ```bash
   aws configure --profile IAM-Secure-Gate
   # Enter: Access Key, Secret Key, eu-west-1, json
   ```

### Verification Commands

```powershell
# Check Terraform
terraform version
# Expected: Terraform v1.5.0 or later

# Check AWS CLI
aws --version
# Expected: aws-cli/2.x or later

# Check AWS Access
aws sts get-caller-identity --profile IAM-Secure-Gate
# Expected: Your account ID and user ARN

# Check Region
aws configure get region --profile IAM-Secure-Gate
# Expected: eu-west-1
```

---

## 🚀 Deployment Guide

### Quick Start (10 Minutes)

#### Step 1: Clone Repository

```powershell
git clone https://github.com/yourusername/IAM-Secure-Gate.git
cd IAM-Secure-Gate
```

#### Step 2: Set Up AWS Environment

```powershell
.\scripts\Set-AWSEnvironment.ps1

# Expected output:
# ✅ AWS Environment Configured
# Profile: IAM-Secure-Gate
# Region: eu-west-1
# Account ID: 826232761554
```

#### Step 3: (Optional) Set Up Remote State

```powershell
# For team collaboration or production
.\scripts\Setup-TerraformBackend.ps1

# Creates:
# - S3 bucket for state
# - S3 bucket for logs
# - DynamoDB table for locking
# Cost: ~$0.50/month
```

#### Step 4: Deploy S3 Foundation

```powershell
# Dry run first (no changes)
.\scripts\Deploy-Phase1.ps1 -DryRun

# Review the plan, then deploy
.\scripts\Deploy-Phase1.ps1

# Expected duration: 2-5 minutes
# Expected cost: ~$1/month
```

#### Step 5: Verify Deployment

```powershell
.\scripts\Verify-Phase1.ps1 -Detailed

# Expected:
# ✅ S3 Buckets: 3/3
# ✅ KMS Keys: 1/1
# ❌ CloudTrail: 0/2 (not deployed yet)
# ❌ Config: 0/3 (not deployed yet)
```

### Detailed Deployment Steps

#### 1. Configure terraform.tfvars

```powershell
cd terraform\environments\dev

# Copy example file
Copy-Item terraform.tfvars.example terraform.tfvars

# Edit the file
notepad terraform.tfvars
```

**terraform.tfvars:**

```hcl
# Required
owner_email = "your.email@company.com"
alert_email = "security-alerts@company.com"

# Optional (defaults shown)
aws_region = "eu-west-1"

# Optional lifecycle customization
cloudtrail_log_retention_days = 365  # 1 year
config_log_retention_days     = 365  # 1 year
access_log_retention_days     = 365  # 1 year
transition_to_ia_days         = 90   # 3 months
transition_to_glacier_days    = 180  # 6 months
```

#### 2. Initialize Terraform

```powershell
terraform init

# Expected output:
# Initializing modules...
# Initializing the backend...
# Initializing provider plugins...
# Terraform has been successfully initialized!
```

#### 3. Plan Deployment

```powershell
terraform plan -out=tfplan

# Review the plan:
# Plan: 16 to add, 0 to change, 0 to destroy
#
# Resources to be created:
# - 3 S3 buckets
# - 3 bucket versioning configs
# - 3 encryption configs
# - 3 public access blocks
# - 2 bucket logging configs
# - 3 lifecycle configs
# - 3 ownership controls
# - 2 bucket policies
# - 1 KMS key
# - 1 KMS alias
```

#### 4. Apply Changes

```powershell
terraform apply tfplan

# Monitor progress:
# aws_kms_key.s3: Creating...
# aws_kms_key.s3: Creation complete [10s]
# aws_s3_bucket.logs: Creating...
# aws_s3_bucket.logs: Creation complete [5s]
# ...
# Apply complete! Resources: 16 added, 0 changed, 0 destroyed.
```

#### 5. Save Outputs

```powershell
terraform output -json > ..\..\..\outputs.json

# View outputs
terraform output

# Expected:
# cloudtrail_bucket_name = "iam-security-dev-cloudtrail-826232761554"
# config_bucket_name = "iam-security-dev-config-826232761554"
# kms_key_id = "12345678-1234-1234-1234-123456789012"
```

---

## ✅ Verification

### Automated Verification

```powershell
# Run comprehensive checks
.\scripts\Verify-Phase1.ps1 -Detailed -ExportReport

# Categories checked:
# 1. S3 Buckets (3 checks)
# 2. KMS Keys (1 check)
# 3. CloudTrail (2 checks) - Will fail until CloudTrail deployed
# 4. AWS Config (3 checks) - Will fail until Config deployed
# 5. IAM Access Analyzer (1 check) - Will fail until deployed
# 6. Security Hub (2 checks) - Will fail until enabled
# 7. EventBridge (1 check) - Will fail until rules created
# 8. Terraform State (3 checks)

# Expected current state:
# Total: 16 checks
# Passed: 5/16 (S3 + KMS + Terraform)
# Failed: 11/16 (Services not deployed yet)
```

### Manual Verification

#### Check S3 Buckets

```powershell
# List buckets
aws s3 ls | Select-String "iam-security-dev"

# Expected:
# iam-security-dev-cloudtrail-826232761554
# iam-security-dev-config-826232761554
# iam-security-dev-logs-826232761554

# Check bucket encryption
aws s3api get-bucket-encryption `
  --bucket iam-security-dev-cloudtrail-826232761554

# Expected: KMS encryption enabled

# Check versioning
aws s3api get-bucket-versioning `
  --bucket iam-security-dev-cloudtrail-826232761554

# Expected: Status: Enabled

# Check public access block
aws s3api get-public-access-block `
  --bucket iam-security-dev-cloudtrail-826232761554

# Expected: All 4 settings = true
```

#### Check KMS Key

```powershell
# List keys
aws kms list-keys

# Describe key
aws kms describe-key --key-id <key-id>

# Expected:
# KeyState: Enabled
# KeyManager: CUSTOMER

# Check rotation
aws kms get-key-rotation-status --key-id <key-id>

# Expected: KeyRotationEnabled: true
```

#### Check Costs (After 24 Hours)

```powershell
# Get cost estimate
aws ce get-cost-and-usage `
  --time-period Start=2025-01-01,End=2025-01-31 `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --filter file://filter.json

# filter.json:
{
  "Tags": {
    "Key": "Project",
    "Values": ["IAM-Secure-Gate"]
  }
}

# Expected: $1-2 for first month
```

### Security Verification

```powershell
# Run AWS Trusted Advisor (if you have Business/Enterprise support)
aws support describe-trusted-advisor-checks

# Check Security Hub findings (after enabling Security Hub)
aws securityhub get-findings `
  --filters '{"ResourceType": [{"Value": "AwsS3Bucket", "Comparison": "EQUALS"}]}'

# Expected: 0 findings for S3 buckets (all secure)
```

---

## 🐛 Troubleshooting

### Common Issues

#### Issue 1: "AccessDenied" Error During Deployment

**Symptom:**

```
Error: error creating S3 bucket: AccessDenied
```

**Cause:** IAM user lacks necessary permissions

**Solution:**

```powershell
# Check current permissions
aws iam get-user-policy --user-name terraform-admin --policy-name TerraformPolicy

# Ensure policy includes:
# - s3:CreateBucket
# - s3:PutBucketPolicy
# - s3:PutBucketVersioning
# - kms:CreateKey
# - kms:CreateAlias
```

#### Issue 2: "BucketAlreadyExists" Error

**Symptom:**

```
Error: error creating S3 bucket: BucketAlreadyExists
```

**Cause:** Bucket name collision (account ID should prevent this)

**Solution:**

```powershell
# Check if bucket exists
aws s3 ls | Select-String "iam-security"

# If exists from previous deployment, import it:
terraform import aws_s3_bucket.cloudtrail iam-security-dev-cloudtrail-826232761554

# Or delete and recreate:
aws s3 rb s3://iam-security-dev-cloudtrail-826232761554 --force
```

#### Issue 3: "State Lock" Error

**Symptom:**

```
Error: Error acquiring the state lock
Lock Info:
  ID:        12345678-1234-1234-1234-123456789012
  Path:      iam-security-terraform-state/dev/terraform.tfstate
```

**Cause:** Previous `terraform apply` didn't complete properly

**Solution:**

```powershell
# Force unlock (use the Lock ID from error)
terraform force-unlock 12345678-1234-1234-1234-123456789012

# Verify no other processes running
Get-Process | Select-String "terraform"
```

#### Issue 4: High KMS Costs

**Symptom:** KMS costs higher than expected ($1+/month)

**Cause:** Too many encryption/decryption API calls

**Solution:**

- Bucket keys are enabled (reduces API calls by 99%)
- Check CloudTrail for excessive S3 operations:

```powershell
aws cloudtrail lookup-events `
  --lookup-attributes AttributeKey=EventName,AttributeValue=Encrypt

# If excessive calls, review application S3 usage
```

#### Issue 5: Cannot Delete Bucket (NotEmpty)

**Symptom:**

```
Error: error deleting S3 bucket: BucketNotEmpty
```

**Cause:** Bucket contains objects or versions

**Solution:**

```powershell
# Empty bucket (including versions)
aws s3 rm s3://bucket-name --recursive

# Delete all versions
aws s3api list-object-versions `
  --bucket bucket-name | ConvertFrom-Json | ForEach-Object {
    $_.Versions | ForEach-Object {
        aws s3api delete-object `
          --bucket bucket-name `
          --key $_.Key `
          --version-id $_.VersionId
    }
}

# Then try terraform destroy again
terraform destroy
```

### Getting Help

1. **Check Terraform Logs:**

   ```powershell
   $env:TF_LOG="DEBUG"
   terraform apply
   ```

2. **Check AWS CloudTrail:**

   ```powershell
   aws cloudtrail lookup-events --max-results 50
   ```

3. **Validation Commands:**

   ```powershell
   terraform fmt -check
   terraform validate
   terraform plan
   ```

4. **Contact Support:**
   - GitHub Issues: `https://github.com/yourusername/IAM-Secure-Gate/issues`
   - Email: your.email@company.com

---

## 📊 Success Metrics

### Deployment Metrics

| Metric                  | Target       | Measurement                               |
| ----------------------- | ------------ | ----------------------------------------- |
| Deployment Time         | <10 minutes  | Time from `terraform apply` to completion |
| First-time Success Rate | >95%         | Deployments succeeding without errors     |
| Resource Creation       | 16 resources | Count in `terraform plan`                 |
| Cost                    | <$2/month    | AWS Cost Explorer after 7 days            |

### Security Metrics

| Metric              | Target | Measurement                |
| ------------------- | ------ | -------------------------- |
| Public Buckets      | 0      | AWS Trusted Advisor        |
| Unencrypted Buckets | 0      | Security Hub findings      |
| Versioning Enabled  | 100%   | `Verify-Phase1.ps1`        |
| HTTPS Enforcement   | 100%   | Bucket policy audit        |
| Access Logging      | 100%   | Bucket configuration check |

### Operational Metrics

| Metric                 | Target                 | Measurement                |
| ---------------------- | ---------------------- | -------------------------- |
| Verification Pass Rate | 100% (5/5 for S3 only) | `Verify-Phase1.ps1` output |
| False Positive Rate    | <1%                    | Manual review of findings  |
| Mean Time to Deploy    | <5 minutes             | Deployment script logs     |
| Mean Time to Verify    | <2 minutes             | Verification script logs   |

---

## 🎯 Next Steps

### Phase 1 Completion

After S3 foundation is deployed, complete Phase 1 by building:

1. **CloudTrail Module** (Week 2)

   - Enable multi-region trail
   - Configure log delivery to S3
   - Set up CloudWatch Logs integration
   - Estimated time: 2-4 hours

2. **AWS Config Module** (Week 2)

   - Configure recorder for IAM resources
   - Deploy 5 IAM-focused Config Rules
   - Set up remediation actions
   - Estimated time: 3-5 hours

3. **IAM Access Analyzer Module** (Week 3)

   - Create ACCOUNT analyzer
   - Configure finding delivery to Security Hub
   - Set up alerts for external access
   - Estimated time: 1-2 hours

4. **Security Hub Integration** (Week 3)

   - Enable Security Hub
   - Subscribe to CIS Benchmark
   - Configure finding aggregation
   - Create custom insights
   - Estimated time: 2-3 hours

5. **EventBridge Rules** (Week 4)

   - Create IAM event filters
   - Configure SNS notifications
   - Set up CloudWatch Logs targets
   - Estimated time: 2-3 hours

6. **CloudWatch Dashboard** (Week 4)
   - Create metrics dashboard
   - Configure alarms
   - Set up anomaly detection
   - Estimated time: 2-3 hours

### Phase 2: Remediation (Weeks 5-8)

1. Lambda function: PolicyRemediator
2. Lambda function: TrustPolicyRemediator
3. EventBridge routing by severity
4. SNS approval workflow
5. DynamoDB remediation history

### Phase 3: IaC Security Gate (Weeks 9-12)

1. GitHub Actions workflow
2. Checkov integration
3. OPA/Conftest policies
4. SARIF output
5. PR blocking on violations

---

## 📚 Additional Resources

### Documentation

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/cloudtrail/)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/)
- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/)
- [IAM Access Analyzer Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer.html)

### Best Practices

- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

### Community

- [Terraform AWS Modules](https://github.com/terraform-aws-modules)
- [AWS Security Blog](https://aws.amazon.com/blogs/security/)
- [r/aws on Reddit](https://reddit.com/r/aws)
- [Stack Overflow: AWS](https://stackoverflow.com/questions/tagged/amazon-web-services)

---

## 📝 Changelog

### v0.1.0 - Phase 1 Foundation (2025-01-20)

**Added:**

- S3 module with KMS encryption
- 3-tier bucket architecture (CloudTrail, Config, Logs)
- Lifecycle policies for cost optimization
- Comprehensive deployment scripts
- Automated verification suite
- Detection testing framework
- Terraform backend configuration

**Security:**

- KMS customer-managed keys with rotation
- HTTPS-only enforcement
- Public access blocked (4 controls)
- Access logging enabled
- Bucket ownership controls

**Documentation:**

- Complete README for Phase 1
- S3 module documentation
- Implementation guides
- Troubleshooting section

---

## 📄 License

This project is part of a Final Year Cloud Security Project.

**Author:** Roko Skugor  
**Institution:** TUD
**Year:** 2025-2026  
**Project:** IAM-Secure-Gate - Intelligent IAM Misconfiguration Auditor
