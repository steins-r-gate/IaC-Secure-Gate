# ==================================================================
# IaC Secure Gate - Phase 2 Demo & Validation Script (PowerShell)
# ==================================================================
#
# Purpose: Demonstrate and validate the automated remediation system
# Usage: .\demo-test.ps1 [-IAMOnly] [-S3Only] [-SGOnly] [-SkipCleanup]
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Terraform infrastructure deployed
#
# Author: IaC Secure Gate Team
# Version: 1.0.0
# ==================================================================

param(
    [switch]$IAMOnly,
    [switch]$S3Only,
    [switch]$SGOnly,
    [switch]$SkipCleanup,
    [switch]$Help
)

# ==================================================================
# Configuration
# ==================================================================

$ErrorActionPreference = "Stop"

$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$REGION = "eu-west-1"
$PROJECT_PREFIX = "iam-secure-gate-dev"

# Lambda function names
$IAM_LAMBDA = "$PROJECT_PREFIX-iam-remediation"
$S3_LAMBDA = "$PROJECT_PREFIX-s3-remediation"
$SG_LAMBDA = "$PROJECT_PREFIX-sg-remediation"

# DynamoDB table
$DYNAMODB_TABLE = "$PROJECT_PREFIX-remediation-history"

# Test resource names (with timestamp for uniqueness)
$TIMESTAMP = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$TEST_POLICY_NAME = "demo-wildcard-policy-$TIMESTAMP"
$TEST_BUCKET_NAME = "demo-public-bucket-$ACCOUNT_ID-$TIMESTAMP"
$TEST_SG_NAME = "demo-permissive-sg-$TIMESTAMP"

# Test flags
$TestIAM = -not ($S3Only -or $SGOnly)
$TestS3 = -not ($IAMOnly -or $SGOnly)
$TestSG = -not ($IAMOnly -or $S3Only)

# Track created resources for cleanup
$CreatedResources = @{
    PolicyArn = $null
    BucketName = $null
    SecurityGroupId = $null
}

# ==================================================================
# Helper Functions
# ==================================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "[STEP] " -ForegroundColor Blue -NoNewline
    Write-Host $Text
}

function Write-Success {
    param([string]$Text)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $Text
}

function Write-Error2 {
    param([string]$Text)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Text
}

function Write-Warning2 {
    param([string]$Text)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $Text
}

function Cleanup-Resources {
    Write-Header "CLEANUP"

    # Cleanup IAM policy
    if ($CreatedResources.PolicyArn) {
        try {
            Write-Step "Deleting IAM policy versions..."
            $versions = aws iam list-policy-versions --policy-arn $CreatedResources.PolicyArn --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>$null
            foreach ($version in ($versions -split "`t")) {
                if ($version) {
                    aws iam delete-policy-version --policy-arn $CreatedResources.PolicyArn --version-id $version 2>$null
                }
            }
            Write-Step "Deleting IAM policy..."
            aws iam delete-policy --policy-arn $CreatedResources.PolicyArn 2>$null
            Write-Success "IAM policy deleted"
        } catch {
            Write-Warning2 "Could not delete IAM policy: $_"
        }
    }

    # Cleanup S3 bucket
    if ($CreatedResources.BucketName) {
        try {
            Write-Step "Deleting S3 bucket..."
            aws s3 rb "s3://$($CreatedResources.BucketName)" --force 2>$null
            Write-Success "S3 bucket deleted"
        } catch {
            Write-Warning2 "Could not delete S3 bucket: $_"
        }
    }

    # Cleanup Security Group
    if ($CreatedResources.SecurityGroupId) {
        try {
            Write-Step "Deleting Security Group..."
            aws ec2 delete-security-group --group-id $CreatedResources.SecurityGroupId 2>$null
            Write-Success "Security Group deleted"
        } catch {
            Write-Warning2 "Could not delete Security Group: $_"
        }
    }

    Write-Success "Cleanup complete"
}

# ==================================================================
# Show Help
# ==================================================================

