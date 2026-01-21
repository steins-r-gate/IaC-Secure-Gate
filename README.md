# 🛡️ IaC-Secure-Gate - AWS Security Baseline Infrastructure

## 🎯 Project Overview

**IaC-Secure-Gate** is a production-grade AWS security baseline infrastructure built with Terraform, implementing CIS AWS Foundations Benchmark controls for detection, logging, and continuous compliance monitoring. This project demonstrates modern Infrastructure as Code (IaC) practices with security-first design principles.

### **The Problem**

Manual cloud security setup is:

- ⏰ Time-consuming (hours to configure logging, monitoring, and compliance)
- 🐛 Error-prone (misconfigured trails, missing encryption, incomplete coverage)
- 🔓 Security-risky (gaps in audit logging, no compliance validation)
- 📊 Inconsistent (different security postures across environments)
- 📝 Unauditable (no centralized security event tracking)
- 💰 Costly (over-provisioned resources, unused features)

### **The Solution**

Automated security baseline deployment using:

- **Infrastructure as Code** - Version-controlled, peer-reviewed security infrastructure
- **CIS Compliance by Default** - Automated CIS AWS Foundations Benchmark controls
- **Multi-Layer Detection** - CloudTrail + AWS Config + managed rules
- **KMS Encryption** - All logs encrypted with customer-managed keys
- **Cost-Optimized** - Dev (~$7/month), Prod-ready with optional features
- **Deterministic Deployment** - No flaky applies, proper dependency management

---

## 🏗️ Architecture

### Phase 1: Detection Baseline

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
│  │ Foundation │ → │  CloudTrail │   │    Config   │       │
│  │            │   │             │   │             │       │
│  │ • KMS CMK  │   │ • Multi-    │   │ • Recorder  │       │
│  │ • S3 Logs  │   │   Region    │   │ • 8 CIS     │       │
│  │ • Policies │   │ • Encrypted │   │   Rules     │       │
│  └────────────┘   └─────────────┘   └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      AWS Cloud                              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Foundation (Security Infrastructure)                 │  │
│  │                                                      │  │
│  │  ✅ KMS CMK (auto-rotation enabled)                 │  │
│  │  ✅ CloudTrail S3 bucket (encrypted, versioned)     │  │
│  │  ✅ Config S3 bucket (encrypted, versioned)         │  │
│  │  ✅ Lifecycle policies (90-day retention)           │  │
│  │  ✅ Public access blocked (all layers)              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ CloudTrail (Audit Logging)                           │  │
│  │                                                      │  │
│  │  ✅ Multi-region trail (CIS 3.1)                    │  │
│  │  ✅ Log file validation (CIS 3.2)                   │  │
│  │  ✅ KMS encryption (CIS 3.3)                        │  │
│  │  ✅ Global service events (IAM/STS)                 │  │
│  │  ✅ Management events (read + write)                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ AWS Config (Compliance Monitoring)                   │  │
│  │                                                      │  │
│  │  ✅ Recorder (all resource types)                   │  │
│  │  ✅ Global resources (IAM, Route53)                 │  │
│  │  ✅ 24-hour snapshot delivery                       │  │
│  │  ✅ 8 CIS compliance rules:                         │  │
│  │     • cloudtrail-enabled                            │  │
│  │     • multi-region-cloudtrail-enabled               │  │
│  │     • s3-bucket-public-read-prohibited              │  │
│  │     • s3-bucket-public-write-prohibited             │  │
│  │     • s3-bucket-server-side-encryption-enabled      │  │
│  │     • iam-password-policy                           │  │
│  │     • root-account-mfa-enabled                      │  │
│  │     • iam-user-mfa-enabled                          │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔒 Security Features

### CIS AWS Foundations Benchmark Compliance

| Control | Description | Implementation | Status |
|---------|-------------|----------------|--------|
| **CIS 3.1** | Multi-region CloudTrail enabled | CloudTrail module with `is_multi_region_trail = true` | ✅ |
| **CIS 3.2** | CloudTrail log file validation | CloudTrail module with `enable_log_file_validation = true` | ✅ |
| **CIS 3.3** | CloudTrail logs encrypted with KMS | Foundation KMS key + CloudTrail integration | ✅ |
| **CIS 3.4** | CloudTrail integrated with CloudWatch (optional) | Available via `enable_cloudwatch_logs = true` | 🟡 |
| **CIS 3.6** | S3 bucket access logging | Foundation module bucket logging | ✅ |
| **CIS 3.7** | CloudTrail logs in dedicated S3 bucket | Foundation module with service-specific buckets | ✅ |

