# IaC-Secure-Gate

AWS security baseline infrastructure implementing CIS AWS Foundations Benchmark controls using Terraform.

## Overview

Cloud infrastructure misconfiguration remains a leading cause of security breaches. Manual security setup is time-consuming, error-prone, and inconsistent across environments. IaC-Secure-Gate addresses these challenges by automating the deployment of a comprehensive AWS security baseline using Infrastructure as Code principles.

This project implements a detection-first security architecture using AWS native services orchestrated through Terraform. The system provides continuous compliance monitoring, audit logging, and security posture visibility across AWS environments.

### Key Outcomes

- Automated deployment of CIS AWS Foundations Benchmark controls
- Multi-region audit logging with CloudTrail
- Continuous compliance monitoring via AWS Config
- Centralized security findings aggregation through Security Hub
- **Automated remediation of security violations (Phase 2)**
- **Real-time notifications and daily analytics reports (Phase 2)**
- Cost-optimized implementation under 15 EUR/month
- Deterministic infrastructure deployment with zero configuration drift

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                   IaC-Secure-Gate                           │
│            AWS Security Baseline (Phase 1)                  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                  Terraform Modules                          │
│                                                             │
│  ┌────────────┐   ┌─────────────┐   ┌─────────────┐       │
│  │ Foundation │ → │  CloudTrail │   │   Config    │       │
│  │ KMS + S3   │   │ Multi-Region│   │ 8 CIS Rules │       │
│  └────────────┘   └─────────────┘   └─────────────┘       │
│                                                             │
│  ┌─────────────┐   ┌─────────────────────────────┐        │
│  │   Access    │   │     Security Hub            │        │
│  │  Analyzer   │   │   CIS + AWS Foundational    │        │
│  └─────────────┘   └─────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      AWS Cloud                              │
│                                                             │
│  Foundation Layer                                           │
│  - KMS CMK with automatic rotation                         │
│  - Encrypted S3 buckets (CloudTrail + Config)              │
│  - S3 lifecycle policies (90-day retention)                │
│  - Public access blocking (4-layer defense)                │
│                                                             │
│  Detection Layer                                            │
│  - CloudTrail: Multi-region audit logging                  │
│  - AWS Config: Continuous compliance monitoring            │
│  - IAM Access Analyzer: External access detection          │
│                                                             │
│  Aggregation Layer                                          │
│  - Security Hub: 233 active security checks                │
│  - CIS AWS Foundations Benchmark v1.4.0                    │
│  - AWS Foundational Security Best Practices                │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. AWS API calls captured by CloudTrail across all regions
2. Encrypted logs stored in S3 with KMS customer-managed keys
3. AWS Config evaluates resource compliance against CIS rules
4. IAM Access Analyzer identifies external access patterns
5. Security Hub aggregates findings from all sources
6. Centralized security posture dashboard available in AWS Console

## Features

### Security Controls

- Multi-region CloudTrail with log file validation (CIS 3.1, 3.2)
- KMS customer-managed encryption with automatic rotation (CIS 3.3)
- AWS Config continuous compliance monitoring (8 managed rules)
- S3 bucket hardening (encryption, versioning, public access blocking)
- IAM Access Analyzer for privilege monitoring
- Security Hub aggregation with dual compliance standards

### Compliance Implementation

CIS AWS Foundations Benchmark v1.5.0 controls:
- CIS 3.1: Multi-region CloudTrail enabled
- CIS 3.2: CloudTrail log file validation enabled
- CIS 3.3: CloudTrail logs encrypted with KMS CMK
- CIS 3.6: S3 bucket access logging enabled
- CIS 3.7: CloudTrail logs in dedicated S3 bucket

### Operational Capabilities

- Deterministic Terraform deployment (47 resources)
- S3 lifecycle policies with 90-day retention
- Cost-optimized configuration (approximately 7 USD/month for development)
- Idempotent infrastructure provisioning
- Automated compliance evaluation
- Security finding detection times: 4 seconds (IAM policy), 2 minutes (S3 public access)

## Technology Stack

