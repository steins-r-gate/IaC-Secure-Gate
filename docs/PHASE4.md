# Phase 4 — Security Metrics Dashboard (Amazon Managed Grafana)

---

## Part 1: Education — What Is This and Why Does It Matter

### The Problem Phase 4 Solves

Phases 1–3 built a fully automated security system:
- **Phase 1/2:** Security Hub detects IAM/S3/SG violations → Lambda auto-remediates → DynamoDB logs every action
- **Phase 3:** Every PR runs Checkov + OPA/Conftest → gate blocks merges with violations

But right now, **all that data lives in silos** — DynamoDB records, CloudWatch logs, GitHub Actions job outputs — and you can only see it by querying each service individually. There is no single view that answers:

> "How healthy is my infrastructure right now? Is it getting better or worse? How fast am I fixing problems?"

A Grafana dashboard gives you that single pane of glass.

---

### What is Grafana?

Grafana is an **open-source data visualization platform**. It does not store data itself — instead it connects to existing data sources (CloudWatch, databases, S3, etc.) and lets you build dashboards with graphs, gauges, and tables.

**Amazon Managed Grafana (AMG)** is AWS's hosted version of Grafana. AWS runs the servers, handles updates, and manages backups — you just configure dashboards.

---

### What Are the Metrics You Want?

#### MTTD — Mean Time To Detect
**Definition:** How long (on average) between when a dangerous IAM policy is created and when Security Hub detects it.

**Formula:** `average(detection_timestamp - policy_creation_timestamp)`

**Where this data lives:** DynamoDB field `detection_time` (written by the E2E test suite per finding). The E2E suite already prints MTTD per test — this would show it historically over all real remediations.

**Why it matters:** A smaller MTTD means threats are caught faster. If MTTD is growing, your detection pipeline is slowing down.

---

#### MTTR — Mean Time To Remediate
**Definition:** How long (on average) between Security Hub detecting a violation and the Lambda completing remediation.

**Formula:** `average(remediation_time - detection_time)`

**Where this data lives:** DynamoDB fields `detection_time` and `remediation_time` (written by `iam_remediation.py`, `s3_remediation.py`, `sg_remediation.py`). The `analytics.py` Lambda already calculates this daily — Phase 4 makes it visible on a dashboard.

**Why it matters:** Core SLA metric for any security team. Industry benchmark is under 24 hours for critical findings.

---

#### MTTP — Mean Time To Protect (PR Gate)
**Definition:** How long (on average) between a PR being opened and the security gate completing its checks.

**Formula:** `average(all_checks_completed_timestamp - pr_opened_timestamp)`

**Where this data lives:** GitHub Actions run metadata (start/end times per workflow run). This has to be pushed into CloudWatch from the workflow.

**Why it matters:** Measures the friction your security gate adds to development. If MTTP climbs to 20 minutes, developers start resenting the gate.

---

#### False Positive Rate
**Definition:** What percentage of remediations were incorrectly flagged (i.e., the policy was actually fine)?

**Formula:** `(count of FALSE_POSITIVE records in DynamoDB) / (total records) × 100`

**Where this data lives:** DynamoDB records with `violation_type = FALSE_POSITIVE`.

**Why it matters:** A high false positive rate means your detection rules are too aggressive and are creating noise — wasting engineering time.

---

#### Security Health Score
**Definition:** A single composite number (0–100) that summarizes your overall security posture.

**Formula (proposed):**
```
health_score = (
  (successful_remediations / total_remediations × 40)   # 40% weight — are you fixing things?
  + (1 - false_positive_rate × 20)                       # 20% weight — is detection accurate?
  + (pr_gate_pass_rate × 30)                             # 30% weight — is code clean?
  + (1 - (MTTR / target_MTTR_hours) × 10)               # 10% weight — are you fast?
)
```

This is a custom metric you define — there is no standard industry formula.

---

#### Checkov & OPA/Conftest Results Over Time
**Definition:** Historical trend of how many IaC checks pass/fail per PR.

**Metrics:**
- `CheckovPassed` / `CheckovFailed` / `CheckovSkipped` — raw counts per scan
- `OPAViolations` / `OPAWarnings` — raw counts per scan
- `GateDecision` — 1 (pass) or 0 (fail) per PR

