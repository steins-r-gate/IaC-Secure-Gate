# Phase 2: Automated Remediation - Plain English Plan & TODO

## What is Phase 2?

**In simple terms:** Phase 1 detects security problems. Phase 2 automatically FIXES them.

Right now, when someone creates a bad IAM policy or makes an S3 bucket public, Security Hub flags it as a finding. But nothing happens automatically - you'd have to manually go fix it.

Phase 2 changes that. When a security violation is detected, a Lambda function automatically runs and fixes the problem within seconds. Everything gets logged so you have a complete audit trail.

---

## The Big Picture

```
PHASE 1 (Done)                    PHASE 2 (Building)
--------------                    ------------------
Detect violations       --->      Automatically fix them
Log to Security Hub     --->      Route to Lambda via EventBridge
Generate findings       --->      Remediate + Log to DynamoDB
```

---

## What We're Building

### 1. Lambda Functions (The Fixers)
Three Python functions that automatically fix security issues:

| Lambda | What It Fixes |
|--------|---------------|
| **IAM Remediation** | Removes wildcard (*) permissions from IAM policies |
| **S3 Remediation** | Blocks public access, enables encryption |
| **Security Group Remediation** | Removes overly permissive rules (0.0.0.0/0) |

### 2. EventBridge Rules (The Router)
EventBridge watches Security Hub for new findings. When it sees a violation:
- IAM violation? → Send to IAM Lambda
- S3 violation? → Send to S3 Lambda
- Security Group violation? → Send to SG Lambda

### 3. DynamoDB Table (The Logger)
Every remediation action gets logged:
- What was fixed
- When it was fixed
- Did it succeed or fail
- Original configuration (for rollback if needed)

### 4. SNS Notifications (The Alerter)
Email notifications for:
- Every remediation that happens
- Failed remediations needing manual review
- Daily analytics summaries

### 5. Analytics Lambda (The Analyst)
Runs daily to analyze patterns:
- Which resources keep violating policies?
- Are we getting better or worse over time?
- What's our mean time to remediate?

---

## How It All Flows

```
1. Someone creates bad IAM policy
         ↓
2. Security Hub detects it (4 seconds)
         ↓
3. EventBridge sees the finding
         ↓
4. EventBridge triggers IAM Lambda
         ↓
5. Lambda removes the wildcard permission
         ↓
6. Lambda logs the fix to DynamoDB
         ↓
7. SNS sends you an email notification
         ↓
8. Total time: ~10 seconds from violation to fix
```

---

## Cost Impact

Phase 2 adds almost nothing to your monthly bill:

| Component | Monthly Cost |
|-----------|--------------|
| Lambda functions | €0.00 (free tier) |
| DynamoDB | €0.01 |
| EventBridge | €0.00 (free tier) |
| SNS emails | €0.00 (free tier) |
| CloudWatch Logs | €0.00 |
| **Phase 2 Total** | **~€0.01** |
| **Project Total** | **~€8.51** (still under €15 budget) |

---

## Success Criteria

When Phase 2 is complete, you should be able to:

1. Create a wildcard IAM policy → It gets automatically fixed in <10 seconds
2. Make an S3 bucket public → Public access gets blocked in <30 seconds
3. Create a permissive Security Group → Dangerous rules get removed in <15 seconds
4. Check DynamoDB → See complete history of all remediations
5. Check email → Get notifications for every fix

---

## What You Need Before Starting

- [x] Phase 1 fully operational (CloudTrail, Config, Security Hub working)
- [x] Terraform state recovered and synced
- [x] AWS credentials configured
- [ ] Python 3.12 available for Lambda development
- [ ] Your email ready for SNS subscriptions

---

# Phase 2 TODO List

## Week 1: Lambda Remediation Functions

### Day 1-2: IAM Remediation Lambda
- [ ] Create `terraform/modules/lambda-remediation/` directory
- [ ] Write `iam_remediation.py` Lambda function
  - [ ] Parse Security Hub finding from EventBridge
  - [ ] Get the offending IAM policy
  - [ ] Backup original policy to DynamoDB
  - [ ] Remove wildcard statements
  - [ ] Create new policy version
  - [ ] Log success/failure to DynamoDB
- [ ] Create `iam-remediation.tf` Terraform config
  - [ ] Lambda function resource
  - [ ] IAM execution role with least privilege
  - [ ] CloudWatch Log Group
  - [ ] Dead Letter Queue (SQS)
