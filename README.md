# Intelligent IAM Misconfiguration Auditor & Remediation Pipeline with Secure IaC PR Gate

## Final Year Cloud Security Project - Implementation Guide

---

## **MERGED PROJECT CONCEPT & RATIONALE**

## Project Title

### Intelligent IAM Misconfiguration Auditor & Remediation Pipeline with Secure IaC PR Gate for AWS

## **Unified Problem Statement**

AWS IAM misconfigurations represent one of the most critical security vulnerabilities in cloud environments, with 82% of breaches involving human error in IAM settings (Verizon DBIR 2024). This project addresses this challenge through a **dual-layer defence-in-depth approach**:

1. **Shift-Left Prevention (IaC PR Gate)**: A GitHub Actions-based security gate that analyses Terraform code during pull requests, blocking IAM misconfigurations before they reach production using Checkov and OPA/Conftest policies.

2. **Runtime Detection & Remediation (AWS Native)**: An AWS-native pipeline using CloudTrail, Config, IAM Access Analyzer, and Security Hub to detect IAM misconfigurations in near real-time, with automated or semi-automated remediation via Lambda functions and SNS approval workflows.

The two components create a **closed-loop security system** where:

- The PR gate prevents known misconfigurations from being deployed
- The runtime detector catches drift, manual changes, and zero-day patterns
- Runtime findings feed back to strengthen PR gate policies
- Together, they reduce Mean Time to Detect (MTTD) from days to <5 minutes and Mean Time to Remediate (MTTR) to <3 minutes

## **In-Scope Features**

✅ **Core Deliverables:**

- AWS-native IAM misconfiguration detection (CloudTrail, Config, Access Analyzer)
- Security Hub as centralised findings aggregator
- EventBridge routing for sensitive IAM API calls
- Lambda-based remediation with SNS approval workflow
- GitHub Actions PR security gate (Checkov + OPA/Conftest)
- SARIF/JUnit artefact generation for security findings
- Grafana dashboard for security metrics (violations, MTTD/MTTR trends)
- Feedback loop: runtime findings → PR gate policy updates

## **Stretch Goals**

🎯 **If Time Permits:**

- Multi-account support via AWS Organizations
- JIRA ticket creation for complex remediations
- Prowler/Cloudsplaining integration for deeper analysis
- Custom OPA policies generated from runtime findings
- Security Hub Insights dashboard
- Terraform drift detection and reconciliation

## **Explicit Non-Goals**

❌ **Out of Scope:**

- Cost/FinOps analysis (no Infracost, no € metrics)
- Docker orchestration as primary requirement
- Multi-cloud support (AWS-only)
- Full SIEM integration
- Kubernetes/container security
- Network security configurations

---

## **HIGH-LEVEL ARCHITECTURE (SECURITY-ONLY)**

## **Architecture Overview**

```
┌─────────────────────────────────────────────────────────────────┐
│                     SHIFT-LEFT PREVENTION                       │
├─────────────────────────────────────────────────────────────────┤
│  Developer → GitHub PR → IaC Security Gate → Pass/Fail Decision │
│                    ↓                                            │
│         [Checkov + OPA/Conftest + Terraform Plan]               │
│                    ↓                                            │
│          Security Artefacts (SARIF/JUnit/JSON)                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓ (If Passed)
┌─────────────────────────────────────────────────────────────────┐
│                     RUNTIME DETECTION                           │
├─────────────────────────────────────────────────────────────────┤
│   AWS Environment → CloudTrail → EventBridge Rules              │
│          ↓                ↓                ↓                    │
│    Config Rules   IAM Access Analyzer   Direct Events           │
│          ↓                ↓                ↓                    │
│              Security Hub (Normalised Findings)                 │
│                           ↓                                     │
│                    EventBridge Router                           │
│                     ↓            ↓                              │
│            Auto-Remediate    SNS Approval                       │
│              (Lambda)         Workflow                          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                    FEEDBACK & METRICS                           │
├─────────────────────────────────────────────────────────────────┤
│   CloudWatch Logs → Metrics → Grafana Dashboard                 │
│   Security Hub Findings → OPA Policy Generator                  │
│   Runtime Patterns → PR Gate Rule Updates                       │
└─────────────────────────────────────────────────────────────────┘
```