**Where this data lives:** Currently only inside GitHub Actions job outputs — they are NOT pushed to AWS at all. This is the main new pipeline to build.

---

### What Has To Be Built (Overview)

Three new components are needed:

**1. Metrics Publisher Lambda** (new)
A Lambda that runs on a schedule (every 5 minutes), reads DynamoDB, calculates MTTR/MTTD/false-positive-rate/health-score, and **writes the results to CloudWatch custom metrics**. CloudWatch becomes the single queryable metrics store.

**2. GitHub Actions → CloudWatch bridge** (workflow update)
Add steps to `security-scan.yml` that push Checkov counts, OPA counts, and gate decision to CloudWatch custom metrics after each PR scan. Uses the official `aws-actions/action-cloudwatch-metrics` action.

**3. AMG Workspace + Dashboard** (new Terraform module)
- Provision an AMG workspace via Terraform
- Connect CloudWatch as the data source
- Define dashboards as JSON (Grafana dashboard-as-code)

---

### How CloudWatch Fits In

CloudWatch is the **aggregation layer** that bridges everything:

```
DynamoDB records
      ↓ (Metrics Publisher Lambda, every 5 min)

GitHub Actions results
      ↓ (aws-actions/action-cloudwatch-metrics, per PR)

CloudWatch Custom Metrics
(Namespace: IaCSecureGate/SecurityMetrics)
      ↓
Amazon Managed Grafana
(CloudWatch datasource → dashboards)
```

This avoids the DynamoDB-in-Grafana problem entirely (no native plugin exists) — instead of trying to query DynamoDB from Grafana, a Lambda pre-computes everything and writes scalar metrics to CloudWatch, which Grafana queries natively.

---

### Why Not Query DynamoDB Directly From Grafana?

Grafana has no native DynamoDB plugin in the standard edition. The enterprise plugin ($45/user/month) exists but has documented bugs with nested data structures (the exact format this project uses — JSON strings, maps, arrays).

The Lambda → CloudWatch pattern is:
- Free (CloudWatch custom metrics: $0.30/metric/month)
- No data structure limitations
- Already natural for AWS-native projects
- Queryable from Grafana's built-in CloudWatch datasource

---

### Challenges and Limitations

