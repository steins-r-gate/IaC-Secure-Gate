# IaC-Secure-Gate Architecture Diagrams

**Project:** IaC-Secure-Gate
**Version:** 1.0
**Date:** February 2026

---

## 1. High-Level System Architecture

```
+===================================================================================+
|                              AWS CLOUD (eu-west-1)                                |
+===================================================================================+
|                                                                                   |
|  +----------------------------------+     +---------------------------------+     |
|  |     PHASE 1: DETECTION           |     |     PHASE 2: REMEDIATION        |     |
|  |     (Passive Monitoring)         |     |     (Active Response)           |     |
|  +----------------------------------+     +---------------------------------+     |
|  |                                  |     |                                 |     |
|  |  +----------+    +----------+    |      |  +------------+                |     |
|  |  |CloudTrail|    |AWS Config|    |     |  |EventBridge |                 |     |
|  |  |  Audit   |    |Compliance|    |     |  |   Rules    |                 |     |
|  |  +----+-----+    +----+-----+    |     |  +-----+------+                 |     |
|  |       |              |           |     |        |                        |     |
|  |       |    +---------+------+    |     |   +----+----+----+----+         |     |
|  |       |    | IAM Access     |    |     |   |         |         |         |     |
|  |       |    |   Analyzer     |    |     |   v         v         v         |     |
|  |       |    +-------+--------+    |     |  +---+   +---+   +---+          |     |
|  |       |            |             |     |  |IAM|   | S3|   | SG|          |     |
|  |       v            v             |     |  +---+   +---+   +---+          |     |
|  |  +----------------------+        |     |  Lambda  Lambda  Lambda         |     |
|  |  |    SECURITY HUB      |        |     |    |       |       |            |     |
|  |  | (Finding Aggregation)|--------+-----+----+-------+-------+            |     |
|  |  +----------------------+        |     |            |                    |     |
|  |                                  |     |            v                    |     |
|  +----------------------------------+     |  +--------------------+         |     |
|                                           |  |     DynamoDB       |         |     |
|  +----------------------------------+     |  |   (Audit Trail)    |         |     |
|  |         DATA LAYER               |     |  +--------------------+         |     |
|  +----------------------------------+     |            |                    |     |
|  |  +----------+    +----------+    |     |            v                    |     |
|  |  |    S3    |    |    S3    |    |     |  +--------------------+         |     |
|  |  |CloudTrail|    |  Config  |    |     |  |   SNS Topics       |         |     |
|  |  |   Logs   |    | Snapshots|    |     |  |  (Notifications)   |         |     |
|  |  +----+-----+    +----+-----+    |     |  +--------------------+         |     |
|  |       |              |           |     |                                 |     |
|  |       +------+-------+           |     +---------------------------------+     |
|  |              |                   |                                             |
|  |  +-----------v-----------+       |                                             |
|  |  |    KMS Encryption     |       |                                             |
|  |  |   (Customer Key)      |       |                                             |
|  |  +-----------------------+       |                                             |
|  +----------------------------------+                                             |
|                                                                                   |
+===================================================================================+
```

---

## 2. Phase 1: Detection Pipeline

```
+============================================================================+
|                        DETECTION PIPELINE                                  |
+============================================================================+

                         +------------------+
                         |   User/System    |
                         | Creates/Modifies |
                         |    Resource      |
                         +--------+---------+
                                  |
                                  | 1. API Call
                                  v
                         +------------------+
                         |     AWS API      |
                         +--------+---------+
                                  |
            +---------------------+---------------------+
            |                     |                     |
            | 2. ~5 seconds       |                     | 3. ~1-15 min
            v                     |                     v
   +----------------+             |            +----------------+
   |   CloudTrail   |             |            |   AWS Config   |
   | Audit Logging  |             |            |   Recording    |
   +-------+--------+             |            +-------+--------+
           |                      |                    |
           |                      |                    | 4. Rule Evaluation
           v                      |                    v
   +----------------+             |            +----------------+
   | S3 CloudTrail  |             |            |  8 CIS Rules   |
   |    Bucket      |             |            | (Compliance)   |
   | (Encrypted)    |             |            +-------+--------+
   +----------------+             |                    |
                                  |                    | 5. NON_COMPLIANT
                      +-----------+-----------+        |
                      |   IAM Access          |        |
                      |    Analyzer           +--------+
                      | (External Access)     |        |
                      +-----------+-----------+        |
                                  |                    v
                                  |          +------------------+
                                  |          |     Finding      |
                                  |          |    Generated     |
                                  |          +--------+---------+
                                  |                   |
                                  |                   | 6. Aggregation
                                  |                   v
                                  |          +------------------+
                                  +--------->|   Security Hub   |
                                             | (~30 CIS Controls)|
                                             +--------+---------+
                                                      |
                                                      | 7. Triggers Phase 2
                                                      v
                                             +------------------+
                                             |   EventBridge    |
                                             +------------------+
```