## **Component Details**

### **1. IaC PR Gate (GitHub Actions)**

- **Trigger**: Pull request events on `main` branch
- **Tools**:
  - Checkov (750+ built-in security policies)
  - OPA/Conftest (custom IAM policies)
  - Terraform plan (no apply)
- **Blocking Criteria**: High/Critical findings
- **Outputs**: SARIF, JUnit, JSON artefacts

### **2. AWS Detection Pipeline**

- **CloudTrail**: Monitors IAM API calls (AttachUserPolicy, UpdateAssumeRolePolicy, etc.)
- **Config Rules**:
  - `iam-policy-no-statements-with-admin-access`
  - `iam-root-access-key-check`
  - `mfa-enabled-for-iam-console-access`
  - Custom rules for wildcards
- **IAM Access Analyzer**:
  - ACCOUNT analyzer for external access
  - Policy validation for syntax/semantics
- **Security Hub**: Central findings aggregation with severity normalisation

### **3. Remediation Engine**

- **EventBridge Rules**: Route findings by severity/type
- **Lambda Functions**:
  - `PolicyRemediator`: Remove wildcards, scope down permissions
  - `TrustPolicyRemediator`: Fix overly permissive trust relationships
  - `AccessKeyRotator`: Disable/rotate old keys
- **SNS Approval**: Human-in-the-loop for high-impact changes

### **4. Feedback Loop**

- Runtime findings generate suggested OPA policies
- Repeated violations trigger PR gate rule tightening
- Security Hub patterns inform Checkov custom rules

## **Sequence Diagram: End-to-End Flow**

```
Developer        GitHub         IaC Gate        AWS            Detection      Remediation
    │               │               │             │                │              │
    ├──PR with──────>               │             │                │              │
    │  IAM policy   │               │             │                │              │
    │               ├──Trigger────>│              │                │              │
    │               │               │             │                │              │
    │               │               ├─Checkov────>│                │              │
    │               │               ├─OPA────────>│                │              │
    │               │               ├─TF Plan────>│                │              │
    │               │               │             │                │              │
    │               │<──Results─────┤             │                │              │
    │               │  (Pass/Fail)  │             │                │              │
    │               │               │             │                │              │
    │               ├──Deploy──────────────────>  │                │              │
    │               │  (if passed)                │                │              │
    │               │                             ├──IAM Change───>│              │
    │               │                             │                │              │
    │               │                             │                ├─Analyze──────>
    │               │                             │                │  Finding     │
    │               │                             │                │              │
    │               │                             │                │<─────────────┤
    │               │                             │                │  Remediate   │
    │               │                             │<───────────────┤              │
    │               │                             │  Fixed Policy  │              │
    │               │                             │                │              │
    │               │<──Feedback───────────────── ┤                │              │
    │               │  (New OPA rule)             │                │              │
```

---

## **PROJECT OBJECTIVES & RESEARCH QUESTIONS**

## **Objectives**

1. **O1: Rapid Detection** - Achieve <5 minute MTTD for critical IAM misconfigurations using AWS-native services
2. **O2: Shift-Left Prevention** - Block 95%+ of known IAM misconfigurations at PR stage before deployment
3. **O3: Safe Automation** - Implement automated remediation for low-risk findings with <1% false positive rate
4. **O4: Policy Learning** - Create feedback mechanism where runtime findings strengthen PR gate policies
5. **O5: Compliance Tracking** - Maintain continuous CIS benchmark compliance score >90%
6. **O6: Developer Experience** - Provide actionable security feedback within PR comments in <30 seconds

## **Research/Engineering Questions**

