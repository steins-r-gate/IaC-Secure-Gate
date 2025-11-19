# Verify-Phase1.ps1
# Comprehensive verification of Phase 1 IAM-Secure-Gate deployment

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportReport
)

$ErrorActionPreference = "Continue"
$verificationResults = @{
    Timestamp = Get-Date
    Environment = $Environment
    Checks = @()
    Summary = @{}
}

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White", [switch]$NoNewline)
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Add-CheckResult {
    param(
        [string]$Category,
        [string]$CheckName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Recommendation = "",
        [object]$Data = $null
    )
    
    $result = [PSCustomObject]@{
        Category = $Category
        CheckName = $CheckName
        Passed = $Passed
        Details = $Details
        Recommendation = $Recommendation
        Data = $Data
        Timestamp = Get-Date
    }
    
    $script:verificationResults.Checks += $result
    
    $icon = if ($Passed) { "✅" } else { "❌" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-ColorOutput "  $icon $CheckName" $color
    if ($Details -and $Detailed) {
        Write-ColorOutput "     $Details" "White"
    }
    if (-not $Passed -and $Recommendation) {
        Write-ColorOutput "     → $Recommendation" "Yellow"
    }
}

Write-ColorOutput "`n=====================================" "Cyan"
Write-ColorOutput " 🔍 Phase 1 Verification" "Cyan"
Write-ColorOutput " Environment: $Environment" "Cyan"
Write-ColorOutput "=====================================" "Cyan"
Write-Host ""

# Get AWS Account Info
Write-ColorOutput "📋 AWS Environment Information:" "Yellow"
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    $region = aws configure get region
    if ([string]::IsNullOrEmpty($region)) {
        $region = $env:AWS_REGION
    }
    
    Write-ColorOutput "  Account ID: $($identity.Account)" "Cyan"
    Write-ColorOutput "  Region: $region" "Cyan"
    Write-ColorOutput "  User/Role: $($identity.Arn.Split('/')[-1])" "Cyan"
    Write-Host ""
    
    $accountId = $identity.Account
} catch {
    Write-ColorOutput "❌ Failed to get AWS identity" "Red"
    exit 1
}

# Try to load Terraform outputs
$tfOutputs = $null
$tfOutputFile = "outputs.json"
if (Test-Path $tfOutputFile) {
    try {
        $tfOutputs = Get-Content $tfOutputFile -Raw | ConvertFrom-Json
        Write-ColorOutput "📄 Loaded Terraform outputs from $tfOutputFile" "Green"
        Write-Host ""
    } catch {
        Write-ColorOutput "⚠️  Could not parse $tfOutputFile" "Yellow"
    }
}

# ============================================================================
# CATEGORY 1: S3 BUCKETS
# ============================================================================
Write-ColorOutput "1️⃣  S3 Buckets" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

$expectedBuckets = @{
    "CloudTrail" = "iam-security-$Environment-cloudtrail-$accountId"
    "Config" = "iam-security-$Environment-config-$accountId"
    "Logs" = "iam-security-$Environment-logs-$accountId"
}