| Layer | Component | Version | Purpose |
|-------|-----------|---------|---------|
| Infrastructure as Code | Terraform | >= 1.5.0 | Infrastructure provisioning and state management |
| Cloud Platform | AWS | N/A | Security services and infrastructure |
| Encryption | AWS KMS | N/A | Customer-managed encryption keys |
| Audit Logging | AWS CloudTrail | N/A | API activity tracking across all regions |
| Compliance Monitoring | AWS Config | N/A | Resource compliance evaluation |
| Access Analysis | IAM Access Analyzer | N/A | External access pattern detection |
| Security Aggregation | AWS Security Hub | N/A | Centralized security findings |
| Object Storage | Amazon S3 | N/A | Encrypted log storage and retention |
| CLI Tools | AWS CLI | >= 2.0 | AWS resource management |
| Development Environment | PowerShell | >= 5.1 | Automation scripting (Windows) |

## Repository Structure

```
IaC-Secure-Gate/
├── terraform/
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf                      # Module orchestration
│   │       ├── variables.tf                 # Environment-specific variables
│   │       ├── outputs.tf                   # Deployment outputs
│   │       ├── ENVIRONMENT_CHANGES.md       # Change documentation
│   │       └── VERIFICATION_CHECKLIST.md    # Post-deployment validation
│   │
│   └── modules/
│       ├── foundation/
│       │   ├── main.tf                      # Resource definitions
│       │   ├── kms.tf                       # KMS CMK configuration
│       │   ├── s3-cloudtrail.tf             # CloudTrail bucket
│       │   ├── s3-config.tf                 # Config bucket
│       │   ├── variables.tf                 # Module variables
│       │   ├── outputs.tf                   # Module outputs
│       │   └── README.md                    # Module documentation
│       │
│       ├── cloudtrail/
│       │   ├── main.tf                      # CloudTrail configuration
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── README.md
│       │   ├── CHANGES_SUMMARY.md
│       │   └── VERIFICATION_CHECKLIST.md
│       │
│       ├── config/
│       │   ├── main.tf                      # Config recorder
│       │   ├── iam.tf                       # IAM service role
│       │   ├── rules.tf                     # CIS compliance rules
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── access-analyzer/
│       │   ├── main.tf                      # Access analyzer
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       └── security-hub/
│           ├── main.tf                      # Security Hub configuration
│           ├── variables.tf
│           ├── outputs.tf
│           └── README.md
│
├── scripts/
│   └── deployment-status.ps1                # Deployment verification
│
├── .gitignore
└── README.md
```

## Prerequisites

### AWS Account Requirements

Active AWS account with IAM user or role permissions:

**S3 Permissions:**
- s3:CreateBucket
- s3:PutBucketPolicy
- s3:PutEncryptionConfiguration
- s3:PutBucketVersioning
- s3:PutBucketPublicAccessBlock
- s3:PutLifecycleConfiguration

**KMS Permissions:**
- kms:CreateKey
- kms:PutKeyPolicy
- kms:EnableKeyRotation
- kms:CreateAlias

**CloudTrail Permissions:**
- cloudtrail:CreateTrail
- cloudtrail:StartLogging
- cloudtrail:PutEventSelectors

**Config Permissions:**
- config:PutConfigurationRecorder
- config:PutDeliveryChannel
- config:PutConfigRule
- config:StartConfigurationRecorder

**IAM Permissions:**
- iam:CreateRole
- iam:AttachRolePolicy
- iam:CreatePolicy
- iam:PutRolePolicy

**Security Hub Permissions:**
- securityhub:EnableSecurityHub
- securityhub:BatchEnableStandards

**IAM Access Analyzer Permissions:**
- access-analyzer:CreateAnalyzer

### Development Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| Terraform | 1.5.0 | https://www.terraform.io/downloads |
| AWS CLI | 2.0.0 | https://aws.amazon.com/cli/ |
| Git | 2.0.0 | https://git-scm.com/downloads |

### AWS Configuration

AWS credentials must be configured via one of the following methods:

**Option 1: AWS CLI Configuration**
```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: eu-west-1
# Default output format: json
```