### Security Layers

| Layer | Feature | Implementation |
|-------|---------|----------------|
| **Encryption** | KMS CMK with auto-rotation | Foundation module KMS key |
| **Encryption** | S3 bucket encryption (KMS) | Foundation S3 bucket encryption |
| **Encryption** | CloudTrail log encryption | CloudTrail → Foundation KMS |
| **Access Control** | S3 public access block (4 layers) | Foundation S3 configuration |
| **Access Control** | S3 bucket policies (least-privilege) | CloudTrail/Config service policies |
| **Access Control** | IAM roles (least-privilege) | Config IAM role with scoped policies |
| **Integrity** | S3 versioning enabled | Foundation S3 versioning |
| **Integrity** | CloudTrail log file validation | CloudTrail digest files |
| **Audit** | CloudTrail multi-region logging | All API calls logged |
| **Compliance** | AWS Config continuous monitoring | 8 managed Config rules |
| **Retention** | 90-day log retention (configurable) | S3 lifecycle policies |

---

## 📁 Project Structure

```
IaC-Secure-Gate/
│
├── terraform/
│   ├── environments/               # Environment-specific configs
│   │   └── dev/
│   │       ├── main.tf             # Module composition
│   │       ├── variables.tf        # Environment variables
│   │       ├── outputs.tf          # Environment outputs
│   │       ├── ENVIRONMENT_CHANGES.md
│   │       └── VERIFICATION_CHECKLIST.md
│   │
│   └── modules/                    # Reusable Terraform modules
│       ├── foundation/             # KMS + S3 foundation
│       │   ├── main.tf
│       │   ├── kms.tf              # KMS CMK configuration
│       │   ├── s3-cloudtrail.tf    # CloudTrail bucket
│       │   ├── s3-config.tf        # Config bucket
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md
│       │
│       ├── cloudtrail/             # Multi-region audit trail
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── README.md
│       │   ├── CHANGES_SUMMARY.md
│       │   └── VERIFICATION_CHECKLIST.md
│       │
│       └── config/                 # AWS Config compliance
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── iam.tf              # Config IAM role
│           ├── rules.tf            # CIS compliance rules
│           └── README.md
│
├── scripts/
│   ├── deployment-status.ps1       # Quick status check
│   └── (legacy demo scripts)
│
├── .gitignore                      # Security-enhanced patterns
└── README.md                       # This file
```

---

## 🚀 Quick Start Guide

### **Prerequisites**

1. **AWS Account** with appropriate IAM permissions:
   - S3: CreateBucket, PutBucketPolicy, PutBucketEncryption, etc.
   - KMS: CreateKey, PutKeyPolicy, EnableKeyRotation
   - CloudTrail: CreateTrail, StartLogging, PutEventSelectors
   - Config: PutConfigurationRecorder, PutDeliveryChannel, PutConfigRule
   - IAM: CreateRole, AttachRolePolicy (for Config service role)

2. **Software Requirements**

```bash
# Check installations
aws --version        # AWS CLI v2.x+
terraform version    # Terraform v1.5.0+
git --version        # Git v2.x+
```

3. **Install Missing Tools**

```bash
# AWS CLI (Windows)
winget install Amazon.AWSCLI

# Terraform (Windows)
# Download from: https://www.terraform.io/downloads
# Or use: choco install terraform

# Git (Windows)
winget install Git.Git
```

### **Installation**

```bash
# 1. Clone the repository
git clone <repository-url>
cd IaC-Secure-Gate

# 2. Checkout the phase-1 branch
git checkout phase-1

# 3. Configure AWS credentials
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: eu-west-1
# - Output format: json

# 4. Verify AWS access
aws sts get-caller-identity
```

---

## 🎮 Usage

### **Deploy Phase 1 Security Baseline**

```bash
# Navigate to dev environment
cd terraform/environments/dev

# Initialize Terraform (download providers and modules)
terraform init

# Review what will be created (~45-50 resources)
terraform plan

# Deploy the infrastructure
terraform apply
```

