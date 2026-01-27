# IAM Secure Gate - 12-Week Project Timeline

**Project Duration:** 20 weeks total
**Time Remaining:** 12 weeks (January 27 - April 20, 2026)
**Student:** Roko Skugor | **Supervisor:** Dariusz Terefenko

---

## Overall Progress

```
████████████░░░░░░░░░░░░░░░░░░░░░░░░ 20% Complete (Phase 1 near completion)

Phase 1: ████████████████████ 95% (Week 4 - Wrapping up)
Phase 2: ░░░░░░░░░░░░░░░░░░░░  0% (Weeks 5-8)
Phase 3: ░░░░░░░░░░░░░░░░░░░░  0% (Weeks 9-12)
Phase 4: ░░░░░░░░░░░░░░░░░░░░  0% (Weeks 13-16)
Phase 5: ░░░░░░░░░░░░░░░░░░░░  0% (Weeks 17-20)
```

---

## Phase 1: AWS Detection Baseline (Weeks 1-4) - 95% COMPLETE

**Timeline:** December 2025 - January 2026
**Current Status:** ✅ Infrastructure deployed, ⏳ Final testing & documentation
**Completion Target:** January 28, 2026 (Tomorrow)

### What Was Done:

#### Infrastructure Deployed (✅ Complete):
- ✅ **Foundation Module**
  - KMS key with auto-rotation
  - CloudTrail S3 bucket (encrypted, versioned, lifecycle policies)
  - Config S3 bucket (encrypted, versioned, lifecycle policies)
  - Bucket policies for secure service access

- ✅ **CloudTrail Module**
  - Multi-region trail deployed
  - Log file validation enabled
  - Global service events enabled
  - Logging to encrypted S3 bucket

- ✅ **AWS Config Module**
  - Configuration recorder active (all resource types)
  - Delivery channel configured with KMS encryption
  - 8 CIS compliance rules deployed:
    - root-account-mfa-enabled (CIS 1.5)
    - iam-password-policy (CIS 1.8-1.11)
    - access-keys-rotated (CIS 1.14)
    - iam-user-mfa-enabled (CIS 1.10)
    - cloudtrail-enabled (CIS 3.1)
    - cloudtrail-log-file-validation-enabled (CIS 3.2)
    - s3-bucket-public-read-prohibited (CIS 2.3.1)
    - s3-bucket-public-write-prohibited (CIS 2.3.1)

- ✅ **IAM Access Analyzer Module**
  - Account analyzer deployed
  - Scanning for external access to resources
  - 90-day archive rule configured

- ✅ **Security Hub Module**
  - Security Hub enabled
  - CIS AWS Foundations Benchmark v1.4.0 (25 controls)
  - AWS Foundational Security Best Practices v1.0.0 (200+ controls)
  - Config integration enabled
  - Access Analyzer integration enabled
  - Total: 233 security controls active

#### Documentation Created (✅ Complete):
- ✅ Comprehensive architecture story (`docs/PHASE1-ARCHITECTURE-STORY.md`)
- ✅ Phase 1 completion status document (`PHASE1-COMPLETION-STATUS.md`)
- ✅ Project progress tracker (`PROJECT-PROGRESS-TRACKER.md`)
- ✅ Module READMEs (Foundation, CloudTrail, Config, Access Analyzer, Security Hub)
- ✅ Verification checklist for deployment

#### Cost Management (✅ Complete):
- ✅ Monthly cost: $7-9 (within budget)
- ✅ AWS credits ($180) confirmed to be used first
- ✅ S3 lifecycle policies implemented for cost optimization
- ✅ Free Tier services maximized

### What Needs to Be Done (Tomorrow - January 28):

#### Testing (2-3 hours):
- ⏳ Run 3 validation test scenarios:
  - Scenario 1: IAM user without MFA (Config detection)
  - Scenario 2: Wildcard IAM policy (Security Hub detection)
  - Scenario 3: External access detection (Access Analyzer)
- ⏳ Measure MTTD (Mean Time to Detect) for each scenario
- ⏳ Document test results with timestamps and screenshots

#### Security Fixes (1 hour):
- ⏳ Enable hardware MFA on root account (manual in AWS Console)
- ⏳ Restrict security group sg-0cff3d7b22eeb40cf SSH access (remove 0.0.0.0/0)
- ⏳ (Optional) Block SSM document public sharing

