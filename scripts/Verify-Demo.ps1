# scripts/Verify-Demo.ps1
# Simple verification that demo is working

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Continue"

function Write-Color {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Test-Check {
    param([string]$Name, [scriptblock]$Test)
    
    Write-Host "  Checking $Name... " -NoNewline
    try {
        $result = & $Test
        if ($result) {
            Write-Color "✅" "Green"
            return $true
        } else {
            Write-Color "❌" "Red"
            return $false
        }
    } catch {
        Write-Color "❌ Error: $_" "Red"
        return $false
    }
}

# Banner
Write-Color "`n╔═══════════════════════════════════════════════════╗" "Cyan"
Write-Color "║          DEMO VERIFICATION                        ║" "Cyan"
Write-Color "╚═══════════════════════════════════════════════════╝" "Cyan"
Write-Host ""

$checks = @{
    Passed = 0
    Failed = 0
}

# Check AWS credentials
$awsOk = Test-Check "AWS Credentials" {
    $identity = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
    return $null -ne $identity.Account
}
if ($awsOk) { $checks.Passed++ } else { $checks.Failed++ }

# Check Terraform
$tfOk = Test-Check "Terraform Installation" {
    $null -ne (Get-Command terraform -ErrorAction SilentlyContinue)
}
if ($tfOk) { $checks.Passed++ } else { $checks.Failed++ }

# Check Terraform directory
$tfDir = "terraform\environments\$Environment"
$tfDirOk = Test-Check "Terraform Directory" {
    Test-Path $tfDir
}
if ($tfDirOk) { $checks.Passed++ } else { $checks.Failed++ }

# Check Terraform state
if ($tfDirOk) {
    Push-Location $tfDir
    
    $tfInitOk = Test-Check "Terraform Initialized" {
        Test-Path ".terraform"
    }
    if ($tfInitOk) { $checks.Passed++ } else { $checks.Failed++ }
    
    $tfStateOk = Test-Check "Terraform State" {
        Test-Path "terraform.tfstate"
    }
    if ($tfStateOk) { $checks.Passed++ } else { $checks.Failed++ }
    
    # Check if resources exist
    if ($tfStateOk) {
        try {
            $outputs = terraform output -json 2>$null | ConvertFrom-Json
            $bucketName = $outputs.demo_bucket_name.value
            
            $bucketOk = Test-Check "S3 Bucket Exists" {
                $null = aws s3api head-bucket --bucket $bucketName 2>&1
                return $LASTEXITCODE -eq 0
            }
            if ($bucketOk) { $checks.Passed++ } else { $checks.Failed++ }
            
            # Check bucket configuration
            if ($bucketOk) {
                $versioningOk = Test-Check "Versioning Enabled" {
                    $ver = aws s3api get-bucket-versioning --bucket $bucketName | ConvertFrom-Json
                    return $ver.Status -eq "Enabled"
                }
                if ($versioningOk) { $checks.Passed++ } else { $checks.Failed++ }
                
                $encryptionOk = Test-Check "Encryption Enabled" {
                    $enc = aws s3api get-bucket-encryption --bucket $bucketName 2>$null | ConvertFrom-Json
                    return $null -ne $enc.Rules
                }
                if ($encryptionOk) { $checks.Passed++ } else { $checks.Failed++ }
                
                $publicBlockOk = Test-Check "Public Access Blocked" {
                    $block = aws s3api get-public-access-block --bucket $bucketName | ConvertFrom-Json
                    return $block.PublicAccessBlockConfiguration.BlockPublicAcls -and
                           $block.PublicAccessBlockConfiguration.BlockPublicPolicy
                }
                if ($publicBlockOk) { $checks.Passed++ } else { $checks.Failed++ }
            }
        } catch {
            Write-Color "  ⚠️  Could not verify deployed resources" "Yellow"
        }
    }
    
    Pop-Location
}

# Summary
Write-Host ""
Write-Color "═══════════════════════════════════════════════════" "Cyan"
Write-Color "VERIFICATION SUMMARY" "Cyan"
Write-Color "═══════════════════════════════════════════════════" "Cyan"

$total = $checks.Passed + $checks.Failed
$passRate = if ($total -gt 0) { [math]::Round(($checks.Passed / $total) * 100, 0) } else { 0 }

Write-Host "`nTotal Checks: $total" -ForegroundColor White
Write-Host "Passed: $($checks.Passed)" -ForegroundColor Green
Write-Host "Failed: $($checks.Failed)" -ForegroundColor $(if ($checks.Failed -eq 0) { "Green" } else { "Red" })
Write-Host "Success Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

Write-Host ""

if ($passRate -eq 100) {
    Write-Color "🎉 Demo is fully operational!" "Green"
    exit 0
} elseif ($passRate -ge 80) {
    Write-Color "✅ Demo is mostly working (minor issues)" "Yellow"
    exit 0
} else {
    Write-Color "❌ Demo has issues - run Deploy-Demo.ps1" "Red"
    exit 1
}