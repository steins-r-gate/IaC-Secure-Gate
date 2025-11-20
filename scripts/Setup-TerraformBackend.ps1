# Setup-TerraformBackend.ps1
# Sets up secure Terraform backend with S3 and DynamoDB for IAM-Secure-Gate project

param(
    [Parameter(Mandatory=$false)]
    [string]$Profile = "IAM-Secure-Gate",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu-west-1",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-AWSResource {
    param(
        [string]$Command,
        [string]$ResourceName,
        [string]$ResourceType
    )
    
    try {
        $result = Invoke-Expression $Command 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput " $ResourceType '$ResourceName' already exists" "Green"
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

Write-ColorOutput "=====================================" "Cyan"
Write-ColorOutput " Terraform Backend Setup" "Cyan"
Write-ColorOutput " Environment: $Environment" "Cyan"
Write-ColorOutput "=====================================" "Cyan"
Write-Host ""

# Validate prerequisites
Write-ColorOutput "Checking prerequisites..." "Yellow"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-ColorOutput " AWS CLI not installed" "Red"
    exit 1
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-ColorOutput " Terraform not installed" "Red"
    exit 1
}

Write-ColorOutput " Prerequisites OK" "Green"
Write-Host ""

# Set AWS environment
$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $Region

# Get and validate account ID
Write-ColorOutput "Validating AWS credentials..." "Yellow"
try {
    $accountId = aws sts get-caller-identity --query Account --output text 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($accountId)) {
        throw "Failed to get AWS account ID"
    }
    
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-ColorOutput " AWS Account: $accountId" "Green"
    Write-ColorOutput "   User/Role: $($identity.Arn.Split('/')[-1])" "White"
    Write-Host ""
} catch {
    Write-ColorOutput " Failed to validate AWS credentials" "Red"
    Write-ColorOutput "   Run: aws configure --profile $Profile" "Yellow"
    exit 1
}

# Define resource names
$bucketName = "iam-security-terraform-state-$accountId"
$tableName = "iam-security-terraform-locks"
$logsBucketName = "iam-security-terraform-logs-$accountId"

Write-ColorOutput "Resource Configuration:" "Cyan"
Write-ColorOutput "  State Bucket:  $bucketName" "White"
Write-ColorOutput "  Logs Bucket:   $logsBucketName" "White"
Write-ColorOutput "  Lock Table:    $tableName" "White"
Write-ColorOutput "  Region:        $Region" "White"
Write-Host ""

# Check if resources already exist
$bucketExists = Test-AWSResource `
    -Command "aws s3api head-bucket --bucket $bucketName 2>&1" `
    -ResourceName $bucketName `
    -ResourceType "S3 Bucket"

$tableExists = Test-AWSResource `
    -Command "aws dynamodb describe-table --table-name $tableName 2>&1" `
    -ResourceName $tableName `
    -ResourceType "DynamoDB Table"

if ($bucketExists -and $tableExists -and -not $Force) {
    Write-Host ""
    Write-ColorOutput " Backend infrastructure already exists" "Green"
    Write-ColorOutput "   Use -Force to reconfigure" "Yellow"
    
    # Still create backend.tf if it doesn't exist
    $backendFile = "terraform\environments\$Environment\backend.tf"
    if (-not (Test-Path $backendFile)) {
        Write-ColorOutput "`nCreating backend configuration..." "Yellow"
        # Jump to backend.tf creation at the end
    } else {
        Write-Host ""
        Write-ColorOutput "Backend ready to use! Run:" "Green"
        Write-ColorOutput "  cd terraform\environments\$Environment" "Cyan"
        Write-ColorOutput "  terraform init" "Cyan"
        exit 0
    }
}

Write-Host ""
if (-not $Force) {
    Write-ColorOutput " This will create AWS resources (estimated cost: <$1/month)" "Yellow"
    $confirm = Read-Host "Continue? (yes/no)"
    if ($confirm -ne "yes") {
        Write-ColorOutput "Setup cancelled" "Yellow"
        exit 0
    }
}