**Expected Output:**

```
Plan: 47 resources to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.foundation.aws_kms_key.logs: Creating...
module.foundation.aws_s3_bucket.cloudtrail: Creating...
module.foundation.aws_s3_bucket.config: Creating...
...
module.cloudtrail.aws_cloudtrail.main: Creating...
module.config.aws_config_configuration_recorder.main: Creating...
module.config.aws_config_config_rule.cloudtrail_enabled: Creating...
...

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

**Deployment Time:** 2-3 minutes for complete Phase 1 baseline

---

### **Verify Deployment**

```bash
cd terraform/environments/dev

# Check deployment summary
terraform output deployment_summary

# Verify CloudTrail is logging
TRAIL_NAME=$(terraform output -raw cloudtrail_trail_name)
aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region eu-west-1

# Verify Config recorder is running
RECORDER_NAME=$(terraform output -raw config_recorder_name)
aws configservice describe-configuration-recorder-status \
  --configuration-recorder-names "$RECORDER_NAME" \
  --region eu-west-1

# Quick deployment status check
../../scripts/deployment-status.ps1
```

**For comprehensive verification**, see: [terraform/environments/dev/VERIFICATION_CHECKLIST.md](terraform/environments/dev/VERIFICATION_CHECKLIST.md)

---

### **View in AWS Console**

**CloudTrail:**
- Console: https://console.aws.amazon.com/cloudtrail
- Search for: `iam-secure-gate-dev-trail`
- Verify: Multi-region enabled, Log validation enabled, Logging status

**AWS Config:**
- Console: https://console.aws.amazon.com/config
- Check: Recorder status (recording), Delivery channel, 8 rules deployed
- Review: Compliance dashboard for rule status

**S3 Buckets:**
- Console: https://console.aws.amazon.com/s3
- Find: `iam-secure-gate-dev-cloudtrail-*` and `iam-secure-gate-dev-config-*`
- Verify: Encryption enabled, Versioning enabled, Public access blocked

**KMS:**
- Console: https://console.aws.amazon.com/kms
- Find: `alias/iam-secure-gate-dev-logs`
- Verify: Key rotation enabled

---

### **Cleanup Resources**

```bash
cd terraform/environments/dev

# Preview what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Important Notes:**
- S3 buckets must be empty before destruction
- If buckets contain logs, Terraform will fail with "BucketNotEmpty"
- To force empty and destroy:

```bash
# Get bucket names
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket_name)
CONFIG_BUCKET=$(terraform output -raw config_bucket_name)

# Empty buckets (including all versions)
aws s3 rm s3://$CLOUDTRAIL_BUCKET/ --recursive
aws s3 rm s3://$CONFIG_BUCKET/ --recursive

# Then destroy
terraform destroy
```

---

## 🧪 Testing & Verification

### **Automated Verification**

See the comprehensive checklist: [terraform/environments/dev/VERIFICATION_CHECKLIST.md](terraform/environments/dev/VERIFICATION_CHECKLIST.md)

The checklist includes:
- ✅ Pre-deployment validation (fmt, init, validate)
- ✅ Deployment testing (clean apply, idempotency)
- ✅ Post-deployment verification (18-step checklist)
- ✅ Security testing (CloudTrail events, Config rules)
- ✅ Cost verification
- ✅ CIS compliance verification

---

### **Quick Manual Verification**

```bash
cd terraform/environments/dev

# 1. Check deployment summary
terraform output deployment_summary

# Should show:
# phase_1_ready = true
# cloudtrail_cis_3_1_compliant = true
# cloudtrail_cis_3_2_compliant = true
# config_recorder_enabled = true
# config_rules_deployed = 8

# 2. Verify CloudTrail is logging
TRAIL_NAME=$(terraform output -raw cloudtrail_trail_name)
aws cloudtrail get-trail-status --name "$TRAIL_NAME" --region eu-west-1 \
  --query 'IsLogging' --output text
# Expected: true

# 3. Verify Config recorder is running
RECORDER_NAME=$(terraform output -raw config_recorder_name)
aws configservice describe-configuration-recorder-status \
  --configuration-recorder-names "$RECORDER_NAME" \
  --region eu-west-1 \
  --query 'ConfigurationRecordersStatus[0].recording' \
  --output text
# Expected: true

# 4. Verify KMS key rotation
KMS_KEY_ARN=$(terraform output -raw kms_key_arn)
aws kms get-key-rotation-status --key-id "$KMS_KEY_ARN" --region eu-west-1
# Expected: KeyRotationEnabled: true

# 5. Test CloudTrail is capturing IAM events
aws iam list-users --region eu-west-1
# Wait 2-3 minutes, then check CloudTrail:
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ListUsers \
  --region eu-west-1 --max-results 1
# Should show recent ListUsers event
```

