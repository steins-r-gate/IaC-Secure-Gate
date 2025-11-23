# 📘 IAM-Secure-Gate Demo - README

## 🎯 Project Overview

**IAM-Secure-Gate** is an automated cloud security infrastructure system that demonstrates modern Infrastructure as Code (IaC) practices using Terraform and AWS. This demo showcases how to deploy production-ready, secure cloud infrastructure in under 60 seconds with security best practices enforced automatically.

### **The Problem**

Manual cloud infrastructure setup is:

- ⏰ Time-consuming (20+ minutes per resource)
- 🐛 Error-prone (human configuration mistakes)
- 🔓 Security-risky (missing security controls)
- 📊 Inconsistent (different results each time)
- 📝 Unauditable (no change tracking)

### **The Solution**

Automated infrastructure deployment using:

- **Infrastructure as Code** - Define infrastructure in version-controlled code
- **Security by Default** - Bake security into every deployment
- **One-Click Deployment** - 60 seconds from code to production
- **100% Repeatable** - Identical results every time
- **Fully Auditable** - Complete change history in Git

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    IAM-Secure-Gate                      │
│                      Demo System                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                     Terraform                           │
│              Infrastructure as Code                     │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   main.tf    │  │ variables.tf │  │  outputs.tf  │ │
│  │   (config)   │  │  (inputs)    │  │  (results)   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                    AWS Cloud                            │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │              S3 Bucket (Demo)                     │ │
│  │  ┌─────────────────────────────────────────────┐ │ │
│  │  │  ✅ Versioning Enabled                      │ │ │
│  │  │  ✅ Encryption (AES-256)                    │ │ │
│  │  │  ✅ Public Access Blocked (4 layers)        │ │ │
│  │  │  ✅ HTTPS-Only Policy                       │ │ │
│  │  │  ✅ Ownership Controls                      │ │ │
│  │  │  ✅ Security Policy Enforced                │ │ │
│  │  └─────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## 🔒 Security Features

| Feature                 | Description                  | Benefit                      |
| ----------------------- | ---------------------------- | ---------------------------- |
| **Versioning**          | Every file change tracked    | Accidental deletion recovery |
| **Encryption at Rest**  | AES-256 encryption automatic | Data protection compliance   |
| **Public Access Block** | 4-layer protection system    | Zero public exposure risk    |
| **HTTPS-Only Policy**   | Encrypted transport enforced | Secure data in transit       |
| **Bucket Key Enabled**  | Reduced KMS costs            | Cost optimization + security |
| **Ownership Controls**  | BucketOwnerEnforced          | Prevent ACL-based attacks    |

---

## 📁 Project Structure

```
IAM-SECURE-GATE/
│
├── terraform/
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf          # Main configuration
│   │       ├── variables.tf     # Input variables
│   │       └── outputs.tf       # Output values
│   │
│   └── modules/
│       └── s3/
│           ├── main.tf          # S3 bucket resources
│           ├── variables.tf     # Module variables
│           └── outputs.tf       # Module outputs
│
├── scripts/
│   ├── Set-AWSEnvironment.ps1   # AWS credential setup
│   ├── Deploy-Demo.ps1          # Automated deployment
│   ├── Cleanup-Demo.ps1         # Resource cleanup
│   └── Verify-Demo.ps1          # Verification checks
│
├── .gitignore                   # Git exclusions
└── README.md                    # This file
```

---

## 🚀 Quick Start Guide

### **Prerequisites**

1. **AWS Account** with appropriate permissions

   - S3 full access
   - IAM read access (for identity verification)

2. **Software Requirements**

```powershell
   # Check installations
   aws --version        # AWS CLI v2.x+
   terraform version    # Terraform v1.5.0+
   git --version        # Git v2.x+
```

3. **Install Missing Tools**

```powershell
   # AWS CLI
   winget install Amazon.AWSCLI

   # Terraform
   # Download from: https://www.terraform.io/downloads

   # Git
   winget install Git.Git
```

### **Installation**

```powershell
# 1. Clone the repository
git clone <repository-url>
cd IAM-Secure-Gate

# 2. Switch to demo branch
git checkout demo

# 3. Configure AWS credentials
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: eu-west-1
# - Output format: json

# 4. Verify AWS access
.\scripts\Set-AWSEnvironment.ps1
```

---

## 🎮 Usage

### **Deploy Infrastructure**

```powershell
# Full guided deployment
.\scripts\Deploy-Demo.ps1

# Automatic approval (skip confirmations)
.\scripts\Deploy-Demo.ps1 -AutoApprove
```

**Expected Output:**

```
========================================
  IAM-SECURE-GATE DEMO DEPLOYMENT
========================================

> Checking AWS credentials...
  OK - Account ID: 826232761554

> Checking Terraform...
  OK - Terraform v1.5.0

> Deploying infrastructure...

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

========================================
  DEPLOYMENT SUCCESSFUL!
========================================

Deployment Summary:
  Environment:  dev
  AWS Account:  826232761554
  Region:       eu-west-1

Created Resources:
  S3 Bucket:    iam-security-dev-demo-826232761554

Deployment completed in 45.3 seconds
```

### **Verify Deployment**

```powershell
# Run verification checks
.\scripts\Verify-Demo.ps1
```

**Expected Output:**