#### Documentation (1 hour):
- ⏳ Create `docs/PHASE1-TESTING-REPORT.md` with test results
- ⏳ Update main README with Phase 1 completion status
- ⏳ Create architecture diagram (optional, can defer to Phase 5)

#### Git & GitHub (30 minutes):
- ⏳ Stage all changes
- ⏳ Commit with comprehensive message
- ⏳ Push to GitHub
- ⏳ Create Pull Request: `phase-1` → `main`

**Phase 1 Milestone:** Detection baseline complete with validated <5min MTTD ✅

---

## Phase 2: Basic Remediation (Weeks 5-8) - 0% NOT STARTED

**Timeline:** February 3 - February 28, 2026 (4 weeks)
**Current Status:** ⏸️ Not started
**Complexity:** High (EventBridge + Lambda + SNS approval workflow)

### What Will Be Done:

#### Week 5 (Feb 3-9): Design & Setup
- 🔲 Design Lambda remediation architecture
- 🔲 Create DynamoDB state tracking table for remediation history
- 🔲 Design SNS approval workflow (human-in-the-loop for high-impact changes)
- 🔲 Document 3+ IAM misconfiguration types for remediation:
  - Wildcard IAM policies (`Action: "*"`)
  - Overly permissive roles (PowerUserAccess/AdministratorAccess)
  - Unrotated access keys (>90 days old)

#### Week 6 (Feb 10-16): Lambda Development
- 🔲 Develop Lambda function: Wildcard Policy Remediator
  - Detect policies with `"Action": "*"` or `"Resource": "*"`
  - Remove inline policies OR add deny statement
  - Log remediation action to DynamoDB
  - Send SNS notification
- 🔲 Develop Lambda function: Overly Permissive Role Handler
  - Detect roles with AdministratorAccess/PowerUserAccess
  - Downgrade permissions OR require approval
  - Track state in DynamoDB
- 🔲 Develop Lambda function: Unrotated Keys Detector
  - Identify access keys >90 days old
  - Disable keys OR send rotation reminder
  - Track in DynamoDB

#### Week 7 (Feb 17-23): EventBridge Integration
- 🔲 Configure EventBridge rules (3+ patterns):
  - Rule 1: IAM policy creation/update → Wildcard Policy Remediator
  - Rule 2: IAM role creation → Overly Permissive Role Handler
  - Rule 3: Scheduled (daily) → Unrotated Keys Detector
- 🔲 Implement event filtering (reduce noise, focus on critical events)
- 🔲 Connect EventBridge → Lambda → SNS approval workflow

#### Week 8 (Feb 24-28): Testing & Validation
- 🔲 Setup SNS approval workflow
  - SNS topic for remediation approvals
  - Email subscription for approval requests
  - Lambda function to process approval responses
- 🔲 Lambda unit & integration testing:
  - Test each Lambda function individually
  - Test EventBridge triggering
  - Test SNS approval flow (approve/reject)
- 🔲 Measure MTTR (Mean Time to Remediate):
  - Target: <5 minutes for automated remediation
  - Target: <1 hour for approval-based remediation
- 🔲 Document remediation logic and test results

**Phase 2 Milestone:** Automated remediation live for 3+ IAM misconfiguration types ✅

**Phase 2 Deliverables:**
- Lambda functions (3+) with error handling and logging
- EventBridge rules integrated with Lambda
- SNS approval workflow for high-impact changes
- DynamoDB state table for remediation tracking
- Test results showing <5min MTTR for automated remediation
- Documentation of remediation logic

---

## Phase 3: IaC Security Gate (Weeks 9-12) - 0% NOT STARTED

**Timeline:** March 2 - March 29, 2026 (4 weeks)
**Current Status:** ⏸️ Not started
**Complexity:** Medium-High (GitHub Actions + OPA/Rego learning curve)

### What Will Be Done:

#### Week 9 (Mar 2-8): Learning & Setup
- 🔲 **OPA/Rego Learning** (dedicated 8-10 hours):
  - Complete OPA documentation tutorials
  - Learn Rego policy language syntax
  - Study Terraform-specific OPA patterns
  - Practice writing 5+ simple policies
- 🔲 Setup GitHub repository structure for PR gate
- 🔲 Research Checkov integration with GitHub Actions

#### Week 10 (Mar 9-15): GitHub Actions Workflow
- 🔲 Create `.github/workflows/iac-security-gate.yml`
- 🔲 Configure Checkov in GitHub Actions:
  - Scan all Terraform files
  - 750+ built-in policies
  - SARIF output format for GitHub Security tab