---

## 📊 Performance Metrics

### Phase 1 Detection Baseline

| Metric | Dev Environment | Production Ready |
|--------|-----------------|------------------|
| **Deployment Time** | 2-3 minutes | 3-5 minutes (with optional features) |
| **Resources Deployed** | 47 resources | 50+ resources |
| **Terraform Modules** | 3 (Foundation, CloudTrail, Config) | Same |
| **CIS Controls** | 8 automated rules | Same + custom rules |
| **Security Layers** | 11 controls | 11+ controls |
| **Monthly Cost (Dev)** | ~$6-7 | ~$50-80 (with CloudWatch/Insights) |
| **Lines of Terraform** | ~1,200 lines | Same codebase |
| **Repeatability** | 100% deterministic | 100% deterministic |
| **Manual Setup Time** | 2-4 hours | 8+ hours |
| **Engineering Time Saved** | 95%+ | 95%+ |

### Cost Breakdown (Dev Environment)

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| CloudTrail | $2.00 | First trail free, management events only |
| AWS Config | $2.00 | First 1000 config items free |
| Config Rules (8) | $1.60 | $0.20 per rule × 8 |
| S3 Storage | <$1.00 | Minimal logs in dev |
| KMS CMK | $1.00 | 1 customer-managed key |
| **Total** | **~$6-7/month** | Full CIS-compliant detection baseline |

**Optional features** (disabled in dev to reduce costs):
- CloudWatch Logs: +$10-20/month
- SNS Notifications: +$0.50/month
- CloudTrail Insights: +$35-50/month
- S3 Data Events: +$100s/month (high-volume)

---

## 🔧 Troubleshooting

### **Common Issues**

#### **Issue: "AWS credentials not configured"**

```
❌ AWS credentials not configured
```

**Solution:**

```powershell
# Configure AWS CLI
aws configure

# Verify configuration
aws sts get-caller-identity
```

---

#### **Issue: "Terraform not found"**

```
❌ Terraform not installed
```

**Solution:**

```powershell
# Download Terraform from:
# https://www.terraform.io/downloads

# Or use Chocolatey:
choco install terraform

# Verify installation
terraform version
```

---

#### **Issue: "Bucket not empty" during cleanup**

```
Error: deleting S3 Bucket: BucketNotEmpty
```

**Solution:**

```powershell
# Empty bucket (including versions)
$bucket = "iam-security-dev-demo-826232761554"

# Delete all versions
aws s3api list-object-versions --bucket $bucket --output json | ConvertFrom-Json | ForEach-Object {
    $_.Versions | ForEach-Object {
        aws s3api delete-object --bucket $bucket --key $_.Key --version-id $_.VersionId
    }
}

# Then retry cleanup
.\scripts\Cleanup-Demo.ps1
```

---

#### **Issue: "Access Denied" errors**

```
Error: AccessDenied: Access Denied
```

**Solution:**

- Verify IAM user has S3 full access permissions
- Check AWS account limits haven't been reached
- Ensure you're in the correct AWS region (eu-west-1)

---

#### **Issue: "State lock" error**

```
Error: Error acquiring the state lock
```

**Solution:**

```powershell
# Force unlock (use carefully)
cd terraform\environments\dev
terraform force-unlock <LOCK_ID>
```

---

## 🎓 Educational Value

### **What This Project Teaches**

1. **Infrastructure as Code Principles**
   - Declarative configuration with Terraform HCL
   - State management and backend configuration
   - Idempotency and deterministic deployments
   - Module composition and reusability
   - Dependency management (explicit `depends_on` vs implicit)

