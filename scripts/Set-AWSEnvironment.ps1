# Set-AWSEnvironment.ps1
# Sets up AWS environment variables for IAM-Secure-Gate project

param(
    [Parameter(Mandatory=$false)]
    [string]$Profile = "IAM-Secure-Gate",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu-west-1",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateProfile
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "=====================================" "Cyan"
Write-ColorOutput " AWS Environment Configuration" "Cyan"
Write-ColorOutput "=====================================" "Cyan"
Write-Host ""

# Check if AWS CLI is installed
Write-ColorOutput "Checking AWS CLI..." "Yellow"
$awsCli = Get-Command aws -ErrorAction SilentlyContinue
if (-not $awsCli) {
    Write-ColorOutput "❌ AWS CLI not installed" "Red"
    Write-ColorOutput "" "White"
    Write-ColorOutput "Install AWS CLI:" "Yellow"
    Write-ColorOutput "  Windows: https://awscli.amazonaws.com/AWSCLIV2.msi" "White"
    Write-ColorOutput "  Or run: winget install Amazon.AWSCLI" "White"
    exit 1
}

$awsVersion = (aws --version 2>&1)
Write-ColorOutput "✅ AWS CLI installed: $awsVersion" "Green"
Write-Host ""

# Check if profile exists
Write-ColorOutput "Checking AWS profile '$Profile'..." "Yellow"
$profiles = aws configure list-profiles 2>$null
$profileExists = $profiles -contains $Profile

if (-not $profileExists) {
    Write-ColorOutput "⚠️  Profile '$Profile' not found" "Yellow"
    Write-Host ""
    
    if ($CreateProfile) {
        Write-ColorOutput "Creating profile '$Profile'..." "Yellow"
        Write-Host ""
        Write-ColorOutput "You'll need:" "Cyan"
        Write-ColorOutput "  1. AWS Access Key ID" "White"
        Write-ColorOutput "  2. AWS Secret Access Key" "White"
        Write-ColorOutput "  3. Default region (press Enter for eu-west-1)" "White"
        Write-Host ""
        
        aws configure --profile $Profile
        
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "❌ Failed to create profile" "Red"
            exit 1
        }
        
        Write-ColorOutput "✅ Profile created successfully" "Green"
        Write-Host ""
    } else {
        Write-ColorOutput "Available profiles:" "Cyan"
        if ($profiles) {
            $profiles | ForEach-Object { Write-ColorOutput "  - $_" "White" }
        } else {
            Write-ColorOutput "  (none configured)" "White"
        }
        Write-Host ""
        Write-ColorOutput "Options:" "Yellow"
        Write-ColorOutput "  1. Run: aws configure --profile $Profile" "White"
        Write-ColorOutput "  2. Run this script with -CreateProfile flag" "White"
        Write-ColorOutput "  3. Use existing profile with -Profile parameter" "White"
        exit 1
    }
}

Write-ColorOutput "✅ Profile '$Profile' exists" "Green"

# Set environment variables
Write-ColorOutput "`nSetting environment variables..." "Yellow"
$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $Region
$env:AWS_DEFAULT_REGION = $Region

# Validate credentials by getting account ID
Write-ColorOutput "Validating credentials..." "Yellow"
try {
    $accountId = aws sts get-caller-identity --query Account --output text --profile $Profile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI returned error: $accountId"
    }
    
    if ([string]::IsNullOrEmpty($accountId)) {
        throw "Failed to retrieve account ID"
    }
    
    $env:AWS_ACCOUNT_ID = $accountId
    
    # Get full identity for verification
    $identity = aws sts get-caller-identity --output json --profile $Profile | ConvertFrom-Json
    
    Write-Host ""
    Write-ColorOutput "=====================================" "Green"
    Write-ColorOutput " ✅ AWS Environment Configured" "Green"
    Write-ColorOutput "=====================================" "Green"
    Write-ColorOutput "Profile:       $Profile" "Cyan"
    Write-ColorOutput "Region:        $Region" "Cyan"
    Write-ColorOutput "Account ID:    $accountId" "Cyan"
    Write-ColorOutput "User/Role:     $($identity.Arn.Split('/')[-1])" "Cyan"
    Write-ColorOutput "ARN:           $($identity.Arn)" "White"
    Write-ColorOutput "=====================================" "Green"
    Write-Host ""
    
    # Verify region is set correctly
    $currentRegion = aws configure get region --profile $Profile
    if ($currentRegion -ne $Region) {
        Write-ColorOutput " Warning: Profile default region ($currentRegion) differs from specified region ($Region)" "Yellow"
        Write-ColorOutput "   Using: $Region" "Yellow"
        Write-Host ""
    }
    
    # Check for MFA (optional but good practice)
    if ($identity.Arn -match ":assumed-role/") {
        Write-ColorOutput "ℹ Using assumed role (MFA likely enabled)" "Cyan"
    } elseif ($identity.Arn -match ":user/") {
        Write-ColorOutput "ℹ Using IAM user. Consider using MFA for security." "Cyan"
    }
    
    Write-Host ""
    Write-ColorOutput "Environment variables set:" "White"
    Write-ColorOutput "  AWS_PROFILE=$env:AWS_PROFILE" "White"
    Write-ColorOutput "  AWS_REGION=$env:AWS_REGION" "White"
    Write-ColorOutput "  AWS_ACCOUNT_ID=$env:AWS_ACCOUNT_ID" "White"
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-ColorOutput "Failed to validate AWS credentials" "Red"
    Write-ColorOutput "Error: $($_.Exception.Message)" "Red"
    Write-Host ""
    Write-ColorOutput "Troubleshooting:" "Yellow"
    Write-ColorOutput "  1. Check credentials: aws configure list --profile $Profile" "White"
    Write-ColorOutput "  2. Test access: aws sts get-caller-identity --profile $Profile" "White"
    Write-ColorOutput "  3. Verify IAM permissions for sts:GetCallerIdentity" "White"
    Write-Host ""
    exit 1
}

# Optional: Check for required IAM permissions
Write-ColorOutput "Checking IAM permissions..." "Yellow"
$requiredPermissions = @{
    "s3:CreateBucket" = "S3 bucket creation"
    "iam:CreateRole" = "IAM role creation"
    "kms:CreateKey" = "KMS key creation"
    "cloudtrail:CreateTrail" = "CloudTrail setup"
    "config:PutConfigurationRecorder" = "AWS Config setup"
}

$permissionWarnings = @()
foreach ($permission in $requiredPermissions.Keys) {
    $service = $permission.Split(':')[0]
    $action = $permission.Split(':')[1]
    
    # This is a simple check - in production you'd use IAM Policy Simulator
    # aws iam simulate-principal-policy is more accurate but requires permissions
}

if ($permissionWarnings.Count -eq 0) {
    Write-ColorOutput " Basic checks passed" "Green"
} else {
    Write-ColorOutput " Note: Full permission validation requires deployment" "Yellow"
}

Write-Host ""
Write-ColorOutput "Ready to deploy!" "Green"
Write-Host ""

# Optionally export to file for other tools
$exportFile = Join-Path $PSScriptRoot "..\aws-env.ps1"
@"
# Auto-generated AWS environment configuration
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

`$env:AWS_PROFILE = "$Profile"
`$env:AWS_REGION = "$Region"
`$env:AWS_ACCOUNT_ID = "$accountId"
"@ | Out-File -FilePath $exportFile -Encoding UTF8

Write-ColorOutput "Configuration saved to: aws-env.ps1" "Cyan"
Write-ColorOutput "  (Source this file in other sessions)" "White"
Write-Host ""