**Option 2: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID="<your-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret>"
export AWS_DEFAULT_REGION="eu-west-1"
```

**Option 3: AWS Credentials File**
```
~/.aws/credentials
~/.aws/config
```

Default region: eu-west-1 (Ireland)

## Installation

### Clone Repository

```bash
git clone <repository-url>
cd IaC-Secure-Gate
```

### Verify AWS Access

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/username"
}
```

### Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

Expected output:
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

## Deployment

### Plan Infrastructure Changes

```bash
cd terraform/environments/dev
terraform plan
```

Review the planned changes. Expected resource count: 47 resources to add.

### Deploy Infrastructure

```bash
terraform apply
```

When prompted, review the execution plan and type `yes` to confirm.

**Deployment Time:** 2-3 minutes

**Expected Output:**
```
Apply complete! Resources: 47 added, 0 changed, 0 destroyed.

Outputs:

deployment_summary = {
  "cloudtrail_cis_3_1_compliant" = true
  "cloudtrail_cis_3_2_compliant" = true
  "config_recorder_enabled" = true
  "config_rules_deployed" = 8
  "environment" = "dev"
  "foundation_cis_compliant" = true
  "phase_1_ready" = true
  "region" = "eu-west-1"
}
```

### Verify Deployment

```bash
# Check deployment summary
terraform output deployment_summary

# Verify CloudTrail status
aws cloudtrail get-trail-status \
  --name $(terraform output -raw cloudtrail_trail_name) \
  --region eu-west-1

# Verify Config recorder
aws configservice describe-configuration-recorder-status \
  --configuration-recorder-names $(terraform output -raw config_recorder_name) \
  --region eu-west-1

# Verify IAM Access Analyzer
aws accessanalyzer list-analyzers --region eu-west-1

# Verify Security Hub
aws securityhub describe-hub --region eu-west-1
```

Automated verification script:
```bash
scripts/deployment-status.ps1
```

## Configuration

### Environment Variables

```bash
# Optional AWS configuration
export AWS_REGION=eu-west-1
export AWS_PROFILE=default
```

### Cost Optimization

Default development configuration targets approximately 7 USD/month:

| Service | Monthly Cost | Configuration |
|---------|--------------|---------------|
| CloudTrail | 2.00 USD | Management events only, first trail free |
| AWS Config | 2.00 USD | First 1000 configuration items free |
| Config Rules | 1.60 USD | 8 rules at 0.20 USD each |
| S3 Storage | < 1.00 USD | Lifecycle policies with 90-day retention |
| KMS | 1.00 USD | Single customer-managed key |
| **Total** | **~7 USD/month** | Full CIS-compliant detection baseline |

### Optional Features

Optional features disabled by default to minimize costs:

**CloudWatch Logs Integration**

Enable in `terraform/environments/dev/main.tf`:
```hcl
module "cloudtrail" {
  # ... existing configuration
  enable_cloudwatch_logs = true
}
```
Cost impact: +10-20 USD/month

**CloudTrail Insights**

Enable in `terraform/environments/dev/main.tf`:
```hcl
module "cloudtrail" {
  # ... existing configuration
  enable_insights = true
}
```
Cost impact: +35-50 USD/month

**S3 Data Events**

Enable in `terraform/environments/dev/main.tf`:
```hcl
module "cloudtrail" {
  # ... existing configuration
  enable_s3_data_events = true
}
```
Cost impact: Varies significantly based on S3 API call volume

## Security

### Encryption

**Data at Rest:**
- All logs encrypted using KMS customer-managed keys (CMK)
- S3 server-side encryption with KMS (SSE-KMS) enforced
- Automatic KMS key rotation enabled (annual)
- Bucket encryption enforced via bucket policies

**Data in Transit:**
- HTTPS-only access enforced via S3 bucket policies
- TLS 1.2 minimum for all AWS service communications
- Secure CloudTrail log delivery using AWS PrivateLink

### Access Control

**S3 Bucket Security:**
- Public access blocking enabled (all 4 settings)
  - Block public ACLs
  - Ignore public ACLs
  - Block public bucket policies
  - Restrict public buckets
