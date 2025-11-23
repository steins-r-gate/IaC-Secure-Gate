# Cleanup-Demo.ps1
param(
    [string]$StateFile,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

Write-Host "IAM SECURITY DEMO - CLEANUP" -ForegroundColor Yellow

# Find state file
if (-not $StateFile) {
    $stateFiles = Get-ChildItem -Filter "demo-state-*.json" | Sort-Object LastWriteTime -Descending
    if ($stateFiles.Count -eq 0) {
        Write-Host "No demo state files found" -ForegroundColor Red
        exit 1
    }
    $StateFile = $stateFiles[0].Name
}

# Load state
$demoState = Get-Content $StateFile | ConvertFrom-Json

if (-not $Force) {
    $confirm = Read-Host "Delete ALL demo resources? (yes/no)"
    if ($confirm -ne "yes") { exit 0 }
}

Write-Host "Starting cleanup..." -ForegroundColor Yellow

# Delete IAM policies
foreach ($policyArn in $demoState.IAMPolicies) {
    aws iam delete-policy --policy-arn $policyArn 2>$null
    Write-Host "  Deleted policy" -ForegroundColor Green
}

# Delete IAM roles  
foreach ($roleName in $demoState.IAMRoles) {
    aws iam delete-role --role-name $roleName 2>$null
    Write-Host "  Deleted role" -ForegroundColor Green
}

# Terraform destroy
if (Test-Path $demoState.TerraformDir) {
    Set-Location $demoState.TerraformDir
    terraform destroy -auto-approve | Out-Null
    Set-Location ..
    Remove-Item $demoState.TerraformDir -Recurse -Force
    Write-Host "  Terraform resources destroyed" -ForegroundColor Green
}

Remove-Item $StateFile -Force
Write-Host "CLEANUP COMPLETE" -ForegroundColor Green