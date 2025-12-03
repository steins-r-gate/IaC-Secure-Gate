# Foundation Module - Technical Documentation

**Module:** `terraform/modules/foundation`  
**Purpose:** Encryption and storage infrastructure for Phase 1 AWS detection baseline  
**Version:** 1.0  
**Last Updated:** December 2, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Resource Breakdown](#resource-breakdown)
4. [Security Controls](#security-controls)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Cost Analysis](#cost-analysis)
7. [Deployment Guide](#deployment-guide)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### What is the Foundation Module?

The Foundation Module creates the **secure encryption and storage layer** for all Phase 1 detection services. It establishes:

- **1 KMS customer-managed encryption key** (with automatic rotation)
- **2 S3 buckets** (CloudTrail logs + AWS Config snapshots)
- **Comprehensive security controls** (encryption, versioning, public access blocking, lifecycle management)

Think of it as building a **secure vault system**:

- **KMS key** = The master key to the vault
- **CloudTrail bucket** = Vault for "who did what" logs
- **Config bucket** = Vault for "what resources exist" snapshots

### Why Do We Need This?

**Problem:**

- AWS CloudTrail and Config generate sensitive audit logs
- These logs must be encrypted, versioned, and retained for compliance
- Setting up secure storage is complex (multiple AWS services, policies, encryption)

**Solution:**

- Foundation module provides production-ready storage infrastructure
- Other modules (CloudTrail, Config) simply reference foundation outputs
- Single source of truth for encryption keys and bucket names

### Module Outputs (Used by Other Modules)

```hcl
output "kms_key_id"              # KMS key ID for encryption
output "kms_key_arn"             # KMS key ARN for IAM policies
output "cloudtrail_bucket_name"  # CloudTrail S3 bucket name
output "config_bucket_name"      # Config S3 bucket name
```

---

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Foundation Module                         │
│                  (17 AWS Resources)                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │           KMS Encryption Layer (3 resources)       │    │
│  │                                                     │    │
│  │  ┌──────────────────┐                              │    │
│  │  │  KMS Key         │  ← Auto-rotation enabled     │    │
│  │  │  (logs)          │  ← 7-day deletion window     │    │
│  │  └────────┬─────────┘                              │    │
│  │           │                                         │    │
│  │  ┌────────▼─────────┐                              │    │
│  │  │  KMS Alias       │  ← Human-friendly name       │    │
│  │  │  (logs)          │  ← Easy reference            │    │
│  │  └──────────────────┘                              │    │
│  │           │                                         │    │
│  │  ┌────────▼─────────┐                              │    │
│  │  │  KMS Key Policy  │  ← Service permissions       │    │
│  │  │                  │  ← Encryption context checks │    │
│  │  └──────────────────┘                              │    │
│  └────────────────────────────────────────────────────┘    │
│           │                          │                      │
│           ▼                          ▼                      │
│  ┌─────────────────────┐   ┌─────────────────────┐        │
│  │  CloudTrail Bucket  │   │   Config Bucket     │        │
│  │  (8 resources)      │   │   (8 resources)     │        │
│  │                     │   │                     │        │
│  │  • S3 Bucket        │   │  • S3 Bucket        │        │
│  │  • Versioning       │   │  • Versioning       │        │
│  │  • KMS Encryption   │   │  • KMS Encryption   │        │
│  │  • Public Blocking  │   │  • Public Blocking  │        │
│  │  • Ownership        │   │  • Ownership        │        │
│  │  • Lifecycle        │   │  • Lifecycle        │        │
│  │  • Bucket Policy    │   │  • Bucket Policy    │        │
│  │  • (encrypted)      │   │  • (encrypted)      │        │
│  └─────────────────────┘   └─────────────────────┘        │
│     ↓ Retention              ↓ Retention                   │
│  90 days (30→Glacier)     365 days (90→Glacier)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Information

**Region:** eu-west-1 (Ireland)  
**Environment:** dev  
**Account ID:** 826232761554  
**Total Resources:** 17  
**Deployment Time:** ~2-3 minutes  
**Monthly Cost:** $1.50-2.00

---

## Resource Breakdown

### Part 1: KMS Encryption Layer (3 Resources)

#### Resource 1: `aws_kms_key.logs`

**Type:** AWS KMS Customer Managed Key  
**Purpose:** Master encryption key for all Phase 1 audit logs

**Configuration:**

```hcl
resource "aws_kms_key" "logs" {
  description             = "KMS key for Phase 1 detection logs (CloudTrail + Config)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}
```

**Key Features:**

| Feature             | Value               | Explanation                                        |
| ------------------- | ------------------- | -------------------------------------------------- |
| **Key Type**        | Symmetric           | Used for both encryption and decryption            |
| **Key Rotation**    | Enabled (automatic) | AWS rotates key material every 365 days            |
| **Deletion Window** | 7 days              | Safety net - recoverable for 7 days after deletion |
| **Key Usage**       | ENCRYPT_DECRYPT     | Standard encryption operations                     |

**Why Customer-Managed (Not AWS-Managed)?**

✅ **Advantages:**

- You control key policies (grant/revoke access)
- You can disable/enable the key
- You can audit key usage in CloudTrail
- You can add tags for cost allocation

❌ **AWS-Managed Limitations:**

- Fixed permissions (can't customize)
- Can't be disabled
- Limited CloudTrail visibility

**How Encryption Works:**

```
┌─────────────────────────────────────────────────────────┐
│ 1. Service (CloudTrail) requests encryption             │
│    ↓                                                     │
│ 2. KMS generates Data Encryption Key (DEK)              │
│    ↓                                                     │
│ 3. KMS encrypts DEK with Master Key                     │
│    ↓                                                     │
│ 4. KMS returns:                                          │
│    - Plain DEK (for immediate use)                      │
│    - Encrypted DEK (stored with data)                   │
│    ↓                                                     │
│ 5. Service encrypts log with Plain DEK                  │
│    ↓                                                     │
│ 6. Service stores:                                       │
│    - Encrypted log                                      │
│    - Encrypted DEK (in metadata)                        │
│    ↓                                                     │
│ 7. Service discards Plain DEK (never stored)            │
└─────────────────────────────────────────────────────────┘
```

**To decrypt later:**

```
Encrypted log + Encrypted DEK → KMS decrypts DEK → Use Plain DEK to decrypt log
```

**Cost:** $1.00/month + $0.03 per 10,000 API requests

---

#### Resource 2: `aws_kms_alias.logs`

**Type:** KMS Key Alias  
**Purpose:** Human-readable name for the KMS key

**Configuration:**

```hcl
resource "aws_kms_alias" "logs" {
  name          = "alias/iam-secure-gate-dev-logs"
  target_key_id = aws_kms_key.logs.key_id
}
```

**Why Aliases Matter:**

**Without alias:**

```hcl
kms_key_id = "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"  # Unreadable, changes if key recreated
```

**With alias:**

```hcl
kms_key_id = "alias/iam-secure-gate-dev-logs"  # Readable, stable reference
```

**Benefits:**

- ✅ Code readability
- ✅ Stable reference (alias doesn't change if key is recreated)
- ✅ Easier CloudTrail log analysis (alias shows in logs)

**Cost:** Free (included with KMS key)

---

#### Resource 3: `aws_kms_key_policy.logs`

**Type:** KMS Resource-Based Policy  
**Purpose:** Defines who can use the encryption key

**Policy Structure:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::826232761554:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow CloudTrail to encrypt logs",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": ["kms:GenerateDataKey*", "kms:DescribeKey"],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "kms:EncryptionContext:aws:cloudtrail:arn": "arn:aws:cloudtrail:eu-west-1:826232761554:trail/*"
        }
      }
    },
    {
      "Sid": "Allow Config to use the key",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "*"
    }
  ]
}
```

**Policy Statement Breakdown:**

**Statement 1: Root Account Access**

- **Who:** Your AWS account root (arn:aws:iam::826232761554:root)
- **What:** Full key management (kms:\*)
- **Why:** Without this, you'd lock yourself out of managing the key
- **Critical:** This allows IAM users/roles in your account to be granted permissions via IAM policies

**Statement 2: CloudTrail Service Access**

- **Who:** CloudTrail service (cloudtrail.amazonaws.com)
- **What:**
  - `kms:GenerateDataKey*` - Create data encryption keys
  - `kms:DescribeKey` - Read key metadata
- **Condition:** **CRITICAL SECURITY FEATURE**
  ```
  CloudTrail must include encryption context matching:
  "aws:cloudtrail:arn" = "arn:aws:cloudtrail:eu-west-1:826232761554:trail/*"
  ```
  - Prevents other AWS accounts from using your key
  - CloudTrail automatically includes its trail ARN in encryption context
  - KMS validates: "Is this CloudTrail from MY account?" → Yes → Allow

**Statement 3: Config Service Access**

- **Who:** Config service (config.amazonaws.com)
- **What:**
  - `kms:Decrypt` - Decrypt existing snapshots (when reading)
  - `kms:GenerateDataKey` - Encrypt new snapshots (when writing)
- **No condition:** Config doesn't support encryption context (less secure but necessary)

**Security Analysis:**

| Statement    | Security Level   | Reason                                               |
| ------------ | ---------------- | ---------------------------------------------------- |
| Root Account | ✅ Secure        | Required for key management, controlled via IAM      |
| CloudTrail   | ✅✅ Very Secure | Encryption context prevents cross-account misuse     |
| Config       | ✅ Adequate      | No encryption context, but service-level restriction |

---

### Part 2: CloudTrail S3 Bucket (8 Resources)

#### Resource 4: `aws_s3_bucket.cloudtrail`

**Type:** S3 Bucket  
**Name:** `iam-secure-gate-dev-cloudtrail-826232761554`  
**Purpose:** Store encrypted CloudTrail logs

**Bucket Naming Convention:**

```
iam-secure-gate  -  dev  -  cloudtrail  -  826232761554
      ↓             ↓          ↓              ↓
   Project      Environment  Purpose     Account ID
                                      (global uniqueness)
