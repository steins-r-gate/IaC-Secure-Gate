param(
    [Parameter(Mandatory=$false)]
    [string]$Profile = "IAM-Secure-Gate",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu-west-1"
)

Write-Host "Setting up Terraform Backend..." -ForegroundColor Yellow

# Set AWS environment
$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $Region

# Get account ID
$accountId = aws sts get-caller-identity --query Account --output text
Write-Host "Using AWS Account: $accountId" -ForegroundColor Cyan

# Create S3 bucket for state
$bucketName = "iam-security-terraform-state-$accountId"
Write-Host "Creating S3 bucket: $bucketName" -ForegroundColor Yellow

# Check if bucket exists
$bucketExists = aws s3api head-bucket --bucket $bucketName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Bucket already exists" -ForegroundColor Green
} else {
    # Create bucket with proper configuration for eu-west-1
    if ($Region -eq "us-east-1") {
        aws s3api create-bucket `
            --bucket $bucketName `
            --region $Region
    } else {
        aws s3api create-bucket `
            --bucket $bucketName `
            --region $Region `
            --create-bucket-configuration LocationConstraint=$Region
    }
    
    # Enable versioning
    aws s3api put-bucket-versioning `
        --bucket $bucketName `
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption `
        --bucket $bucketName `
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    Write-Host "✅ S3 bucket created and configured" -ForegroundColor Green
}

# Create DynamoDB table for state locking
$tableName = "iam-security-terraform-locks"
Write-Host "Creating DynamoDB table: $tableName" -ForegroundColor Yellow

# Check if table exists
$tableExists = aws dynamodb describe-table --table-name $tableName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Table already exists" -ForegroundColor Green
} else {
    aws dynamodb create-table `
        --table-name $tableName `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region
    
    Write-Host "✅ DynamoDB table created" -ForegroundColor Green
}

# Create backend configuration file
$backendConfig = @"
terraform {
  backend "s3" {
    bucket         = "$bucketName"
    key            = "dev/terraform.tfstate"
    region         = "$Region"
    dynamodb_table = "$tableName"
    encrypt        = true
  }
}
"@

$backendConfig | Out-File -FilePath "terraform\environments\dev\backend.tf" -Encoding UTF8
Write-Host "✅ Backend configuration created at terraform\environments\dev\backend.tf" -ForegroundColor Green

Write-Host "`n✅ Terraform backend setup complete!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. cd terraform\environments\dev" -ForegroundColor Cyan
Write-Host "  2. terraform init" -ForegroundColor Cyan
Write-Host "  3. terraform plan" -ForegroundColor Cyan