1. **RQ1**: What is the optimal balance between PR-time blocking vs runtime remediation for different IAM misconfiguration types?
2. **RQ2**: How can we minimise false positives while maintaining high detection coverage across both static and dynamic analysis?
3. **RQ3**: Which IAM misconfigurations are safe for automated remediation vs requiring human approval?
4. **RQ4**: How effectively can runtime security findings be translated into preventive IaC policies?

---

# **PHASED IMPLEMENTATION PLAN**

## **Phase 1: AWS Detection Baseline (Weeks 1-4)**

**Goal**: Establish core detection capabilities

### **Phase 1 Deliverables**

- ✅ Enable CloudTrail with S3 logging
- ✅ Deploy 5 core Config Rules for IAM
- ✅ Set up IAM Access Analyzer (ACCOUNT type)
- ✅ Enable Security Hub with AWS Foundational Security Best Practices
- ✅ Create EventBridge rules for sensitive IAM events
- ✅ Deploy CloudWatch dashboard for metrics

### **MVP Demo**

Create overly permissive policy → Detection in <5 mins → Security Hub finding

### **Stretch**

- Add custom Config rules for company-specific policies
- Enable CIS AWS Foundations Benchmark

## **Phase 2: Basic Remediation (Weeks 5-8)**

**Goal**: Implement automated response for simple misconfigurations

### **Phase 2 Deliverables**

- ✅ Lambda function: `PolicyRemediator` (remove wildcards)
- ✅ Lambda function: `TrustPolicyRemediator` (scope trust relationships)
- ✅ EventBridge routing by severity
- ✅ CloudWatch Logs for remediation audit trail
- ✅ SNS topic for approval notifications
- ✅ DynamoDB table for remediation history

### **MVP Demo**

Attach AdministratorAccess → Auto-remediate to PowerUserAccess → Log action

### **Stretch**

- Step Functions for complex remediation workflows
- Slack/Teams integration for approvals

## **Phase 3: IaC Security Gate (Weeks 9-12)**

**Goal**: Prevent misconfigurations at source

### **Phase 3 Deliverables**

- ✅ GitHub Actions workflow for PR triggers
- ✅ Checkov integration with IAM-focused policies
- ✅ OPA/Conftest custom rules matching runtime checks
- ✅ SARIF output for GitHub Security tab
- ✅ PR comment with security summary
- ✅ Block merge on High/Critical findings

### **MVP Demo**

PR with `Resource: "*"` → Checkov flags → PR blocked → Fix → Pass → Merge

### **Stretch**

- Terraform plan cost estimation (security cost only)
- Generate OPA policies from Security Hub findings

## **Phase 4: Metrics & Feedback Loop (Weeks 13-16)**

**Goal**: Visualise security posture and close the loop

### **Phase 4 Deliverables**

- ✅ Prometheus/Pushgateway for metrics collection
- ✅ Grafana dashboard with 3 panels:
  - Security violations per PR
  - MTTD/MTTR trends
  - CIS compliance score
- ✅ Python script to generate OPA from runtime findings
- ✅ GitHub Action to update PR gate rules weekly
- ✅ Security Hub custom insights

### **MVP Demo**

Dashboard showing improvement from 10 violations/day → 1 violation/week

### **Stretch**

- ML-based anomaly detection for IAM usage
- Predictive risk scoring

## **Phase 5: Testing & Documentation (Weeks 17-20)**

**Goal**: Validate system and prepare for assessment

### **Phase 5 Deliverables**

- ✅ Attack simulation scripts (10 scenarios)
- ✅ Performance benchmarks (MTTD/MTTR measurements)
- ✅ False positive analysis report
- ✅ User documentation and runbooks
- ✅ Video demo (5 minutes)
- ✅ Final report (10,000 words)

### **MVP Demo**

Live attack simulation → Detection → Remediation → Metrics update

---

# **SUGGESTED EVALUATION METRICS (SECURITY-ONLY)**

## **Quantitative Metrics**

