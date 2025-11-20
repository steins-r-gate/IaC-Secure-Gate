# Deploy-Phase1.ps1

param(
    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Get script & project directories
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path    # ...\IAM-Secure-Gate\scripts
$projectRoot = Split-Path -Parent $scriptDir                      # ...\IAM-Secure-Gate

Set-Location $projectRoot

# Setup logging (keep logs inside scripts/)
$logDir = Join-Path $scriptDir "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
    
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Cleanup function
function Cleanup {
    param([string]$ErrorMessage)
    
    if (Test-Path "tfplan") {
        Remove-Item "tfplan" -Force
        Write-Log "Cleaned up tfplan file" "Yellow"
    }
    
    if ($ErrorMessage) {
        Write-Log "`n $ErrorMessage" "Red"
    }
    
    Set-Location $projectRoot
}

# Banner
Write-Log "=====================================" "Cyan"
Write-Log " IAM-Secure-Gate - Phase 1 Deployment" "Cyan"
Write-Log " Environment: $Environment" "Cyan"
Write-Log "=====================================" "Cyan"
Write-Log ""

# Dry run notice
if ($DryRun) {
    Write-Log " DRY RUN MODE - No changes will be applied" "Yellow"
    Write-Log ""
}

# Verify project structure (relative to project root)
Write-Log "Verifying project structure..." "Yellow"
$requiredPaths = @(
    "terraform\environments\$Environment",
    "scripts",
    "terraform\modules\s3"
)

foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        Cleanup "Missing required directory: $path"
        exit 1
    }
}
Write-Log " Project structure valid" "Green"

# Check prerequisites
Write-Log "`nChecking prerequisites..." "Yellow"

# Check Terraform
$terraform = Get-Command terraform -ErrorAction SilentlyContinue
if (-not $terraform) {
    Cleanup "Terraform not found. Install from: https://www.terraform.io/downloads"
    exit 1
}
$tfVersion = (terraform version -json | ConvertFrom-Json).terraform_version
Write-Log " Terraform $tfVersion" "Green"

# Check AWS CLI
$aws = Get-Command aws -ErrorAction SilentlyContinue
if (-not $aws) {
    Cleanup "AWS CLI not found. Install from: https://aws.amazon.com/cli/"
    exit 1
}
$awsVersion = aws --version
Write-Log " AWS CLI installed" "Green"

# Validate AWS credentials
Write-Log "`nValidating AWS credentials..." "Yellow"
try {
    $awsIdentity = aws sts get-caller-identity --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI returned error"
    }
    
    Write-Log " AWS Account: $($awsIdentity.Account)" "Green"
    Write-Log "   User/Role: $($awsIdentity.Arn)" "White"
    
    # Verify region
    $awsRegion = aws configure get region
    if ([string]::IsNullOrEmpty($awsRegion)) {
        Write-Log "  No default region set, using eu-west-1" "Yellow"
        $env:AWS_DEFAULT_REGION = "eu-west-1"
    } else {
        Write-Log "   Region: $awsRegion" "White"
    }
    
} catch {
    Cleanup "Failed to validate AWS credentials. Run: aws configure"
    exit 1
}

# Set AWS environment (if script exists)
$awsEnvScript = Join-Path $projectRoot "scripts\Set-AWSEnvironment.ps1"
if (Test-Path $awsEnvScript) {
    Write-Log "`nSetting AWS environment..." "Yellow"
    & $awsEnvScript
    if ($LASTEXITCODE -ne 0) {
        Cleanup "Failed to set AWS environment"
        exit 1
    }
}

# Change to Terraform directory
$tfDir = Join-Path $projectRoot "terraform\environments\$Environment"
Set-Location $tfDir
Write-Log "`nWorking directory: $tfDir" "Cyan"

# Check if backend is configured
if (-not (Test-Path "backend.tf")) {
    Write-Log "`n  Backend not configured" "Yellow"
    Write-Log "Terraform state will be stored locally." "Yellow"
    Write-Log "For production, run: .\scripts\Setup-TerraformBackend.ps1" "Yellow"
    Write-Log ""
    
    if (-not $AutoApprove) {
        $proceed = Read-Host "Continue with local state? (yes/no)"
        if ($proceed -ne "yes") {
            Cleanup "Deployment cancelled by user"
            exit 0
        }
    }
}

# Initialize Terraform
Write-Log "`n Initializing Terraform..." "Yellow"
terraform init -upgrade
if ($LASTEXITCODE -ne 0) {
    Cleanup "Terraform initialization failed"
    exit 1
}
Write-Log " Terraform initialized" "Green"

# Format check
Write-Log "`n Checking code formatting..." "Yellow"
terraform fmt -check -recursive
if ($LASTEXITCODE -ne 0) {
    Write-Log " Code formatting issues detected" "Yellow"
    Write-Log "Run 'terraform fmt -recursive' to fix" "Yellow"
}

# Validate configuration
Write-Log "`n✓ Validating configuration..." "Yellow"
terraform validate
if ($LASTEXITCODE -ne 0) {
    Cleanup "Terraform validation failed"
    exit 1
}
Write-Log " Configuration valid" "Green"