- [ ] Unit test with mock AWS calls

### Day 3-4: S3 Remediation Lambda
- [ ] Write `s3_remediation.py` Lambda function
  - [ ] Block all public access on bucket
  - [ ] Enable default encryption (SSE-S3)
  - [ ] Enable versioning
  - [ ] Log to DynamoDB
- [ ] Create `s3-remediation.tf` Terraform config
- [ ] Unit test with mock AWS calls

### Day 5-6: Security Group Remediation Lambda
- [ ] Write `sg_remediation.py` Lambda function
  - [ ] Find overly permissive ingress rules (0.0.0.0/0)
  - [ ] Remove dangerous rules (except 80/443 if tagged)
  - [ ] Tag resource as remediated
  - [ ] Log to DynamoDB
- [ ] Create `sg-remediation.tf` Terraform config
- [ ] Unit test with mock AWS calls

### Day 7: Deploy & Test Lambdas
- [ ] Create `modules/lambda-remediation/main.tf` (module entry point)
- [ ] Create `modules/lambda-remediation/variables.tf`
- [ ] Create `modules/lambda-remediation/outputs.tf`
- [ ] Add module to `environments/dev/main.tf`
- [ ] Run `terraform apply`
- [ ] Manually test each Lambda from AWS Console
- [ ] Verify CloudWatch Logs show execution

---

## Week 2: EventBridge & State Tracking

### Day 1-2: EventBridge Rules
- [ ] Create `terraform/modules/eventbridge-remediation/` directory
- [ ] Create `eventbridge-rules.tf`
  - [ ] Rule for IAM wildcard findings
  - [ ] Rule for S3 public bucket findings
  - [ ] Rule for Security Group findings
- [ ] Create `eventbridge-targets.tf`
  - [ ] Connect each rule to its Lambda
  - [ ] Configure input transformers (extract finding details)
  - [ ] Set retry policy (2 retries, exponential backoff)
- [ ] Deploy EventBridge module

### Day 3-4: DynamoDB State Tracking
- [ ] Create `terraform/modules/remediation-tracking/` directory
- [ ] Create `dynamodb.tf`
  - [ ] Table: `iac-secure-gate-remediation-history`
  - [ ] Partition key: violation_type
  - [ ] Sort key: timestamp
  - [ ] Enable DynamoDB Streams (for Phase 3)
  - [ ] Enable TTL (90 days)
  - [ ] Enable Point-in-Time Recovery
- [ ] Create `cloudwatch-logs.tf`
  - [ ] Log groups for each Lambda
  - [ ] 30-day retention
- [ ] Deploy tracking module

### Day 5-7: End-to-End Integration Testing
- [ ] Test Scenario 1: IAM Wildcard
  - [ ] Create test user with wildcard policy
  - [ ] Verify Security Hub finding (expect ~4 seconds)
  - [ ] Verify EventBridge triggers Lambda
  - [ ] Verify policy is remediated
  - [ ] Verify DynamoDB entry created
  - [ ] Measure total time (target: <10 seconds)
- [ ] Test Scenario 2: S3 Public Bucket
  - [ ] Create public S3 bucket
  - [ ] Verify detection and remediation
  - [ ] Verify public access blocked
  - [ ] Measure time (target: <30 seconds)
- [ ] Test Scenario 3: Security Group
  - [ ] Create SG with 0.0.0.0/0 on all ports
  - [ ] Verify remediation
  - [ ] Measure time (target: <15 seconds)
- [ ] Fix any integration issues

---

## Week 3: Analytics & Notifications

### Day 1-2: SNS Notification Topics
- [ ] Create `terraform/modules/self-improvement/` directory
- [ ] Create `sns-topics.tf`
  - [ ] Topic: `iac-sg-remediation-alerts` (immediate alerts)
  - [ ] Topic: `iac-sg-analytics-reports` (daily summaries)
  - [ ] Topic: `iac-sg-manual-review` (failed remediations)
- [ ] Subscribe your email to each topic
- [ ] Confirm email subscriptions

### Day 3-4: Update Lambdas to Send Notifications
- [ ] Add SNS publish to IAM Lambda (on success/failure)
- [ ] Add SNS publish to S3 Lambda
- [ ] Add SNS publish to SG Lambda
- [ ] Re-deploy Lambda module
- [ ] Test notifications are received