2. **Cloud Security Best Practices**
   - Defense in depth (multiple security layers)
   - Encryption at rest (KMS) and in transit (HTTPS)
   - Principle of least privilege (IAM policies)
   - Security by default, optional features opt-in
   - CIS AWS Foundations Benchmark compliance
   - Audit logging and compliance monitoring

3. **AWS Security Services**
   - **AWS CloudTrail**: API logging, multi-region trails, log validation
   - **AWS Config**: Resource compliance, managed rules, remediation
   - **AWS KMS**: Customer-managed keys, key rotation, encryption contexts
   - **S3 Security**: Bucket policies, encryption, versioning, lifecycle

4. **Terraform Advanced Concepts**
   - Module design patterns (foundation, service modules)
   - Variable validation and type constraints
   - Dynamic blocks and conditional resources
   - Structured outputs and complex objects
   - Data sources for runtime information
   - Count and for_each for conditional creation

5. **DevOps/GitOps Workflows**
   - Version-controlled infrastructure
   - Peer review via pull requests
   - Automated validation (terraform fmt/validate)
   - Documentation as code
   - Environment promotion (dev → staging → prod)

### **Skills Demonstrated**

- ✅ Production-grade Terraform module development
- ✅ AWS security services integration
- ✅ CIS compliance automation
- ✅ Cost optimization strategies
- ✅ Security-first architecture design
- ✅ Comprehensive technical documentation
- ✅ Testing and verification methodologies
- ✅ Git workflow and version control

---

## 🗺️ Roadmap

### **Phase 1: Detection Baseline** ✅ **COMPLETE**

**Status:** Production-ready, CIS AWS Foundations compliant

**What's Included:**
- ✅ Foundation module (KMS + S3 buckets with encryption/versioning/lifecycle)
- ✅ CloudTrail module (multi-region trail, log validation, KMS encryption)
- ✅ AWS Config module (recorder + 8 CIS compliance rules)
- ✅ Complete documentation (README, CHANGES_SUMMARY, VERIFICATION_CHECKLIST)
- ✅ Dev environment configured and validated
- ✅ Cost-optimized for dev (~$7/month)
- ✅ Production-ready optional features (CloudWatch, SNS, Insights)

**CIS Controls Implemented:**
- CIS 3.1: Multi-region CloudTrail
- CIS 3.2: Log file validation
- CIS 3.3: CloudTrail KMS encryption
- CIS 3.6: S3 access logging
- CIS 3.7: Dedicated CloudTrail bucket

---

### **Phase 2: Threat Detection** 🔄 **PLANNED**

**Goal:** Add real-time threat detection and anomaly analysis

**Components:**
- AWS GuardDuty (threat intelligence, anomaly detection)
- Amazon Detective (security investigation)
- VPC Flow Logs (network traffic analysis)
- GuardDuty findings → EventBridge → SNS
- GuardDuty S3 protection
- GuardDuty EKS/ECS protection (if applicable)

**CIS Controls:**
- CIS 4.x: VPC and network monitoring

---

### **Phase 3: Centralized Security** 🔄 **PLANNED**

**Goal:** Unified security posture management and compliance reporting

**Components:**
- AWS Security Hub (aggregated findings from GuardDuty, Config, IAM Access Analyzer)
- Security standards (CIS AWS Foundations, AWS Foundational Security Best Practices)
- Custom Config rules for organization-specific policies
- EventBridge integration for automated ticketing
- Security Hub → SNS → Slack/Teams/Email

**Deliverables:**
- Single pane of glass for security findings
- Automated compliance reporting
- Security score tracking

---

### **Phase 4: IAM Governance** 🔄 **PLANNED**

**Goal:** Least-privilege IAM and identity security

**Components:**
- IAM Access Analyzer (external access detection, unused access)
- IAM credential reports
- IAM password policy enforcement (Config rule)
- MFA enforcement (Config rules)
- IAM role trust policy analysis
- Service Control Policies (SCPs) for AWS Organizations

**CIS Controls:**
- CIS 1.x: IAM controls (password policy, MFA, access keys, root account)

---

### **Phase 5: Automated Remediation** 🔄 **PLANNED**

**Goal:** Auto-remediate non-compliant resources

