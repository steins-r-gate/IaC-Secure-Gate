# scripts/Cleanup-Demo.ps1
# Safe cleanup of demo resources

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Color {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-Color "`n========================================" "Yellow"
Write-Color "  DEMO CLEANUP" "Yellow"
Write-Color "========================================" "Yellow"
Write-Host ""

$deploymentFile = "scripts\.last-deployment.json"
$deploymentInfo = $null

if (Test-Path $deploymentFile) {
    try {
        $deploymentInfo = Get-Content $deploymentFile -Raw | ConvertFrom-Json
        Write-Color "Found previous deployment:" "Cyan"
        Write-Host "  Environment:  $($deploymentInfo.Environment)" -ForegroundColor White
        Write-Host "  Bucket:       $($deploymentInfo.BucketName)" -ForegroundColor White
        Write-Host "  Deployed:     $($deploymentInfo.Timestamp)" -ForegroundColor White
        Write-Host ""
    } catch {
        Write-Color "Could not load deployment info" "Yellow"
    }
}

if (-not $Force) {
    Write-Color "WARNING: This will DELETE all demo resources!" "Yellow"
    Write-Host ""
    $confirm = Read-Host "Continue with cleanup? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Color "`nCleanup cancelled" "Cyan"
        exit 0
    }
}

$tfDir = "terraform\environments\$Environment"

if (-not (Test-Path $tfDir)) {
    Write-Color "Terraform directory not found: $tfDir" "Red"
    exit 1
}

Write-Color "`nNavigating to $tfDir..." "Cyan"
Push-Location $tfDir

if (-not (Test-Path ".terraform")) {
    Write-Color "Terraform not initialized - nothing to clean up" "Yellow"
    Pop-Location
    if (Test-Path "..\..\..\$deploymentFile") {
        Remove-Item "..\..\..\$deploymentFile" -Force -ErrorAction SilentlyContinue
    }
    Write-Color "Local cleanup complete`n" "Green"
    exit 0
}

if (-not (Test-Path "terraform.tfstate")) {
    Write-Color "No Terraform state found - nothing to destroy" "Yellow"
    Pop-Location
    Write-Color "`nCleaning up Terraform files..." "Cyan"
    Push-Location $tfDir
    Remove-Item ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ".terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
    Pop-Location
    Write-Color "Cleanup complete`n" "Green"
    exit 0
}

Write-Color "`nGenerating destruction plan..." "Yellow"
terraform plan -destroy

Write-Host ""
Write-Color "========================================" "Yellow"
Write-Color "Ready to destroy resources" "Yellow"
Write-Color "========================================" "Yellow"

if (-not $Force) {
    Write-Host ""
    $finalConfirm = Read-Host "Type DELETE to confirm destruction"
    
    if ($finalConfirm -ne "DELETE") {
        Write-Color "`nCleanup cancelled" "Cyan"
        Pop-Location
        exit 0
    }
}

Write-Color "`nDestroying resources..." "Red"
Write-Host ""

terraform destroy -auto-approve

if ($LASTEXITCODE -eq 0) {
    Write-Color "`n========================================" "Green"
    Write-Color "  CLEANUP SUCCESSFUL!" "Green"
    Write-Color "========================================" "Green"
    
    Write-Host "`nAll demo resources have been removed:" -ForegroundColor Cyan
    Write-Host "  - S3 bucket deleted" -ForegroundColor White
    Write-Host "  - Security configurations removed" -ForegroundColor White
    Write-Host "  - Terraform state cleared" -ForegroundColor White
    
    Write-Color "`nCleaning up local files..." "Cyan"
    Remove-Item ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ".terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
    Remove-Item "terraform.tfstate*" -Force -ErrorAction SilentlyContinue
    Remove-Item "tfplan" -Force -ErrorAction SilentlyContinue
    Write-Host "  - Local Terraform files cleaned" -ForegroundColor White
    
    Pop-Location
    if (Test-Path $deploymentFile) {
        Remove-Item $deploymentFile -Force -ErrorAction SilentlyContinue
        Write-Host "  - Deployment info cleared" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Color "Demo environment cleaned up successfully!`n" "Green"
    exit 0
}

Write-Color "`nCleanup failed!" "Red"
Write-Color "Some resources may still exist. Check AWS Console." "Yellow"
Write-Color "`nManual cleanup steps:" "Yellow"
Write-Host "  1. Go to S3 Console" -ForegroundColor White
Write-Host "  2. Search for buckets: iam-security-$Environment-demo-*" -ForegroundColor White
Write-Host "  3. Empty and delete manually" -ForegroundColor White
Write-Host "  4. Run: terraform destroy -auto-approve" -ForegroundColor White
Pop-Location
exit 1
