# scripts/Deploy-Demo.ps1
# Simplified deployment script for commission demo

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"

function Write-Color {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n> " -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

Clear-Host
Write-Color "`n========================================" "Cyan"
Write-Color "  IAM-SECURE-GATE DEMO DEPLOYMENT" "Cyan"
Write-Color "  Simple S3 Bucket Demo" "Cyan"
Write-Color "========================================" "Cyan"
Write-Host ""

$startTime = Get-Date

Write-Step "Checking AWS credentials..."
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    $accountId = $identity.Account
    Write-Color "  OK - Account ID: $accountId" "Green"
} catch {
    Write-Color "  ERROR - AWS credentials not configured" "Red"
    Write-Color "`n  Run first: .\Set-AWSEnvironment.ps1" "Yellow"
    exit 1
}

Write-Step "Checking Terraform..."
try {
    $tfVersion = terraform version -json | ConvertFrom-Json
    Write-Color "  OK - Terraform v$($tfVersion.terraform_version)" "Green"
} catch {
    Write-Color "  ERROR - Terraform not installed" "Red"
    Write-Color "`n  Install from: https://www.terraform.io/downloads" "Yellow"
    exit 1
}

$tfDir = "terraform\environments\$Environment"
Write-Step "Navigating to $tfDir..."

if (-not (Test-Path $tfDir)) {
    Write-Color "  ERROR - Directory not found: $tfDir" "Red"
    exit 1
}

Push-Location $tfDir
Write-Color "  OK - In directory: $tfDir" "Green"

Write-Step "Initializing Terraform..."
try {
    terraform init -upgrade 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Init failed" }
    Write-Color "  OK - Terraform initialized" "Green"
} catch {
    Write-Color "  ERROR - Terraform initialization failed" "Red"
    Pop-Location
    exit 1
}

Write-Step "Validating Terraform configuration..."
try {
    $validation = terraform validate -json | ConvertFrom-Json
    if ($validation.valid) {
        Write-Color "  OK - Configuration valid" "Green"
    } else {
        Write-Color "  ERROR - Configuration invalid" "Red"
        Write-Color "  Errors: $($validation.error_message)" "Red"
        Pop-Location
        exit 1
    }
} catch {
    Write-Color "  ERROR - Validation failed" "Red"
    Pop-Location
    exit 1
}

Write-Step "Generating deployment plan..."
Write-Host ""
terraform plan -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Color "`n  ERROR - Planning failed" "Red"
    Pop-Location
    exit 1
}

if (-not $AutoApprove) {
    Write-Host ""
    Write-Color "========================================" "Yellow"
    Write-Color "Ready to deploy!" "Yellow"
    Write-Color "========================================" "Yellow"
    Write-Host "`nThis will create:" -ForegroundColor Cyan
    Write-Host "  - 1 S3 bucket with security best practices" -ForegroundColor White
    Write-Host "  - Encryption enabled (AES256)" -ForegroundColor White
    Write-Host "  - Versioning enabled" -ForegroundColor White
    Write-Host "  - Public access blocked" -ForegroundColor White
    Write-Host "  - HTTPS-only policy" -ForegroundColor White
    Write-Host ""
    
    $confirm = Read-Host "Deploy now? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Color "`nDeployment cancelled" "Yellow"
        Pop-Location
        exit 0
    }
}

Write-Step "Deploying infrastructure..."
Write-Host ""
terraform apply tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Color "`n  ERROR - Deployment failed" "Red"
    Pop-Location
    exit 1
}

Write-Step "Retrieving deployment information..."
$bucketName = $null
try {
    $outputs = terraform output -json | ConvertFrom-Json
    $bucketName = $outputs.demo_bucket_name.value
    
    Write-Color "`n========================================" "Green"
    Write-Color "  DEPLOYMENT SUCCESSFUL!" "Green"
    Write-Color "========================================" "Green"
    
    Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
    Write-Host "  Environment:  $Environment" -ForegroundColor White
    Write-Host "  AWS Account:  $accountId" -ForegroundColor White
    Write-Host "  Region:       $($outputs.aws_region.value)" -ForegroundColor White
    
    Write-Host "`nCreated Resources:" -ForegroundColor Cyan
    Write-Host "  S3 Bucket:    $bucketName" -ForegroundColor White
    Write-Host "  Bucket ARN:   $($outputs.demo_bucket_arn.value)" -ForegroundColor Gray
    
    Write-Host "`nAWS Console:" -ForegroundColor Cyan
    $consoleUrl = $outputs.demo_bucket_url.value
    Write-Host "  View Bucket:  $consoleUrl" -ForegroundColor Blue
    
    $duration = (Get-Date) - $startTime
    Write-Host "`nDeployment completed in $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor Green
    
    Write-Host ""
    Write-Color "========================================" "Cyan"
    Write-Color "Next Steps for Commission Demo:" "Cyan"
    Write-Color "========================================" "Cyan"
    Write-Host "  1. Open the bucket in AWS Console (link above)" -ForegroundColor White
    Write-Host "  2. Show encryption settings" -ForegroundColor White
    Write-Host "  3. Show versioning enabled" -ForegroundColor White
    Write-Host "  4. Show public access blocked" -ForegroundColor White
    Write-Host "  5. Show bucket policy (HTTPS-only)" -ForegroundColor White
    Write-Host "`n  When done: .\Cleanup-Demo.ps1" -ForegroundColor Yellow
    Write-Color "========================================`n" "Cyan"
    
} catch {
    Write-Color "`n  WARNING - Deployment succeeded but could not retrieve outputs" "Yellow"
    Write-Color "  Error: $_" "Gray"
}

Pop-Location

if ($bucketName) {
    try {
        $deploymentInfo = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Environment = $Environment
            AccountId = $accountId
            BucketName = $bucketName
            TerraformDir = $tfDir
        } | ConvertTo-Json

        $deploymentInfo | Out-File -FilePath "scripts\.last-deployment.json" -Encoding UTF8
        Write-Color "Deployment information saved for cleanup`n" "Green"
    } catch {
        Write-Color "WARNING - Could not save deployment info" "Yellow"
    }
}

exit 0