| Metric                            | Target                  | Measurement Method                                                 |
| --------------------------------- | ----------------------- | ------------------------------------------------------------------ |
| **Mean Time to Detect (MTTD)**    | <5 minutes              | CloudWatch timestamp difference: IAM change → Security Hub finding |
| **Mean Time to Remediate (MTTR)** | <3 minutes              | Security Hub: Finding created → Status RESOLVED                    |
| **PR Gate Block Rate**            | >95% for known patterns | (Blocked PRs / Total PRs with violations) × 100                    |
| **False Positive Rate**           | <1%                     | Manual review of 100 findings                                      |
| **Policy Coverage**               | >80% CIS controls       | Security Hub compliance score                                      |
| **Auto-Remediation Success**      | >99%                    | Lambda success rate in CloudWatch                                  |

## **Qualitative Assessment**

- **Developer Experience**: Survey on PR feedback clarity (1-5 scale)
- **Security Posture**: Before/after comparison of IAM complexity
- **Operational Impact**: Reduction in manual security reviews

---

# **RISKS, LIMITATIONS & FUTURE WORK**

## **Technical Risks & Mitigations**

| Risk                                     | Impact | Likelihood | Mitigation                                                        |
| ---------------------------------------- | ------ | ---------- | ----------------------------------------------------------------- |
| **Over-remediation breaking production** | High   | Medium     | Approval workflow, versioned policies, rollback capability        |
| **Alert fatigue from false positives**   | Medium | High       | Tuned thresholds, suppression rules, ML-based filtering [Stretch] |
| **Drift between IaC and reality**        | Medium | Medium     | Daily reconciliation job, PR generation for manual changes        |
| **Performance impact of Config Rules**   | Low    | Low        | Batch evaluations, sampling for non-critical resources            |

## **Limitations**

1. **AWS-Only**: No multi-cloud support (could extend to Azure/GCP)
2. **IAM Focus**: Doesn't cover S3, KMS, network security
3. **Static Policies**: OPA rules are predefined, not adaptive
4. **Single Account**: Multi-account requires Organizations setup

## **Future Work**

1. **Machine Learning**: Anomaly detection for unusual IAM patterns
2. **ChatOps Integration**: Remediate via Slack commands
3. **Policy as Code Library**: Share OPA policies across teams
4. **Cost Attribution**: Track security debt in monetary terms (security-only costs, not infrastructure costs)
5. **Compliance Reporting**: Automated evidence collection for audits

---

# **ACADEMIC ALIGNMENT NOTES**

## **Demonstrating Technical Depth**

This project showcases understanding across multiple domains:

- **Cloud Security**: IAM, least privilege, defence-in-depth
- **DevSecOps**: Shift-left, CI/CD integration, policy as code
- **Software Engineering**: Lambda functions, API integration, error handling
- **Data Visualisation**: Metrics collection, time-series analysis, dashboards
- **Automation**: Event-driven architecture, workflow orchestration

## **Research Contribution**

The feedback loop between runtime and build-time security is novel for a student project, demonstrating:

- Original thinking in connecting traditionally separate tools
- Practical application of academic security principles
- Measurable improvement in security posture

## **Assessment Evidence**

For the final submission, prepare:

1. **GitHub Repository**: All code, configs, documentation
2. **Video Demo** (5 mins): Show attack → detect → remediate → prevent cycle
3. **Technical Report** (10,000 words): Architecture, implementation, evaluation
4. **Presentation Slides**: 10 slides for viva defence
5. **Metrics Dashboard**: Live Grafana showing 4-week trend

---

## Summary

This comprehensive plan merges your two projects into a cohesive security-focused system that:

1. **Prevents** IAM misconfigurations at PR-time using IaC security gates
2. **Detects** runtime violations using AWS-native services
3. **Remediates** issues automatically or with approval
4. **Learns** from runtime to strengthen prevention

The project is academically rigorous, practically implementable, and industry-relevant while completely excluding cost/FinOps scope as requested. The phased approach ensures you can demonstrate a working MVP quickly while having clear stretch goals for additional marks.