| Challenge | Explanation | How We Handle It |
|-----------|-------------|-----------------|
| **IAM Identity Center required** | AMG cannot use regular IAM users. You need AWS IAM Identity Center (formerly AWS SSO) enabled. This requires enabling AWS Organizations (free). | Enable IAM Identity Center in the AWS console before Terraform apply. Takes 5 minutes. |
| **No DynamoDB native plugin** | Standard Grafana cannot query DynamoDB directly. | Metrics Publisher Lambda pre-computes and publishes to CloudWatch. |
| **GitHub Actions data not in AWS** | Checkov/OPA scan counts live only inside GitHub — not visible to CloudWatch. | Add CloudWatch metric publishing steps to the workflow. |
| **MTTD incomplete data** | `detection_time` field is only populated by the E2E test suite runs — not by real Security Hub findings yet (real findings don't record the exact creation timestamp of the violating resource). | MTTD panel shows E2E test data accurately. For real findings, MTTD is approximated as 0 (detection happens near-instantly on EventBridge delivery). |
| **CloudWatch Logs Insights 15-min timeout** | Long queries over large time ranges can timeout. | Use aggregated CloudWatch metrics (not raw logs) for dashboard panels to avoid this. |
| **AMG costs after trial** | After the 90-day free trial (5 users free), AMG charges $9/editor/month. | One editor user = $9/month. For an academic project, the trial covers the demo period entirely. |
| **Dashboard-as-code complexity** | Grafana dashboards exported as JSON are very verbose (~500-2000 lines per dashboard). | Use Terraform's `aws_grafana_workspace` + a pre-built JSON template — the JSON is committed to the repo as `grafana/dashboards/*.json`. |

---

### Cost (For This Project)

| Service | Cost | Notes |
|---------|------|-------|
| AMG workspace | **$0** during 90-day trial, then $9/month | 1 editor user |
| CloudWatch custom metrics | **~$6/month** | ~20 metrics × $0.30 |
| Metrics Publisher Lambda | **~$0** | <1M invocations/month free tier |
| EventBridge rule | **~$0** | First 14M events/month free |
| IAM Identity Center | **$0** | Free service |
| **Total** | **~$6/month** (trial) → **~$15/month** (after trial) | |

---

## Risks, Cost Spikes, and Hardening Decisions

### ⚠️ The One Real Cost Risk: CloudWatch Logs Insights in Grafana

**This is the only scenario that can produce a surprise bill in this architecture.**

CloudWatch has two completely different query modes:
- **CloudWatch Metrics** — pre-aggregated numbers stored as time series. Cost: $0.30/metric/month flat. Querying them is nearly free ($0.01 per 1,000 API calls).
- **CloudWatch Logs Insights** — SQL-like queries that scan raw log data. Cost: **$0.005 per MB scanned per query**.

If you accidentally build a Grafana panel that runs a Logs Insights query (even a simple one), and the dashboard auto-refreshes every 30 seconds, it will scan your logs continuously.

**Example of how it blows up:**
- 100 GB of Lambda/CloudTrail logs in your account
- 1 Logs Insights panel auto-refreshing every 30 seconds
- Dashboard open for 8 hours = 960 queries × 100 GB × $0.005/MB = **$491,520/month**

This is not hypothetical — this is a known billing incident type on AWS. Grafana makes it very easy to accidentally add a "Logs" query instead of a "Metrics" query.

**Mitigation built into the plan:**
- **All Grafana panels will use CloudWatch Metrics only** — pre-aggregated scalars written by the Metrics Publisher Lambda and GitHub Actions.
- No dashboard panel will run a CloudWatch Logs Insights query.
- The Metrics Publisher Lambda pre-computes everything (MTTR, counts, health score) and publishes numeric results to CloudWatch Metrics. Grafana only reads those numbers — it never touches log data.
- This is enforced by architecture: there is nothing to query in Logs Insights that isn't already available as a metric.

**Additional safeguard:** Set a CloudWatch billing alarm at $20/month. If anything goes wrong, you get an email before it becomes a real problem.

---

### Other Concerns Addressed

**Concern: Metric dimension cardinality explosion**
CloudWatch charges per unique metric (name + dimension combination). If you add a dimension like `ResourceARN` or `PRNumber`, every resource/PR creates a new billable metric. At $0.30 each, 1,000 unique resources = $300/month.

**Solution:** The plan limits dimensions to `Environment=dev` only. Per-resource and per-PR detail stays in DynamoDB; Grafana shows aggregate numbers.

---

**Concern: `aws-actions/action-cloudwatch-metrics` only natively publishes one metric**
The action's simple syntax handles one metric at a time. Publishing 3 Checkov metrics + 2 OPA metrics + 2 gate metrics in one step needs either 7 separate action steps or a direct `aws cloudwatch put-metric-data` CLI call.

**Solution:** Use `aws cloudwatch put-metric-data` CLI calls in the workflow directly (not the action). The AWS credentials are already present in the workflow for the Terraform plan step. Example:
```bash
aws cloudwatch put-metric-data \
  --namespace "IaCSecureGate/SecurityMetrics" \
  --metric-data \
    MetricName=CheckovPassed,Value=$PASSED,Unit=Count \
    MetricName=CheckovFailed,Value=$FAILED,Unit=Count \
    MetricName=CheckovSkipped,Value=$SKIPPED,Unit=Count \
  --dimensions Name=Environment,Value=dev \
  --region eu-west-1
```
One CLI call per job (3 total), not 7 separate action steps.

---

**Concern: AMG Terraform requires IAM Identity Center to be active before apply**
The `aws_grafana_workspace` Terraform resource will fail if IAM Identity Center has never been enabled in the account. Terraform cannot enable it — it's a one-time manual console action.

**Solution:** The manual pre-requisite step is kept as Step 1 and is clearly documented. A `terraform plan` check will verify the workspace can be created before `apply` is attempted.

---

**Concern: AMG workspace takes 3–5 minutes to become ready after Terraform creates it**
Immediately calling the Grafana API to import dashboards after `terraform apply` will fail because the workspace is still provisioning.

**Solution:** Dashboard import is a **manual one-time step** after the workspace is confirmed healthy, not a Terraform provisioner. The dashboard JSON is committed to the repo at `grafana/dashboards/security-overview.json` and imported via the Grafana UI (Settings → Dashboards → Import JSON). This is simpler and more reliable than a null_resource provisioner.

---

**Concern: MTTD data only available from E2E test runs**
Real Security Hub findings (triggered by actual IAM policy violations) don't record the exact creation timestamp of the violating resource — only the detection time. So MTTD for real-world events is always 0 (detection fires within seconds of the EventBridge rule triggering).

**Solution:** The MTTD panel shows **E2E test suite MTTD** — the `detection_time` written by `e2e-iam-suite.sh` per test run. This is the meaningful MTTD measurement for this project. The panel label will read "MTTD (E2E tests)" to be accurate.

---

**Concern: IAM policy for existing CI user needs `cloudwatch:PutMetricData`**
The `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in GitHub secrets currently grant permissions for Terraform plan + AWS describe calls. Writing to CloudWatch requires an additional permission.

**Solution:** Add `cloudwatch:PutMetricData` to the CI IAM policy in Terraform. This is a write permission limited to the custom namespace only (resource-level scoping: `arn:aws:cloudwatch:eu-west-1:ACCOUNT:*`).

---

**Cost summary (bulletproof estimate):**

| Item | Monthly Cost | Notes |
|------|-------------|-------|
| AMG workspace | $0 (trial 90d) → $9 | 1 editor |
| CloudWatch custom metrics storage | $6 | 20 metrics × $0.30 |
| CloudWatch GetMetricData (Grafana queries) | ~$0.50 | Estimated 50k queries/month |
| CloudWatch PutMetricData (Lambda + Actions) | ~$0.10 | ~10k calls/month |
| Metrics Publisher Lambda | $0 | Free tier (1M invocations) |
| EventBridge rule | $0 | Free tier |
| **Total** | **~$6.60/month** (trial) → **~$15.60/month** | Hard ceiling, no surprise scenarios |

There is **no variable cost component** in this design — CloudWatch Metrics pricing is flat per metric regardless of query frequency.

---

## Part 2: Architecture

### New Metric Namespace Layout

```
CloudWatch Namespace: IaCSecureGate/SecurityMetrics

Remediations (written by Metrics Publisher Lambda, every 5 min):
  - RemediationSuccessCount    (count over last 5 min)
  - RemediationFailureCount
  - FalsePositiveCount
  - MTTR_Seconds               (rolling 7-day average, in seconds)
  - SecurityHealthScore        (0-100 composite score)
  - ViolationsByType           (dimensions: ViolationType=IAM|S3|SG)

PR Gate (written by GitHub Actions, per PR):
  - CheckovPassed              (count per scan)
  - CheckovFailed
  - CheckovSkipped
  - OPAViolations
  - OPAWarnings
  - GateDecision               (1=pass, 0=fail)
  - MTTP_Seconds               (workflow duration)
```

---

### Planned Dashboard Panels

| Panel | Type | Data Source | Description |
|-------|------|-------------|-------------|
| Security Health Score | Gauge (0-100) | `SecurityHealthScore` metric | Overall posture at a glance |
| MTTR (7-day avg) | Stat + sparkline | `MTTR_Seconds` | How fast are we remediating? |
| MTTD (E2E avg) | Stat | Derived from DynamoDB via Lambda | How fast does detection fire? |
| MTTP (avg gate time) | Stat | `MTTP_Seconds` | How long does CI gate take? |
| Remediation trend | Time series | `Success/Failure counts` | Are violations increasing or decreasing? |
| Violations by type | Pie chart | `ViolationsByType` dim | IAM vs S3 vs SG breakdown |
| False positive rate | Gauge (%) | `FalsePositiveCount / total` | Detection accuracy |
| PR gate decisions | Bar chart | `GateDecision` | Pass/fail rate across PRs |
| Checkov over time | Time series | `CheckovPassed/Failed` | IaC hygiene trend |
| OPA violations | Time series | `OPAViolations/Warnings` | Custom policy violation trend |
| CIS alarm events | Table/heatmap | CloudWatch Alarms namespace | Which CIS controls are firing |
| Repeat offenders | Table | `RemediationSuccessCount` + resource dim | Resources remediated most often |

---

## Part 3: Implementation Plan

### New Files

| File | Purpose |
|------|---------|
| `terraform/modules/grafana/main.tf` | AMG workspace, IAM role, CloudWatch datasource config |
| `terraform/modules/grafana/variables.tf` | Input variables |
| `terraform/modules/grafana/outputs.tf` | Workspace URL output |
| `terraform/modules/metrics-publisher/main.tf` | Lambda + EventBridge rule + IAM role |
| `terraform/modules/metrics-publisher/variables.tf` | |
| `lambda/src/metrics_publisher.py` | Lambda code: reads DynamoDB → writes CloudWatch metrics |
| `grafana/dashboards/security-overview.json` | Dashboard definition (JSON) |

### Modified Files

| File | Change |
|------|--------|
| `terraform/environments/dev/main.tf` | Add `module "grafana"` and `module "metrics_publisher"` blocks |
| `.github/workflows/security-scan.yml` | Add CloudWatch metric publishing steps to checkov-scan, opa-conftest, and pr-comment jobs |

---

### Step 1 — Pre-requisite: Enable IAM Identity Center

**Manual step (AWS Console, done once before Terraform apply):**
1. Go to AWS Console → IAM Identity Center
2. Click "Enable" (automatically enables AWS Organizations if not already active)
3. Create one user: your email address
4. Note the Identity Store ID (used in Terraform)

This is free and takes under 5 minutes.

---

### Step 2 — Metrics Publisher Lambda (`lambda/src/metrics_publisher.py`)

**Logic:**
1. Query DynamoDB for records from the last 7 days across all violation types
2. Calculate:
   - `RemediationSuccessCount` = count of `remediation_status = SUCCESS` in last 5 min
   - `RemediationFailureCount` = count of `remediation_status = FAILED` in last 5 min
   - `FalsePositiveCount` = count of `violation_type = FALSE_POSITIVE` in last 5 min
   - `MTTR_Seconds` = average of `(remediation_time - detection_time)` over last 7 days (for records where both fields exist)
   - `SecurityHealthScore` = composite formula (described above)
   - Per violation type breakdowns using DynamoDB GSI `status-index`
3. Publish all metrics to CloudWatch namespace `IaCSecureGate/SecurityMetrics` using `put_metric_data()`

**Trigger:** EventBridge scheduled rule, every 5 minutes.

**IAM permissions needed:** `dynamodb:Query` + `dynamodb:Scan` on the remediation table, `cloudwatch:PutMetricData`.

---

### Step 3 — GitHub Actions Workflow Update

Add to `security-scan.yml` at the end of each relevant job (after the existing parse/analyze steps):

**In `checkov-scan` job (after "Parse Checkov results" step):**
```yaml
- name: Publish Checkov Metrics to CloudWatch
  uses: aws-actions/action-cloudwatch-metrics@v1
  with:
    namespace: IaCSecureGate/SecurityMetrics
    metrics: |
      [
        {"name": "CheckovPassed",  "value": "${{ steps.parse.outputs.passed }}",  "unit": "Count"},
        {"name": "CheckovFailed",  "value": "${{ steps.parse.outputs.failed }}",  "unit": "Count"},
        {"name": "CheckovSkipped", "value": "${{ steps.parse.outputs.skipped }}", "unit": "Count"}
      ]
```

**In `opa-conftest` job (after "Parse Conftest results" step):**
```yaml
- name: Publish OPA Metrics to CloudWatch
  uses: aws-actions/action-cloudwatch-metrics@v1
  with:
    namespace: IaCSecureGate/SecurityMetrics
    metrics: |
      [
        {"name": "OPAViolations", "value": "${{ steps.conftest.outputs.failures }}", "unit": "Count"},
        {"name": "OPAWarnings",   "value": "${{ steps.conftest.outputs.warnings }}", "unit": "Count"}
      ]
```

**In `pr-comment` job (at the end):**
```yaml
- name: Publish Gate Decision to CloudWatch
  uses: aws-actions/action-cloudwatch-metrics@v1
  with:
    namespace: IaCSecureGate/SecurityMetrics
    metrics: |
      [
        {"name": "GateDecision", "value": "${{ steps.gate.outputs.passed }}", "unit": "Count"},
        {"name": "MTTP_Seconds", "value": "${{ steps.gate.outputs.duration }}", "unit": "Seconds"}
      ]
```

Note: AWS credentials are already present in the workflow for the terraform plan step — the same `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets just need `cloudwatch:PutMetricData` added to the IAM policy.

---

### Step 4 — AMG Terraform Module

```hcl
# terraform/modules/grafana/main.tf (skeleton)

resource "aws_grafana_workspace" "main" {
  name                     = "${var.project_name}-${var.environment}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["CLOUDWATCH"]
  description              = "IaC Secure Gate security metrics dashboard"
}

resource "aws_iam_role" "grafana" {
  name = "${var.project_name}-${var.environment}-grafana"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonGrafanaCloudWatchAccess"
}

# Associate your IAM Identity Center user as Admin
resource "aws_grafana_role_association" "admin" {
  role         = "ADMIN"
  user_ids     = [var.grafana_admin_sso_user_id]
  workspace_id = aws_grafana_workspace.main.id
}
```

The workspace outputs a URL like `https://g-xxxxxxxxxx.grafana-workspace.eu-west-1.amazonaws.com`.

---

### Step 5 — Dashboard JSON

The dashboard JSON (`grafana/dashboards/security-overview.json`) is committed to the repo and provisioned via the Grafana HTTP API (called from a `null_resource` Terraform provisioner or a one-time bootstrap script after workspace creation).

Panels are defined in the JSON using CloudWatch metric queries, e.g.:
```json
{
  "type": "stat",
  "title": "MTTR (7-day avg)",
  "targets": [{
    "datasource": "CloudWatch",
    "namespace": "IaCSecureGate/SecurityMetrics",
    "metricName": "MTTR_Seconds",
    "statistics": ["Average"],
    "period": "604800"
  }]
}
```

---

## Verification

1. **Lambda publishes correctly:**
   - Run `aws cloudwatch list-metrics --namespace IaCSecureGate/SecurityMetrics`
   - All 8+ metrics should appear within 5 minutes of first Lambda invocation

2. **GitHub Actions publishes correctly:**
   - Open a new PR → wait for checkov-scan job to complete
   - Check CloudWatch console → `IaCSecureGate/SecurityMetrics` → `CheckovPassed`, `CheckovFailed` should have a data point

3. **AMG workspace accessible:**
   - Navigate to workspace URL
   - Log in via IAM Identity Center
   - CloudWatch datasource should show "Data source is working"

4. **Dashboard renders:**
   - All panels show data (no "No data" errors)
   - MTTR panel shows a value (will be 0 or N/A if no remediations in past 7 days — run e2e suite to generate data)
   - Health score gauge shows 0–100

5. **End-to-end demo sequence:**
   - Trigger `scripts/e2e-iam-suite.sh` → 10 remediations written to DynamoDB
   - Wait 5 minutes → Metrics Publisher Lambda fires
   - Observe MTTR, health score, violation counts update in Grafana
   - Open a PR with clean Terraform → gate passes → CheckovPassed goes up
   - Dashboard reflects full Phase 1→3 pipeline activity

---

## Key Files Reference

| File | Role |
|------|------|
| `lambda/src/metrics_publisher.py` | **New** — DynamoDB → CloudWatch metrics calculation |
| `terraform/modules/grafana/main.tf` | **New** — AMG workspace Terraform |
| `terraform/modules/metrics-publisher/main.tf` | **New** — Lambda + EventBridge Terraform |
| `grafana/dashboards/security-overview.json` | **New** — Dashboard definition |
| `.github/workflows/security-scan.yml` | **Modified** — Add CloudWatch publish steps |
| `terraform/environments/dev/main.tf` | **Modified** — Wire in new modules |
| `lambda/src/analytics.py` | **Existing** — Already calculates MTTR/success-rate (can reuse logic) |
| `terraform/modules/remediation-tracking/dynamodb.tf` | **Existing** — Source table schema reference |