```

**Why Include Account ID:**

- S3 bucket names must be **globally unique** across ALL AWS accounts worldwide
- Account ID (12 digits) ensures uniqueness
- Prevents naming conflicts

**What Gets Stored:**

```
s3://iam-secure-gate-dev-cloudtrail-826232761554/
└── AWSLogs/
    └── 826232761554/          ← Your account ID
        └── CloudTrail/
            └── eu-west-1/     ← Region
                └── 2024/      ← Year
                    └── 12/    ← Month
                        └── 02/← Day
                            └── 826232761554_CloudTrail_eu-west-1_20241202T1530Z_AbCdEfGh.json.gz
```

**Log File Format:**

- **Format:** Gzipped JSON
- **Size:** ~5-50 KB per file (compressed)
- **Frequency:** New file every ~5 minutes
- **Content:** IAM API calls, timestamps, user identities, parameters

**Example Log Entry:**

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "userName": "terraform-admin",
    "arn": "arn:aws:iam::826232761554:user/terraform-admin"
  },
  "eventTime": "2024-12-02T15:30:45Z",
  "eventSource": "iam.amazonaws.com",
  "eventName": "CreateAccessKey",
  "awsRegion": "eu-west-1",
  "requestParameters": {
    "userName": "test-user"
  },
  "responseElements": {
    "accessKey": {
      "accessKeyId": "AKIAIOSFODNN7EXAMPLE",
      "status": "Active",
      "createDate": "Dec 2, 2024 3:30:45 PM"
    }
  }
}
```

**Tags Applied:**

```hcl
tags = {
  Project     = "IAM-Secure-Gate"
  Phase       = "Phase-1-Detection"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Owner       = "rskugor2907@gmail.com"
  Region      = "eu-west-1"
  Service     = "CloudTrail"
  Module      = "foundation"
  Name        = "CloudTrail Logs Bucket"
}
```

**Cost:** ~$0.25-0.50/month (minimal logs initially)

---

#### Resource 5: `aws_s3_bucket_versioning.cloudtrail`

**Type:** S3 Bucket Versioning Configuration  
**Purpose:** Enable object versioning for compliance and data protection

**Configuration:**

```hcl
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

**How Versioning Works:**

**Without Versioning:**

```
Upload file.json (Version 1) → Upload file.json again → Version 1 OVERWRITTEN
Delete file.json → File PERMANENTLY DELETED
```

**With Versioning:**

```
Upload file.json → Version 1 (ID: abc123)
Upload file.json → Version 2 (ID: def456) ← Version 1 PRESERVED
Delete file.json → Delete marker added ← Both versions PRESERVED (can be restored)
```

**Real-World Scenario:**

**Attack Timeline:**

```
10:00 - Attacker compromises IAM credentials
10:15 - Attacker creates backdoor access key (logged to CloudTrail)
10:30 - Attacker deletes CloudTrail logs to cover tracks
```

**Without Versioning:**

```
10:30 - Logs deleted → EVIDENCE LOST → Investigation stalled
```

**With Versioning:**

```
10:30 - Logs marked as deleted → VERSIONS PRESERVED
11:00 - Security team: aws s3api list-object-versions --bucket ...
11:01 - Security team restores deleted logs
11:02 - Evidence of backdoor creation recovered → Investigation continues
```

**Compliance Requirements:**

| Standard                    | Requirement                          | Met by Versioning? |
| --------------------------- | ------------------------------------ | ------------------ |
| **CIS AWS Foundations 3.6** | Enable S3 bucket versioning          | ✅ Yes             |
| **SOC 2 CC6.1**             | Protect audit logs from modification | ✅ Yes             |
| **ISO 27001 A.12.4.1**      | Event logging retention              | ✅ Yes             |
| **GDPR Article 32**         | Ensure ongoing integrity of systems  | ✅ Yes             |

**Storage Cost Impact:**

```
Scenario: 1 GB CloudTrail logs/month, modified once