- 🔲 Add Conftest/OPA to workflow:
  - Install Conftest
  - Configure OPA policy directory
  - Run OPA checks on Terraform plan JSON
- 🔲 Implement PR blocking logic:
  - Fail PR if CRITICAL findings detected
  - Warn on MEDIUM findings
  - Report all findings as PR comments

#### Week 11 (Mar 16-22): Custom OPA Policies
- 🔲 Write 5+ custom OPA policies for IAM security:
  - Policy 1: Block wildcard IAM actions (`"Action": "*"`)
  - Policy 2: Block wildcard resources (`"Resource": "*"`)
  - Policy 3: Require MFA for all IAM users
  - Policy 4: Enforce least-privilege IAM roles
  - Policy 5: Block public S3 buckets
- 🔲 Integrate custom policies with Conftest
- 🔲 Test policies against sample Terraform code

#### Week 12 (Mar 23-29): Testing & Integration
- 🔲 Test PR gate with intentional misconfigurations:
  - Create test PRs with CRITICAL findings (should block)
  - Create test PRs with MEDIUM findings (should warn)
  - Create test PRs with clean code (should pass)
- 🔲 Add SARIF artifact generation:
  - Upload scan results to GitHub Security tab
  - Enable code scanning alerts
- 🔲 (Stretch Goal) BridgeCrew API integration:
  - Connect Checkov to BridgeCrew Cloud (free tier)
  - Get severity scoring and remediation guidance
- 🔲 Measure PR gate performance:
  - Target: <5 minutes scan time
  - Target: >80% pre-deployment block rate

**Phase 3 Milestone:** PR gate successfully blocks critical IAM misconfigurations ✅

**Phase 3 Deliverables:**
- GitHub Actions workflow with Checkov/OPA integration
- 5+ custom OPA policies for IAM security
- PR blocking logic with automated comments
- SARIF artifacts for GitHub Security tab
- Example blocked/approved PRs with evidence
- Performance metrics (scan time, block rate)

---

## Phase 4: Metrics & Feedback Loop (Weeks 13-16) - 0% NOT STARTED

**Timeline:** March 30 - April 26, 2026 (4 weeks)
**Current Status:** ⏸️ Not started
**Complexity:** High (Grafana + automated policy generation)

### What Will Be Done:

#### Week 13 (Mar 30 - Apr 5): Grafana Setup
- 🔲 Deploy Grafana instance (EC2/Docker or Grafana Cloud free tier)
- 🔲 Configure CloudWatch data sources:
  - CloudTrail metrics
  - Config compliance metrics
  - Lambda execution metrics
  - Security Hub findings
- 🔲 Design dashboard layout:
  - Security violations over time
  - MTTD/MTTR trends
  - System health (Lambda errors, Config recorder status)
  - Cost tracking

#### Week 14 (Apr 6-12): Dashboard Development
- 🔲 Create **Compliance Violations Dashboard**:
  - Config rule compliance by severity
  - Top 5 violated rules
  - Compliance score over 30 days
- 🔲 Create **MTTD/MTTR Dashboard**:
  - Average detection time (target: <5min)
  - Average remediation time (target: <5min)
  - Trend graphs showing improvement
- 🔲 Create **System Health Dashboard**:
  - Lambda execution success rate
  - EventBridge rule invocations
  - Config recorder status
  - CloudTrail logging status
  - Monthly cost tracking

#### Week 15 (Apr 13-19): Feedback Loop - Part 1
- 🔲 Design feedback loop architecture:
  - Lambda function to analyze Security Hub/Config findings
  - Extract common misconfiguration patterns
  - Generate OPA policy templates
- 🔲 Develop Lambda: **Policy Generator**
  - Input: Security Hub finding JSON
  - Output: OPA Rego policy file
  - Store generated policies in S3
- 🔲 Create DynamoDB table for policy tracking:
  - Track generated policies
  - Track which findings triggered policy creation
  - Track policy effectiveness

#### Week 16 (Apr 20-26): Feedback Loop - Part 2
- 🔲 Implement automated OPA policy generation:
  - EventBridge rule: New Security Hub finding → Policy Generator Lambda
  - Generate 5+ OPA policies from runtime findings
  - Automatically commit policies to GitHub (PR workflow)
- 🔲 Test feedback loop end-to-end:
  - Deploy misconfiguration → Config/Security Hub detects
  - Lambda remediates → Policy Generator creates OPA policy
  - OPA policy blocks future deployments
