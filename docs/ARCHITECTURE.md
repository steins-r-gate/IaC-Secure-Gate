# IaC-Secure-Gate: Complete Architecture Documentation

**Version:** 1.0
**Date:** February 2026
**Author:** Final Year Project - Cloud Security Automation
**Status:** Production Ready

---

## Table of Contents

1. [Executive Overview](#1-executive-overview)
2. [System Architecture](#2-system-architecture)
3. [Phase 1: Detection Architecture](#3-phase-1-detection-architecture)
4. [Phase 2: Remediation Architecture](#4-phase-2-remediation-architecture)
5. [Data Flow Diagrams](#5-data-flow-diagrams)
6. [Security Architecture](#6-security-architecture)
7. [Cost Architecture](#7-cost-architecture)
8. [Performance Metrics](#8-performance-metrics)
9. [Terraform Module Structure](#9-terraform-module-structure)
10. [Appendix: CIS Controls Mapping](#10-appendix-cis-controls-mapping)

---

## 1. Executive Overview

### 1.1 What is IaC-Secure-Gate?

IaC-Secure-Gate is an automated cloud security system that **detects** and **remediates** security misconfigurations in AWS infrastructure. Built entirely with Infrastructure as Code (Terraform), it provides continuous compliance monitoring aligned with the CIS AWS Foundations Benchmark.

### 1.2 High-Level Architecture

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║                              AWS CLOUD ENVIRONMENT                                       ║
╠══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                          ║
║  ┌─────────────────────────────────────┐    ┌────────────────────────────────────────┐  ║
║  │       PHASE 1: DETECTION            │    │       PHASE 2: REMEDIATION             │  ║
║  │       (Passive Monitoring)          │    │       (Active Response)                │  ║
║  ├─────────────────────────────────────┤    ├────────────────────────────────────────┤  ║
║  │                                    │     │                                        │  ║
║  │  ┌───────────┐    ┌───────────┐    │     │  ┌─────────────┐                       │  ║
║  │  │CloudTrail │    │AWS Config │    │     │  │ EventBridge │                       │  ║
║  │  │  Audit    │    │Compliance │    │     │  │   Rules     │                       │  ║
║  │  └─────┬─────┘    └─────┬─────┘    │     │  └──────┬──────┘                       │  ║
║  │        │                │          │     │         │                              │  ║
║  │        │    ┌───────────┴───┐      │     │    ┌────┴────┬──────────┬─────────┐    │  ║
║  │        │    │ IAM Access    │      │     │    │         │          │         │    │  ║
║  │        │    │  Analyzer     │      │     │    ▼         ▼          ▼         │   1 │  ║
║  │        │    └───────┬───────┘      │     │ ┌──────┐ ┌──────┐ ┌──────┐        │     │  ║
║  │        │            │              │     │ │Lambda│ │Lambda│ │Lambda│        │     │  ║
║  │        ▼            ▼              │     │ │ IAM  │ │  S3  │ │  SG  │        │     │  ║
║  │  ┌─────────────────────────────┐   │     │ └──┬───┘ └──┬───┘ └──┬───┘        │     │  ║
║  │  │       SECURITY HUB          │   │     │    │        │        │            │     │  ║
║  │  │    (Centralized Findings)   │───┼─────┼────┘        │        │            │     │  ║
║  │  └─────────────────────────────┘   │     │             ▼        ▼            │     │  ║
║  │                                     │     │  ┌─────────────────────────┐      │     │  ║
║  └─────────────────────────────────────┘     │  │      DynamoDB           │      │     │  ║
║                                              │  │    (Audit Trail)        │      │     │  ║
║                                              │  └───────────┬─────────────┘      │     │  ║
║  ┌─────────────────────────────────────┐     │              │                    │     │  ║
║  │         DATA LAYER                  │     │              ▼                    │     │  ║
║  ├─────────────────────────────────────┤     │  ┌─────────────────────────┐      │     │  ║
║  │  ┌──────────┐  ┌──────────┐        │     │  │    SNS Notifications    │      │     │  ║
║  │  │    S3    │  │    S3    │        │     │  └───────────┬─────────────┘      │     │  ║
║  │  │CloudTrail│  │  Config  │        │     │              │                    │     │  ║
║  │  │   Logs   │  │ Snapshots│        │     │              ▼                    │     │  ║
║  │  └────┬─────┘  └────┬─────┘        │     │  ┌─────────────────────────┐      │     │  ║
║  │       │             │              │     │  │   Analytics Lambda      │      │     │  ║
║  │       └──────┬──────┘              │     │  │   (Daily Reports)       │      │     │  ║
║  │              ▼                     │     │  └─────────────────────────┘      │     │  ║
║  │  ┌─────────────────────────┐       │     │                                   │     │  ║
║  │  │     KMS Encryption      │       │     └───────────────────────────────────┘     │  ║
║  │  │    (Customer Key)       │       │                                               │  ║
║  │  └─────────────────────────┘       │                                               │  ║
║  └─────────────────────────────────────┘                                               ║
║                                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝
```

### 1.3 Key Benefits

| Benefit | Description |
|---------|-------------|
| **Automated Detection** | Continuous monitoring of 233+ security controls |
| **Instant Remediation** | Sub-second response to security violations |
| **Complete Audit Trail** | Every action logged and traceable |
| **Cost Efficient** | €8.51/month - 57% under budget |
| **CIS Compliant** | Aligned with industry security benchmarks |
| **Infrastructure as Code** | 100% reproducible and version controlled |

---

## 2. System Architecture

### 2.1 Two-Phase Design

The system operates in two distinct phases:

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: Detection<br/>(Passive Monitoring)"]
        A[Resource Change] --> B[API Logged]
        B --> C[Config Records]
        C --> D[Rules Evaluate]
        D --> E[Finding Created]
        E --> F[Security Hub]
    end

    subgraph Phase2["Phase 2: Remediation<br/>(Active Response)"]
        F --> G[EventBridge]
        G --> H[Lambda Function]
        H --> I[Fix Applied]
        I --> J[Audit Logged]
        J --> K[Alert Sent]
    end

    style Phase1 fill:#e1f5fe
    style Phase2 fill:#fff3e0
```

### 2.2 Component Summary

| Component | Phase | Purpose | Terraform Module |
|-----------|-------|---------|------------------|
| KMS | 1 | Encryption key for all logs | `foundation` |
| S3 Buckets | 1 | Secure log storage | `foundation` |
| CloudTrail | 1 | API audit logging | `cloudtrail` |
| AWS Config | 1 | Configuration recording | `config` |
| IAM Access Analyzer | 1 | External access detection | `access-analyzer` |
| Security Hub | 1 | Finding aggregation | `security-hub` |
| EventBridge | 2 | Event routing | `eventbridge-remediation` |
| Lambda (IAM) | 2 | IAM policy remediation | `lambda-remediation` |
| Lambda (S3) | 2 | S3 bucket remediation | `lambda-remediation` |
| Lambda (SG) | 2 | Security group remediation | `lambda-remediation` |
| DynamoDB | 2 | Remediation audit trail | `remediation-tracking` |
| SNS | 2 | Notifications | `self-improvement` |
| Lambda (Analytics) | 2 | Daily reporting | `self-improvement` |

---

## 3. Phase 1: Detection Architecture

### 3.1 Detection Pipeline Overview

```mermaid
flowchart TB
    subgraph "Detection Flow"
        U[User/System] -->|1. API Call| API[AWS API]
        API -->|2. ~5 seconds| CT[CloudTrail]
        API -->|3. ~1-15 min| CFG[AWS Config]

        CT -->|Logs stored| S3CT[(S3 CloudTrail<br/>Bucket)]
        CFG -->|Snapshots stored| S3CFG[(S3 Config<br/>Bucket)]

        CFG -->|4. Rule Evaluation| RULES[Config Rules<br/>8 CIS Rules]
        RULES -->|5. NON_COMPLIANT| FINDING[Finding Generated]

        AA[IAM Access Analyzer] -->|External Access| FINDING

        FINDING -->|6. Aggregation| SH[Security Hub]
        SH -->|Normalized ASFF| OUT[Ready for<br/>Remediation]
    end

    subgraph "Encryption"
        KMS[KMS CMK]
        S3CT -.->|Encrypted| KMS
        S3CFG -.->|Encrypted| KMS
    end
```

### 3.2 Component Details

#### 3.2.1 KMS Encryption Key

**Purpose:** Single customer-managed key encrypting all security data.

```
┌─────────────────────────────────────────────────────────────┐
│                    KMS Configuration                        │
├─────────────────────────────────────────────────────────────┤
│  Alias:            alias/iam-secure-gate-dev-logs           │
│  Key Rotation:     Automatic (Annual)                       │
│  Deletion Window:  7 days                                   │
│  Authorized:       CloudTrail, Config, Lambda               │
│  CIS Control:      3.8 - Customer managed keys              │
└─────────────────────────────────────────────────────────────┘
```

**Terraform Resource:** `terraform/modules/foundation/kms.tf`

#### 3.2.2 S3 Log Buckets

**CloudTrail Bucket Configuration:**

```mermaid
flowchart LR
    subgraph "S3 CloudTrail Bucket"
        A[Log Files] --> B[Versioning<br/>Enabled]
        B --> C[KMS<br/>Encryption]
        C --> D[Public Access<br/>Blocked]
        D --> E[Lifecycle<br/>Policy]
    end

    subgraph "Lifecycle"
        E --> L1[30 days: Standard]
        L1 --> L2[90 days: Glacier]
        L2 --> L3[Delete after 365 days]
    end
```

| Setting | CloudTrail Bucket | Config Bucket |
|---------|-------------------|---------------|
| Versioning | Enabled | Enabled |
| Encryption | SSE-KMS | SSE-KMS |
| Public Access | All Blocked | All Blocked |
| Hot Storage | 30 days | 90 days |
| Glacier | 90-365 days | 365+ days |
| CIS Controls | 2.1.1, 2.1.2 | 2.1.1, 2.1.2 |

**Terraform Resources:**
- `terraform/modules/foundation/s3_cloudtrail.tf`
- `terraform/modules/foundation/s3_config.tf`

#### 3.2.3 CloudTrail

**Purpose:** Captures all API activity across all AWS regions.

```mermaid
flowchart TB
    subgraph "CloudTrail Architecture"
        subgraph "All 18+ AWS Regions"
            R1[eu-west-1]
            R2[us-east-1]
            R3[ap-southeast-1]
            RN[... other regions]
        end

        R1 --> MT[Multi-Region Trail]
        R2 --> MT
        R3 --> MT
        RN --> MT

        MT --> VAL[Log File<br/>Validation]
        VAL --> S3[(S3 Bucket)]
        VAL --> DIGEST[Digest Files<br/>for Integrity]
    end
```

**Configuration:**

| Setting | Value | CIS Control |
|---------|-------|-------------|
| Multi-Region | Enabled | 3.1 |
| Log Validation | Enabled | 3.2 |
| KMS Encryption | Enabled | 3.3 |
| Global Events | Enabled | 3.1 |
| Management Events | Read + Write | 3.1 |

**Detection Latency:** ~5 seconds (EventBridge), 5-15 minutes (S3)

**Terraform Resource:** `terraform/modules/cloudtrail/main.tf`

#### 3.2.4 AWS Config

**Purpose:** Records configuration state and evaluates compliance rules.

```mermaid
flowchart TB
    subgraph "AWS Config Architecture"
        REC[Configuration<br/>Recorder] -->|Records All Resources| SNAP[Configuration<br/>Snapshots]
        SNAP -->|Daily| S3[(S3 Bucket)]

        REC --> STREAM[Configuration<br/>Stream]
        STREAM --> RULES[Managed Rules]

        subgraph "8 CIS-Aligned Rules"
            RULES --> R1[cloudtrail-enabled]
            RULES --> R2[multi-region-cloudtrail]
            RULES --> R3[s3-public-read-prohibited]
            RULES --> R4[s3-public-write-prohibited]
            RULES --> R5[s3-encryption-enabled]
            RULES --> R6[iam-password-policy]
            RULES --> R7[root-account-mfa]
            RULES --> R8[iam-user-mfa]
        end

        R1 --> COMP{Compliant?}
        R2 --> COMP
        R3 --> COMP
        R4 --> COMP
        R5 --> COMP
        R6 --> COMP
        R7 --> COMP
        R8 --> COMP

        COMP -->|No| FINDING[Generate Finding]
        FINDING --> SH[Security Hub]
    end
```

**Rules Detail:**

| Rule | CIS Control | Description |
|------|-------------|-------------|
| `cloudtrail-enabled` | 3.1 | CloudTrail must be enabled |
| `multi-region-cloudtrail-enabled` | 3.1 | Multi-region trail required |
| `s3-bucket-public-read-prohibited` | 2.1.5 | No public read access |
| `s3-bucket-public-write-prohibited` | 2.1.5 | No public write access |
| `s3-bucket-server-side-encryption-enabled` | 2.1.1 | Encryption required |
| `iam-password-policy` | 1.8 | Strong password policy |
| `root-account-mfa-enabled` | 1.5 | Root MFA required |
| `iam-user-mfa-enabled` | 1.10 | User MFA required |

**Detection Latency:** 1-15 minutes

**Terraform Resources:** `terraform/modules/config/` (main.tf, iam.tf, rules.tf)

#### 3.2.5 IAM Access Analyzer

**Purpose:** Identifies resources shared with external entities.

```mermaid
flowchart LR
    subgraph "Access Analyzer"
        AA[IAM Access<br/>Analyzer] -->|Scans| POL[Resource<br/>Policies]
        POL --> DETECT{External<br/>Access?}
        DETECT -->|Yes| FINDING[Finding]
        FINDING --> SH[Security Hub]
    end

    subgraph "Analyzed Resources"
        S3[S3 Buckets]
        IAM[IAM Roles]
        KMS[KMS Keys]
        SQS[SQS Queues]
        LAMBDA[Lambda Functions]
    end

    S3 --> POL
    IAM --> POL
    KMS --> POL
    SQS --> POL
    LAMBDA --> POL
```

**Configuration:**
- **Analyzer Type:** ACCOUNT (single account scope)
- **Detection:** Cross-account and external principal access
- **Latency:** 1-30 minutes

**Terraform Resource:** `terraform/modules/access-analyzer/main.tf`

#### 3.2.6 Security Hub

**Purpose:** Central aggregation point for all security findings.

```mermaid
flowchart TB
    subgraph "Security Hub Architecture"
        subgraph "Finding Sources"
            CFG[AWS Config<br/>Compliance]
            AA[IAM Access<br/>Analyzer]
            GD[GuardDuty<br/>Future]
        end

        CFG --> SH[Security Hub]
        AA --> SH
        GD -.-> SH

        subgraph "Standards"
            SH --> CIS[CIS Benchmark v1.4<br/>233 Controls]
            SH --> FSBP[AWS Foundational<br/>Disabled for Cost]
        end

        CIS --> ASFF[ASFF Format<br/>Normalized]
        ASFF --> EB[EventBridge<br/>Phase 2]
    end
```

**Enabled Standards:**
- CIS AWS Foundations Benchmark v1.4.0 (233 controls)
- AWS Foundational Security Best Practices (disabled to reduce Config costs)

**Terraform Resource:** `terraform/modules/security-hub/main.tf`

---

## 4. Phase 2: Remediation Architecture

### 4.1 Remediation Pipeline Overview

```mermaid
flowchart TB
    subgraph "8-Stage Remediation Pipeline"
        SH[Security Hub<br/>Finding] -->|1. Import| EB[EventBridge]
        EB -->|2. Pattern Match| ROUTE{Route to<br/>Lambda}

        ROUTE -->|IAM Finding| L1[IAM Lambda]
        ROUTE -->|S3 Finding| L2[S3 Lambda]
        ROUTE -->|SG Finding| L3[SG Lambda]

        L1 -->|3. Transform| T1[Extract<br/>Finding Data]
        L2 -->|3. Transform| T2[Extract<br/>Finding Data]
        L3 -->|3. Transform| T3[Extract<br/>Finding Data]

        T1 -->|4. Invoke| E1[Execute<br/>Remediation]
        T2 -->|4. Invoke| E2[Execute<br/>Remediation]
        T3 -->|4. Invoke| E3[Execute<br/>Remediation]

        E1 -->|5. Fix| FIX[Resource<br/>Modified]
        E2 -->|5. Fix| FIX
        E3 -->|5. Fix| FIX

        FIX -->|6. Audit| DDB[(DynamoDB)]
        DDB -->|7. Alert| SNS[SNS Topic]
        SNS -->|8. Report| AN[Analytics<br/>Lambda]
    end
```

### 4.2 EventBridge Event Routing

**Purpose:** Routes Security Hub findings to the appropriate Lambda function.

```mermaid
flowchart TB
    subgraph "EventBridge Routing"
        SH[Security Hub<br/>Finding] --> EB[EventBridge<br/>Bus]

        EB --> P1{Pattern:<br/>IAM.1, IAM.21?}
        EB --> P2{Pattern:<br/>S3.1-S3.19?}
        EB --> P3{Pattern:<br/>EC2.2, EC2.18?}

        P1 -->|Match| R1[IAM Rule]
        P2 -->|Match| R2[S3 Rule]
        P3 -->|Match| R3[SG Rule]

        R1 -->|Transform| L1[IAM Lambda]
        R2 -->|Transform| L2[S3 Lambda]
        R3 -->|Transform| L3[SG Lambda]

        R1 -->|On Failure| DLQ1[DLQ]
        R2 -->|On Failure| DLQ2[DLQ]
        R3 -->|On Failure| DLQ3[DLQ]
    end
```

**Event Pattern Example (IAM):**

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Compliance": {
        "Status": ["FAILED"]
      },
      "ProductFields": {
        "ControlId": ["IAM.1", "IAM.21"]
      },
      "Resources": {
        "Type": ["AwsIamPolicy"]
      },
      "Workflow": {
        "Status": ["NEW", "NOTIFIED"]
      }
    }
  }
}
```

**Rules Configuration:**

| Rule | Control IDs | Resource Type | Target |
|------|-------------|---------------|--------|
| IAM Wildcard | IAM.1, IAM.21 | AwsIamPolicy | IAM Lambda |
| S3 Public | S3.1-S3.5, S3.8, S3.19 | AwsS3Bucket | S3 Lambda |
| SG Open | EC2.2, EC2.18, EC2.19, EC2.21 | AwsEc2SecurityGroup | SG Lambda |

**Terraform Resource:** `terraform/modules/eventbridge-remediation/rules.tf`

### 4.3 Lambda Remediation Functions

#### 4.3.1 IAM Remediation Lambda

**Purpose:** Removes dangerous wildcard (*) permissions from IAM policies.

```mermaid
flowchart TB
    subgraph "IAM Remediation Flow"
        E[EventBridge<br/>Event] --> VAL[Validate<br/>Input]
        VAL --> CHECK{Protected<br/>Resource?}
        CHECK -->|Yes| SKIP[Skip & Log]
        CHECK -->|No| ANALYZE[Analyze<br/>Policy]

        ANALYZE --> FIND{Wildcard<br/>Found?}
        FIND -->|No| NOOP[No Action<br/>Needed]
        FIND -->|Yes| BACKUP[Backup<br/>Original]

        BACKUP --> DRY{Dry Run<br/>Mode?}
        DRY -->|Yes| SIMULATE[Log What<br/>Would Change]
        DRY -->|No| CREATE[Create New<br/>Policy Version]

        CREATE --> TAG[Tag Resource<br/>with Backup]
        TAG --> LOG[Log to<br/>DynamoDB]
        LOG --> NOTIFY[Send SNS<br/>Alert]
    end
```

**Remediation Logic:**

```
┌─────────────────────────────────────────────────────────────┐
│                  IAM Remediation Actions                    │
├─────────────────────────────────────────────────────────────┤
│  1. Parse IAM policy JSON                                   │
│  2. Identify statements with:                               │
│     - Action: "*" (all actions)                            │
│     - Resource: "*" (all resources)                        │
│  3. Create backup of original policy                        │
│  4. Remove/modify dangerous statements                      │
│  5. Create new policy version (preserves original)          │
│  6. Tag resource with remediation metadata                  │
│  7. Log action to DynamoDB                                  │
│  8. Send notification via SNS                               │
└─────────────────────────────────────────────────────────────┘
```

**Configuration:**
- **Runtime:** Python 3.12
- **Memory:** 256 MB
- **Timeout:** 30 seconds
- **Source Code:** `lambda/src/iam_remediation.py` (~450 lines)

#### 4.3.2 S3 Remediation Lambda

**Purpose:** Secures public S3 buckets by enabling security controls.

```mermaid
flowchart TB
    subgraph "S3 Remediation Flow"
        E[EventBridge<br/>Event] --> VAL[Validate<br/>Bucket Name]
        VAL --> CHECK{Protected<br/>Bucket?}
        CHECK -->|Yes| SKIP[Skip & Log]
        CHECK -->|No| SCAN[Scan Current<br/>Configuration]

        SCAN --> FIX1[Enable Block<br/>Public Access]
        FIX1 --> FIX2[Remove<br/>Public ACLs]
        FIX2 --> FIX3[Enable<br/>Encryption]
        FIX3 --> FIX4[Enable<br/>Versioning]
        FIX4 --> FIX5[Update Bucket<br/>Policy]

        FIX5 --> LOG[Log to<br/>DynamoDB]
        LOG --> NOTIFY[Send SNS<br/>Alert]
    end
```

**Remediation Actions:**

| Action | Description | CIS Control |
|--------|-------------|-------------|
| Block Public Access | Enable all 4 BPA settings | 2.1.5 |
| Remove Public ACLs | Remove public-read, public-read-write | 2.1.5 |
| Enable Encryption | Enable SSE-KMS encryption | 2.1.1 |
| Enable Versioning | Enable bucket versioning | 2.1.2 |
| Update Policy | Remove public statements | 2.1.5 |

**Configuration:**
- **Runtime:** Python 3.12
- **Memory:** 256 MB
- **Timeout:** 90 seconds (bucket operations slower)
- **Source Code:** `lambda/src/s3_remediation.py` (~420 lines)

#### 4.3.3 Security Group Remediation Lambda

**Purpose:** Removes overly permissive ingress rules from security groups.

```mermaid
flowchart TB
    subgraph "SG Remediation Flow"
        E[EventBridge<br/>Event] --> VAL[Validate<br/>SG ID]
        VAL --> CHECK{Protected<br/>SG?}
        CHECK -->|Yes| SKIP[Skip & Log]
        CHECK -->|No| SCAN[Scan Ingress<br/>Rules]

        SCAN --> FIND{0.0.0.0/0<br/>Found?}
        FIND -->|No| NOOP[No Action]
        FIND -->|Yes| WHITE{Whitelisted<br/>Port?}

        WHITE -->|Yes| ALLOW[Keep Rule]
        WHITE -->|No| BACKUP[Backup<br/>Rule]

        BACKUP --> REMOVE[Remove<br/>Rule]
        REMOVE --> TAG[Tag SG<br/>with Backup]
        TAG --> LOG[Log to<br/>DynamoDB]
        LOG --> NOTIFY[Send SNS<br/>Alert]
    end
```

**Remediation Actions:**

| Finding | Action | CIS Control |
|---------|--------|-------------|
| 0.0.0.0/0 on SSH (22) | Remove rule | 5.2 |
| 0.0.0.0/0 on RDP (3389) | Remove rule | 5.3 |
| 0.0.0.0/0 on all ports | Remove rule | 5.1 |
| Overly permissive range | Restrict CIDR | 5.4 |

**Configuration:**
- **Runtime:** Python 3.12
- **Memory:** 256 MB
- **Timeout:** 60 seconds
- **Source Code:** `lambda/src/sg_remediation.py` (~440 lines)

#### 4.3.4 Common Lambda Features

All remediation Lambdas share:

```
┌─────────────────────────────────────────────────────────────┐
│                  Common Lambda Features                      │
├─────────────────────────────────────────────────────────────┤
│  ✓ CloudWatch Log Group (30-day retention)                  │
│  ✓ Dead Letter Queue (SQS, 14-day retention)                │
│  ✓ Least-privilege IAM execution role                       │
│  ✓ Input validation with regex patterns                     │
│  ✓ Protected resource detection (skip tagged)               │
│  ✓ DynamoDB audit logging                                   │
│  ✓ SNS notifications                                        │
│  ✓ Structured logging (no sensitive data)                   │
│  ✓ Dry-run mode for safe testing                            │
│  ✓ Idempotency checks                                       │
└─────────────────────────────────────────────────────────────┘
```

**Terraform Resources:** `terraform/modules/lambda-remediation/`

### 4.4 DynamoDB Audit Trail

**Purpose:** Immutable record of all remediation actions.

```mermaid
flowchart TB
    subgraph "DynamoDB Schema"
        TABLE[(remediation-history)]

        TABLE --> PK["Partition Key:<br/>violation_type"]
        TABLE --> SK["Sort Key:<br/>timestamp"]

        TABLE --> ATTR[Attributes]
        ATTR --> A1[resource_arn]
        ATTR --> A2[action_taken]
        ATTR --> A3[status]
        ATTR --> A4[error_message]
        ATTR --> A5[remediation_lambda]
        ATTR --> A6[finding_id]
        ATTR --> A7[severity]
        ATTR --> A8[original_config]
        ATTR --> A9[new_config]

        TABLE --> GSI1["GSI1: resource-arn-index<br/>Query by resource"]
        TABLE --> GSI2["GSI2: status-index<br/>Query failed remediations"]
    end
```

**Table Configuration:**

| Setting | Value |
|---------|-------|
| Table Name | `iam-secure-gate-dev-remediation-history` |
| Billing Mode | PAY_PER_REQUEST |
| Point-in-Time Recovery | Enabled |
| TTL | 90 days |
| Encryption | AWS managed KMS |
| Streams | Enabled |

**Terraform Resource:** `terraform/modules/remediation-tracking/dynamodb.tf`

### 4.5 SNS Notifications

**Purpose:** Alert operators to security events.

```mermaid
flowchart TB
    subgraph "SNS Architecture"
        L1[IAM Lambda] --> T1[Remediation<br/>Alerts Topic]
        L2[S3 Lambda] --> T1
        L3[SG Lambda] --> T1

        T1 --> SUB1[Email<br/>Subscription]

        AN[Analytics<br/>Lambda] --> T2[Analytics<br/>Reports Topic]
        T2 --> SUB2[Email<br/>Subscription]

        L1 --> T3[Manual<br/>Review Topic]
        L2 --> T3
        L3 --> T3
        T3 --> SUB3[Email<br/>Subscription]
    end
```

**Topics:**

| Topic | Purpose | Trigger |
|-------|---------|---------|
| `remediation-alerts` | Immediate remediation notifications | Each Lambda execution |
| `analytics-reports` | Daily summary reports | Scheduled (2 AM UTC) |
| `manual-review` | Complex cases requiring human review | Failed remediations |

**Terraform Resource:** `terraform/modules/self-improvement/sns-topics.tf`

### 4.6 Analytics Lambda

**Purpose:** Daily analysis and reporting of remediation patterns.

```mermaid
flowchart TB
    subgraph "Analytics Pipeline"
        SCHED[EventBridge<br/>Schedule] -->|Daily 2 AM| AN[Analytics<br/>Lambda]

        AN --> QUERY[Query DynamoDB<br/>Last 30 Days]
        QUERY --> CALC[Calculate<br/>Metrics]

        CALC --> M1[Success Rate]
        CALC --> M2[MTTR by Type]
        CALC --> M3[Repeat Offenders]
        CALC --> M4[Trends]

        M1 --> REPORT[Generate<br/>Report]
        M2 --> REPORT
        M3 --> REPORT
        M4 --> REPORT

        REPORT --> SNS[Publish to<br/>SNS Topic]
        REPORT --> S3[Store in<br/>S3 Bucket]
    end
```

**Metrics Calculated:**

| Metric | Target | Description |
|--------|--------|-------------|
| Success Rate | >95% | Percentage of successful remediations |
| MTTR | <30s | Mean Time to Remediate |
| Repeat Violations | <10% | Resources with >3 violations |
| Cost per Remediation | <€0.01 | Lambda execution cost |

**Configuration:**
- **Runtime:** Python 3.12
- **Memory:** 512 MB
- **Timeout:** 60 seconds
- **Schedule:** `cron(0 2 * * ? *)` (Daily at 2 AM UTC)
- **Source Code:** `lambda/src/analytics.py` (~200 lines)

**Terraform Resource:** `terraform/modules/self-improvement/analytics-lambda.tf`

---

## 5. Data Flow Diagrams

### 5.1 Detection Data Flow

```mermaid
flowchart TB
    subgraph "Detection Data Flow"
        U[User/System] -->|1. API Call| AWS[AWS API]

        AWS -->|2. Captured| CT[CloudTrail]
        CT -->|3. Encrypted & Stored| S3CT[(S3 Logs)]

        AWS -->|4. Config Change| CFG[AWS Config]
        CFG -->|5. Snapshot| S3CFG[(S3 Snapshots)]

        CFG -->|6. Evaluate| RULES[Config Rules]
        RULES -->|7. NON_COMPLIANT| FINDING[Finding]

        FINDING -->|8. Normalize| SH[Security Hub]
        SH -->|9. ASFF Format| EB[EventBridge]
    end

    style S3CT fill:#ffecb3
    style S3CFG fill:#ffecb3
    style SH fill:#c8e6c9
```

### 5.2 Remediation Data Flow

```mermaid
flowchart TB
    subgraph "Remediation Data Flow"
        EB[EventBridge] -->|1. Route| LAMBDA[Lambda Function]

        LAMBDA -->|2. Read Policy| IAM[IAM/S3/EC2 API]
        IAM -->|3. Current State| LAMBDA

        LAMBDA -->|4. Fix| IAM
        IAM -->|5. Confirm| LAMBDA

        LAMBDA -->|6. Audit Record| DDB[(DynamoDB)]
        LAMBDA -->|7. Alert| SNS[SNS Topic]
        SNS -->|8. Email| USER[Operator]
    end

    style DDB fill:#e1bee7
    style SNS fill:#b3e5fc
```

### 5.3 Audit Data Flow

```mermaid
flowchart TB
    subgraph "Audit Data Flow"
        L1[IAM Lambda] -->|Write| DDB[(DynamoDB)]
        L2[S3 Lambda] -->|Write| DDB
        L3[SG Lambda] -->|Write| DDB

        DDB -->|Query| AN[Analytics Lambda]
        AN -->|Report| SNS[SNS Topic]
        AN -->|Archive| S3[(S3 Reports)]

        DDB -->|Stream| FUTURE[Future:<br/>Real-time Dashboard]
    end

    subgraph "Retention"
        DDB -->|90 Day TTL| EXPIRE[Auto-Delete]
    end
```

### 5.4 Notification Data Flow

```mermaid
flowchart TB
    subgraph "Notification Flow"
        subgraph "Sources"
            L1[IAM Lambda]
            L2[S3 Lambda]
            L3[SG Lambda]
            AN[Analytics Lambda]
        end

        subgraph "Topics"
            T1[Remediation Alerts]
            T2[Analytics Reports]
            T3[Manual Review]
        end

        subgraph "Destinations"
            E1[Email: University]
        end

        L1 --> T1
        L2 --> T1
        L3 --> T1

        L1 -->|On Failure| T3
        L2 -->|On Failure| T3
        L3 -->|On Failure| T3

        AN --> T2

        T1 --> E1
        T2 --> E1
        T3 --> E1
    end
```

---

## 6. Security Architecture

### 6.1 IAM Roles and Permissions

```mermaid
flowchart TB
    subgraph "IAM Architecture"
        subgraph "Service Roles"
            R1[CloudTrail Role]
            R2[Config Role]
            R3[Lambda Execution Roles]
        end

        subgraph "Permissions"
            R1 -->|Write| S3CT[S3 CloudTrail]
            R1 -->|Encrypt| KMS[KMS Key]

            R2 -->|Write| S3CFG[S3 Config]
            R2 -->|Encrypt| KMS
            R2 -->|Read| ALL[All Resources]

            R3 -->|Specific| IAM[IAM APIs]
            R3 -->|Specific| S3[S3 APIs]
            R3 -->|Specific| EC2[EC2 APIs]
            R3 -->|Write| DDB[DynamoDB]
            R3 -->|Publish| SNS[SNS]
        end
    end
```

**Principle of Least Privilege:**

| Role | Permissions | Scope |
|------|-------------|-------|
| CloudTrail | S3:PutObject, KMS:GenerateDataKey | Specific bucket only |
| Config | ReadOnlyAccess, S3:PutObject | Account-wide read, specific bucket write |
| IAM Lambda | iam:GetPolicy, iam:CreatePolicyVersion | IAM only |
| S3 Lambda | s3:GetBucket*, s3:PutBucket* | S3 only |
| SG Lambda | ec2:DescribeSecurityGroups, ec2:RevokeSecurityGroupIngress | EC2 only |

### 6.2 Encryption Architecture

```mermaid
flowchart TB
    subgraph "Encryption at Rest"
        KMS[KMS CMK<br/>Annual Rotation]

        KMS --> S3CT[S3 CloudTrail<br/>SSE-KMS]
        KMS --> S3CFG[S3 Config<br/>SSE-KMS]
        KMS --> DDB[DynamoDB<br/>AWS Managed]
        KMS --> SNS[SNS Topics<br/>AWS Managed]
    end

    subgraph "Encryption in Transit"
        TLS[TLS 1.2+]
        TLS --> API[All AWS APIs]
        TLS --> SNS2[SNS Delivery]
        TLS --> LAMBDA[Lambda Invocations]
    end
```

**Encryption Summary:**

| Component | At Rest | In Transit | Key Management |
|-----------|---------|------------|----------------|
| S3 Buckets | SSE-KMS (CMK) | TLS 1.2+ | Customer Managed |
| DynamoDB | AWS Managed | TLS 1.2+ | AWS Managed |
| SNS | AWS Managed | TLS 1.2+ | AWS Managed |
| Lambda Env Vars | AWS Managed | TLS 1.2+ | AWS Managed |
| CloudWatch Logs | AWS Managed | TLS 1.2+ | AWS Managed |

### 6.3 Audit Trail Integrity

```
┌─────────────────────────────────────────────────────────────┐
│                   Audit Trail Protection                     │
├─────────────────────────────────────────────────────────────┤
│  CloudTrail Logs:                                           │
│  ├── Log file validation (digest files)                     │
│  ├── S3 versioning (no silent deletion)                     │
│  ├── Bucket policy (CloudTrail only write)                  │
│  └── MFA delete option (additional protection)              │
│                                                             │
│  DynamoDB Audit:                                            │
│  ├── Point-in-time recovery enabled                         │
│  ├── DynamoDB Streams (change capture)                      │
│  ├── 90-day retention with TTL                              │
│  └── original_config field (pre-remediation state)          │
│                                                             │
│  Lambda Logs:                                               │
│  ├── CloudWatch Logs (30-day retention)                     │
│  ├── Structured JSON logging                                │
│  └── No sensitive data in logs                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Cost Architecture

### 7.1 Monthly Cost Breakdown

```mermaid
pie title Monthly Cost Distribution (€8.51)
    "CloudTrail" : 2.00
    "Config Rules" : 1.60
    "Config Recorder" : 2.00
    "KMS" : 1.00
    "CloudWatch Logs" : 1.00
    "S3 Storage" : 0.59
    "Other (Lambda, DDB, SNS)" : 0.32
```

### 7.2 Detailed Cost Analysis

| Service | Component | Monthly Cost | Notes |
|---------|-----------|--------------|-------|
| **CloudTrail** | Management events | €2.00 | First trail free, ~100K events |
| **AWS Config** | Configuration items | €2.00 | First 1000 free, ~€0.003 each |
| **AWS Config** | Rules (8) | €1.60 | €0.20/rule/month |
| **KMS** | Customer managed key | €1.00 | Plus API calls |
| **S3** | Storage | €0.50 | Lifecycle optimization |
| **S3** | Glacier | €0.09 | Long-term archive |
| **CloudWatch** | Logs ingestion | €1.00 | ~2GB/month |
| **Lambda** | Invocations | €0.00 | Within free tier |
| **Lambda** | Compute | €0.00 | Within free tier |
| **DynamoDB** | On-demand | €0.008 | Pay per request |
| **EventBridge** | Events | €0.00 | First 1M free |
| **SNS** | Notifications | €0.00 | First 1M free |
| **IAM Access Analyzer** | Analyzer | €0.00 | Free |
| **Security Hub** | Findings | €0.00 | First 10K free |
| | **TOTAL** | **€8.51** | **57% under €20 budget** |

### 7.3 Cost Optimization Strategies

```
┌─────────────────────────────────────────────────────────────┐
│               Cost Optimization Applied                      │
├─────────────────────────────────────────────────────────────┤
│  ✓ S3 Lifecycle policies (hot → Glacier → delete)           │
│  ✓ CloudWatch Insights disabled (save €35-50/month)         │
│  ✓ CloudWatch Logs integration optional (save €10-20)       │
│  ✓ AWS Foundational standard disabled (reduce Config)       │
│  ✓ DynamoDB on-demand (no idle capacity cost)               │
│  ✓ Lambda right-sized (256MB sufficient)                    │
│  ✓ 30-day log retention (not 365)                           │
│  ✓ Single KMS key for all services                          │
│  ✓ Regional deployment (no cross-region replication)        │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Performance Metrics

### 8.1 Key Performance Indicators

| Metric | Target | Achieved | Status |
|--------|--------|----------|--------|
| **MTTD** (Mean Time to Detect) | <5 min | 2-4 min | ✅ |
| **MTTR** (Mean Time to Remediate) | <30 sec | 1-2 sec | ✅ |
| **Remediation Success Rate** | >95% | 100% | ✅ |
| **E2E Test Pass Rate** | 100% | 100% | ✅ |
| **Monthly Cost** | <€20 | €8.51 | ✅ |
| **Lambda Cold Start** | <1 sec | ~450ms | ✅ |
| **Lambda Memory Usage** | <80% | 34% (87/256MB) | ✅ |

### 8.2 Detection Timeline

```mermaid
gantt
    title Detection Timeline (Typical Scenario)
    dateFormat  mm:ss
    axisFormat %M:%S

    section CloudTrail
    API Call Captured    :a1, 00:00, 5s

    section Config
    Configuration Recorded :a2, 00:05, 60s
    Rule Evaluation        :a3, 01:05, 30s

    section Security Hub
    Finding Imported       :a4, 01:35, 10s

    section Total
    Detection Complete     :milestone, 01:45, 0s
```

### 8.3 Remediation Timeline

```mermaid
gantt
    title Remediation Timeline (Sub-Second)
    dateFormat  s
    axisFormat %Ss

    section EventBridge
    Event Received    :a1, 0, 100ms
    Pattern Matched   :a2, after a1, 50ms

    section Lambda
    Cold Start        :a3, after a2, 450ms
    Execution         :a4, after a3, 500ms

    section Post-Actions
    DynamoDB Write    :a5, after a4, 50ms
    SNS Publish       :a6, after a4, 50ms

    section Total
    Remediation Done  :milestone, after a6, 0s
```

---

## 9. Terraform Module Structure

### 9.1 Module Hierarchy

```
terraform/
├── environments/
│   └── dev/
│       ├── main.tf              # Root orchestration
│       ├── terraform.tfvars     # Environment variables
│       └── backend.tf           # State configuration
│
└── modules/
    ├── foundation/              # Phase 1: Core infrastructure
    │   ├── kms.tf               # Encryption key
    │   ├── s3_cloudtrail.tf     # CloudTrail bucket
    │   ├── s3_config.tf         # Config bucket
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── cloudtrail/              # Phase 1: Audit logging
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── config/                  # Phase 1: Compliance
    │   ├── main.tf              # Recorder
    │   ├── iam.tf               # Service role
    │   ├── rules.tf             # 8 CIS rules
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── access-analyzer/         # Phase 1: External access
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── security-hub/            # Phase 1: Aggregation
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── lambda-remediation/      # Phase 2: Lambda functions
    │   ├── iam-remediation.tf   # IAM remediation
    │   ├── s3-remediation.tf    # S3 remediation
    │   ├── sg-remediation.tf    # SG remediation
    │   ├── common.tf            # Shared resources
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── eventbridge-remediation/ # Phase 2: Event routing
    │   ├── rules.tf             # 3 EventBridge rules
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── remediation-tracking/    # Phase 2: Audit trail
    │   ├── dynamodb.tf          # DynamoDB table
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── self-improvement/        # Phase 2: Analytics
        ├── sns-topics.tf        # 3 SNS topics
        ├── analytics-lambda.tf  # Analytics function
        ├── variables.tf
        └── outputs.tf
```

### 9.2 Module Dependencies

```mermaid
flowchart TB
    subgraph "Module Dependencies"
        FOUND[foundation] --> CT[cloudtrail]
        FOUND --> CFG[config]

        CT --> SH[security-hub]
        CFG --> SH
        AA[access-analyzer] --> SH

        SH --> EB[eventbridge-remediation]

        TRACK[remediation-tracking] --> LAMBDA[lambda-remediation]
        SELF[self-improvement] --> LAMBDA

        EB --> LAMBDA
    end
```

### 9.3 Resource Count

| Module | Resources | Description |
|--------|-----------|-------------|
| foundation | 12 | KMS key, 2 S3 buckets, policies |
| cloudtrail | 3 | Trail, IAM role, policy |
| config | 15 | Recorder, delivery channel, 8 rules, IAM |
| access-analyzer | 2 | Analyzer, IAM |
| security-hub | 4 | Hub, 2 standards, product |
| lambda-remediation | 21 | 3 functions, IAM, logs, DLQs |
| eventbridge-remediation | 9 | 3 rules, 3 targets, 3 DLQs |
| remediation-tracking | 3 | DynamoDB table, 2 GSIs |
| self-improvement | 11 | 3 SNS topics, analytics Lambda |
| **TOTAL** | **80+** | |

---

## 10. Appendix: CIS Controls Mapping

### 10.1 CIS AWS Foundations Benchmark v1.4.0 Coverage

| CIS Control | Description | Implementation |
|-------------|-------------|----------------|
| **1.5** | Ensure MFA is enabled for root account | Config Rule: `root-account-mfa-enabled` |
| **1.8** | Ensure IAM password policy is configured | Config Rule: `iam-password-policy` |
| **1.10** | Ensure MFA is enabled for all IAM users | Config Rule: `iam-user-mfa-enabled` |
| **1.16** | Ensure IAM policies avoid wildcards | Lambda: IAM Remediation |
| **2.1.1** | Ensure S3 bucket encryption is enabled | Lambda: S3 Remediation |
| **2.1.2** | Ensure S3 bucket versioning is enabled | Lambda: S3 Remediation |
| **2.1.5** | Ensure S3 buckets deny public access | Lambda: S3 Remediation |
| **3.1** | Ensure CloudTrail is enabled | Config Rule + CloudTrail module |
| **3.2** | Ensure CloudTrail log validation | CloudTrail: `enable_log_file_validation` |
| **3.3** | Ensure CloudTrail S3 bucket not public | Foundation: S3 bucket policies |
| **3.8** | Ensure customer managed keys are used | Foundation: KMS CMK |
| **5.1** | Ensure no security groups allow 0.0.0.0/0 | Lambda: SG Remediation |
| **5.2** | Ensure no security groups allow SSH from 0.0.0.0/0 | Lambda: SG Remediation |
| **5.3** | Ensure no security groups allow RDP from 0.0.0.0/0 | Lambda: SG Remediation |

### 10.2 Security Hub Control IDs

| Control ID | Finding Type | Remediation Lambda |
|------------|--------------|-------------------|
| IAM.1 | IAM policies should not allow full "*" administrative privileges | IAM Remediation |
| IAM.21 | IAM customer managed policies should not allow wildcard actions | IAM Remediation |
| S3.1 | S3 Block Public Access setting should be enabled | S3 Remediation |
| S3.2 | S3 buckets should prohibit public read access | S3 Remediation |
| S3.3 | S3 buckets should prohibit public write access | S3 Remediation |
| S3.4 | S3 buckets should have server-side encryption enabled | S3 Remediation |
| S3.5 | S3 buckets should require SSL | S3 Remediation |
| S3.8 | S3 Block Public Access should be enabled at bucket level | S3 Remediation |
| S3.19 | S3 access points should have block public access enabled | S3 Remediation |
| EC2.2 | Default VPC security groups should not allow traffic | SG Remediation |
| EC2.18 | Security groups should only allow unrestricted traffic for authorized ports | SG Remediation |
| EC2.19 | Security groups should not allow unrestricted access to high risk ports | SG Remediation |
| EC2.21 | Network ACLs should not allow ingress from 0.0.0.0/0 | SG Remediation |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | February 2026 | Project Team | Initial comprehensive documentation |

---

*This document was created for the IaC-Secure-Gate Final Year Project commission presentation.*