---

## 3. Phase 2: Remediation Pipeline

```
+============================================================================+
|                       REMEDIATION PIPELINE                                  |
+============================================================================+

+------------------+
|   Security Hub   |
|     Finding      |
+--------+---------+
         |
         | 1. Finding Imported
         v
+------------------+
|   EventBridge    |
|   Pattern Match  |
+--------+---------+
         |
         | 2. Route by Control ID
         |
    +----+----+--------------------+--------------------+
    |         |                    |                    |
    v         v                    v                    v
+-------+ +-------+           +-------+           +-------+
|IAM.1  | |IAM.21 |           |S3.1-19|           |EC2.2  |
|Rule   | |Rule   |           |Rule   |           |EC2.18+|
+---+---+ +---+---+           +---+---+           +---+---+
    |         |                   |                   |
    +----+----+                   |                   |
         |                        |                   |
         v                        v                   v
+------------------+    +------------------+    +------------------+
|   IAM Lambda     |    |    S3 Lambda     |    |    SG Lambda     |
|   Remediation    |    |   Remediation    |    |   Remediation    |
| (~450 lines)     |    |  (~420 lines)    |    |  (~440 lines)    |
+--------+---------+    +--------+---------+    +--------+---------+
         |                       |                       |
         | 3. Execute Fix        | 3. Execute Fix        | 3. Execute Fix
         |                       |                       |
         | - Remove wildcards    | - Block public access | - Remove 0.0.0.0/0
         | - Create new version  | - Enable encryption   | - Log original rule
         | - Backup original     | - Enable versioning   | - Tag resource
         |                       |                       |
         +-------------+---------+---------+-------------+
                       |                   |
                       v                   v
              +------------------+  +------------------+
              |    DynamoDB      |  |    SNS Topics    |
              |  (Audit Trail)   |  | (Notifications)  |
              |  90-day TTL      |  +------------------+
              +------------------+
```

---

## 4. Lambda Remediation Flow (Detailed)

```
+============================================================================+
|                    LAMBDA REMEDIATION FLOW                                  |
+============================================================================+

                    +----------------------+
                    |   EventBridge Event  |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |   Input Validation   |
                    | - Validate ARN format|
                    | - Check required fields
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |  Protected Resource? |
                    |  (Check for tags)    |
                    +----------+-----------+
                               |
              +----------------+----------------+
              |                                 |
              v                                 v
    +------------------+              +------------------+
    |   YES - SKIP     |              |    NO - PROCEED  |
    | Log: "Protected" |              +--------+---------+
    +------------------+                       |
                                               v
                                    +----------------------+
                                    |  Analyze Resource    |
                                    | - Get current config |
                                    | - Identify violations|
                                    +----------+-----------+
                                               |
                                               v
                                    +----------------------+
                                    |  Violation Found?    |
                                    +----------+-----------+
                                               |
                              +----------------+----------------+
                              |                                 |
                              v                                 v
                    +------------------+              +------------------+
                    |   NO - NO ACTION |              |  YES - REMEDIATE |
                    | Log: "Compliant" |              +--------+---------+
                    +------------------+                       |
                                                               v
                                                    +----------------------+
                                                    |  Dry Run Mode?       |
                                                    +----------+-----------+
                                                               |
                                              +----------------+----------------+
                                              |                                 |
                                              v                                 v
                                    +------------------+              +------------------+
                                    |  YES - SIMULATE  |              |   NO - APPLY     |
                                    | Log what would   |              | - Backup original|
                                    | change           |              | - Apply fix      |
                                    +------------------+              | - Create version |
                                                                      +--------+---------+
                                                                               |
                                                                               v
                                                                    +----------------------+
                                                                    |  Log to DynamoDB     |
                                                                    | - violation_type     |
                                                                    | - timestamp          |
                                                                    | - resource_arn       |
                                                                    | - action_taken       |
                                                                    | - status             |
                                                                    | - original_config    |
                                                                    +----------+-----------+
                                                                               |
                                                                               v
                                                                    +----------------------+
                                                                    |  Send SNS Alert      |
                                                                    +----------------------+
```