```
  Checking AWS Credentials... ✅
  Checking Terraform Installation... ✅
  Checking S3 Bucket Exists... ✅
  Checking Versioning Enabled... ✅
  Checking Encryption Enabled... ✅
  Checking Public Access Blocked... ✅

Success Rate: 100%
🎉 Demo is fully operational!
```

### **View in AWS Console**

```powershell
# Get console URL
cd terraform\environments\dev
terraform output demo_bucket_url
```

Or manually navigate to:

- **S3 Console**: https://console.aws.amazon.com/s3
- Search for: `iam-security-dev-demo-*`

### **Cleanup Resources**

```powershell
# Guided cleanup (with confirmations)
.\scripts\Cleanup-Demo.ps1

# Force cleanup (no confirmations)
.\scripts\Cleanup-Demo.ps1 -Force
```

**Important:** If bucket contains files, empty it first:

```powershell
$bucket = "iam-security-dev-demo-826232761554"
aws s3 rm s3://$bucket/ --recursive
```

---

## 🧪 Testing & Verification

### **Manual Verification in AWS Console**

1. **Navigate to S3 Bucket**

   - Go to AWS Console → S3
   - Find bucket: `iam-security-dev-demo-<account-id>`

2. **Check Properties Tab**

   - ✅ Bucket Versioning: **Enabled**
   - ✅ Default encryption: **Enabled (SSE-S3 with AES-256)**

3. **Check Permissions Tab**
   - ✅ Block all public access: **On** (all 4 settings)
   - ✅ Bucket policy: **HTTPS-only enforcement**

### **AWS CloudShell Verification**

```bash
# Open CloudShell in AWS Console
# Set your bucket name
export BUCKET_NAME=iam-security-dev-demo-826232761554

# Check versioning
aws s3api get-bucket-versioning --bucket $BUCKET_NAME

# Check encryption
aws s3api get-bucket-encryption --bucket $BUCKET_NAME

# Check public access blocks
aws s3api get-public-access-block --bucket $BUCKET_NAME

# Check bucket policy
aws s3api get-bucket-policy --bucket $BUCKET_NAME --query Policy --output text
```

---

## 📊 Performance Metrics

| Metric                     | Value         | Comparison                  |
| -------------------------- | ------------- | --------------------------- |
| **Deployment Time**        | 45-60 seconds | vs. 20+ minutes manual      |
| **Security Controls**      | 6 automatic   | vs. 0-2 typical manual      |
| **Lines of Code**          | ~150 lines    | Manages 6 resources         |
| **Repeatability**          | 100%          | vs. ~60% manual consistency |
| **Cost per Bucket**        | $0.023/month  | (empty bucket)              |
| **Engineering Time Saved** | 80-90%        | Automation vs. manual       |

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

### **What This Demo Teaches**

1. **Infrastructure as Code Principles**

   - Declarative vs. imperative configuration
   - State management
   - Idempotency

2. **Cloud Security Best Practices**

   - Defense in depth
   - Encryption at rest and in transit
   - Principle of least privilege
   - Public access prevention

3. **DevOps Automation**

   - Continuous deployment
   - Automated testing
   - GitOps workflows

4. **Terraform Core Concepts**
   - Resources and data sources
   - Modules and composition
   - Variables and outputs
   - Provider configuration

### **Skills Demonstrated**

- ✅ Cloud infrastructure management
- ✅ Security automation
- ✅ Scripting and automation (PowerShell)
- ✅ Version control (Git)
- ✅ AWS services knowledge
- ✅ Terraform proficiency
- ✅ DevOps practices

---

## 🗺️ Roadmap

### **Current: Phase 1 - Secure Storage** ✅

- S3 bucket with security best practices
- Automated deployment and cleanup
- Verification tooling

### **Future Phases**

#### **Phase 2 - Security Monitoring**

- AWS CloudTrail integration
- AWS Config rules
- Real-time compliance checking
- Security event logging

#### **Phase 3 - Threat Detection**

- AWS GuardDuty integration
- Anomaly detection
- Security alerting (SNS/Email)
- EventBridge event routing

#### **Phase 4 - Automated Remediation**

- Lambda-based auto-remediation
- Security incident response
- Automatic policy enforcement
- Compliance drift correction

#### **Phase 5 - IAM Policy Analysis**

- IAM Access Analyzer integration
- Policy risk scoring
- Least privilege recommendations
- Access pattern analysis

---

## 📚 Additional Resources

### **Documentation**

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Terraform Module Best Practices](https://www.terraform.io/docs/language/modules/develop/index.html)

### **Learning Materials**

- [HashiCorp Learn - Terraform](https://learn.hashicorp.com/terraform)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Infrastructure as Code Principles](https://infrastructure-as-code.com/)

### **Tools & Extensions**

- VS Code Terraform Extension
- AWS Toolkit for VS Code
- Terraform LSP (Language Server)

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

- Project: IAM-Secure-Gate Demo
- Purpose: Commission Demonstration
- Date: November 2025

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

## 🎯 Demo Success Criteria

This demo is successful when:

- ✅ Infrastructure deploys in under 60 seconds
- ✅ All 6 security controls are verified
- ✅ Resources are accessible in AWS Console
- ✅ Cleanup removes all resources completely
- ✅ Process is reproducible and consistent

---

## 📈 Version History

### **v1.0.0 - Demo Release**

- Initial demo version
- Single S3 bucket deployment
- Core security features
- PowerShell automation scripts
- Verification tooling

---