- 🔲 Build **Feedback Loop Dashboard**:
  - Number of auto-generated policies
  - Policy generation triggers (findings)
  - Policy effectiveness (blocked PRs)

**Phase 4 Milestone:** Closed-loop system with Grafana dashboards and 5+ auto-generated OPA policies ✅

**Phase 4 Deliverables:**
- Grafana dashboards (Compliance, MTTD/MTTR, System Health, Feedback Loop)
- Lambda function for automated OPA policy generation
- 5+ auto-generated OPA policies from runtime findings
- DynamoDB table tracking policy generation
- 30-day trend data visualized
- Complete closed-loop documentation

---

## Phase 5: Testing & Documentation (Weeks 17-20) - 0% NOT STARTED

**Timeline:** April 27 - May 24, 2026 (4 weeks)
**Current Status:** ⏸️ Not started
**Complexity:** Medium (comprehensive testing + final report)

### What Will Be Done:

#### Week 17 (Apr 27 - May 3): Test Environment Preparation
- 🔲 Create isolated AWS test environment (separate account or region)
- 🔲 Deploy complete IAM Secure Gate system in test environment
- 🔲 Prepare 10 attack scenarios:
  1. Deploy wildcard IAM policy via Terraform → measure MTTD → validate auto-remediation
  2. Create overly permissive role → verify Config rule trigger → confirm Lambda remediation
  3. Simulate unrotated access keys → test compliance detection
  4. Disable MFA on IAM user → validate Security Hub alert
  5. Grant external account access → verify IAM Access Analyzer detection
  6. Create public S3 bucket → test Access Analyzer + Config detection
  7. Modify assume role trust policy (external account) → verify detection
  8. Add inline policy with wildcards → test Lambda remediation
  9. Disable CloudTrail logging → verify Config rule detection
  10. Break Security Hub integration → verify system health monitoring

#### Week 18 (May 4-10): Execute Attack Scenarios
- 🔲 Execute scenarios 1-3:
  - Measure MTTD (target: <5min)
  - Measure MTTR (target: <5min)
  - Document detection evidence (screenshots, logs)
- 🔲 Execute scenarios 4-6:
  - Test manual approval workflow (SNS)
  - Validate false positive rate (target: <5%)
  - Document remediation actions
- 🔲 Execute scenarios 7-10:
  - Test system resilience
  - Validate monitoring/alerting
  - Document edge cases and failures

#### Week 19 (May 11-17): Metrics Collection & Analysis
- 🔲 Collect and analyze metrics:
  - MTTD average across all scenarios (target: <5min)
  - MTTR average across all scenarios (target: <5min)
  - Detection coverage: 100% for critical misconfigurations
  - False positive rate (target: <5%)
  - Pre-deployment block rate (target: >80%)
  - System availability (target: >99%)
  - Monthly AWS cost (target: <€15)
- 🔲 Create metrics visualization:
  - Graphs showing MTTD/MTTR trends
  - Detection coverage by control type
  - Cost breakdown by service
- 🔲 **Performance Optimization Pass**:
  - Identify bottlenecks in detection/remediation
  - Optimize Lambda functions for faster execution
  - Tune EventBridge filtering to reduce noise
  - Refine Config rules to reduce false positives

#### Week 20 (May 18-24): Final Documentation & Presentation
- 🔲 Write comprehensive final report:
  - Executive summary
  - Project objectives and achievements
  - Architecture documentation with diagrams
  - Test results and metrics analysis
  - Lessons learned
  - Future enhancements and recommendations
  - Cost analysis
  - References
- 🔲 Create architecture diagrams:
  - Overall system architecture
  - Detection flow diagram
  - Remediation flow diagram
  - Feedback loop diagram
- 🔲 Prepare final presentation:
  - Live demo of system operation
  - Show detection of misconfiguration
  - Show automated remediation
  - Show PR gate blocking deployment
  - Show Grafana dashboards
  - Show feedback loop generating OPA policy
- 🔲 Code cleanup and final commit:
  - Remove test resources
  - Clean up commented code
  - Ensure all documentation is current
  - Final commit and tag: `v1.0.0-release`

**Phase 5 Milestone:** All test scenarios pass success criteria, final report complete ✅