---

## 5. Data Flow Overview

```
+============================================================================+
|                         DATA FLOW OVERVIEW                                  |
+============================================================================+

  DETECTION FLOW                  REMEDIATION FLOW               AUDIT FLOW
  ==============                  ================               ==========

+-------------+                   +-------------+               +-------------+
| API Call    |                   |Security Hub |               | IAM Lambda  |
+------+------+                   |   Finding   |               +------+------+
       |                          +------+------+                      |
       v                                 |                             |
+-------------+                          v                             v
| CloudTrail  |                   +-------------+               +-------------+
+------+------+                   | EventBridge |               |  DynamoDB   |
       |                          +------+------+               |   Table     |
       v                                 |                      +------+------+
+-------------+                          v                             |
|  S3 Bucket  |                   +-------------+                      v
| (Encrypted) |                   |   Lambda    |               +-------------+
+-------------+                   |  Function   |               |  Analytics  |
                                  +------+------+               |   Lambda    |
+-------------+                          |                      +------+------+
| AWS Config  |                          v                             |
+------+------+                   +-------------+                      v
       |                          |   AWS API   |               +-------------+
       v                          | (Fix Applied)|              | SNS Reports |
+-------------+                   +-------------+               +-------------+
| Config Rules|
| (8 CIS)     |
+------+------+
       |
       v
+-------------+
|   Finding   |
+------+------+
       |
       v
+-------------+
|Security Hub |
|(~30 Controls)|
+-------------+
```

---

## 6. Terraform Module Structure

```
+============================================================================+
|                      TERRAFORM MODULE STRUCTURE                             |
+============================================================================+

terraform/
|
+-- environments/
|   |
|   +-- dev/
|       |-- main.tf .............. Root module orchestration
|       |-- variables.tf ......... Environment variables
|       |-- outputs.tf ........... Deployment outputs
|       +-- terraform.tfvars ..... Variable values
|
+-- modules/
    |
    +-- foundation/ .............. PHASE 1: Core Infrastructure
    |   |-- kms.tf ............... KMS encryption key
    |   |-- s3_cloudtrail.tf ..... CloudTrail log bucket
    |   |-- s3_config.tf ......... Config snapshot bucket
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- cloudtrail/ .............. PHASE 1: Audit Logging
    |   |-- main.tf .............. Multi-region trail
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- config/ .................. PHASE 1: Compliance
    |   |-- main.tf .............. Configuration recorder
    |   |-- iam.tf ............... Service role
    |   |-- rules.tf ............. 8 CIS compliance rules
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- access-analyzer/ ......... PHASE 1: External Access
    |   |-- main.tf .............. Account analyzer
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- security-hub/ ............ PHASE 1: Aggregation
    |   |-- main.tf .............. Hub + CIS Benchmark
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- lambda-remediation/ ...... PHASE 2: Remediation
    |   |-- iam-remediation.tf ... IAM Lambda function
    |   |-- s3-remediation.tf .... S3 Lambda function
    |   |-- sg-remediation.tf .... SG Lambda function
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- eventbridge-remediation/.. PHASE 2: Event Routing
    |   |-- rules.tf ............. 3 EventBridge rules
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- remediation-tracking/ .... PHASE 2: Audit Trail
    |   |-- dynamodb.tf .......... DynamoDB table
    |   |-- variables.tf
    |   +-- outputs.tf
    |
    +-- self-improvement/ ........ PHASE 2: Analytics
        |-- sns-topics.tf ........ 3 SNS topics
        |-- analytics-lambda.tf .. Daily reporting
        |-- variables.tf
        +-- outputs.tf
```

---

## 7. Module Dependencies