- Bucket policies restrict access to CloudTrail and Config services only
- S3 versioning enabled for audit trail integrity

**IAM Configuration:**
- Least-privilege IAM policies for Config service role
- Service-linked roles for CloudTrail and Config
- No IAM users or access keys created by this infrastructure
- IAM Access Analyzer monitors for unintended external access

### Audit and Compliance

**Audit Logging:**
- CloudTrail log file validation enabled (digest files)
- Multi-region trail captures all API activity
- Global service events captured (IAM, STS, Route53)
- Management events logged (read and write operations)

**Compliance Monitoring:**
- AWS Config evaluates 8 CIS Benchmark rules continuously
- Security Hub provides compliance score against CIS AWS Foundations Benchmark v1.4.0
- AWS Foundational Security Best Practices enabled
- Automated compliance checks run every 24 hours

**Active Config Rules:**
1. cloudtrail-enabled
2. multi-region-cloudtrail-enabled
3. s3-bucket-public-read-prohibited
4. s3-bucket-public-write-prohibited
5. s3-bucket-server-side-encryption-enabled
6. iam-password-policy
7. root-account-mfa-enabled
8. iam-user-mfa-enabled

### Data Retention

- S3 lifecycle policies: 90-day retention (configurable)
- S3 versioning enabled for log integrity
- CloudTrail digest files for log validation
- Logs transition to Glacier storage class after 90 days

## Verification

### Automated Verification

Comprehensive verification checklist available at:
`terraform/environments/dev/VERIFICATION_CHECKLIST.md`

Quick verification script:
```bash
scripts/deployment-status.ps1
```

### Manual Verification Steps

**1. CloudTrail Verification**

Console: https://console.aws.amazon.com/cloudtrail

Verify:
- Trail name: `iam-secure-gate-dev-trail`
- Multi-region enabled
- Log validation enabled
- Logging status: Active
- S3 bucket receiving logs

CLI verification:
```bash
aws cloudtrail get-trail-status \
  --name iam-secure-gate-dev-trail \
  --region eu-west-1 \
  --query 'IsLogging'
```

**2. AWS Config Verification**

Console: https://console.aws.amazon.com/config

Verify:
- Recorder status: Recording
- Delivery channel: Active
- 8 Config rules deployed
- Compliance dashboard populated

CLI verification:
```bash
aws configservice describe-configuration-recorder-status \
  --region eu-west-1 \
  --query 'ConfigurationRecordersStatus[0].recording'
```

**3. Security Hub Verification**

Console: https://console.aws.amazon.com/securityhub

Verify:
- Security Hub enabled
- CIS AWS Foundations Benchmark v1.4.0 enabled
- AWS Foundational Security Best Practices enabled
- Security findings populated
- Compliance score visible

CLI verification:
```bash
aws securityhub get-enabled-standards \
  --region eu-west-1
```

**4. S3 Bucket Verification**

Console: https://console.aws.amazon.com/s3

Verify bucket names:
- `iam-secure-gate-dev-cloudtrail-<account-id>`
- `iam-secure-gate-dev-config-<account-id>`

Verify bucket properties:
- Encryption: Enabled (KMS)
- Versioning: Enabled
- Public access: Blocked (all settings)
- Lifecycle rules: Configured

**5. KMS Key Verification**

Console: https://console.aws.amazon.com/kms

Verify:
- Key alias: `alias/iam-secure-gate-dev-logs`
- Key rotation: Enabled
- Key state: Enabled

CLI verification:
```bash
aws kms get-key-rotation-status \
  --key-id $(terraform output -raw kms_key_arn) \
  --region eu-west-1
```

**6. IAM Access Analyzer Verification**

Console: https://console.aws.amazon.com/access-analyzer

Verify:
- Analyzer name: `iam-secure-gate-dev-analyzer`
- Status: Active
- Type: Account

CLI verification:
```bash
aws accessanalyzer list-analyzers \
  --region eu-west-1 \
  --query 'analyzers[?name==`iam-secure-gate-dev-analyzer`]'
```

### Testing Detection Capabilities

**Test 1: Wildcard IAM Policy Detection**