foreach ($bucketType in $expectedBuckets.Keys) {
    $bucketName = $expectedBuckets[$bucketType]
    
    try {
        # Check if bucket exists
        $null = aws s3api head-bucket --bucket $bucketName 2>&1
        if ($LASTEXITCODE -eq 0) {
            
            # Check versioning
            $versioning = aws s3api get-bucket-versioning --bucket $bucketName | ConvertFrom-Json
            $versioningEnabled = $versioning.Status -eq "Enabled"
            
            # Check encryption
            $encryption = aws s3api get-bucket-encryption --bucket $bucketName 2>$null | ConvertFrom-Json
            $encryptionEnabled = $encryption.Rules.Count -gt 0
            
            # Check public access block
            $publicBlock = aws s3api get-public-access-block --bucket $bucketName 2>$null | ConvertFrom-Json
            $publicAccessBlocked = $publicBlock.PublicAccessBlockConfiguration.BlockPublicAcls -and
                                   $publicBlock.PublicAccessBlockConfiguration.BlockPublicPolicy
            
            # Check lifecycle policy
            $lifecycle = aws s3api get-bucket-lifecycle-configuration --bucket $bucketName 2>$null | ConvertFrom-Json
            $lifecycleConfigured = $lifecycle.Rules.Count -gt 0
            
            # Check logging (except for logs bucket itself)
            $loggingEnabled = $false
            if ($bucketType -ne "Logs") {
                $logging = aws s3api get-bucket-logging --bucket $bucketName 2>$null | ConvertFrom-Json
                $loggingEnabled = $logging.LoggingEnabled -ne $null
            } else {
                $loggingEnabled = $true # Logs bucket doesn't need logging on itself
            }
            
            # Overall bucket check
            $allChecksPassed = $versioningEnabled -and $encryptionEnabled -and $publicAccessBlocked -and $lifecycleConfigured -and $loggingEnabled
            
            $details = "Versioning: $versioningEnabled | Encryption: $encryptionEnabled | Public Block: $publicAccessBlocked | Lifecycle: $lifecycleConfigured | Logging: $loggingEnabled"
            
            Add-CheckResult -Category "S3" -CheckName "$bucketType Bucket ($bucketName)" `
                -Passed $allChecksPassed -Details $details `
                -Data @{
                    BucketName = $bucketName
                    Versioning = $versioningEnabled
                    Encryption = $encryptionEnabled
                    PublicAccessBlocked = $publicAccessBlocked
                    Lifecycle = $lifecycleConfigured
                    Logging = $loggingEnabled
                }
            
            if (-not $allChecksPassed) {
                $issues = @()
                if (-not $versioningEnabled) { $issues += "Enable versioning" }
                if (-not $encryptionEnabled) { $issues += "Enable encryption" }
                if (-not $publicAccessBlocked) { $issues += "Block public access" }
                if (-not $lifecycleConfigured) { $issues += "Configure lifecycle policy" }
                if (-not $loggingEnabled -and $bucketType -ne "Logs") { $issues += "Enable access logging" }
                
                Write-ColorOutput "     Issues: $($issues -join ', ')" "Yellow"
            }
            
        } else {
            Add-CheckResult -Category "S3" -CheckName "$bucketType Bucket" `
                -Passed $false -Details "Bucket not found: $bucketName" `
                -Recommendation "Deploy S3 module: terraform apply"
        }
    } catch {
        Add-CheckResult -Category "S3" -CheckName "$bucketType Bucket" `
            -Passed $false -Details "Error checking bucket: $($_.Exception.Message)" `
            -Recommendation "Check AWS permissions"
    }
}

Write-Host ""