Without versioning:
1 GB × $0.023/GB = $0.023/month

With versioning:
Original: 1 GB × $0.023 = $0.023
Version:  1 GB × $0.023 = $0.023
Total: $0.046/month (2x cost)
```

**Mitigation:** Lifecycle policies delete old versions after 90 days

**Best Practice:** Versioning cost is **insurance** against data loss/tampering

---

#### Resource 6: `aws_s3_bucket_server_side_encryption_configuration.cloudtrail`

**Type:** S3 Server-Side Encryption Configuration  
**Purpose:** Automatically encrypt all objects with KMS key

**Configuration:**

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}
```

**Encryption Algorithm Comparison:**

| Algorithm                 | Key Management                  | Performance     | Cost                      | Use Case            |
| ------------------------- | ------------------------------- | --------------- | ------------------------- | ------------------- |
| **AES256**                | AWS-managed                     | Fast            | Free                      | Non-sensitive data  |
| **aws:kms**               | Customer-managed                | Slightly slower | $1/month + requests       | Audit logs (THIS)   |
| **aws:kms + bucket keys** | Customer-managed + optimization | Fast            | $1/month (fewer requests) | High-volume logs ✅ |

**What is `bucket_key_enabled = true`?**

**Without Bucket Keys:**

```
CloudTrail writes 1,000 logs
  ↓
1,000 separate KMS API calls (one per log)
  ↓
Slow (network latency for each call)
Expensive ($0.03 per 10,000 requests = $0.003 for 1,000)
```

**With Bucket Keys:**

```
CloudTrail requests 1 bucket key from KMS
  ↓
KMS generates time-limited bucket key
  ↓
CloudTrail uses bucket key to encrypt 1,000 logs LOCALLY
  ↓
Fast (no network latency per log)
Cheap (1 KMS request instead of 1,000 = 99.9% reduction)
```

**Bucket Key Lifecycle:**

```
Hour 1: KMS generates bucket key → CloudTrail caches it
Hour 2-24: CloudTrail reuses cached bucket key
Hour 25: Bucket key expires → Request new one
```

**Security:** Bucket keys are time-limited and automatically rotated

**Cost Impact:**

```
Scenario: 100,000 logs/month

Without bucket keys:
100,000 KMS requests × $0.03/10,000 = $0.30/month

With bucket keys:
~100 KMS requests × $0.03/10,000 = $0.0003/month

Savings: 99.9% ($0.30 → $0.0003)
```

**Why This Matters for Phase 1:**

- Real-time IAM detection generates MANY logs
- Without bucket keys, KMS costs could exceed $5/month budget
- With bucket keys, KMS costs stay negligible

---

#### Resource 7: `aws_s3_bucket_public_access_block.cloudtrail`

**Type:** S3 Public Access Block Configuration  
**Purpose:** 4-layer defense preventing bucket from becoming public

**Configuration:**

```hcl
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**The 4 Layers of Protection:**

**Layer 1: `block_public_acls = true`**

**What it blocks:**

- New public Access Control Lists (ACLs)
- PutObject requests with public ACL headers

**Example blocked action:**

```bash
# Attacker tries:
aws s3api put-object-acl --bucket cloudtrail-bucket --key log.json --acl public-read