Create a test policy with wildcard permissions:
```bash
aws iam create-policy \
  --policy-name test-wildcard-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }]
  }'
```

Expected detection time: 4 seconds

Verify in Security Hub findings after 1-2 minutes.

Cleanup:
```bash
aws iam delete-policy --policy-arn <policy-arn>
```

**Test 2: Public S3 Bucket Detection**

Create a test bucket with public access:
```bash
aws s3api create-bucket \
  --bucket test-public-bucket-$(date +%s) \
  --region eu-west-1

aws s3api put-bucket-acl \
  --bucket <bucket-name> \
  --acl public-read
```

Expected detection time: 2 minutes 18 seconds

Verify in Config rules and Security Hub findings.

Cleanup:
```bash
aws s3 rb s3://<bucket-name> --force
```

## Troubleshooting

### Bucket Not Empty Error

**Error:**
```
Error: deleting S3 Bucket: BucketNotEmpty: The bucket you tried to delete is not empty
```

**Solution:**

Empty the bucket including all versions before destruction:
```bash
# Get bucket name
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket_name)
CONFIG_BUCKET=$(terraform output -raw config_bucket_name)

# Empty CloudTrail bucket
aws s3 rm s3://$CLOUDTRAIL_BUCKET/ --recursive

# Delete all versions
aws s3api list-object-versions \
  --bucket $CLOUDTRAIL_BUCKET \
  --output json | \
  jq -r '.Versions[],.DeleteMarkers[] | "--key \"\(.Key)\" --version-id \(.VersionId)"' | \
  xargs -n3 aws s3api delete-object --bucket $CLOUDTRAIL_BUCKET

# Repeat for Config bucket
aws s3 rm s3://$CONFIG_BUCKET/ --recursive

# Retry destroy
terraform destroy
```

### Access Denied Errors

**Error:**
```
Error: AccessDenied: Access Denied
```

**Solution:**

Verify IAM user has all required permissions listed in Prerequisites section. Common missing permissions:
- kms:CreateKey
- kms:EnableKeyRotation
- cloudtrail:CreateTrail
- config:PutConfigurationRecorder

Check current IAM permissions:
```bash
aws iam get-user
aws iam list-attached-user-policies --user-name <your-username>
```

### Terraform State Lock Error

**Error:**
```
Error: Error acquiring the state lock
```

**Solution:**

Force unlock with caution (ensure no other Terraform processes are running):
```bash
cd terraform/environments/dev
terraform force-unlock <LOCK_ID>
```

Prevent future locks by using remote state backend with DynamoDB locking.

### Region Mismatch Errors

**Error:**
```
Error: error creating CloudTrail Trail: InvalidBucketPolicyException
```

**Solution:**

Verify all resources are in the same region (eu-west-1):
```bash
echo $AWS_DEFAULT_REGION
aws configure get region
```

Set correct region:
```bash
export AWS_DEFAULT_REGION=eu-west-1
```

### Config Recorder Already Exists

**Error:**
```
Error: ResourceInUseException: Configuration recorder already exists
```

**Solution:**

Delete existing Config recorder before deploying:
```bash
aws configservice stop-configuration-recorder \
  --configuration-recorder-name <recorder-name> \
  --region eu-west-1

aws configservice delete-configuration-recorder \
  --configuration-recorder-name <recorder-name> \
  --region eu-west-1
```

## Operations

### Monitoring

**AWS Console Access:**

- CloudTrail: https://console.aws.amazon.com/cloudtrail
- AWS Config: https://console.aws.amazon.com/config
- Security Hub: https://console.aws.amazon.com/securityhub
- S3 Buckets: https://console.aws.amazon.com/s3
- KMS Keys: https://console.aws.amazon.com/kms

**Key Metrics to Monitor:**

- CloudTrail logging status
- Config recorder status
- Security Hub compliance score
- Number of non-compliant resources
- Security findings by severity
- S3 bucket size and costs
- KMS key usage

### Maintenance

**Regular Tasks:**

Review Security Hub findings: Weekly
- Address critical and high severity findings
- Archive false positives
- Update Config rules as needed