**Components:**
- AWS Config remediation actions (SSM Automation documents)
- Lambda-based custom remediation
- EventBridge rules for real-time response
- SNS notifications for remediation actions
- Audit trail of all automated changes

**Example Remediations:**
- Auto-enable S3 encryption on non-compliant buckets
- Auto-enable CloudTrail if disabled
- Auto-revoke overly permissive security group rules
- Auto-rotate IAM access keys > 90 days old

---

### **Phase 6: Multi-Account Governance** 🔄 **FUTURE**

**Goal:** Organization-wide security baseline

**Components:**
- AWS Organizations integration
- Organization CloudTrail
- Centralized Config aggregator
- Cross-account Security Hub
- StackSets for baseline deployment
- Service Control Policies (SCPs)

**Deliverables:**
- Single security baseline across all accounts
- Centralized logging and compliance
- Automated account provisioning with security controls

---

## 📚 Additional Resources

### **AWS Security Documentation**

- [CIS AWS Foundations Benchmark v1.5.0](https://www.cisecurity.org/benchmark/amazon_web_services)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

### **Terraform Documentation**

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Module Best Practices](https://developer.hashicorp.com/terraform/language/modules/develop)
- [HashiCorp Learn - Terraform](https://learn.hashicorp.com/terraform)

### **Project Documentation**

- [Foundation Module README](terraform/modules/foundation/README.md)
- [CloudTrail Module README](terraform/modules/cloudtrail/README.md)
- [Config Module README](terraform/modules/config/README.md)
- [Environment Verification Checklist](terraform/environments/dev/VERIFICATION_CHECKLIST.md)

### **Tools & Extensions**

- [VS Code Terraform Extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
- [AWS Toolkit for VS Code](https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.aws-toolkit-vscode)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs) - Generate documentation from Terraform modules

---

## 🤝 Contributing

This is a demonstration project for educational purposes. For improvements or suggestions:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -m 'Add improvement'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

---

## 📄 License

This project is created for educational and demonstration purposes.

---

## 👤 Author

**Roko Skugor**

- Project: IaC-Secure-Gate - AWS Security Baseline
- Purpose: Production-grade cloud security infrastructure
- Phase 1 Completed: January 2026

---

## 🙏 Acknowledgments

- HashiCorp for Terraform
- AWS for cloud infrastructure
- The DevOps and CloudSec communities

---

## 📞 Support

For questions about this demo:

- Review the troubleshooting section above
- Check AWS and Terraform documentation
- Verify prerequisites are met

---

## 🎯 Phase 1 Success Criteria

Phase 1 Detection Baseline is successful when:

- ✅ All 3 modules deploy cleanly (Foundation, CloudTrail, Config)
- ✅ CloudTrail is logging and multi-region enabled
- ✅ CloudTrail log validation enabled (CIS 3.2)
- ✅ All logs encrypted with KMS CMK
- ✅ AWS Config recorder is running
- ✅ All 8 CIS Config rules are ACTIVE
- ✅ `terraform apply` is idempotent (second apply shows no changes)
- ✅ `deployment_summary` shows `phase_1_ready = true`
- ✅ All CIS compliance flags = true
- ✅ Resources accessible and verifiable in AWS Console
- ✅ Cleanup removes all resources completely
- ✅ Total cost < $10/month for dev environment

---

## 📈 Version History

### **v2.0.0 - Phase 1 Complete** (January 2026)

**Major Features:**
- ✅ Foundation module (KMS + S3 buckets)
- ✅ CloudTrail module v2.0 (production-grade, advanced event selectors)
- ✅ AWS Config module (8 CIS compliance rules)
- ✅ Complete dev environment integration
- ✅ CIS AWS Foundations Benchmark compliance
- ✅ Comprehensive documentation suite

**Breaking Changes:**
- CloudTrail module: `kms_key_id` → `kms_key_arn`
- Removed `region` and `account_id` variables (auto-detected)
- Migrated from legacy `event_selector` to `advanced_event_selector`

**Infrastructure:**
- 47 resources deployed in Phase 1
- 11 security layers
- 8 automated CIS compliance rules
- ~$6-7/month dev cost

---

### **v1.0.0 - Demo Release** (November 2025)

- Initial demo version
- Single S3 bucket deployment
- Core security features
- PowerShell automation scripts
- Basic verification tooling

---