# AWS response:
AccessDenied: Public access is blocked on this bucket
```

**Why ACLs are problematic:**

- Legacy S3 permission system (pre-2012)
- Complex, error-prone
- Often accidentally set to public
- Bucket policies are superior

---

**Layer 2: `block_public_policy = true`**

**What it blocks:**

- Bucket policies granting public access
- PutBucketPolicy requests with `Principal: "*"`

**Example blocked policy:**

```json
{
  "Effect": "Allow",
  "Principal": "*",  ← This would be BLOCKED
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::cloudtrail-bucket/*"
}
```

**AWS response:**

```
PolicyValidationException: Policy contains public access grants
```

**Why this matters:**

- Prevents accidental public bucket policies
- Common mistake: Copy-paste policy from internet without reviewing

---

**Layer 3: `ignore_public_acls = true`**

**What it does:**

- Ignores existing public ACLs (treats them as if they don't exist)
- Applies even if ACLs were set before public access block was enabled

**Scenario:**

```
Day 1: Bucket created with public ACL (before your security audit)
Day 2: You enable public access block with ignore_public_acls = true
Day 3: Old public ACL exists but is IGNORED → Bucket effectively private
```

**Why this is a safety net:**

- Catches legacy misconfigurations
- Doesn't require deleting old ACLs (non-destructive)

---

**Layer 4: `restrict_public_buckets = true`**

**What it does:**

- Ignores public bucket policies
- Restricts access to:
  - AWS service principals
  - Authorized users within your account

**Example:**

```
Bucket policy says: "Allow public access to *.json"
                    ↓
Layer 4 restriction: "Ignore that policy, allow only authorized principals"
                    ↓
Result: Even with public policy, bucket stays private
```

**Why this is critical:**

- Final failsafe if other layers fail
- Prevents bucket-level public access grants

---

**Combined Defense-in-Depth:**

```
Attacker attempts public access
  ↓
Layer 1: Block via ACL? → BLOCKED
  ↓
Layer 2: Block via policy? → BLOCKED
  ↓
Layer 3: Existing public ACL? → IGNORED
  ↓
Layer 4: Existing public policy? → RESTRICTED
  ↓
Result: ACCESS DENIED (4 separate checks)
```

**Compliance:**

- **CIS AWS Foundations 2.1.5:** Block public access to S3 buckets ✅
- **AWS Well-Architected SEC03-BP01:** Implement least privilege ✅

**Cost:** Free (included with S3)

---

#### Resource 8: `aws_s3_bucket_ownership_controls.cloudtrail`

**Type:** S3 Bucket Ownership Controls  
**Purpose:** Enforce bucket owner ownership, disable ACLs

**Configuration:**

```hcl
resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
```

**What `BucketOwnerEnforced` Means:**

**Before (Without Ownership Controls):**

```
CloudTrail writes log to your bucket
  ↓
Object owned by: cloudtrail.amazonaws.com (AWS service account)
  ↓
Object has ACL: CloudTrail can modify object ACL
  ↓
Potential issue: CloudTrail could set permissive ACLs
```

**After (With BucketOwnerEnforced):**

```
CloudTrail writes log to your bucket
  ↓
Object owned by: YOU (bucket owner)
  ↓
Object ACL: DISABLED (all ACLs ignored)
  ↓
Access control: ONLY via bucket policy
```

**Why This Matters:**

**Security Issue (Historical):**

```
1. CloudTrail writes logs to your bucket
2. Objects owned by CloudTrail service
3. CloudTrail sets object ACL: "CloudTrail can read"
4. You (bucket owner) cannot modify object ACL without CloudTrail permission
5. Complicated permission model (ACLs + bucket policy + IAM)
```

**Solution:**

```
1. BucketOwnerEnforced → You own all objects
2. ACLs completely disabled
3. Access controlled ONLY by bucket policy
4. Simpler, more secure permission model
```

**ACL vs. Bucket Policy:**

| Method            | Complexity          | Granularity | Modern Best Practice |
| ----------------- | ------------------- | ----------- | -------------------- |
| **ACLs**          | High (object-level) | Per-object  | ❌ Avoid (legacy)    |
| **Bucket Policy** | Low (bucket-level)  | Per-bucket  | ✅ Use this          |

**BucketOwnerEnforced = "No more ACLs, bucket policy only"**

**Compliance:**

- **CIS AWS Foundations 2.1.5.1:** Disable ACLs ✅
- **AWS Well-Architected SEC03-BP02:** Use bucket policies over ACLs ✅

**Cost:** Free

---

#### Resource 9: `aws_s3_bucket_lifecycle_configuration.cloudtrail`

**Type:** S3 Lifecycle Configuration  
**Purpose:** Automatically archive and delete old logs to reduce costs

**Configuration:**

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-log-retention"
    status = "Enabled"

    filter {}  # Apply to all objects

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}
```

**Lifecycle Timeline:**

```
Day 0: Log created
  ↓
  Storage: S3 Standard
  Cost: $0.023/GB/month
  Access: Instant (milliseconds)
  ↓
Day 30: Transition to Glacier
  ↓
  Storage: S3 Glacier
  Cost: $0.004/GB/month (82% savings)
  Access: 1-5 minutes retrieval
  ↓
Day 90: Expiration (deletion)
  ↓
  Storage: None (deleted)
  Cost: $0
  Access: None (gone forever)
```

**Storage Class Comparison:**

| Storage Class               | Cost/GB/Month | Retrieval Time | Use Case                     |
| --------------------------- | ------------- | -------------- | ---------------------------- |
| **S3 Standard**             | $0.023        | Instant        | Active logs (0-30 days)      |
| **S3 Standard-IA**          | $0.0125       | Instant        | Infrequent access (not used) |
| **S3 Glacier**              | $0.004        | 1-5 minutes    | Archive (30-90 days) ✅      |
| **S3 Glacier Deep Archive** | $0.00099      | 12 hours       | Long-term archive (not used) |

**Why Glacier (Not Deep Archive)?**

✅ **Glacier Advantages:**

- Reasonable retrieval time (1-5 minutes)
- Good balance of cost vs. accessibility
- Suitable for compliance investigations

❌ **Deep Archive Disadvantages:**

- 12-hour retrieval (too slow for investigations)
- Only 75% cheaper than Glacier
- Overkill for 90-day retention

**Why 90-Day Retention?**

**Compliance Requirements:**

| Standard                    | Requirement                                      | Met?                        |
| --------------------------- | ------------------------------------------------ | --------------------------- |
| **CIS AWS Foundations 3.6** | Retain logs for at least 90 days                 | ✅ Yes                      |
| **SOC 2**                   | Retain logs for audit period (typically 90 days) | ✅ Yes                      |
| **PCI DSS 10.7**            | Retain audit logs for at least one year          | ❌ No (would need 365 days) |
| **GDPR Article 5(1)(e)**    | Keep no longer than necessary                    | ✅ Yes (not excessive)      |

**For this project:** CIS benchmark = target → 90 days sufficient

**Cost Analysis:**

**Scenario:** 10 GB CloudTrail logs/month

**Without Lifecycle (90 days in Standard):**

```
Storage: 10 GB × 3 months = 30 GB
Cost: 30 GB × $0.023/GB = $0.69/month
```

**With Lifecycle (30 days Standard + 60 days Glacier):**

```
Standard: 10 GB × 1 month × $0.023 = $0.23
Glacier:  10 GB × 2 months × $0.004 = $0.08
Total: $0.31/month

Savings: $0.69 - $0.31 = $0.38/month (55% reduction)
```

**Lifecycle Request Costs:**

- Transition to Glacier: $0.05 per 1,000 objects
- Expiration (deletion): Free

**For 1,000 logs/month:**

- 1,000 transitions × $0.05/1,000 = $0.05/month (negligible)

**The `filter {}` Block:**

```hcl
filter {}  # Empty filter = apply to ALL objects
```

**Alternative (filtered):**

```hcl
filter {
  prefix = "AWSLogs/826232761554/CloudTrail/"  # Only CloudTrail logs
}
```

**Why empty filter?**

- Simpler configuration
- Entire bucket dedicated to CloudTrail (no mixed content)
- Future-proof (applies to any subdirectories)

---

#### Resource 10: `aws_s3_bucket_policy.cloudtrail`

**Type:** S3 Bucket Policy  
**Purpose:** Define who can access the bucket and how

**Configuration:**

```hcl
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
```

**Policy Statement Breakdown:**

**Statement 1: CloudTrail ACL Check**

```json
{
  "Sid": "AWSCloudTrailAclCheck",
  "Effect": "Allow",
  "Principal": { "Service": "cloudtrail.amazonaws.com" },
  "Action": "s3:GetBucketAcl",
  "Resource": "arn:aws:s3:::iam-secure-gate-dev-cloudtrail-826232761554"
}
```

**What it does:**

- Allows CloudTrail to **read** the bucket's ACL (Access Control List)

**Why CloudTrail needs this:**

```
1. CloudTrail wants to write logs
2. CloudTrail checks: "Do I have permission to write to this bucket?"
3. CloudTrail reads bucket ACL: s3:GetBucketAcl
4. CloudTrail verifies: "Yes, bucket policy allows me"
5. CloudTrail proceeds to write logs
```

**Security note:** Read-only permission, cannot modify bucket

---

**Statement 2: CloudTrail Write Access**

```json
{
  "Sid": "AWSCloudTrailWrite",
  "Effect": "Allow",
  "Principal": { "Service": "cloudtrail.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::iam-secure-gate-dev-cloudtrail-826232761554/*",
  "Condition": {
    "StringEquals": {
      "s3:x-amz-acl": "bucket-owner-full-control"
    }
  }
}
```

**What it does:**

- Allows CloudTrail to **write** (upload) log files
- **Only if** CloudTrail includes the `bucket-owner-full-control` ACL header

**The Condition Explained:**

**Without condition:**

```
CloudTrail writes log → Object owned by CloudTrail → You can't modify/delete it
```

**With condition:**

```
CloudTrail writes log WITH header: x-amz-acl=bucket-owner-full-control
  ↓
S3 checks: "Did CloudTrail include the required ACL header?" → Yes
  ↓
S3 accepts upload AND grants you (bucket owner) full control
  ↓
Object owned by YOU → You can modify/delete it
```

**Why this matters:**

- Ensures you retain control of all objects in your bucket
- Prevents CloudTrail from "locking" objects with restrictive ACLs
- Aligns with `BucketOwnerEnforced` ownership controls

**The `/*` Resource:**

```
"Resource": "arn:aws:s3:::bucket-name/*"
                                      ↑
                          Applies to objects INSIDE bucket
vs.
"Resource": "arn:aws:s3:::bucket-name"
                                   ↑
                          Applies to bucket ITSELF
```

- Statement 1: Bucket-level permission (read ACL of bucket)
- Statement 2: Object-level permission (write objects inside bucket)

---

**Statement 3: Deny Insecure Transport**

```json
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
}
```

**What it does:**

- **Denies ALL actions** on bucket AND objects if connection is not HTTPS

**The Condition Breakdown:**

```json
"aws:SecureTransport": "false"
```

**What this checks:**

```
Is the request using TLS/SSL (HTTPS)? → aws:SecureTransport = true  → ALLOW
Is the request using plain HTTP?       → aws:SecureTransport = false → DENY
```

**Why `"Principal": "*"`:**

- Applies to EVERYONE (including CloudTrail, your IAM users, external attackers)
- Even bucket owner cannot use HTTP

**Example blocked request:**

```bash
# Attacker tries HTTP:
curl http://s3.amazonaws.com/iam-secure-gate-dev-cloudtrail-826232761554/log.json

# S3 response:
AccessDenied: Requests must use TLS/SSL
```

**Encryption Layers:**

| Layer          | Type            | Applied By     | Purpose                                   |
| -------------- | --------------- | -------------- | ----------------------------------------- |
| **In Transit** | TLS/SSL (HTTPS) | This policy ✅ | Encrypts data while uploading/downloading |
| **At Rest**    | KMS encryption  | Resource 6 ✅  | Encrypts data while stored in S3          |

**Defense in Depth:**

```
Data never exists in plain text:
  ↓
In transit (upload): Encrypted via HTTPS
  ↓
At rest (storage): Encrypted via KMS
  ↓
In transit (download): Encrypted via HTTPS
```

**Compliance:**

- **CIS AWS Foundations 2.1.5:** Enforce HTTPS ✅
- **PCI DSS 4.1:** Use strong cryptography for data in transit ✅

---

### Part 3: Config S3 Bucket (6 Resources)

#### Resources 11-16: Config Bucket (Identical to CloudTrail)

The Config bucket has **the same 6 security resources** as CloudTrail:

| Resource            | CloudTrail             | Config                    | Difference             |
| ------------------- | ---------------------- | ------------------------- | ---------------------- |
| **Bucket**          | `cloudtrail`           | `config`                  | Name only              |
| **Versioning**      | Enabled                | Enabled                   | None                   |
| **Encryption**      | KMS                    | KMS                       | None                   |
| **Public Blocking** | 4 layers               | 4 layers                  | None                   |
| **Ownership**       | BucketOwnerEnforced    | BucketOwnerEnforced       | None                   |
| **Bucket Policy**   | CloudTrail permissions | Config permissions        | Service principal      |
| **Lifecycle**       | 90 days (30→Glacier)   | **365 days (90→Glacier)** | ⚠️ Different retention |

**Key Differences:**

**1. Bucket Name:**

```
CloudTrail: iam-secure-gate-dev-cloudtrail-826232761554
Config:     iam-secure-gate-dev-config-826232761554
            ↑ Only difference
```

**2. Lifecycle Policy:**

```
CloudTrail:
  Day 30 → Glacier
  Day 90 → Delete

Config:
  Day 90 → Glacier
  Day 365 → Delete
```

**Why longer retention for Config?**

**CloudTrail = Transactional Logs:**

- "User X did action Y at time Z"
- Useful for incident investigation (recent events)
- 90-day retention sufficient for most audits

**Config = Compliance Records:**

- "Resource X had configuration Y at time Z"
- Useful for compliance audits (long-term evidence)
- "Show me your IAM configuration from 6 months ago"
- 365-day retention for annual audits

**3. Bucket Policy Service Principal:**

```
CloudTrail policy:
"Principal": {"Service": "cloudtrail.amazonaws.com"}

Config policy:
"Principal": {"Service": "config.amazonaws.com"}
```

**Config Policy Statements:**

```json
{
  "Statement": [
    {
      "Sid": "AWSConfigBucketPermissionsCheck",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::config-bucket"
    },
    {
      "Sid": "AWSConfigBucketExistenceCheck",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::config-bucket"
    },
    {
      "Sid": "AWSConfigWrite",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::config-bucket/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::config-bucket",
        "arn:aws:s3:::config-bucket/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "false" }
      }
    }
  ]
}
```

**Extra permission: `s3:ListBucket`**

Config needs to:

1. Check bucket ACL (like CloudTrail)
2. **List existing objects** (to avoid overwriting snapshots)
3. Write new snapshots

**What Config Stores:**

```
s3://iam-secure-gate-dev-config-826232761554/
└── AWSLogs/
    └── 826232761554/
        └── Config/
            └── eu-west-1/
                └── 2024/
                    └── 12/
                        └── 02/
                            └── ConfigSnapshot/
                                └── 826232761554_Config_eu-west-1_ConfigSnapshot_20241202T153045Z.json.gz
```

**Config Snapshot Content:**

```json
{
  "configurationItems": [
    {
      "resourceType": "AWS::IAM::User",
      "resourceId": "AIDACKCEVSQ6C2EXAMPLE",
      "resourceName": "test-user",
      "configuration": {
        "userName": "test-user",
        "userId": "AIDACKCEVSQ6C2EXAMPLE",
        "arn": "arn:aws:iam::826232761554:user/test-user",
        "createDate": "2024-12-02T15:30:45.000Z",
        "userPolicyList": [],
        "attachedManagedPolicies": [
          {
            "policyName": "ReadOnlyAccess",
            "policyArn": "arn:aws:iam::aws:policy/ReadOnlyAccess"
          }
        ]
      },
      "configurationItemCaptureTime": "2024-12-02T15:30:45.000Z"
    }
  ]
}
```

**CloudTrail vs. Config:**

| Aspect        | CloudTrail                    | Config                             |
| ------------- | ----------------------------- | ---------------------------------- |
| **What**      | API calls (actions)           | Resource states (configurations)   |
| **When**      | Real-time (as actions happen) | Periodic (snapshots every 6 hours) |
| **Format**    | Event logs                    | Configuration snapshots            |
| **Size**      | Small (KB per file)           | Large (MB per snapshot)            |
| **Use Case**  | "Who did what?"               | "What exists now?"                 |
| **Retention** | 90 days                       | 365 days                           |

---

## Security Controls

### Defense-in-Depth Layers

```
┌─────────────────────────────────────────────────────────┐
│ Layer 7: Compliance & Monitoring                        │
│ - CIS Benchmark alignment                               │
│ - Tagged resources for audit trail                      │
│ - CloudWatch metrics (future phases)                    │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 6: Data Lifecycle Management                      │
│ - Automatic archival to Glacier                         │
│ - Retention policies (90/365 days)                      │
│ - Cost optimization without sacrificing security        │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 5: Object Ownership & ACL Disablement             │
│ - BucketOwnerEnforced (you own all objects)             │
│ - ACLs disabled (bucket policy only)                    │
│ - Prevents ACL-based bypass attacks                     │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 4: Public Access Blocking (4 sub-layers)          │
│ - Block public ACLs                                     │
│ - Block public policies                                 │
│ - Ignore public ACLs                                    │
│ - Restrict public buckets                               │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 3: Bucket Policy Controls                         │
│ - Service-specific permissions (CloudTrail/Config only) │
│ - HTTPS-only enforcement (TLS in transit)               │
│ - bucket-owner-full-control condition                   │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Versioning & Data Protection                   │
│ - All modifications create new versions                 │
│ - Deletions are soft (recoverable)                      │
│ - Protects against accidental/malicious data loss       │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Encryption (At Rest & In Transit)              │
│ - KMS customer-managed key (automatic rotation)         │
│ - Server-side encryption (all objects)                  │
│ - Bucket keys enabled (performance optimization)        │
│ - Encryption context validation (KMS policy)            │
└─────────────────────────────────────────────────────────┘
```

### CIS AWS Foundations Benchmark Compliance

| Control ID  | Description                                    | Status        | Implementation                 |
| ----------- | ---------------------------------------------- | ------------- | ------------------------------ |
| **2.1.5**   | Ensure S3 buckets have public access blocked   | ✅            | Public access block (4 layers) |
| **2.1.5.1** | Ensure S3 buckets use bucket policies not ACLs | ✅            | BucketOwnerEnforced ownership  |
| **3.6**     | Ensure S3 bucket logging is enabled            | ⏭️ Next phase | CloudTrail module will enable  |
| **3.6**     | Ensure CloudTrail logs are encrypted at rest   | ✅            | KMS encryption configured      |
| **3.7**     | Ensure CloudTrail logs have versioning enabled | ✅            | Versioning enabled             |
| **3.10**    | Ensure KMS key rotation is enabled             | ✅            | `enable_key_rotation = true`   |

---

## Data Flow Diagrams

### Flow 1: CloudTrail Log Creation & Storage

```
┌─────────────────────────────────────────────────────────────┐
│ 1. IAM Action Occurs                                         │
│    User creates access key via AWS Console                   │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. CloudTrail Captures Event                                 │
│    Records: timestamp, user, action, parameters, result      │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. CloudTrail Prepares Log File                              │
│    Format: JSON, compress with gzip                          │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. CloudTrail Requests Encryption                            │
│    API Call: KMS.GenerateDataKey(KeyId=logs, Context=ARN)   │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. KMS Validates Request                                     │
│    Check: Key policy allows CloudTrail?           → Yes ✓    │
│    Check: Encryption context matches trail ARN?   → Yes ✓    │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. KMS Generates Data Key                                    │
│    Returns:                                                  │
│    - Plain data key (for immediate encryption)               │
│    - Encrypted data key (to store with log)                  │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. CloudTrail Encrypts Log                                   │
│    Uses plain data key → Encrypted log file                  │
│    Discards plain data key (not stored anywhere)             │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. CloudTrail Writes to S3                                   │
│    API Call: S3.PutObject(                                   │
│       Bucket=cloudtrail-bucket,                              │
│       Key=AWSLogs/.../log.json.gz,                           │
│       Body=<encrypted log>,                                  │
│       x-amz-acl=bucket-owner-full-control,                   │
│       x-amz-server-side-encryption-aws-kms-key-id=<KMS ARN>  │
│    )                                                         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 9. S3 Validates Request                                      │
│    Check: Bucket policy allows CloudTrail s3:PutObject? → Yes│
│    Check: HTTPS used (aws:SecureTransport)?             → Yes│
│    Check: x-amz-acl=bucket-owner-full-control included? → Yes│
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 10. S3 Stores Encrypted Log                                  │
│     Object stored with metadata:                             │
│     - Encrypted data key                                     │
│     - KMS key ID                                             │
│     - Encryption algorithm                                   │
│     - Object ownership: Bucket owner                         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 11. Versioning Applied                                       │
│     S3 creates version ID for object                         │
│     Previous versions (if any) preserved                     │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 12. Lifecycle Scheduled                                      │
│     Day 30: Transition to Glacier (scheduled)                │
│     Day 90: Expiration/deletion (scheduled)                  │
└─────────────────────────────────────────────────────────────┘
```

### Flow 2: Reading Encrypted Logs (Authorized User)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User Requests Log                                         │
│    AWS CLI: aws s3 cp s3://cloudtrail-bucket/log.json ./    │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. S3 Checks IAM Permissions                                 │
│    Does user have s3:GetObject permission?     → Yes ✓       │
│    User inherits from root account permissions               │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. S3 Retrieves Encrypted Log                                │
│    Reads: Encrypted log file + Encrypted data key from      │
│    object metadata                                           │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. S3 Requests Decryption                                    │
│    API Call: KMS.Decrypt(                                    │
│       CiphertextBlob=<encrypted data key>,                   │
│       RequestedBy=<user ARN>                                 │
│    )                                                         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. KMS Validates Request                                     │
│    Check: Key policy allows user to decrypt?  → Yes ✓        │
│    Root account has kms:* permission                         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. KMS Decrypts Data Key                                     │
│    Returns: Plain data key                                   │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. S3 Decrypts Log                                           │
│    Uses plain data key → Decrypted log                       │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. S3 Returns Decrypted Log to User                          │
│    Via HTTPS (encrypted in transit)                          │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 9. User Receives Plain Text Log                              │
│    Can read IAM activity details                             │
└─────────────────────────────────────────────────────────────┘
```

### Flow 3: Attack Scenario (Blocked)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Attacker Compromises Limited IAM User                     │
│    Attacker has basic S3 read permissions                    │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Attacker Attempts to Read Logs                            │
│    aws s3 cp s3://cloudtrail-bucket/log.json ./              │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. S3 Checks IAM Permissions                                 │
│    Does attacker have s3:GetObject?     → Maybe ✓            │
│    Assume yes (attacker has read permissions)                │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. S3 Retrieves Encrypted Log                                │
│    Returns encrypted log + encrypted data key                │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. S3 Requests Decryption for Attacker                       │
│    API Call: KMS.Decrypt(                                    │
│       CiphertextBlob=<encrypted data key>,                   │
│       RequestedBy=<attacker ARN>                             │
│    )                                                         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. KMS Validates Request                                     │
│    Check: Key policy allows attacker to decrypt? → NO ✗      │
│    Attacker not in root account's allowed principals         │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. KMS Denies Decryption                                     │
│    Returns: AccessDenied error                               │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. S3 Cannot Decrypt Log                                     │
│    Returns encrypted gibberish to attacker                   │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 9. Attacker Gets Useless Data                                │
│    Encrypted log is unreadable without KMS key               │
│    Attacker's actions logged in CloudTrail ✓                 │
└─────────────────────────────────────────────────────────────┘
```

**Key Takeaway:** Even with S3 access, encryption provides critical defense layer.

---

## Cost Analysis

### Monthly Cost Breakdown (Foundation Only)

| Component      | Resource                    | Quantity | Unit Cost  | Monthly Cost    | Notes            |
| -------------- | --------------------------- | -------- | ---------- | --------------- | ---------------- |
| **KMS**        | Customer-managed key        | 1        | $1.00/key  | **$1.00**       | Flat fee         |
| **KMS**        | API requests                | ~1,000   | $0.03/10k  | **$0.003**      | With bucket keys |
| **S3**         | CloudTrail Standard storage | 10 GB    | $0.023/GB  | **$0.23**       | First 30 days    |
| **S3**         | CloudTrail Glacier storage  | 20 GB    | $0.004/GB  | **$0.08**       | Days 31-90       |
| **S3**         | Config Standard storage     | 5 GB     | $0.023/GB  | **$0.12**       | First 90 days    |
| **S3**         | Config Glacier storage      | 15 GB    | $0.004/GB  | **$0.06**       | Days 91-365      |
| **S3**         | Lifecycle transitions       | 2,000    | $0.05/1k   | **$0.10**       | Negligible       |
| **S3**         | Data transfer (same-region) | 50 GB    | $0.00      | **$0.00**       | Free             |
| **Versioning** | Storage overhead            | ~5%      | Varies     | **$0.02**       | Old versions     |
|                |                             |          | **Total:** | **$1.62/month** | ✅ Under budget  |

### Cost Optimization Strategies Implemented

**1. Lifecycle Policies:**

```
Without lifecycle: 90 days × $0.023/GB = $2.07/GB
With lifecycle:    30 days × $0.023 + 60 days × $0.004 = $0.93/GB
Savings: 55% reduction
```

**2. Bucket Keys:**

```
Without: 100,000 KMS requests × $0.03/10k = $0.30/month
With:    ~100 KMS requests × $0.03/10k = $0.0003/month
Savings: 99.9% reduction
```

**3. Gzip Compression:**

```
CloudTrail logs: ~70% size reduction (built-in)
Storage cost: 30% of uncompressed
```

**4. Regional Deployment:**

```
All resources in eu-west-1 → No cross-region data transfer charges
```

### Full Phase 1 Projected Costs

When Phase 1 is complete (all modules deployed):

| Module                | Monthly Cost     | Status           |
| --------------------- | ---------------- | ---------------- |
| Foundation (KMS + S3) | $1.62            | ✅ Deployed      |
| CloudTrail (service)  | $0.00            | ⏭️ Next (free)   |
| AWS Config (3 rules)  | $6.00            | ⏭️ Week 2        |
| Security Hub          | $3.00            | ⏭️ Week 2        |
| IAM Access Analyzer   | $0.00            | ⏭️ Week 2 (free) |
| EventBridge (rules)   | $0.00            | ⏭️ Week 2 (free) |
| CloudWatch Dashboard  | $3.00            | ⏭️ Week 3        |
|                       |                  |
| **Phase 1 Total**     | **$13.62/month** | Target: <$15 ✅  |

### Cost Tracking via Tags

All resources tagged for cost allocation:

```hcl
tags = {
  Project     = "IAM-Secure-Gate"    # Filter AWS Cost Explorer by project
  Phase       = "Phase-1-Detection"  # Filter by phase
  Environment = "dev"                # Filter by environment
  Module      = "foundation"         # Filter by module
}
```

**AWS Cost Explorer Query:**

```
Dimension: Tag:Project
Filter: IAM-Secure-Gate
Group by: Tag:Module
```

Result: See cost per module (foundation, cloudtrail, config, etc.)

---

## Deployment Guide

### Prerequisites

✅ AWS CLI configured (region: eu-west-1)  
✅ Terraform >= 1.5.0 installed  
✅ AWS credentials with administrator access  
✅ Git repository initialized

### Deployment Steps

**1. Navigate to dev environment:**

```powershell
cd terraform/environments/dev
```

**2. Initialize Terraform:**

```powershell
terraform init
```

Expected output:

```
Initializing modules...
- foundation in ../../modules/foundation

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

**3. Create terraform.tfvars:**

```powershell
@'
owner_email = "your-email@example.com"
'@ | Out-File -FilePath "terraform.tfvars" -Encoding UTF8
```

**4. Validate configuration:**

```powershell
terraform validate
```

Expected output:

```
Success! The configuration is valid.
```

**5. Generate deployment plan:**

```powershell
terraform plan -out=tfplan
```

Review output for:

- `Plan: 17 to add, 0 to change, 0 to destroy` ✓
- All resources prefixed with `module.foundation.` ✓
- Your email in tags ✓

**6. Deploy infrastructure:**

```powershell
terraform apply tfplan
```

Deployment time: ~2-3 minutes

**7. Verify outputs:**

```powershell
terraform output
```

Expected outputs:

```
aws_account_id         = "826232761554"
aws_region             = "eu-west-1"
cloudtrail_bucket_name = "iam-secure-gate-dev-cloudtrail-826232761554"
config_bucket_name     = "iam-secure-gate-dev-config-826232761554"
kms_key_arn           = "arn:aws:kms:eu-west-1:826232761554:key/..."
kms_key_id            = "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
```

**8. Verify in AWS Console:**

**KMS Key:**

```
AWS Console → KMS → Customer managed keys → "iam-secure-gate-dev-logs-kms"
Check: Key rotation = Enabled ✓
```

**S3 Buckets:**

```
AWS Console → S3 → Buckets
See: iam-secure-gate-dev-cloudtrail-826232761554 ✓
See: iam-secure-gate-dev-config-826232761554 ✓
```

**Bucket Security:**

```
Click bucket → Properties
Check: Versioning = Enabled ✓
Check: Default encryption = Enabled (KMS) ✓

Click bucket → Permissions
Check: Block public access = On (all 4) ✓
Check: Bucket policy exists ✓
```

---

## Troubleshooting

### Common Issues

**Issue 1: "Error creating S3 bucket: BucketAlreadyExists"**

**Cause:** Bucket name already taken globally

**Solution:**

```
Option A: Bucket already exists in your account (redeploy attempt)
  → Run: terraform destroy
  → Run: terraform apply

Option B: Bucket name collision (rare with account ID)
  → Update account_id variable
  → Run: terraform plan again
```

---

**Issue 2: "AccessDenied: User is not authorized to perform kms:CreateKey"**

**Cause:** IAM user lacks KMS permissions

**Solution:**

```
Verify IAM user has AdministratorAccess or KMS full access:
  aws iam list-attached-user-policies --user-name terraform-admin

If missing, attach policy:
  aws iam attach-user-policy \
    --user-name terraform-admin \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

---

**Issue 3: "Error putting S3 bucket policy: MalformedPolicy"**

**Cause:** Bucket policy JSON syntax error

**Solution:**

```
Validate JSON in main.tf:
  - Check matching brackets { }
  - Check proper escaping in Terraform jsonencode()

Test policy separately:
  echo '{ "Version": "2012-10-17", ... }' | jq .
```

---

**Issue 4: "Timeout waiting for bucket encryption configuration"**

**Cause:** KMS key not ready when S3 tries to use it

**Solution:**

```
Usually auto-resolves on retry:
  terraform apply

If persists, add explicit dependency:
  resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
    depends_on = [aws_kms_key.logs, aws_kms_key_policy.logs]
    ...
  }
```

---

**Issue 5: "Plan shows unexpected changes on subsequent runs"**

**Cause:** Terraform detecting drift or policy normalization

**Solution:**

```
Check what changed:
  terraform plan -detailed-exitcode

Common benign changes:
  - KMS key policy formatting (JSON reordering)
  - S3 bucket policy Principal order

If changes are real (someone modified via Console):
  terraform apply  # Restore to desired state
```

---

### Verification Checklist

After deployment, verify:

- [ ] **KMS Key:**

  - [ ] Key rotation enabled
  - [ ] Key alias exists: `alias/iam-secure-gate-dev-logs`
  - [ ] Key policy allows CloudTrail and Config

- [ ] **CloudTrail Bucket:**

  - [ ] Bucket exists with correct name
  - [ ] Versioning enabled
  - [ ] Encryption configured (KMS)
  - [ ] Public access blocked (all 4 layers)
  - [ ] Bucket policy present
  - [ ] Lifecycle rule configured (30→Glacier, 90→Delete)

- [ ] **Config Bucket:**

  - [ ] Bucket exists with correct name
  - [ ] All settings same as CloudTrail bucket
  - [ ] Lifecycle rule configured (90→Glacier, 365→Delete)

- [ ] **Tags:**

  - [ ] All resources have Project tag
  - [ ] All resources have Owner tag
  - [ ] All resources have Environment tag

- [ ] **Terraform State:**
  - [ ] `terraform.tfstate` exists (17 resources)
  - [ ] `terraform.tfstate` NOT committed to Git (.gitignore)
  - [ ] Outputs accessible via `terraform output`

---

## Appendix A: Resource ARN Reference

```
KMS Key:
arn:aws:kms:eu-west-1:826232761554:key/{key-id}

KMS Alias:
arn:aws:kms:eu-west-1:826232761554:alias/iam-secure-gate-dev-logs

CloudTrail Bucket:
arn:aws:s3:::iam-secure-gate-dev-cloudtrail-826232761554

Config Bucket:
arn:aws:s3:::iam-secure-gate-dev-config-826232761554
```

---

## Appendix B: Related Documentation

- **Phase-1-README.md** - Complete Phase 1 implementation plan
- **Phase-1-EU-WEST-1-Guide.md** - Region-specific considerations
- **CIS AWS Foundations Benchmark v1.2.0** - Compliance standard
- **AWS Well-Architected Framework** - Security pillar best practices

---

## Appendix C: Future Enhancements

**Not in Foundation Scope (Future Phases):**

- CloudTrail trail creation (Phase 1, CloudTrail module)
- AWS Config recorder and rules (Phase 1, Config module)
- EventBridge rules for real-time detection (Phase 1, EventBridge module)
- Lambda remediation functions (Phase 2)
- Security Hub integration (Phase 1, Security Hub module)
- Grafana dashboard (Phase 4)

**Potential Foundation Improvements:**

- Multi-region KMS key replication
- S3 Cross-Region Replication for disaster recovery
- S3 Object Lock for immutable logs (compliance++)
- CloudWatch Logs integration (stream logs to CloudWatch)
- SNS notifications on bucket policy changes

---

**Document Version:** 1.0  
**Last Updated:** December 2, 2025  
**Status:** Production-Ready ✅  
**Module Version:** foundation-v1.0

---

## Quick Reference Card

**Module:** foundation  
**Resources:** 17  
**Cost:** ~$1.62/month  
**Region:** eu-west-1  
**Security:** CIS compliant ✅

**Outputs:**

```
kms_key_id              # For CloudTrail/Config encryption
cloudtrail_bucket_name  # For CloudTrail module
config_bucket_name      # For Config module
```

**Key Commands:**

```powershell
terraform init        # Initialize
terraform validate    # Check syntax
terraform plan        # Preview changes
terraform apply       # Deploy
terraform output      # View outputs
terraform destroy     # Clean up
```

**Support:** rskugor2907@gmail.com