# Handle terraform.tfvars
if (-not (Test-Path "terraform.tfvars")) {
    Write-Log "`n  terraform.tfvars not found" "Yellow"
    
    if (Test-Path "terraform.tfvars.example") {
        Copy-Item "terraform.tfvars.example" "terraform.tfvars"
        Write-Log "Created terraform.tfvars from example" "Cyan"
        
        Write-Log ""
        Write-Log " Required variables in terraform.tfvars:" "Cyan"
        Write-Log "   - owner_email     (your email address)" "White"
        Write-Log "   - alert_email     (security alerts email)" "White"
        Write-Log ""
        Write-Log "File location: $tfDir\terraform.tfvars" "Cyan"
        Write-Log ""
        
        $edit = Read-Host "Open in editor now? (y/n)"
        if ($edit -eq "y") {
            if (Get-Command code -ErrorAction SilentlyContinue) {
                code terraform.tfvars
            } else {
                notepad terraform.tfvars
            }
        }
        
        Write-Log ""
        Read-Host "Press Enter when ready to continue"
        
        # Validate tfvars was updated
        $tfvarsContent = Get-Content "terraform.tfvars" -Raw
        if ($tfvarsContent -match '@example\.com') {
            Cleanup "terraform.tfvars still contains example values. Please update it."
            exit 1
        }
        
        Write-Log " terraform.tfvars configured" "Green"
    } else {
        Cleanup "terraform.tfvars.example not found"
        exit 1
    }
}

# Check for state locks
Write-Log "`n Checking for state locks..." "Yellow"
try {
    $null = terraform force-unlock -help 2>&1
    Write-Log " No state locks detected" "Green"
} catch {
    Write-Log "  Could not check state locks" "Yellow"
}

# Create plan
Write-Log "`n Creating execution plan..." "Yellow"
Write-Log "This may take a few minutes..." "White"
Write-Log ""

terraform plan -out=tfplan -input=false
if ($LASTEXITCODE -ne 0) {
    Cleanup "Terraform plan failed"
    exit 1
}

# Show plan summary
Write-Log "`n" ""
Write-Log "=====================================" "Cyan"
Write-Log " PLAN SUMMARY" "Cyan"
Write-Log "=====================================" "Cyan"
terraform show -no-color tfplan | Select-String -Pattern "Plan:|No changes|Terraform will perform" | ForEach-Object {
    Write-Log $_.Line "Yellow"
}
Write-Log "=====================================" "Cyan"
Write-Log ""

# Exit if dry run
if ($DryRun) {
    Write-Log " DRY RUN COMPLETE - No changes applied" "Cyan"
    Write-Log "Review the plan above. Remove -DryRun to apply changes." "Yellow"
    Cleanup
    exit 0
}

# Apply changes
$applyPlan = $false

if ($AutoApprove) {
    Write-Log "⚡ Auto-approve enabled, applying changes..." "Yellow"
    $applyPlan = $true
} else {
    Write-Log ""
    Write-Log "⚠️  REVIEW THE PLAN ABOVE CAREFULLY" "Yellow"
    Write-Log ""
    $confirm = Read-Host "Apply these changes? Type 'yes' to confirm"
    
    if ($confirm -eq "yes") {
        $applyPlan = $true
    } else {
        Write-Log "Deployment cancelled by user" "Yellow"
        Cleanup
        exit 0
    }
}

if ($applyPlan) {
    Write-Log "`n Applying infrastructure changes..." "Yellow"
    Write-Log "This may take several minutes..." "White"
    Write-Log ""
    
    $startTime = Get-Date
    terraform apply tfplan
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log ""
        Write-Log "=====================================" "Green"
        Write-Log "  DEPLOYMENT SUCCESSFUL!" "Green"
        Write-Log "=====================================" "Green"
        Write-Log "Duration: $([math]::Round($duration, 2)) seconds" "White"
        Write-Log ""
        
        # Save outputs at project root
        $outputsFile = Join-Path $projectRoot "outputs.json"
        terraform output -json | Out-File -FilePath $outputsFile -Encoding UTF8
        Write-Log " Outputs saved to: outputs.json" "Cyan"
        
        # Show key outputs
        Write-Log "`n Key Resources Created:" "Cyan"
        try {
            $outputs = terraform output -json | ConvertFrom-Json
            if ($outputs.cloudtrail_bucket_name) {
                Write-Log "   CloudTrail Bucket: $($outputs.cloudtrail_bucket_name.value)" "White"
            }
            if ($outputs.config_bucket_name) {
                Write-Log "   Config Bucket: $($outputs.config_bucket_name.value)" "White"
            }
            if ($outputs.kms_key_id) {
                Write-Log "   KMS Key: $($outputs.kms_key_id.value)" "White"
            }
        } catch {
            Write-Log "   (Run 'terraform output' to see all outputs)" "White"
        }
        
        # Cleanup plan file
        Remove-Item "tfplan" -Force -ErrorAction SilentlyContinue
        
        # Return to project root
        Set-Location $projectRoot
        
        # Run verification
        $verifyScript = Join-Path $projectRoot "scripts\Verify-Phase1.ps1"
        if (Test-Path $verifyScript) {
            Write-Log "`n Running verification tests..." "Yellow"
            & $verifyScript
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "`n All verification tests passed!" "Green"
            } else {
                Write-Log "`n Some verification tests failed" "Yellow"
                Write-Log "Review the output above for details" "Yellow"
            }
        }
        
        Write-Log "`n Log file: $logFile" "Cyan"
        Write-Log ""
        
    } else {
        Cleanup "Terraform apply failed. Check the output above for details."
        exit 1
    }
}