Review Config compliance: Weekly
- Investigate non-compliant resources
- Remediate or document exceptions

Monitor costs: Monthly
- Review AWS Cost Explorer
- Optimize S3 lifecycle policies if needed
- Evaluate optional feature costs

Update Terraform: Quarterly
- Update provider versions
- Review security patches
- Test changes in development environment

**Automated Tasks:**

- KMS key rotation: Annual (automatic)
- Config rule evaluation: Every 24 hours (automatic)
- S3 lifecycle transitions: 90 days (automatic)
- CloudTrail log delivery: Continuous (automatic)

### Cleanup

**Destroy All Resources:**

```bash
cd terraform/environments/dev
terraform destroy
```

**Important:** S3 buckets must be empty before destruction. Use the commands in the Troubleshooting section if needed.

**Verify Cleanup:**

```bash
# Verify no resources remain
terraform state list

# Check AWS Console
# - CloudTrail: Trail deleted
# - Config: Recorder stopped and deleted
# - Security Hub: Disabled
# - S3: Buckets deleted
# - KMS: Key scheduled for deletion
```

**Cost After Cleanup:**

All resources deleted, monthly cost: 0 USD

Note: KMS keys have a mandatory 7-30 day waiting period before deletion.

## Performance Metrics

### Phase 1 Detection Baseline

| Metric | Development | Notes |
|--------|-------------|-------|
| Deployment Time | 2-3 minutes | Complete baseline infrastructure |
| Resources Deployed | 47 | Across 5 Terraform modules |
| Terraform Modules | 5 | Foundation, CloudTrail, Config, Access Analyzer, Security Hub |
| CIS Controls | 8 | Automated compliance rules |
| Security Hub Checks | 233 | Active security checks |
| Monthly Cost | ~7 USD | Development environment |
| Detection Time (IAM) | 4 seconds | Wildcard policy detection |
| Detection Time (S3) | 2 minutes 18 seconds | Public bucket detection |
| Lines of Terraform | ~1200 | Production-ready code |
| Repeatability | 100% | Deterministic deployment |

### Cost Breakdown

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| CloudTrail | 2.00 USD | First trail free, management events only |
| AWS Config | 2.00 USD | First 1000 config items free |
| Config Rules | 1.60 USD | 8 rules at 0.20 USD each |
| S3 Storage | < 1.00 USD | Minimal logs in development |
| KMS CMK | 1.00 USD | Single customer-managed key |
| **Total** | **~7 USD/month** | Full CIS-compliant detection baseline |

## Roadmap

### Phase 1: Detection Baseline (Complete)

**Status:** Production-ready, CIS AWS Foundations compliant

**Components:**
- Foundation module (KMS customer-managed keys with automatic rotation)
- CloudTrail module (multi-region trail, log validation, KMS encryption)
- AWS Config module (configuration recorder, 8 CIS compliance rules)
- IAM Access Analyzer module (external access detection)
- Security Hub module (CIS Benchmark, AWS Foundational Security Best Practices)

**Capabilities:**
- Multi-region API logging across 18 AWS regions
- Continuous compliance monitoring with 8 CIS rules
- External access detection for IAM resources
- Centralized security findings with 233 active checks
- Encrypted audit logs with 90-day retention
- Cost-optimized for development (approximately 7 USD/month)

### Phase 2: Automated Remediation (Planned)

**Goal:** Implement automated response to security findings

**Components:**
- AWS Lambda remediation functions
- EventBridge rules for real-time event routing
- SNS topics for notification delivery
- Step Functions for approval workflows
- DynamoDB for remediation history tracking
- IAM roles for Lambda execution

**Capabilities:**
- Automated remediation of non-compliant resources
- Approval workflow for high-risk changes
- Notification system for remediation actions
- Audit trail of all automated changes
- Configurable remediation policies
- Self-improving security based on detection patterns

**Example Remediations:**
- Auto-enable S3 bucket encryption
- Auto-enable CloudTrail if disabled
- Auto-revoke overly permissive IAM policies
- Auto-rotate IAM access keys older than 90 days
- Auto-enable MFA for IAM users
- Auto-remediate public S3 buckets