Write-Host ""

# ============================================================================
# CREATE LOGS BUCKET (for access logging)
# ============================================================================
if (-not (Test-AWSResource -Command "aws s3api head-bucket --bucket $logsBucketName 2>&1" -ResourceName $logsBucketName -ResourceType "Logs Bucket")) {
    Write-ColorOutput "Creating logs bucket: $logsBucketName" "Yellow"
    
    try {
        if ($Region -eq "us-east-1") {
            aws s3api create-bucket --bucket $logsBucketName --region $Region
        } else {
            aws s3api create-bucket --bucket $logsBucketName --region $Region --create-bucket-configuration LocationConstraint=$Region
        }
        
        if ($LASTEXITCODE -ne 0) { throw "Failed to create logs bucket" }
        
        # Enable versioning on logs bucket
        aws s3api put-bucket-versioning --bucket $logsBucketName --versioning-configuration Status=Enabled
        
        # Block public access
        aws s3api put-public-access-block --bucket $logsBucketName --public-access-block-configuration `
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        # Enable encryption
        aws s3api put-bucket-encryption --bucket $logsBucketName --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
        
        # Add lifecycle policy for logs
        $logsLifecycle = @"
{
    "Rules": [{
        "Id": "DeleteOldLogs",
        "Status": "Enabled",
        "Prefix": "",
        "Transitions": [
            {
                "Days": 90,
                "StorageClass": "STANDARD_IA"
            }
        ],
        "Expiration": {
            "Days": 365
        }
    }]
}
"@
        $logsLifecycle | aws s3api put-bucket-lifecycle-configuration --bucket $logsBucketName --lifecycle-configuration file:///dev/stdin
        
        # Add tags
        aws s3api put-bucket-tagging --bucket $logsBucketName --tagging "TagSet=[
            {Key=Project,Value=IAM-Secure-Gate},
            {Key=Environment,Value=$Environment},
            {Key=ManagedBy,Value=Terraform},
            {Key=Purpose,Value=AccessLogs}
        ]"
        
        Write-ColorOutput " Logs bucket created and secured" "Green"
    } catch {
        Write-ColorOutput " Failed to create logs bucket: $($_.Exception.Message)" "Red"
        exit 1
    }
}

# ============================================================================
# CREATE STATE BUCKET
# ============================================================================
if (-not $bucketExists) {
    Write-ColorOutput "`nCreating state bucket: $bucketName" "Yellow"
    
    try {
        # Create bucket
        if ($Region -eq "us-east-1") {
            aws s3api create-bucket --bucket $bucketName --region $Region
        } else {
            aws s3api create-bucket --bucket $bucketName --region $Region --create-bucket-configuration LocationConstraint=$Region
        }
        
        if ($LASTEXITCODE -ne 0) { throw "Failed to create state bucket" }
        
        Write-ColorOutput "  ✓ Bucket created" "White"
        
        # Enable versioning (CRITICAL for state recovery)
        aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled
        Write-ColorOutput "  ✓ Versioning enabled" "White"
        
        # Block ALL public access (CRITICAL SECURITY)
        aws s3api put-public-access-block --bucket $bucketName --public-access-block-configuration `
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        Write-ColorOutput "  ✓ Public access blocked" "White"
        
        # Enable default encryption
        aws s3api put-bucket-encryption --bucket $bucketName --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
        Write-ColorOutput "  ✓ Encryption enabled" "White"
        
        # Enable access logging
        aws s3api put-bucket-logging --bucket $bucketName --bucket-logging-status '{
            "LoggingEnabled": {
                "TargetBucket": "'$logsBucketName'",
                "TargetPrefix": "terraform-state-access/"
            }
        }'
        Write-ColorOutput "  ✓ Access logging enabled" "White"
        
        # Add bucket policy to enforce secure transport
        $bucketPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureTransport",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$bucketName",
                "arn:aws:s3:::$bucketName/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Sid": "DenyUnencryptedObjectUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$bucketName/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        }
    ]
}
"@
        $bucketPolicy | aws s3api put-bucket-policy --bucket $bucketName --policy file:///dev/stdin
        Write-ColorOutput "  ✓ Security policies applied" "White"
        
        # Add lifecycle policy for old state versions
        $lifecycle = @"
{
    "Rules": [{
        "Id": "CleanupOldStateVersions",
        "Status": "Enabled",
        "Prefix": "",
        "NoncurrentVersionExpiration": {
            "NoncurrentDays": 90
        }
    }]
}
"@
        $lifecycle | aws s3api put-bucket-lifecycle-configuration --bucket $bucketName --lifecycle-configuration file:///dev/stdin
        Write-ColorOutput "  ✓ Lifecycle policy set (90 days retention)" "White"
        
        # Add tags
        aws s3api put-bucket-tagging --bucket $bucketName --tagging "TagSet=[
            {Key=Project,Value=IAM-Secure-Gate},
            {Key=Environment,Value=$Environment},
            {Key=ManagedBy,Value=Terraform},
            {Key=Purpose,Value=TerraformState},
            {Key=Critical,Value=true}
        ]"
        Write-ColorOutput "  ✓ Tags applied" "White"
        
        Write-ColorOutput " State bucket created and secured" "Green"
        
    } catch {
        Write-ColorOutput " Failed to create state bucket: $($_.Exception.Message)" "Red"
        
        # Cleanup on failure
        Write-ColorOutput "Cleaning up..." "Yellow"
        aws s3api delete-bucket --bucket $bucketName 2>$null
        
        exit 1
    }
}

# ============================================================================
# CREATE DYNAMODB TABLE (for state locking)
# ============================================================================
if (-not $tableExists) {
    Write-ColorOutput "`nCreating DynamoDB table: $tableName" "Yellow"
    
    try {
        aws dynamodb create-table `
            --table-name $tableName `
            --attribute-definitions AttributeName=LockID,AttributeType=S `
            --key-schema AttributeName=LockID,KeyType=HASH `
            --billing-mode PAY_PER_REQUEST `
            --region $Region `
            --tags Key=Project,Value=IAM-Secure-Gate Key=Environment,Value=$Environment Key=ManagedBy,Value=Terraform Key=Purpose,Value=StateLocking
        
        if ($LASTEXITCODE -ne 0) { throw "Failed to create DynamoDB table" }
        
        Write-ColorOutput "  ✓ Table created" "White"
        
        # Wait for table to be active
        Write-ColorOutput "  Waiting for table to be active..." "White"
        $maxAttempts = 30
        $attempt = 0
        
        do {
            Start-Sleep -Seconds 2
            $tableStatus = aws dynamodb describe-table --table-name $tableName --query "Table.TableStatus" --output text 2>$null
            $attempt++
            
            if ($tableStatus -eq "ACTIVE") {
                break
            }
            
            if ($attempt -ge $maxAttempts) {
                throw "Table creation timeout"
            }
        } while ($true)
        
        Write-ColorOutput "  ✓ Table is active" "White"
        
        # Enable point-in-time recovery
        aws dynamodb update-continuous-backups `
            --table-name $tableName `
            --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
        Write-ColorOutput "  ✓ Point-in-time recovery enabled" "White"
        
        Write-ColorOutput " DynamoDB table created and configured" "Green"
        
    } catch {
        Write-ColorOutput " Failed to create DynamoDB table: $($_.Exception.Message)" "Red"
        
        # Cleanup on failure
        Write-ColorOutput "Cleaning up..." "Yellow"
        aws dynamodb delete-table --table-name $tableName 2>$null
        
        exit 1
    }
}

# ============================================================================
# CREATE BACKEND CONFIGURATION FILES
# ============================================================================
Write-ColorOutput "`nCreating backend configuration..." "Yellow"

# Create backend.tf for the specified environment
$backendDir = "terraform\environments\$Environment"
$backendFile = Join-Path $backendDir "backend.tf"

if (-not (Test-Path $backendDir)) {
    Write-ColorOutput "  Directory not found: $backendDir" "Yellow"
    New-Item -ItemType Directory -Path $backendDir -Force | Out-Null
    Write-ColorOutput "  Created directory" "White"
}

$backendConfig = @"
# Auto-generated Terraform backend configuration
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# DO NOT EDIT MANUALLY - Managed by Setup-TerraformBackend.ps1

terraform {
  backend "s3" {
    bucket         = "$bucketName"
    key            = "$Environment/terraform.tfstate"
    region         = "$Region"
    dynamodb_table = "$tableName"
    encrypt        = true
    
    # Additional security settings
    acl = "private"
  }
}
"@

$backendConfig | Out-File -FilePath $backendFile -Encoding UTF8

Write-ColorOutput " Backend configuration created" "Green"
Write-ColorOutput "   Location: $backendFile" "White"

# Create backend config summary
$summaryFile = "terraform-backend-info.txt"
$summary = @"
====================================
 Terraform Backend Configuration
====================================
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Environment: $Environment
AWS Account: $accountId
Region: $Region

Resources:
  State Bucket:  $bucketName
  Logs Bucket:   $logsBucketName
  Lock Table:    $tableName

Security Features:
  ✓ S3 versioning enabled
  ✓ Public access blocked
  ✓ AES256 encryption
  ✓ HTTPS-only policy
  ✓ Access logging enabled
  ✓ State locking enabled
  ✓ Point-in-time recovery

State File Location:
  s3://$bucketName/$Environment/terraform.tfstate

Usage:
  cd terraform\environments\$Environment
  terraform init
  terraform plan

Cost Estimate:
  S3 Storage: ~$0.023/GB/month
  DynamoDB: Pay-per-request (minimal)
  Estimated: <$1/month

====================================
"@

$summary | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host ""
Write-ColorOutput "=====================================" "Green"
Write-ColorOutput "  BACKEND SETUP COMPLETE!" "Green"
Write-ColorOutput "=====================================" "Green"
Write-Host ""

Write-ColorOutput "Summary saved to: $summaryFile" "Cyan"
Write-Host ""

Write-ColorOutput "Next Steps:" "Yellow"
Write-ColorOutput "  1. cd terraform\environments\$Environment" "Cyan"
Write-ColorOutput "  2. terraform init" "Cyan"
Write-ColorOutput "  3. terraform plan" "Cyan"
Write-Host ""

Write-ColorOutput "Backend Info:" "White"
Write-ColorOutput "  State: s3://$bucketName/$Environment/terraform.tfstate" "White"
Write-ColorOutput "  Locks: DynamoDB table '$tableName'" "White"
Write-Host ""

# Verify setup
Write-ColorOutput "Verifying setup..." "Yellow"
$verificationPassed = $true

# Check bucket
$bucketCheck = aws s3api head-bucket --bucket $bucketName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput " State bucket verification failed" "Red"
    $verificationPassed = $false
} else {
    Write-ColorOutput "✅ State bucket accessible" "Green"
}

# Check table
$tableCheck = aws dynamodb describe-table --table-name $tableName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ColorOutput " DynamoDB table verification failed" "Red"
    $verificationPassed = $false
} else {
    Write-ColorOutput " DynamoDB table accessible" "Green"
}

# Check backend.tf
if (Test-Path $backendFile) {
    Write-ColorOutput " Backend configuration file exists" "Green"
} else {
    Write-ColorOutput " Backend configuration file not found" "Red"
    $verificationPassed = $false
}

Write-Host ""

if ($verificationPassed) {
    Write-ColorOutput " All verification checks passed!" "Green"
    exit 0
} else {
    Write-ColorOutput "  Some verification checks failed" "Yellow"
    Write-ColorOutput "   Review the output above" "White"
    exit 1
}