```
+============================================================================+
|                        MODULE DEPENDENCIES                                  |
+============================================================================+

                              +-------------+
                              | foundation  |
                              | (KMS + S3)  |
                              +------+------+
                                     |
                    +----------------+----------------+
                    |                                 |
                    v                                 v
             +-------------+                   +-------------+
             | cloudtrail  |                   |   config    |
             +------+------+                   +------+------+
                    |                                 |
                    |         +-------------+         |
                    |         |   access-   |         |
                    |         |  analyzer   |         |
                    |         +------+------+         |
                    |                |                |
                    +----------------+----------------+
                                     |
                                     v
                              +-------------+
                              |security-hub |
                              +------+------+
                                     |
                                     v
                           +------------------+
                           |   eventbridge-   |
                           |   remediation    |
                           +--------+---------+
                                    |
           +------------------------+------------------------+
           |                        |                        |
           v                        v                        v
    +-------------+          +-------------+          +-------------+
    | remediation-|          |   lambda-   |          |    self-    |
    |  tracking   |          | remediation |          | improvement |
    | (DynamoDB)  |          | (3 Lambdas) |          |   (SNS)     |
    +-------------+          +-------------+          +-------------+
```

---

## 8. Security Architecture

```
+============================================================================+
|                       SECURITY ARCHITECTURE                                 |
+============================================================================+

+---------------------------+
|     ENCRYPTION AT REST    |
+---------------------------+
|                           |
|  +-------------------+    |         +-------------------+
|  |    KMS CMK        |    |         |   S3 CloudTrail   |
|  | (Annual Rotation) +----------->  |    (SSE-KMS)      |
|  +-------------------+    |         +-------------------+
|           |               |
|           |               |         +-------------------+
|           +-------------------->    |    S3 Config      |
|           |               |         |    (SSE-KMS)      |
|           |               |         +-------------------+
|           |               |
|           |               |         +-------------------+
|           +-------------------->    |    DynamoDB       |
|                           |         |  (AWS Managed)    |
+---------------------------+         +-------------------+


+---------------------------+
|   ENCRYPTION IN TRANSIT   |
+---------------------------+
|                           |
|  All AWS API Calls        |         +-------------------+
|  +-------------------+    |         |                   |
|  |    TLS 1.2+       +----------->  |   HTTPS Only      |
|  +-------------------+    |         |                   |
|                           |         +-------------------+
+---------------------------+


+---------------------------+
|   IAM LEAST PRIVILEGE     |
+---------------------------+
|                           |
|  +-------------------+              +-------------------+
|  | CloudTrail Role   |              | S3:PutObject only |
|  +-------------------+   -------->  | to specific bucket|
|                                     +-------------------+
|  +-------------------+              +-------------------+
|  |  Config Role      |              | ReadOnly + S3 Put |
|  +-------------------+   -------->  | to specific bucket|
|                                     +-------------------+
|  +-------------------+              +-------------------+
|  | IAM Lambda Role   |              | iam:GetPolicy     |
|  +-------------------+   -------->  | iam:CreateVersion |
|                                     +-------------------+
|  +-------------------+              +-------------------+
|  |  S3 Lambda Role   |              | s3:GetBucket*     |
|  +-------------------+   -------->  | s3:PutBucket*     |
|                                     +-------------------+
|  +-------------------+              +-------------------+
|  |  SG Lambda Role   |              | ec2:Describe*     |
|  +-------------------+   -------->  | ec2:Revoke*       |
|                           |         +-------------------+
+---------------------------+
```

---

## 9. Cost Architecture

```
+============================================================================+
|                         COST BREAKDOWN (~8.51 EUR/month)                    |
+============================================================================+

                    +------------------------------------------+
                    |            MONTHLY COSTS                  |
                    +------------------------------------------+

    +---------------+     +---------------+     +---------------+
    |  CloudTrail   |     |  AWS Config   |     |     KMS       |
    |    ~2.00 EUR  |     |   ~3.60 EUR   |     |   ~1.00 EUR   |
    +---------------+     +---------------+     +---------------+
           |                     |                     |
           |              +------+------+              |
           |              |             |              |
           |              v             v              |
           |        +---------+   +---------+         |
           |        |Recorder |   | 8 Rules |         |
           |        | ~2.00   |   | ~1.60   |         |
           |        +---------+   +---------+         |
           |                                          |
           +------------------+  +--------------------+
                              |  |
                              v  v
                    +------------------------------------------+
                    |              S3 Storage                  |
                    |              ~0.59 EUR                   |
                    |  +----------------+  +----------------+  |
                    |  | CloudTrail Logs|  |Config Snapshots|  |
                    |  |   + Lifecycle  |  |   + Lifecycle  |  |
                    |  +----------------+  +----------------+  |
                    +------------------------------------------+

                    +------------------------------------------+
                    |          CloudWatch Logs                 |
                    |             ~1.00 EUR                    |
                    +------------------------------------------+

                    +------------------------------------------+
                    |     FREE TIER SERVICES (0.00 EUR)        |
                    +------------------------------------------+
                    |  Lambda     | EventBridge | DynamoDB     |
                    |  SNS        | Access Analyzer | Sec Hub  |
                    +------------------------------------------+

                    +------------------------------------------+
                    |         TOTAL: ~8.51 EUR/month           |
                    |         (57% under 20 EUR budget)        |
                    +------------------------------------------+
```

