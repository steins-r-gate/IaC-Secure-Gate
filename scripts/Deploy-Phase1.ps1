param(
    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " IAM Security Pipeline - Phase 1" -ForegroundColor Cyan
Write-Host " Deployment Script" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$terraform = Get-Command terraform -ErrorAction SilentlyContinue
if (-not $terraform) {
    Write-Host "❌ Terraform not found. Please install Terraform first." -ForegroundColor Red
    exit 1
}

$aws = Get-Command aws -ErrorAction SilentlyContinue
if (-not $aws) {
    Write-Host "❌ AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    exit 1
}

# Set AWS environment
.\scripts\Set-AWSEnvironment.ps1

# Change to Terraform directory
Set-Location "terraform\environments\$Environment"

# Check if backend is configured
if (-not (Test-Path "backend.tf")) {
    Write-Host "Backend not configured. Running setup..." -ForegroundColor Yellow
    Set-Location ..\..\..
    .\scripts\Setup-TerraformBackend.ps1
    Set-Location "terraform\environments\$Environment"
}

# Initialize Terraform
Write-Host "`nInitializing Terraform..." -ForegroundColor Yellow
terraform init

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Terraform init failed" -ForegroundColor Red
    exit 1
}

# Validate configuration
Write-Host "`nValidating Terraform configuration..." -ForegroundColor Yellow
terraform validate

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Terraform validation failed" -ForegroundColor Red
    exit 1
}

# Create tfvars if not exists
if (-not (Test-Path "terraform.tfvars")) {
    Write-Host "`nCreating terraform.tfvars..." -ForegroundColor Yellow
    Copy-Item "terraform.tfvars.example" "terraform.tfvars"
    Write-Host "⚠️ Please edit terraform.tfvars with your email addresses" -ForegroundColor Yellow
    notepad terraform.tfvars
    Read-Host "Press Enter after updating terraform.tfvars"
}

# Plan deployment
Write-Host "`nPlanning infrastructure changes..." -ForegroundColor Yellow
terraform plan -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Terraform plan failed" -ForegroundColor Red
    exit 1
}

# Show plan summary
Write-Host "`n📋 Plan Summary:" -ForegroundColor Cyan
terraform show -no-color tfplan | Select-String -Pattern "Plan:|No changes" 

# Apply changes
if ($AutoApprove) {
    Write-Host "`nApplying changes..." -ForegroundColor Yellow
    terraform apply tfplan
} else {
    Write-Host "`n⚠️ Review the plan above carefully" -ForegroundColor Yellow
    $confirm = Read-Host "Do you want to apply these changes? (yes/no)"
    if ($confirm -eq "yes") {
        terraform apply tfplan
    } else {
        Write-Host "Deployment cancelled" -ForegroundColor Yellow
        exit 0
    }
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Phase 1 deployment successful!" -ForegroundColor Green
    
    # Save outputs
    terraform output -json | Out-File -FilePath "..\..\..\outputs.json" -Encoding UTF8
    Write-Host "Outputs saved to outputs.json" -ForegroundColor Cyan
    
    # Return to root
    Set-Location ..\..\..
    
    # Run verification
    Write-Host "`nRunning verification..." -ForegroundColor Yellow
    .\scripts\Verify-Phase1.ps1
} else {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    Set-Location ..\..\..
    exit 1
}