### Day 5-6: Analytics Lambda
- [ ] Write `analytics.py` Lambda function
  - [ ] Query DynamoDB for last 30 days
  - [ ] Calculate remediation success rate
  - [ ] Calculate mean time to remediate
  - [ ] Identify repeat offenders (same resource >3 violations)
  - [ ] Generate JSON report
  - [ ] Store report in S3
  - [ ] Send summary via SNS
- [ ] Create `analytics-lambda.tf`
- [ ] Create scheduled EventBridge rule (daily at 2 AM UTC)
- [ ] Deploy and test

### Day 7: Full System Test
- [ ] Run all 3 test scenarios again
- [ ] Verify full flow: detect → remediate → log → notify
- [ ] Verify analytics Lambda runs and generates report
- [ ] Check all email notifications received

---

## Week 4: Polish & Documentation

### Day 1-2: Testing & Validation
- [ ] Test rollback capability (can you restore original config?)
- [ ] Test failed remediation scenario (permission denied)
- [ ] Verify DLQ receives failed invocations
- [ ] Verify cost is still under budget
- [ ] Run Phase 1 tests to confirm no regression

### Day 3-4: Documentation
- [ ] Update main README with Phase 2 info
- [ ] Create architecture diagram for Phase 2
- [ ] Document each Lambda's purpose and logic
- [ ] Document DynamoDB schema
- [ ] Document EventBridge patterns
- [ ] Create troubleshooting guide

### Day 5-6: Demo Preparation
- [ ] Create demo script (60-second walkthrough)
- [ ] Prepare test violation resources
- [ ] Practice the demo flow
- [ ] Take screenshots for presentation
- [ ] Record demo video (optional)

### Day 7: Final Validation
- [ ] Final end-to-end test
- [ ] Git commit all changes
- [ ] Tag release: `git tag -a v2.0.0 -m "Phase 2: Automated Remediation"`
- [ ] Push to GitHub
- [ ] Update PROJECT-TIMELINE.md
- [ ] Celebrate Phase 2 completion!

---

## File Structure After Phase 2

```
iac-secure-gate/
├── terraform/
│   ├── modules/
│   │   ├── foundation/           # Phase 1 (existing)
│   │   ├── cloudtrail/           # Phase 1 (existing)
│   │   ├── config/               # Phase 1 (existing)
│   │   ├── access-analyzer/      # Phase 1 (existing)
│   │   ├── security-hub/         # Phase 1 (existing)
│   │   ├── lambda-remediation/   # Phase 2 NEW
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── iam-remediation.tf
│   │   │   ├── s3-remediation.tf
│   │   │   └── sg-remediation.tf
│   │   ├── eventbridge-remediation/  # Phase 2 NEW
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── rules.tf
│   │   ├── remediation-tracking/     # Phase 2 NEW
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── dynamodb.tf
│   │   └── self-improvement/         # Phase 2 NEW
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── sns-topics.tf
│   │       └── analytics-lambda.tf
│   └── environments/dev/
│       └── main.tf                   # Updated to include Phase 2 modules
├── lambda/
│   └── src/
│       ├── iam_remediation.py        # Phase 2 NEW
│       ├── s3_remediation.py         # Phase 2 NEW
│       ├── sg_remediation.py         # Phase 2 NEW
│       └── analytics.py              # Phase 2 NEW
└── docs/
    ├── PHASE1.md
    ├── PHASE2.md
    ├── PHASE2-TODO.md                # This file
    └── PHASE2-3.md
```

---

## Quick Reference: Key Commands

```bash
# Deploy Phase 2
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# Test Lambda manually
aws lambda invoke --function-name iac-sg-iam-remediation \
  --payload '{"findingId":"test","resourceArn":"arn:aws:iam::123456789:user/test"}' \
  output.json

# Check DynamoDB logs
aws dynamodb scan --table-name iac-secure-gate-remediation-history

# Check CloudWatch Logs
aws logs tail /aws/lambda/iac-sg-iam-remediation --follow

# Trigger analytics manually
aws lambda invoke --function-name iac-sg-analytics output.json
```

---

## Need Help?

If you get stuck:
1. Check CloudWatch Logs for Lambda errors
2. Check DLQ (SQS) for failed invocations
3. Verify IAM permissions on Lambda execution roles
4. Check EventBridge rule is enabled and pattern matches
5. Refer to PHASE2.md for detailed technical specifications

---

**Document Version:** 1.0
**Created:** February 1, 2026
**Status:** Ready to Start Implementation