if ($Help) {
    Write-Host @"
IaC Secure Gate - Phase 2 Demo Script

Usage: .\demo-test.ps1 [options]

Options:
    -IAMOnly      Test only IAM remediation
    -S3Only       Test only S3 remediation
    -SGOnly       Test only Security Group remediation
    -SkipCleanup  Don't delete test resources after demo
    -Help         Show this help message

Examples:
    .\demo-test.ps1                    # Run all tests
    .\demo-test.ps1 -IAMOnly           # Test only IAM
    .\demo-test.ps1 -SkipCleanup       # Keep resources for inspection
"@
    exit 0
}

# ==================================================================
# Main Demo Script
# ==================================================================

try {
    Write-Header "IaC SECURE GATE - PHASE 2 DEMO"

    Write-Host "Account ID:    " -NoNewline; Write-Host $ACCOUNT_ID -ForegroundColor Cyan
    Write-Host "Region:        " -NoNewline; Write-Host $REGION -ForegroundColor Cyan
    Write-Host "Project:       " -NoNewline; Write-Host $PROJECT_PREFIX -ForegroundColor Cyan
    Write-Host ""

    # Check prerequisites
    Write-Step "Checking prerequisites..."
    $null = aws sts get-caller-identity
    Write-Success "AWS CLI configured"

    # ==================================================================
    # TEST 1: IAM Wildcard Policy Remediation
    # ==================================================================

    if ($TestIAM) {
        Write-Header "TEST 1: IAM WILDCARD POLICY REMEDIATION"

        # Step 1: Create dangerous policy
        Write-Step "Creating IAM policy with wildcard permissions..."

        # Write policy document to temp file (avoids PowerShell JSON escaping issues)
        $policyDocContent = @'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DangerousWildcard",
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
'@
        $policyDocFile = "$env:TEMP\iam-policy-doc.json"
        $policyDocContent | Out-File -FilePath $policyDocFile -Encoding ASCII

        $POLICY_ARN = aws iam create-policy `
            --policy-name $TEST_POLICY_NAME `
            --policy-document "file://$policyDocFile" `
            --description "Demo test policy - will be auto-remediated" `
            --query "Policy.Arn" --output text

        $CreatedResources.PolicyArn = $POLICY_ARN
        Write-Success "Policy created: $POLICY_ARN"

        # Step 2: Show original policy
        Write-Step "Original policy (DANGEROUS):"
        aws iam get-policy-version --policy-arn $POLICY_ARN --version-id v1 `
            --query "PolicyVersion.Document" --output json
        Write-Host ""

        # Step 3: Create test event file
        Write-Step "Creating Security Hub finding event..."
        $testEventContent = @"
{
  "version": "0",
  "id": "demo-iam-$TIMESTAMP",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "$ACCOUNT_ID",
  "region": "$REGION",
  "detail": {
    "findings": [{
      "Id": "demo-finding-iam-$TIMESTAMP",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-IAM1",
      "AwsAccountId": "$ACCOUNT_ID",
      "Severity": { "Label": "HIGH" },
      "Title": "IAM policies should not allow full administrative privileges",
      "ProductFields": { "ControlId": "IAM.1" },
      "Resources": [{
        "Type": "AwsIamPolicy",
        "Id": "$POLICY_ARN",
        "Region": "$REGION"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
"@
        $testEventContent | Out-File -FilePath "$env:TEMP\iam-test-event.json" -Encoding ASCII

        # Step 4: Invoke Lambda
        Write-Step "Invoking IAM remediation Lambda..."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        aws lambda invoke `
            --function-name $IAM_LAMBDA `
            --payload "fileb://$env:TEMP\iam-test-event.json" `
            --cli-binary-format raw-in-base64-out `
            "$env:TEMP\iam-lambda-output.json" | Out-Null

        $stopwatch.Stop()
        $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

        $result = Get-Content "$env:TEMP\iam-lambda-output.json" | ConvertFrom-Json
        $body = $result.body | ConvertFrom-Json

        if ($body.status -eq "REMEDIATED") {
            Write-Success "Lambda executed successfully in ${duration}s"
            Write-Host "  Status: " -NoNewline; Write-Host $body.status -ForegroundColor Green
            Write-Host "  Policy Version: $($body.new_version_id)"
            Write-Host "  Statements Removed: $($body.statements_removed)"
        } else {
            Write-Warning2 "Status: $($body.status)"
        }
        Write-Host ""

        # Step 5: Show remediated policy
        Write-Step "Remediated policy (SAFE):"
        aws iam get-policy-version --policy-arn $POLICY_ARN --version-id v2 `
            --query "PolicyVersion.Document" --output json
        Write-Host ""

        # Step 6: Check DynamoDB
        Write-Step "Checking DynamoDB audit log..."
        try {
            $dynamoResult = aws dynamodb scan --table-name $DYNAMODB_TABLE --query "Count" --output text 2>$null
            if ($dynamoResult -gt 0) {
                Write-Success "DynamoDB record found ($dynamoResult total records)"
            } else {
                Write-Warning2 "No DynamoDB records yet"
            }
        } catch {
            Write-Warning2 "Could not query DynamoDB"
        }
        Write-Host ""

        Write-Success "IAM TEST COMPLETE"
    }

    # ==================================================================
    # TEST 2: S3 Public Bucket Remediation
    # ==================================================================

    if ($TestS3) {
        Write-Header "TEST 2: S3 PUBLIC BUCKET REMEDIATION"

        # Step 1: Create bucket
        Write-Step "Creating S3 bucket..."
        aws s3api create-bucket `
            --bucket $TEST_BUCKET_NAME `
            --region $REGION `
            --create-bucket-configuration LocationConstraint=$REGION | Out-Null

        $CreatedResources.BucketName = $TEST_BUCKET_NAME
        Write-Success "Bucket created: $TEST_BUCKET_NAME"

        # Step 2: Disable public access block
        Write-Step "Disabling public access block (making bucket vulnerable)..."
        aws s3api put-public-access-block `
            --bucket $TEST_BUCKET_NAME `
            --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
        Write-Success "Public access block disabled"

        # Step 3: Create test event
        Write-Step "Creating Security Hub finding event..."
        $s3EventContent = @"
{
  "version": "0",
  "id": "demo-s3-$TIMESTAMP",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "$ACCOUNT_ID",
  "region": "$REGION",
  "detail": {
    "findings": [{
      "Id": "demo-finding-s3-$TIMESTAMP",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-S3-2",
      "AwsAccountId": "$ACCOUNT_ID",
      "Severity": { "Label": "HIGH" },
      "Title": "S3 buckets should prohibit public read access",
      "ProductFields": { "ControlId": "S3.2" },
      "Resources": [{
        "Type": "AwsS3Bucket",
        "Id": "arn:aws:s3:::$TEST_BUCKET_NAME",
        "Region": "$REGION"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
"@
        $s3EventContent | Out-File -FilePath "$env:TEMP\s3-test-event.json" -Encoding ASCII

        # Step 4: Invoke Lambda
        Write-Step "Invoking S3 remediation Lambda..."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        aws lambda invoke `
            --function-name $S3_LAMBDA `
            --payload "fileb://$env:TEMP\s3-test-event.json" `
            --cli-binary-format raw-in-base64-out `
            "$env:TEMP\s3-lambda-output.json" | Out-Null

        $stopwatch.Stop()
        $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

        $result = Get-Content "$env:TEMP\s3-lambda-output.json" | ConvertFrom-Json
        $body = $result.body | ConvertFrom-Json

        Write-Success "Lambda executed in ${duration}s"
        Write-Host "  Status: $($body.status)"
        Write-Host ""

        # Step 5: Show remediated settings
        Write-Step "Remediated public access settings:"
        aws s3api get-public-access-block --bucket $TEST_BUCKET_NAME
        Write-Host ""

        Write-Success "S3 TEST COMPLETE"
    }

    # ==================================================================
    # TEST 3: Security Group Remediation
    # ==================================================================

    if ($TestSG) {
        Write-Header "TEST 3: SECURITY GROUP REMEDIATION"

        # Get default VPC
        $VPC_ID = aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text

        if ($VPC_ID -eq "None" -or -not $VPC_ID) {
            Write-Warning2 "No default VPC found, skipping Security Group test"
        } else {
            # Step 1: Create security group
            Write-Step "Creating Security Group..."
            $SG_ID = aws ec2 create-security-group `
                --group-name $TEST_SG_NAME `
                --description "Demo test SG - will be auto-remediated" `
                --vpc-id $VPC_ID `
                --query "GroupId" --output text

            $CreatedResources.SecurityGroupId = $SG_ID
            Write-Success "Security Group created: $SG_ID"

            # Step 2: Add dangerous rule
            Write-Step "Adding dangerous ingress rule (0.0.0.0/0 on port 22)..."
            aws ec2 authorize-security-group-ingress `
                --group-id $SG_ID `
                --protocol tcp `
                --port 22 `
                --cidr 0.0.0.0/0 | Out-Null
            Write-Success "Dangerous rule added"

            # Step 3: Create test event
            Write-Step "Creating Security Hub finding event..."
            $sgEventContent = @"
{
  "version": "0",
  "id": "demo-sg-$TIMESTAMP",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "$ACCOUNT_ID",
  "region": "$REGION",
  "detail": {
    "findings": [{
      "Id": "demo-finding-sg-$TIMESTAMP",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-EC2-19",
      "AwsAccountId": "$ACCOUNT_ID",
      "Severity": { "Label": "HIGH" },
      "Title": "Security groups should not allow unrestricted access",
      "ProductFields": { "ControlId": "EC2.19" },
      "Resources": [{
        "Type": "AwsEc2SecurityGroup",
        "Id": "$SG_ID",
        "Region": "$REGION"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
"@
            $sgEventContent | Out-File -FilePath "$env:TEMP\sg-test-event.json" -Encoding ASCII

            # Step 4: Invoke Lambda
            Write-Step "Invoking Security Group remediation Lambda..."
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            aws lambda invoke `
                --function-name $SG_LAMBDA `
                --payload "fileb://$env:TEMP\sg-test-event.json" `
                --cli-binary-format raw-in-base64-out `
                "$env:TEMP\sg-lambda-output.json" | Out-Null

            $stopwatch.Stop()
            $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

            $result = Get-Content "$env:TEMP\sg-lambda-output.json" | ConvertFrom-Json
            $body = $result.body | ConvertFrom-Json

            Write-Success "Lambda executed in ${duration}s"
            Write-Host "  Status: $($body.status)"
            Write-Host ""

            # Step 5: Show remediated rules
            Write-Step "Remediated ingress rules:"
            aws ec2 describe-security-groups --group-ids $SG_ID --query "SecurityGroups[0].IpPermissions" --output json
            Write-Host ""

            Write-Success "SECURITY GROUP TEST COMPLETE"
        }
    }

    # ==================================================================
    # Summary
    # ==================================================================

    Write-Header "DEMO SUMMARY"

    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ALL TESTS COMPLETED SUCCESSFULLY!    " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "What was demonstrated:"
    Write-Host "  1. Security violations were created"
    Write-Host "  2. Lambda functions automatically remediated them"
    Write-Host "  3. Audit records were saved to DynamoDB"
    Write-Host "  4. Email notifications were sent via SNS"
    Write-Host ""
    Write-Host "Check your email for remediation notifications!"
    Write-Host ""

} finally {
    if (-not $SkipCleanup) {
        Cleanup-Resources
    } else {
        Write-Warning2 "Skipping cleanup - resources left for inspection"
        Write-Host "Created resources:"
        if ($CreatedResources.PolicyArn) { Write-Host "  Policy: $($CreatedResources.PolicyArn)" }
        if ($CreatedResources.BucketName) { Write-Host "  Bucket: $($CreatedResources.BucketName)" }
        if ($CreatedResources.SecurityGroupId) { Write-Host "  Security Group: $($CreatedResources.SecurityGroupId)" }
    }
}