# ============================================================================
# CATEGORY 2: KMS KEYS
# ============================================================================
Write-ColorOutput "2️⃣  KMS Encryption Keys" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    # Try to get KMS key from Terraform outputs first
    $kmsKeyId = $null
    if ($tfOutputs -and $tfOutputs.kms_key_id) {
        $kmsKeyId = $tfOutputs.kms_key_id.value
    }
    
    if ($kmsKeyId) {
        # Verify key exists and is enabled
        $keyMetadata = aws kms describe-key --key-id $kmsKeyId | ConvertFrom-Json
        
        if ($keyMetadata.KeyMetadata.KeyState -eq "Enabled") {
            $rotationEnabled = (aws kms get-key-rotation-status --key-id $kmsKeyId | ConvertFrom-Json).KeyRotationEnabled
            
            Add-CheckResult -Category "KMS" -CheckName "S3 Encryption Key" `
                -Passed $true -Details "Key enabled, Rotation: $rotationEnabled" `
                -Data @{
                    KeyId = $kmsKeyId
                    State = $keyMetadata.KeyMetadata.KeyState
                    RotationEnabled = $rotationEnabled
                }
            
            if (-not $rotationEnabled) {
                Write-ColorOutput "     ⚠️  Key rotation not enabled" "Yellow"
            }
        } else {
            Add-CheckResult -Category "KMS" -CheckName "S3 Encryption Key" `
                -Passed $false -Details "Key state: $($keyMetadata.KeyMetadata.KeyState)" `
                -Recommendation "Check key status in KMS console"
        }
    } else {
        # Search for key by alias
        $aliases = aws kms list-aliases --output json | ConvertFrom-Json
        $targetAlias = $aliases.Aliases | Where-Object { $_.AliasName -eq "alias/iam-security-$Environment-s3" }
        
        if ($targetAlias) {
            Add-CheckResult -Category "KMS" -CheckName "S3 Encryption Key" `
                -Passed $true -Details "Found key via alias"
        } else {
            Add-CheckResult -Category "KMS" -CheckName "S3 Encryption Key" `
                -Passed $false -Details "KMS key not found" `
                -Recommendation "Deploy S3 module with KMS key"
        }
    }
} catch {
    Add-CheckResult -Category "KMS" -CheckName "S3 Encryption Key" `
        -Passed $false -Details "Error checking KMS: $($_.Exception.Message)" `
        -Recommendation "Verify KMS permissions"
}

Write-Host ""

# ============================================================================
# CATEGORY 3: CLOUDTRAIL
# ============================================================================
Write-ColorOutput "3️⃣  CloudTrail" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    $trails = aws cloudtrail describe-trails --output json | ConvertFrom-Json
    $iamTrail = $trails.trailList | Where-Object { $_.Name -like "*iam*" -or $_.S3BucketName -like "*iam-security*" }
    
    if ($iamTrail) {
        $trailName = $iamTrail.Name
        $status = aws cloudtrail get-trail-status --name $trailName | ConvertFrom-Json
        
        $isLogging = $status.IsLogging
        $isMultiRegion = $iamTrail.IsMultiRegionTrail
        $includesGlobalEvents = $iamTrail.IncludeGlobalServiceEvents
        
        Add-CheckResult -Category "CloudTrail" -CheckName "Trail Status" `
            -Passed $isLogging -Details "Logging: $isLogging | Multi-region: $isMultiRegion | Global events: $includesGlobalEvents" `
            -Data @{
                TrailName = $trailName
                IsLogging = $isLogging
                IsMultiRegion = $isMultiRegion
                IncludesGlobalEvents = $includesGlobalEvents
                S3Bucket = $iamTrail.S3BucketName
            }
        
        # Verify trail is using the correct bucket
        $expectedBucket = "iam-security-$Environment-cloudtrail-$accountId"
        if ($iamTrail.S3BucketName -eq $expectedBucket) {
            Add-CheckResult -Category "CloudTrail" -CheckName "Correct S3 Bucket" `
                -Passed $true -Details $expectedBucket
        } else {
            Add-CheckResult -Category "CloudTrail" -CheckName "Correct S3 Bucket" `
                -Passed $false -Details "Using: $($iamTrail.S3BucketName), Expected: $expectedBucket" `
                -Recommendation "Update CloudTrail to use correct bucket"
        }
        
    } else {
        Add-CheckResult -Category "CloudTrail" -CheckName "Trail Status" `
            -Passed $false -Details "No IAM-related trail found" `
            -Recommendation "Create CloudTrail: aws cloudtrail create-trail"
    }
} catch {
    Add-CheckResult -Category "CloudTrail" -CheckName "Trail Status" `
        -Passed $false -Details "Error checking CloudTrail: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CATEGORY 4: AWS CONFIG
# ============================================================================
Write-ColorOutput "4️⃣  AWS Config" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    $recorders = aws configservice describe-configuration-recorders --output json | ConvertFrom-Json
    $recorderStatus = aws configservice describe-configuration-recorder-status --output json | ConvertFrom-Json
    
    if ($recorders.ConfigurationRecorders.Count -gt 0) {
        $recorder = $recorders.ConfigurationRecorders[0]
        $status = $recorderStatus.ConfigurationRecordersStatus[0]
        
        $isRecording = $status.recording
        $lastStatus = $status.lastStatus
        
        Add-CheckResult -Category "Config" -CheckName "Configuration Recorder" `
            -Passed $isRecording -Details "Recording: $isRecording | Status: $lastStatus" `
            -Data @{
                RecorderName = $recorder.name
                IsRecording = $isRecording
                LastStatus = $lastStatus
            }
        
        # Check delivery channel
        $deliveryChannels = aws configservice describe-delivery-channels --output json | ConvertFrom-Json
        if ($deliveryChannels.DeliveryChannels.Count -gt 0) {
            $channel = $deliveryChannels.DeliveryChannels[0]
            $expectedBucket = "iam-security-$Environment-config-$accountId"
            
            if ($channel.s3BucketName -eq $expectedBucket) {
                Add-CheckResult -Category "Config" -CheckName "Delivery Channel" `
                    -Passed $true -Details "Using correct bucket: $expectedBucket"
            } else {
                Add-CheckResult -Category "Config" -CheckName "Delivery Channel" `
                    -Passed $false -Details "Using: $($channel.s3BucketName), Expected: $expectedBucket" `
                    -Recommendation "Update Config delivery channel"
            }
        }
        
    } else {
        Add-CheckResult -Category "Config" -CheckName "Configuration Recorder" `
            -Passed $false -Details "No recorder found" `
            -Recommendation "Enable AWS Config"
    }
    
    # Check Config Rules
    $rules = aws configservice describe-config-rules --output json | ConvertFrom-Json
    $iamRules = $rules.ConfigRules | Where-Object { 
        $_.Source.SourceIdentifier -like "*IAM*" -or $_.ConfigRuleName -like "*iam*"
    }
    
    if ($iamRules.Count -gt 0) {
        Add-CheckResult -Category "Config" -CheckName "IAM Config Rules" `
            -Passed $true -Details "Found $($iamRules.Count) IAM-related rule(s)" `
            -Data @{
                Rules = $iamRules | Select-Object -ExpandProperty ConfigRuleName
            }
        
        if ($Detailed) {
            Write-ColorOutput "     Rules:" "White"
            $iamRules | ForEach-Object {
                Write-ColorOutput "       - $($_.ConfigRuleName)" "Cyan"
            }
        }
    } else {
        Add-CheckResult -Category "Config" -CheckName "IAM Config Rules" `
            -Passed $false -Details "No IAM rules configured" `
            -Recommendation "Deploy Config rules for IAM monitoring"
    }
    
} catch {
    Add-CheckResult -Category "Config" -CheckName "Configuration Status" `
        -Passed $false -Details "Error checking Config: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CATEGORY 5: IAM ACCESS ANALYZER
# ============================================================================
Write-ColorOutput "5️⃣  IAM Access Analyzer" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    $analyzers = aws accessanalyzer list-analyzers --output json | ConvertFrom-Json
    $activeAnalyzers = $analyzers.analyzers | Where-Object { $_.status -eq "ACTIVE" }
    
    if ($activeAnalyzers.Count -gt 0) {
        foreach ($analyzer in $activeAnalyzers) {
            $isAccountAnalyzer = $analyzer.type -eq "ACCOUNT"
            
            Add-CheckResult -Category "AccessAnalyzer" -CheckName "Analyzer: $($analyzer.name)" `
                -Passed $true -Details "Type: $($analyzer.type) | Status: $($analyzer.status)" `
                -Data @{
                    AnalyzerName = $analyzer.name
                    Type = $analyzer.type
                    Status = $analyzer.status
                    Arn = $analyzer.arn
                }
            
            # Check for findings
            $findings = aws accessanalyzer list-findings --analyzer-arn $analyzer.arn `
                --filter "{`"status`": {`"eq`": [`"ACTIVE`"]}}" --output json 2>$null | ConvertFrom-Json
            
            if ($findings.findings.Count -gt 0) {
                Write-ColorOutput "     ⚠️  $($findings.findings.Count) active finding(s)" "Yellow"
            } else {
                Write-ColorOutput "     ✓ No active findings" "Green"
            }
        }
    } else {
        Add-CheckResult -Category "AccessAnalyzer" -CheckName "Active Analyzers" `
            -Passed $false -Details "No active analyzers found" `
            -Recommendation "Create Access Analyzer: aws accessanalyzer create-analyzer"
    }
} catch {
    Add-CheckResult -Category "AccessAnalyzer" -CheckName "Access Analyzer Status" `
        -Passed $false -Details "Error checking Access Analyzer: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CATEGORY 6: SECURITY HUB
# ============================================================================
Write-ColorOutput "6️⃣  AWS Security Hub" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    $hub = aws securityhub describe-hub --output json 2>$null | ConvertFrom-Json
    
    if ($hub.HubArn) {
        Add-CheckResult -Category "SecurityHub" -CheckName "Hub Status" `
            -Passed $true -Details "Enabled" `
            -Data @{
                HubArn = $hub.HubArn
                SubscribedAt = $hub.SubscribedAt
            }
        
        # Check enabled standards
        $standards = aws securityhub describe-standards-subscriptions --output json | ConvertFrom-Json
        
        if ($standards.StandardsSubscriptions.Count -gt 0) {
            Add-CheckResult -Category "SecurityHub" -CheckName "Security Standards" `
                -Passed $true -Details "$($standards.StandardsSubscriptions.Count) standard(s) enabled"
            
            if ($Detailed) {
                Write-ColorOutput "     Standards:" "White"
                $standards.StandardsSubscriptions | ForEach-Object {
                    $standardName = $_.StandardsArn.Split('/')[-1]
                    Write-ColorOutput "       - $standardName [$($_.StandardsStatus)]" "Cyan"
                }
            }
        } else {
            Add-CheckResult -Category "SecurityHub" -CheckName "Security Standards" `
                -Passed $false -Details "No standards enabled" `
                -Recommendation "Enable AWS Foundational Security Best Practices"
        }
        
        # Check for IAM-related findings
        $findings = aws securityhub get-findings --max-results 100 `
            --filters "{`"ResourceType`": [{`"Value`": `"AwsIamPolicy`", `"Comparison`": `"EQUALS`"}]}" `
            --output json 2>$null | ConvertFrom-Json
        
        if ($findings.Findings.Count -gt 0) {
            $criticalCount = ($findings.Findings | Where-Object { $_.Severity.Label -eq "CRITICAL" }).Count
            $highCount = ($findings.Findings | Where-Object { $_.Severity.Label -eq "HIGH" }).Count
            
            Write-ColorOutput "     IAM Findings: $($findings.Findings.Count) total (Critical: $criticalCount, High: $highCount)" "Yellow"
        }
        
    } else {
        Add-CheckResult -Category "SecurityHub" -CheckName "Hub Status" `
            -Passed $false -Details "Security Hub not enabled" `
            -Recommendation "Enable Security Hub: aws securityhub enable-security-hub"
    }
} catch {
    Add-CheckResult -Category "SecurityHub" -CheckName "Hub Status" `
        -Passed $false -Details "Error checking Security Hub: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CATEGORY 7: EVENTBRIDGE
# ============================================================================
Write-ColorOutput "7️⃣  EventBridge Rules" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

try {
    $rules = aws events list-rules --output json | ConvertFrom-Json
    $iamRules = $rules.Rules | Where-Object { 
        $_.Name -like "*iam*" -or $_.EventPattern -like "*iam*" 
    }
    
    if ($iamRules.Count -gt 0) {
        $enabledRules = $iamRules | Where-Object { $_.State -eq "ENABLED" }
        
        Add-CheckResult -Category "EventBridge" -CheckName "IAM Event Rules" `
            -Passed ($enabledRules.Count -gt 0) `
            -Details "$($enabledRules.Count) enabled of $($iamRules.Count) total" `
            -Data @{
                Rules = $enabledRules | Select-Object -ExpandProperty Name
            }
        
        if ($Detailed) {
            Write-ColorOutput "     Rules:" "White"
            $enabledRules | ForEach-Object {
                Write-ColorOutput "       - $($_.Name) [$($_.State)]" "Cyan"
            }
        }
    } else {
        Add-CheckResult -Category "EventBridge" -CheckName "IAM Event Rules" `
            -Passed $false -Details "No IAM-related EventBridge rules found" `
            -Recommendation "Create EventBridge rules for IAM monitoring"
    }
} catch {
    Add-CheckResult -Category "EventBridge" -CheckName "EventBridge Status" `
        -Passed $false -Details "Error checking EventBridge: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CATEGORY 8: TERRAFORM STATE
# ============================================================================
Write-ColorOutput "8️⃣  Terraform State" "Cyan"
Write-ColorOutput "════════════════════════════════════" "Cyan"

$tfDir = "terraform\environments\$Environment"
if (Test-Path $tfDir) {
    # Check if initialized
    if (Test-Path "$tfDir\.terraform") {
        Add-CheckResult -Category "Terraform" -CheckName "Terraform Initialized" -Passed $true
    } else {
        Add-CheckResult -Category "Terraform" -CheckName "Terraform Initialized" `
            -Passed $false -Recommendation "Run: terraform init"
    }
    
    # Check for backend configuration
    if (Test-Path "$tfDir\backend.tf") {
        Add-CheckResult -Category "Terraform" -CheckName "Backend Configured" -Passed $true
    } else {
        Add-CheckResult -Category "Terraform" -CheckName "Backend Configured" `
            -Passed $false -Recommendation "Run Setup-TerraformBackend.ps1"
    }
    
    # Check for tfvars
    if (Test-Path "$tfDir\terraform.tfvars") {
        Add-CheckResult -Category "Terraform" -CheckName "Variables Configured" -Passed $true
    } else {
        Add-CheckResult -Category "Terraform" -CheckName "Variables Configured" `
            -Passed $false -Recommendation "Create terraform.tfvars from example"
    }
} else {
    Add-CheckResult -Category "Terraform" -CheckName "Terraform Directory" `
        -Passed $false -Details "Directory not found: $tfDir"
}

Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================
Write-ColorOutput "=====================================" "Cyan"
Write-ColorOutput " 📊 VERIFICATION SUMMARY" "Cyan"
Write-ColorOutput "=====================================" "Cyan"

$totalChecks = $verificationResults.Checks.Count
$passedChecks = ($verificationResults.Checks | Where-Object { $_.Passed }).Count
$failedChecks = $totalChecks - $passedChecks
$passRate = [math]::Round(($passedChecks / $totalChecks) * 100, 1)

Write-ColorOutput "`nTotal Checks: $totalChecks" "White"
Write-ColorOutput "Passed: $passedChecks" "Green"
Write-ColorOutput "Failed: $failedChecks" $(if ($failedChecks -gt 0) { "Red" } else { "Green" })
Write-ColorOutput "Success Rate: $passRate%" $(if ($passRate -ge 80) { "Green" } elseif ($passRate -ge 50) { "Yellow" } else { "Red" })

# Group by category
$verificationResults.Summary = @{
    Total = $totalChecks
    Passed = $passedChecks
    Failed = $failedChecks
    PassRate = $passRate
    ByCategory = @{}
}

$categories = $verificationResults.Checks | Group-Object Category
foreach ($category in $categories) {
    $catPassed = ($category.Group | Where-Object { $_.Passed }).Count
    $catTotal = $category.Count
    $verificationResults.Summary.ByCategory[$category.Name] = @{
        Passed = $catPassed
        Total = $catTotal
    }
    
    $icon = if ($catPassed -eq $catTotal) { "✅" } else { "⚠️" }
    Write-ColorOutput "`n$icon $($category.Name): $catPassed/$catTotal" $(if ($catPassed -eq $catTotal) { "Green" } else { "Yellow" })
}

# Failed checks with recommendations
$failedWithRecommendations = $verificationResults.Checks | Where-Object { -not $_.Passed -and $_.Recommendation }
if ($failedWithRecommendations.Count -gt 0) {
    Write-ColorOutput "`n📋 Recommended Actions:" "Yellow"
    $failedWithRecommendations | ForEach-Object {
        Write-ColorOutput "  • $($_.CheckName):" "White"
        Write-ColorOutput "    → $($_.Recommendation)" "Cyan"
    }
}

Write-Host ""

# Export report if requested
if ($ExportReport) {
    $reportFile = "verification-report-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $verificationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportFile -Encoding UTF8
    Write-ColorOutput "📄 Detailed report exported: $reportFile" "Cyan"
    Write-Host ""
}

# Final status
if ($passRate -eq 100) {
    Write-ColorOutput "🎉 Phase 1 is FULLY OPERATIONAL!" "Green"
    exit 0
} elseif ($passRate -ge 80) {
    Write-ColorOutput "✅ Phase 1 is mostly operational (minor issues)" "Yellow"
    exit 0
} elseif ($passRate -ge 50) {
    Write-ColorOutput "⚠️  Phase 1 needs attention (multiple issues)" "Yellow"
    exit 1
} else {
    Write-ColorOutput "❌ Phase 1 has significant issues" "Red"
    exit 1
}