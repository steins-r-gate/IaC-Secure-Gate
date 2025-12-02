# scripts/Set-AWSEnvironment.ps1
# Simplified AWS environment setup for demo

param(
    [Parameter(Mandatory=$false)]
    [string]$Profile = "default",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu-west-1"
)

$ErrorActionPreference = "Stop"

function Write-Color {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-Color "`n========================================" "Cyan"
Write-Color "  AWS Environment Setup" "Cyan"
Write-Color "========================================" "Cyan"

# Check AWS CLI
Write-Color "`nChecking AWS CLI..." "Yellow"
try {
    $awsVersion = aws --version 2>&1
    Write-Color "✅ AWS CLI installed: $($awsVersion.Split()[0])" "Green"
} catch {
    Write-Color "❌ AWS CLI not installed" "Red"
    Write-Color "`nInstall with: winget install Amazon.AWSCLI" "Yellow"
    exit 1
}

# Check credentials
Write-Color "`nValidating AWS credentials..." "Yellow"
try {
    $identity = aws sts get-caller-identity --profile $Profile --output json 2>&1 | ConvertFrom-Json
    
    if (-not $identity.Account) {
        throw "No valid credentials"
    }
    
    $accountId = $identity.Account
    $userArn = $identity.Arn
    
    Write-Color "✅ Credentials valid" "Green"
    Write-Color "`nAWS Account Information:" "Cyan"
    Write-Color "  Account ID: $accountId" "White"
    Write-Color "  Region:     $Region" "White"
    Write-Color "  User/Role:  $($userArn.Split('/')[-1])" "White"
    Write-Color "  ARN:        $userArn" "Gray"
    
    # Set environment variables
    $env:AWS_PROFILE = $Profile
    $env:AWS_REGION = $Region
    $env:AWS_DEFAULT_REGION = $Region
    $env:AWS_ACCOUNT_ID = $accountId
    
    Write-Color "`n✅ Environment configured successfully!" "Green"
    Write-Color "`nEnvironment Variables Set:" "Cyan"
    Write-Color "  AWS_PROFILE = $Profile" "White"
    Write-Color "  AWS_REGION = $Region" "White"
    Write-Color "  AWS_ACCOUNT_ID = $accountId" "White"
    
} catch {
    Write-Color "❌ AWS credentials not configured or invalid" "Red"
    Write-Color "`nError: $_" "Red"
    Write-Color "`nSetup Options:" "Yellow"
    Write-Color "  1. Configure default profile: aws configure" "White"
    Write-Color "  2. Use named profile: aws configure --profile IAM-Secure-Gate" "White"
    Write-Color "  3. Then run: .\Set-AWSEnvironment.ps1 -Profile IAM-Secure-Gate" "White"
    exit 1
}

Write-Color "`n========================================" "Cyan"
Write-Color "Ready to deploy!" "Green"
Write-Color "Run: .\Deploy-Demo.ps1" "Cyan"
Write-Color "========================================`n" "Cyan"