---

## 10. Detection Timeline

```
+============================================================================+
|                        DETECTION TIMELINE                                   |
+============================================================================+

Time (seconds)    0      5     60    90    120   150   180   210   240
                  |------|------|------|------|------|------|------|------|

CloudTrail        [===]
Capture           0-5s

Config            [=========================]
Recording         5s-90s (variable)

Config Rule              [===========]
Evaluation               60s-120s

Security Hub                          [===]
Import                                90s-120s

                  |<---- MTTD: 2-4 minutes ---->|

+----------------------------------------------------------------------------+
|  ACHIEVED: Mean Time to Detect = 2-4 minutes (Target was <5 minutes)       |
+----------------------------------------------------------------------------+
```

---

## 11. Remediation Timeline

```
+============================================================================+
|                       REMEDIATION TIMELINE                                  |
+============================================================================+

Time (milliseconds)  0    100   200   300   400   500   600   700   800   900
                     |----|----|----|----|----|----|----|----|----|----|----|

EventBridge          [==]
Receive              0-50ms

Pattern Match             [=]
                          50-100ms

Lambda Cold Start              [================]
                               100-550ms (~450ms)

Lambda Execution                                  [==================]
                                                  550-1100ms (~500ms)

DynamoDB Write                                                        [=]
                                                                      ~50ms

SNS Publish                                                           [=]
                                                                      ~50ms

                     |<-------- MTTR: 1-2 seconds -------->|

+----------------------------------------------------------------------------+
|  ACHIEVED: Mean Time to Remediate = 1.66 seconds (Target was <30 seconds)  |
+----------------------------------------------------------------------------+
```

---

## 12. CIS Controls Coverage

```
+============================================================================+
|                    CIS AWS FOUNDATIONS BENCHMARK COVERAGE                   |
+============================================================================+

+----------------------+---------------------------+-------------------------+
|   CIS CONTROL        |   IMPLEMENTATION          |   METHOD                |
+----------------------+---------------------------+-------------------------+
|                      |                           |                         |
|   1.5  Root MFA      |   Config Rule             |   Detection             |
|   1.8  Password Policy|   Config Rule            |   Detection             |
|   1.10 User MFA      |   Config Rule             |   Detection             |
|   1.16 No Wildcards  |   Lambda Remediation      |   Detection + Fix       |
|                      |                           |                         |
+----------------------+---------------------------+-------------------------+
|                      |                           |                         |
|   2.1.1 S3 Encryption|   Lambda Remediation      |   Detection + Fix       |
|   2.1.2 S3 Versioning|   Lambda Remediation      |   Detection + Fix       |
|   2.1.5 S3 No Public |   Config Rule + Lambda    |   Detection + Fix       |
|                      |                           |                         |
+----------------------+---------------------------+-------------------------+
|                      |                           |                         |
|   3.1  CloudTrail On |   Config Rule + Module    |   Detection + Enforce   |
|   3.2  Log Validation|   CloudTrail Module       |   Enforce               |
|   3.3  S3 Not Public |   Foundation Module       |   Enforce               |
|   3.8  CMK Encryption|   Foundation Module       |   Enforce               |
|                      |                           |                         |
+----------------------+---------------------------+-------------------------+
|                      |                           |                         |
|   5.1  No 0.0.0.0/0  |   Lambda Remediation      |   Detection + Fix       |
|   5.2  No SSH Open   |   Lambda Remediation      |   Detection + Fix       |
|   5.3  No RDP Open   |   Lambda Remediation      |   Detection + Fix       |
|                      |                           |                         |
+----------------------+---------------------------+-------------------------+

Total Active Controls: ~30 (CIS Benchmark v1.4.0)
Config Rules Deployed: 8
Lambda Remediations:   3 (IAM, S3, Security Group)
```

---

*End of Architecture Diagrams*