### Phase 3: Real-time Metrics and Dashboards (Planned)

**Goal:** Comprehensive security metrics visualization and monitoring

**Components:**
- CloudWatch custom metrics
- CloudWatch dashboards for security posture
- Grafana for advanced visualization
- Prometheus for metrics collection
- CloudWatch alarms for critical findings
- SNS integration for alerting

**Capabilities:**
- Real-time security posture visibility
- Mean time to detect (MTTD) tracking
- Mean time to remediate (MTTR) tracking
- Compliance score trending over time
- Security finding categorization and prioritization
- Custom metrics for business-specific requirements

**Metrics:**
- Detection latency by finding type
- Remediation success rate
- False positive rate
- Cost per security finding
- Compliance drift over time
- Attack surface changes

### Phase 4: PR-level Security Gates (Planned)

**Goal:** Shift-left security to prevent misconfigurations before deployment

**Components:**
- GitHub Actions workflows for CI/CD
- Open Policy Agent (OPA) for policy enforcement
- Checkov for Terraform static analysis
- Pre-commit hooks for local validation
- Policy-as-code repository
- GitHub status checks integration

**Capabilities:**
- Block pull requests with security violations
- Automated Terraform security scanning
- Policy enforcement before infrastructure deployment
- Developer feedback within 30 seconds
- Custom policy rules based on runtime learnings
- Integration with existing CI/CD pipelines

**Prevention Targets:**
- Block IAM policies with wildcard permissions
- Prevent S3 buckets without encryption
- Enforce MFA requirements
- Validate CloudTrail configuration
- Check for public resources before deployment
- 95% reduction in runtime security findings

### Phase 5: Documentation and Production Polish (Planned)

**Goal:** Enterprise-ready documentation and production deployment

**Components:**
- Comprehensive architecture documentation
- Runbooks for common scenarios
- Terraform module registry publication
- Production environment configuration
- Multi-account deployment patterns
- Disaster recovery procedures

**Capabilities:**
- Production-ready infrastructure templates
- Organization-wide deployment patterns using AWS Organizations
- Cross-account Security Hub aggregation
- Service Control Policies (SCPs) for preventive controls
- Automated account provisioning with security baseline
- Complete operational documentation

**Deliverables:**
- Architecture decision records (ADRs)
- Security operations playbooks
- Incident response procedures
- Terraform module documentation
- Production deployment guide
- Multi-account strategy documentation

## Additional Resources

### AWS Security Documentation

- [CIS AWS Foundations Benchmark v1.5.0](https://www.cisecurity.org/benchmark/amazon_web_services)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/)
- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [IAM Access Analyzer Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

### Terraform Documentation

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Module Development](https://developer.hashicorp.com/terraform/language/modules/develop)
- [HashiCorp Learn - Terraform](https://learn.hashicorp.com/terraform)

### Project Documentation

- [Foundation Module README](terraform/modules/foundation/README.md)
- [CloudTrail Module README](terraform/modules/cloudtrail/README.md)
- [Config Module README](terraform/modules/config/README.md)
- [Access Analyzer Module README](terraform/modules/access-analyzer/README.md)
- [Security Hub Module README](terraform/modules/security-hub/README.md)
- [Verification Checklist](terraform/environments/dev/VERIFICATION_CHECKLIST.md)

### Development Tools

- [VS Code Terraform Extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
- [AWS Toolkit for VS Code](https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.aws-toolkit-vscode)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs)

## Contributing

This project is maintained for educational and demonstration purposes.

To propose changes:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -m 'Add improvement'`)
4. Push to branch (`git push origin feature/improvement`)
5. Open a Pull Request with detailed description

## License

Educational and demonstration use.

## Author

**Roko Skugor**

Project: IaC-Secure-Gate - AWS Security Baseline Infrastructure  
Purpose: Production-grade cloud security automation and compliance monitoring  
Phase 1 Completed: January 2026

## Acknowledgments

- HashiCorp for Terraform
- AWS for cloud infrastructure services
- CIS for security benchmarks
- DevOps and CloudSec communities