**Phase 5 Deliverables:**
- Final project report (comprehensive documentation)
- Architecture diagrams (system, detection, remediation, feedback)
- Test results with validated metrics (MTTD, MTTR, coverage, etc.)
- Lessons learned document
- Final presentation slides
- Complete system demo video (optional)
- Tagged release: `v1.0.0-release`

---

## Success Criteria Summary

| Metric Category | Metric | Target | Current Status |
|----------------|--------|--------|----------------|
| **Detection** | MTTD (Mean Time to Detect) | <5 minutes | ⏳ To be measured |
| **Remediation** | MTTR (Mean Time to Remediate) | <5 minutes | ⏳ To be measured |
| **Accuracy** | False Positive Rate | <5% | ⏳ To be measured |
| **Coverage** | Detection Coverage (Critical) | 100% | ✅ 233 controls active |
| **Prevention** | Pre-deployment Block Rate | >80% | ⏳ Phase 3 |
| **Performance** | IaC Scan Time (GitHub Actions) | <5 minutes | ⏳ Phase 3 |
| **Operational** | System Availability | >99% | ✅ Currently 100% |
| **Cost** | Monthly AWS Infrastructure Cost | <€15 | ✅ $7-9/month |
| **Feedback Loop** | Auto-Generated OPA Policies | >5 policies | ⏳ Phase 4 |

---

## Risk Management

### Active Risks:

| Risk | Severity | Mitigation Strategy | Deadline |
|------|----------|---------------------|----------|
| **Time Constraint** | 🔴 HIGH | Only 12 weeks remaining (vs 20 planned). Focus on MVP for each phase. Descope Phase 4/5 if needed. | Ongoing |
| **OPA/Rego Learning Curve** | 🟡 MEDIUM | Dedicate Week 9 entirely to learning. Use Checkov-only as fallback if OPA too complex. | Week 9 |
| **AWS Cost Overrun** | 🟡 MEDIUM | Billing alerts at €5/€10/€14. Monitor Grafana (EC2) costs in Phase 4. Use Grafana Cloud free tier if needed. | Ongoing |
| **Lambda Complexity (Phase 2)** | 🟡 MEDIUM | Start simple (1 Lambda first), iterate. Use boto3 documentation extensively. Request supervisor help if blocked. | Week 6-7 |
| **Feedback Loop Automation (Phase 4)** | 🟡 MEDIUM | This is the most complex component. Allow 2-week buffer. Consider manual policy generation as fallback. | Week 15-16 |

### Contingency Plans:

- **If behind schedule:** Descope Phase 4 feedback loop to manual policy generation (supervisor approval), defer to future work
- **If AWS costs exceed budget:** Reduce log retention to 7 days, use LocalStack for testing, request university AWS credits
- **If OPA too complex:** Use Checkov-only for Phase 3 MVP, defer custom OPA policies to "stretch goal"

---

## Weekly Check-In Questions for Supervisor

1. **Week 5:** Lambda architecture review - is remediation approach sound?
2. **Week 8:** Review Lambda code quality and error handling
3. **Week 9:** OPA learning progress check - need additional resources?
4. **Week 12:** PR gate demo - is blocking logic appropriate?
5. **Week 14:** Grafana dashboards review - are metrics meaningful?
6. **Week 16:** Feedback loop architecture review - is policy generation approach valid?
7. **Week 19:** Test results review - do metrics meet success criteria?
8. **Week 20:** Final report review before submission

---

## Phase 1 Final Tasks (Tomorrow - January 28)

### Morning (2-3 hours):
1. ✅ Run 3 test scenarios and measure MTTD
2. ✅ Create `docs/PHASE1-TESTING-REPORT.md`
3. ✅ Fix critical security findings (root MFA, security group)

### Afternoon (1-2 hours):
4. ✅ Push all changes to GitHub
5. ✅ Create PR: `phase-1` → `main`
6. ✅ Mark Phase 1 complete in tracker
7. ✅ Begin Phase 2 planning (review Lambda requirements)

---

## Notes

- **Buffer Time:** Built-in 2-week buffer by having 20-week plan in 12 weeks = need to be efficient
- **Stretch Goals:** BridgeCrew API (Phase 3), ML-based false positive reduction (Phase 4), architecture diagrams (Phase 5)
- **Documentation Philosophy:** Document as you go, not at the end (saves time in Phase 5)
- **Testing Philosophy:** Test early and often, don't wait until Phase 5

---

**Last Updated:** January 27, 2026
**Next Milestone:** Phase 1 Complete (January 28, 2026)
**Current Focus:** Final Phase 1 testing and documentation
