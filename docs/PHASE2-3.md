# Phase 2 → Phase 3 Integration Guide

## IaC-Secure-Gate Project
**Integration Overview: Automated Remediation to Real-Time Metrics & Dashboards**

---

## Table of Contents
1. [Integration Overview](#integration-overview)
2. [Data Flow Architecture](#data-flow-architecture)
3. [Phase 2 Outputs → Phase 3 Inputs](#phase-2-outputs--phase-3-inputs)
4. [Metrics Pipeline](#metrics-pipeline)
5. [Dashboard Data Sources](#dashboard-data-sources)
6. [Technical Integration Points](#technical-integration-points)
7. [Timeline & Handoff](#timeline--handoff)

---

## Integration Overview

### The Big Picture

Phase 2 builds the **data foundation** that Phase 3 will **visualize and analyze**. Think of it this way:

- **Phase 1:** Detects security violations (generates events)
- **Phase 2:** Remediates violations AND logs everything (generates metrics data)
- **Phase 3:** Visualizes the entire security pipeline in real-time (consumes metrics data)

### Why Phase 2 Must Come First

Phase 3 needs **data to display**. Without Phase 2's remediation tracking, you'd only have detection events from Phase 1. Phase 2 adds:
- Remediation success/failure rates
- Time-to-remediate metrics
- Violation patterns over time
- Self-improvement analytics
- Complete security lifecycle visibility

---

## Data Flow Architecture

### End-to-End Flow: Detection → Remediation → Visualization

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PHASE 1: DETECTION                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CloudTrail/Config/IAM Analyzer  →  Security Hub Findings               │
│                                                                          │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        PHASE 2: REMEDIATION                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Security Hub  →  EventBridge  →  Lambda Remediation                    │
│                                        ↓                                 │
│                                   DynamoDB Logging  ←─── (METRICS DATA)  │
│                                        ↓                                 │
│                                   CloudWatch Metrics                     │
│                                        ↓                                 │
│                                   S3 Analytics Reports                   │
│                                                                          │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    PHASE 3: METRICS & DASHBOARDS                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Data Sources:                        Visualization:                    │
│  • DynamoDB (real-time)       →      Grafana Dashboards                 │
│  • CloudWatch Metrics         →      Prometheus (optional)              │
│  • S3 Analytics               →      Custom queries                     │
│  • DynamoDB Streams           →      Real-time updates                  │
│                                                                          │
│  Displays:                                                               │
│  • Violation trends over time                                           │
│  • Remediation success rates                                            │
│  • Mean Time to Remediate (MTTR)                                        │
│  • Security posture score                                               │
│  • Top violation types                                                  │
│  • Repeat offender resources                                            │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 2 Outputs → Phase 3 Inputs

### Data Sources Phase 2 Creates for Phase 3

| Phase 2 Component | Data Generated | Phase 3 Usage |
|-------------------|----------------|---------------|
| **DynamoDB Table** | Remediation history with timestamps, status, resource details | Primary data source for historical trends, success rates, MTTR calculations |
| **DynamoDB Streams** | Real-time change events | Live dashboard updates as remediations happen |
| **CloudWatch Metrics** | Lambda execution metrics, error rates, duration | Performance monitoring, SLO tracking |
| **CloudWatch Logs** | Detailed remediation execution logs | Troubleshooting, detailed analysis, log analytics |
| **S3 Analytics Reports** | Daily/weekly aggregated analytics from self-improvement module | Executive reporting, trend analysis |
| **SNS Topics** | Notification history | Alert frequency analysis |

### Specific Metrics Phase 2 Generates

#### 1. **Remediation Performance Metrics**
```
From: DynamoDB + CloudWatch
Available to Phase 3:

- Total remediations (count by day/week/month)
- Success rate percentage
- Failure rate percentage
- Mean Time to Remediate (MTTR)
- Remediation duration by violation type
- Peak remediation times (when violations happen most)
```

#### 2. **Violation Pattern Metrics**
```
From: DynamoDB + Analytics Lambda
Available to Phase 3:

- Top 10 most common violations
- Violations by severity (CRITICAL, HIGH, MEDIUM, LOW)
- Violations by resource type (IAM, S3, SG)
- Repeat violations (same resource multiple times)
- Violation trends (increasing/decreasing over time)
```

#### 3. **Resource Health Metrics**
```
From: DynamoDB queries
Available to Phase 3:

- Resources with most violations
- Resources never violated (compliant resources)
- Time since last violation per resource
- Compliance score per resource type
```

#### 4. **Self-Improvement Metrics**
```
From: Analytics Lambda + S3 reports
Available to Phase 3:

- Violations prevented by proactive measures
- Repeat violation rate over time
- Policy adjustment effectiveness
- Alert response times
```

---

## Metrics Pipeline

### How Metrics Flow from Phase 2 to Phase 3

#### Real-Time Metrics Path

```
Remediation Event
      ↓
DynamoDB Write (Phase 2)
      ↓
DynamoDB Streams ← Enabled in Phase 2
      ↓
Lambda Stream Processor (Phase 3 NEW)
      ↓
Prometheus Time-Series DB (Phase 3 NEW)
      ↓
Grafana Dashboard (Phase 3 NEW)
      ↓
LIVE VISUALIZATION
```

**Key Integration Point:** DynamoDB Streams
- Phase 2 enables streams on the remediation table
- Phase 3 consumes stream events for real-time updates
- No polling needed = efficient and instant

#### Historical Metrics Path

```
DynamoDB Table (Phase 2)
      ↓
Scheduled Query Lambda (Phase 3 NEW)
  - Runs every 5 minutes
  - Aggregates last N records
  - Calculates running statistics
      ↓
CloudWatch Custom Metrics (Phase 3 NEW)
      ↓
Grafana Dashboard (Phase 3 NEW)
      ↓
HISTORICAL TRENDS
```

#### Analytics Reports Path

```
Analytics Lambda (Phase 2)
  - Runs daily at 2 AM
      ↓
S3 Analytics Bucket (Phase 2)
  - JSON reports with aggregated data
      ↓
S3 Event Notification (Phase 3 NEW)
      ↓
Lambda Report Processor (Phase 3 NEW)
  - Parses JSON
  - Extracts key metrics
      ↓
Grafana (Phase 3 NEW)
      ↓
EXECUTIVE DASHBOARDS
```

---

## Dashboard Data Sources

### Grafana Data Source Configuration (Phase 3)

#### Data Source 1: CloudWatch
```yaml
Name: AWS CloudWatch
Type: CloudWatch
Configuration:
  - Region: eu-west-1
  - Authentication: IAM Role
  
Metrics Available:
  - Lambda invocation counts
  - Lambda error rates
  - Lambda duration
  - Custom metrics from Phase 3 aggregation
```

#### Data Source 2: Prometheus (Optional, Cost-Effective)
```yaml
Name: Prometheus
Type: Prometheus
Configuration:
  - Scrape interval: 15s
  - Storage: Local (7-day retention)
  
Metrics Available:
  - Real-time remediation events (from DynamoDB Streams)
  - Aggregated violation counts
  - Success/failure rates
  - MTTR calculations
```

#### Data Source 3: DynamoDB Direct (via Lambda Proxy)
```yaml
Name: DynamoDB Proxy
Type: JSON API
Configuration:
  - API Gateway endpoint (Phase 3 NEW)
  - Lambda function queries DynamoDB
  - Returns formatted JSON for Grafana
  
Queries Available:
  - Last N remediations
  - Violations by type
  - Resource compliance status
  - Historical trends (custom time ranges)
```

#### Data Source 4: S3 Analytics Reports
```yaml
Name: S3 Analytics
Type: JSON API
Configuration:
  - Lambda reads latest S3 reports
  - Returns aggregated analytics
  
Queries Available:
  - Daily/weekly/monthly summaries
  - Repeat violation analysis
  - Top violating resources
  - Compliance trends
```

---

## Technical Integration Points

### 1. DynamoDB Stream Consumer (Phase 3)

**What Phase 2 Provides:**
```hcl
# In Phase 2: modules/remediation-tracking/dynamodb.tf

resource "aws_dynamodb_table" "remediation_history" {
  name           = "iac-sg-remediation-history"
  billing_mode   = "PAY_PER_REQUEST"
  
  stream_enabled   = true  # ← KEY: Enabled for Phase 3
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # ... rest of config
}
```

**What Phase 3 Adds:**
```hcl
# In Phase 3: modules/metrics-pipeline/stream-processor.tf

resource "aws_lambda_function" "stream_processor" {
  function_name = "iac-sg-stream-processor"
  runtime       = "python3.12"
  handler       = "stream_processor.lambda_handler"
  
  # Processes DynamoDB stream events in real-time
}

resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = var.dynamodb_stream_arn  # ← From Phase 2 output
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  
  batch_size = 10
}
```

**Data Flow:**
```
DynamoDB Write (remediation logged)
  ↓ (milliseconds)
DynamoDB Stream Event
  ↓
Lambda Stream Processor
  ↓
Prometheus Push
  ↓
Grafana sees update LIVE
```

---

### 2. CloudWatch Metrics Export (Phase 3)

**What Phase 2 Provides:**
```python
# In Phase 2: Lambda functions emit CloudWatch metrics

import boto3
cloudwatch = boto3.client('cloudwatch')

# After successful remediation
cloudwatch.put_metric_data(
    Namespace='IaC-Secure-Gate',
    MetricData=[
        {
            'MetricName': 'RemediationSuccess',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'ViolationType', 'Value': 'iam-wildcard-policy'}
            ]
        }
    ]
)
```

**What Phase 3 Does:**
```
Grafana connects to CloudWatch data source
  ↓
Queries custom metrics: IaC-Secure-Gate/*
  ↓
Displays in panels:
  - Success rate (RemediationSuccess / Total)
  - Violations by type (dimension filtering)
  - Time-series graphs
```

---

### 3. S3 Analytics Consumer (Phase 3)

**What Phase 2 Provides:**
```python
# In Phase 2: modules/self-improvement/lambda/analytics.py

# Daily analytics Lambda writes to S3
s3.put_object(
    Bucket='iac-sg-analytics-reports',
    Key=f'reports/{date}/daily-analytics.json',
    Body=json.dumps({
        'date': date,
        'total_violations': 45,
        'by_type': {
            'iam-wildcard-policy': 20,
            's3-public-bucket': 15,
            'sg-overly-permissive': 10
        },
        'repeat_offenders': [
            {'resource': 'arn:...', 'count': 5},
            # ...
        ],
        'mttr_average': 12.5,  # seconds
        'success_rate': 97.8   # percent
    })
)
```

**What Phase 3 Adds:**
```hcl
# S3 event notification triggers Lambda on new report
resource "aws_s3_bucket_notification" "analytics_reports" {
  bucket = var.analytics_bucket_id  # From Phase 2
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.report_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".json"
  }
}
```

**Report Processor Lambda:**
```python
# Phase 3: Reads S3 report and updates metrics

def lambda_handler(event, context):
    # Get S3 object
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    report = json.loads(s3.get_object(Bucket=bucket, Key=key)['Body'].read())
    
    # Push to Prometheus/CloudWatch
    push_metrics(report)
    
    # Now available in Grafana dashboards
```

---

### 4. API Gateway for Direct Queries (Phase 3)

**Purpose:** Allow Grafana to query DynamoDB directly for custom time ranges

**Phase 3 Architecture:**
```
Grafana Dashboard
    ↓ (HTTP GET request)
API Gateway: /api/metrics/{metric_type}?start={timestamp}&end={timestamp}
    ↓
Lambda: Query DynamoDB
    ↓
DynamoDB Table (from Phase 2)
    ↓
Return JSON response
    ↓
Grafana renders chart
```

**Example API Endpoint:**
```
GET /api/metrics/remediation-history?start=2025-01-01&end=2025-01-31

Response:
{
  "data": [
    {
      "timestamp": "2025-01-15T10:30:00Z",
      "violation_type": "iam-wildcard-policy",
      "count": 5,
      "success_rate": 100.0
    },
    // ... more data points
  ],
  "summary": {
    "total_violations": 150,
    "avg_mttr": 8.5,
    "success_rate": 98.2
  }
}
```

---

## Phase 3 Dashboard Examples

### Dashboard 1: Security Posture Overview

**Data Sources:**
- DynamoDB (via API Gateway)
- CloudWatch Metrics
- S3 Analytics Reports

**Panels:**

**Panel 1: Overall Security Score**
```
Metric: Percentage of time with zero active violations
Source: DynamoDB query (count violations with status=OPEN)
Visualization: Gauge (0-100%)

Query:
SELECT 
  (1 - COUNT(violations_open) / TOTAL_RESOURCES) * 100 
FROM dynamodb_proxy
WHERE timestamp > now() - 24h
```

**Panel 2: Violations Over Time**
```
Metric: Count of violations by type (time-series)
Source: DynamoDB stream → Prometheus
Visualization: Stacked area chart

Series:
- IAM violations (blue)
- S3 violations (green)
- SG violations (orange)
```

**Panel 3: Mean Time to Remediate (MTTR)**
```
Metric: Average time from detection to remediation
Source: DynamoDB calculation
Visualization: Line graph with target threshold

Calculation:
MTTR = AVG(remediation_timestamp - detection_timestamp)
Target: < 30 seconds
```

**Panel 4: Success Rate**
```
Metric: Remediation success percentage
Source: CloudWatch custom metric
Visualization: Percentage stat with sparkline

Formula:
Success Rate = (SUCCESS count / TOTAL attempts) * 100
```

---

### Dashboard 2: Remediation Performance

**Data Sources:**
- Lambda CloudWatch Logs (via Insights)
- DynamoDB historical data
- CloudWatch Metrics

**Panels:**

**Panel 1: Remediation Latency Heatmap**
```
Shows: When remediations happen and how long they take
X-axis: Time of day
Y-axis: Day of week
Color: Average remediation duration
```

**Panel 2: Top 10 Violating Resources**
```
Source: DynamoDB query
Shows: Resources with most violations (last 30 days)

Table columns:
- Resource ARN
- Violation count
- Last violation time
- Remediation success rate
```

**Panel 3: Lambda Performance**
```
Source: CloudWatch Lambda metrics
Shows:
- Invocation count
- Error rate
- Duration (p50, p95, p99)
- Throttles (if any)
```

---

### Dashboard 3: Executive Summary

**Data Sources:**
- S3 Daily Analytics Reports
- DynamoDB aggregations

**Panels:**

**Panel 1: Weekly Security Trend**
```
Shows: Are we getting more or less secure?
Metric: Violation count trend (7-day moving average)
Visualization: Area chart with trend line
```

**Panel 2: Compliance Score**
```
Calculation: 
  (Resources never violated / Total resources) * 100
Visualization: Big number with change indicator (↑↓)
```

**Panel 3: Top Violation Types (Pie Chart)**
```
Source: Last 30 days DynamoDB data
Shows distribution:
- IAM issues: 45%
- S3 issues: 35%
- SG issues: 20%
```

**Panel 4: Self-Improvement Impact**
```
Metric: Repeat violation rate over time
Shows: Is analytics reducing repeat issues?
Trend: Downward = good (learning from patterns)
```

---

## Timeline & Handoff

### Week 8: Phase 2 Completion Checklist

**Data Infrastructure Ready for Phase 3:**

✅ **DynamoDB Table:**
- [ ] Streams enabled with NEW_AND_OLD_IMAGES
- [ ] TTL configured (90 days)
- [ ] Sample data populated (at least 100 remediation records)
- [ ] GSI (Global Secondary Index) on resource_arn for queries

✅ **CloudWatch Integration:**
- [ ] Lambda functions emitting custom metrics
- [ ] Log groups created with proper retention
- [ ] Metric namespace: `IaC-Secure-Gate`

✅ **S3 Analytics:**
- [ ] Analytics Lambda running on schedule
- [ ] At least one report generated in S3
- [ ] Report format documented

✅ **Documentation:**
- [ ] DynamoDB schema documented
- [ ] Metric dimensions documented
- [ ] S3 report format documented
- [ ] API requirements for Phase 3 defined

---

### Week 9: Phase 3 Kickoff

**Phase 3 Setup Tasks (using Phase 2 data):**

**Day 1-2: Data Source Integration**
- Connect Grafana to CloudWatch
- Set up DynamoDB proxy API (Lambda + API Gateway)
- Configure S3 event notifications

**Day 3-4: Stream Processing**
- Deploy DynamoDB stream processor Lambda
- Set up Prometheus (optional, for real-time metrics)
- Test real-time data flow

**Day 5-7: Dashboard Development**
- Build Security Posture Overview dashboard
- Build Remediation Performance dashboard
- Build Executive Summary dashboard

---

### Phase 2 Output Variables for Phase 3

**Terraform Outputs Required:**
```hcl
# In Phase 2: modules/remediation-tracking/outputs.tf

output "dynamodb_table_name" {
  value = aws_dynamodb_table.remediation_history.name
}

output "dynamodb_stream_arn" {
  value = aws_dynamodb_table.remediation_history.stream_arn
}

output "cloudwatch_log_group_arns" {
  value = [
    aws_cloudwatch_log_group.iam_remediation.arn,
    aws_cloudwatch_log_group.s3_remediation.arn,
    aws_cloudwatch_log_group.sg_remediation.arn
  ]
}

output "analytics_s3_bucket" {
  value = aws_s3_bucket.analytics_reports.id
}

output "sns_topic_arns" {
  value = {
    remediation_alerts = aws_sns_topic.remediation_alerts.arn
    analytics_reports  = aws_sns_topic.analytics_reports.arn
  }
}
```

**Phase 3 Imports:**
```hcl
# In Phase 3: environments/dev/main.tf

module "metrics_pipeline" {
  source = "../../modules/metrics-pipeline"
  
  # Import Phase 2 outputs
  dynamodb_table_name   = data.terraform_remote_state.phase2.outputs.dynamodb_table_name
  dynamodb_stream_arn   = data.terraform_remote_state.phase2.outputs.dynamodb_stream_arn
  analytics_bucket_id   = data.terraform_remote_state.phase2.outputs.analytics_s3_bucket
  
  # Phase 3 specific configs
  grafana_instance_type = "t3.small"
  prometheus_retention  = "7d"
}
```

---

## Key Integration Principles

### 1. **Phase 2 is the Data Producer**
- Every remediation creates multiple data points
- Logging is comprehensive and structured
- Metrics are pushed to CloudWatch
- Analytics are pre-aggregated

### 2. **Phase 3 is the Data Consumer**
- Does NOT modify Phase 2 infrastructure
- Reads from Phase 2's data stores
- Adds visualization and analysis layers
- Optional: Adds alerting on metrics

### 3. **Separation of Concerns**
- Phase 2: Focuses on security automation
- Phase 3: Focuses on visibility and insights
- Each can be deployed/updated independently

### 4. **Data Flows One Direction**
```
Phase 1 → Phase 2 → Phase 3
(Detect)  (Remediate + Log)  (Visualize)

No circular dependencies
No backward data flow
Clean architectural boundaries
```

---

## Cost Impact of Integration

### Phase 3 Additional Costs

**Grafana (Self-Hosted on EC2):**
```
EC2 t3.small instance: ~€15/month
EBS volume (20 GB): ~€2/month
```

**DynamoDB Streams:**
```
Read Request Units for stream processing:
  - 100 violations/month × stream reads
  - Cost: ~€0.01/month (negligible)
```

**API Gateway (for DynamoDB proxy):**
```
REST API requests: 1 million free/month
Expected: ~1,000 requests/month (Grafana queries)
Cost: €0.00 (within free tier)
```

**Lambda Stream Processor:**
```
Invocations: 100/month (per remediation event)
Compute: Minimal (< 1 second execution)
Cost: €0.00 (within free tier)
```

**Prometheus (Optional):**
```
If self-hosted on same EC2 instance: €0.00 additional
Storage: ~500 MB for 7-day retention: €0.01/month
```

**Phase 3 Total Estimated Cost:** ~€17/month
**Project Total (All 3 Phases):** ~€25.51/month

**Budget Impact:** Still reasonable for university project, can optimize Grafana to t3.micro if needed (€7.50/month)

---

## Alternative: Budget-Conscious Phase 3

**If €25/month exceeds budget:**

### Option 1: CloudWatch Dashboards Only
```
Cost: €0.00 additional
Limitation: Less flexible than Grafana, AWS console only
Benefits: 
  - Native AWS integration
  - No infrastructure to manage
  - Perfect for demonstrating metrics exist
```

### Option 2: Grafana Cloud Free Tier
```
Cost: €0.00 (up to 10k series, 50GB logs, 14-day retention)
Benefits:
  - No EC2 costs
  - Managed service
  - Professional dashboards
Limitation: Free tier limits may be tight
```

### Option 3: Localhost Grafana (Demo Only)
```
Cost: €0.00
Process:
  - Run Grafana on your Windows laptop
  - Connect to AWS via credentials
  - Show dashboards during presentations
  - Destroy after demo
Benefits: Zero AWS costs, full Grafana features
Limitation: Only available when laptop running
```

---

## Summary: The Integration Story

**Phase 1:** "We detect security violations within minutes"
- CloudTrail logs events
- AWS Config evaluates compliance
- Security Hub aggregates findings

**Phase 2:** "We automatically fix those violations AND track everything"
- EventBridge routes findings to remediation
- Lambda functions fix the issues
- **DynamoDB logs every action with timestamps**
- **CloudWatch captures performance metrics**
- **Analytics Lambda identifies patterns**

**Phase 3:** "Here's our complete security posture at a glance"
- **Grafana reads all that logged data**
- **Real-time dashboards via DynamoDB Streams**
- **Historical trends from DynamoDB queries**
- **Executive summaries from S3 analytics**
- **SLO tracking from CloudWatch metrics**

**The Magic:** Phase 2 doesn't need to know Phase 3 exists. It just logs everything properly. Phase 3 taps into those logs and makes them beautiful and actionable.

---

## Next Steps

### Before Starting Phase 3 (Week 9)

1. **Verify Phase 2 Data Quality:**
   - Run a week of real remediations
   - Check DynamoDB has good sample data
   - Verify CloudWatch metrics are being emitted
   - Confirm analytics Lambda is generating reports

2. **Document Data Schemas:**
   - DynamoDB item structure
   - CloudWatch metric dimensions
   - S3 report JSON format

3. **Test Data Access:**
   - Query DynamoDB from AWS Console
   - View CloudWatch metrics manually
   - Download and inspect S3 analytics report

4. **Define Dashboard Requirements:**
   - What do you want to show your mentor?
   - What do you want to show the commission?
   - What metrics matter most for security posture?

### When Starting Phase 3 (Week 9)

1. **Start Small:** Build one simple dashboard first (Security Posture Overview)
2. **Test Data Flow:** Ensure Grafana can read Phase 2 data
3. **Iterate:** Add panels one at a time
4. **Optimize:** Tune queries for performance
5. **Polish:** Make dashboards visually impressive for presentations

---

**Document Version:** 1.0  
**Date:** January 31, 2025  
**Status:** Integration Planning Guide  

This document should be reviewed at Phase 2 completion (Week 8) to ensure all integration points are properly configured before beginning Phase 3 development.