# Test-Detection.ps1
# Comprehensive IAM detection pipeline testing suite

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("quick", "full", "custom")]
    [string]$TestType = "quick",
    
    [Parameter(Mandatory=$false)]
    [int]$WaitTimeSeconds = 60,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipCleanup,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$testResults = @()
$createdResources = @()

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White", [switch]$NoNewline)
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Details = "",
        [int]$DetectionTime = 0
    )
    
    $result = [PSCustomObject]@{
        TestName = $TestName
        Status = $Status
        Details = $Details
        DetectionTime = $DetectionTime
        Timestamp = Get-Date
    }
    
    $script:testResults += $result
    
    $statusColor = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "White" }
    }
    
    $icon = switch ($Status) {
        "PASS" { "✅" }
        "FAIL" { "❌" }
        "WARN" { "⚠️" }
        default { "ℹ️" }
    }
    
    Write-ColorOutput "$icon $TestName : $Status" $statusColor
    if ($Details) {
        Write-ColorOutput "   $Details" "White"
    }
    if ($DetectionTime -gt 0) {
        Write-ColorOutput "   Detection time: $DetectionTime seconds" "Cyan"
    }
}

function Wait-ForDetection {
    param(
        [string]$ResourceArn,
        [int]$MaxWaitSeconds = 300,
        [string]$Service = "SecurityHub"
    )
    
    $startTime = Get-Date
    $detected = $false
    
    Write-ColorOutput "`n⏳ Waiting for $Service detection (max ${MaxWaitSeconds}s)..." "Yellow"
    
    $dots = 0
    while (((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitSeconds) {
        
        if ($Service -eq "SecurityHub") {
            $findings = aws securityhub get-findings `
                --filters "{`"ResourceId`": [{`"Value`": `"$ResourceArn`", `"Comparison`": `"EQUALS`"}]}" `
                2>$null | ConvertFrom-Json
            
            if ($findings.Findings.Count -gt 0) {
                $detected = $true
                break
            }
        } elseif ($Service -eq "Config") {
            $resourceId = $ResourceArn.Split('/')[-1]
            $compliance = aws configservice describe-compliance-by-resource `
                --resource-type "AWS::IAM::Policy" `
                --resource-id $resourceId 2>$null | ConvertFrom-Json
            
            if ($compliance.ComplianceByResources -and 
                $compliance.ComplianceByResources[0].Compliance.ComplianceType -eq "NON_COMPLIANT") {
                $detected = $true
                break
            }
        }
        
        # Progress indicator
        Write-Host "." -NoNewline -ForegroundColor Gray
        $dots++
        if ($dots % 60 -eq 0) { Write-Host " $([int]((Get-Date) - $startTime).TotalSeconds)s" -ForegroundColor Gray }
        
        Start-Sleep -Seconds 1
    }
    
    Write-Host "" # New line after dots
    
    $detectionTime = [int]((Get-Date) - $startTime).TotalSeconds
    
    return @{
        Detected = $detected
        DetectionTime = $detectionTime
    }
}

function Cleanup-TestResources {
    Write-ColorOutput "`n🧹 Cleaning up test resources..." "Yellow"
    
    foreach ($resource in $script:createdResources) {
        try {
            switch ($resource.Type) {
                "Policy" {
                    # First detach from any users/roles/groups
                    $entities = aws iam list-entities-for-policy --policy-arn $resource.Arn 2>$null | ConvertFrom-Json
                    
                    if ($entities.PolicyUsers) {
                        foreach ($user in $entities.PolicyUsers) {
                            aws iam detach-user-policy --user-name $user.UserName --policy-arn $resource.Arn 2>$null
                        }
                    }
                    
                    if ($entities.PolicyRoles) {
                        foreach ($role in $entities.PolicyRoles) {
                            aws iam detach-role-policy --role-name $role.RoleName --policy-arn $resource.Arn 2>$null
                        }
                    }
                    
                    if ($entities.PolicyGroups) {
                        foreach ($group in $entities.PolicyGroups) {
                            aws iam detach-group-policy --group-name $group.GroupName --policy-arn $resource.Arn 2>$null
                        }
                    }
                    
                    aws iam delete-policy --policy-arn $resource.Arn 2>$null
                    Write-ColorOutput "  ✓ Deleted policy: $($resource.Name)" "White"
                }
                "Role" {
                    # Delete inline policies
                    $inlinePolicies = aws iam list-role-policies --role-name $resource.Name 2>$null | ConvertFrom-Json
                    if ($inlinePolicies.PolicyNames) {
                        foreach ($policyName in $inlinePolicies.PolicyNames) {
                            aws iam delete-role-policy --role-name $resource.Name --policy-name $policyName 2>$null
                        }
                    }
                    
                    # Detach managed policies
                    $attachedPolicies = aws iam list-attached-role-policies --role-name $resource.Name 2>$null | ConvertFrom-Json
                    if ($attachedPolicies.AttachedPolicies) {
                        foreach ($policy in $attachedPolicies.AttachedPolicies) {
                            aws iam detach-role-policy --role-name $resource.Name --policy-arn $policy.PolicyArn 2>$null
                        }
                    }
                    
                    aws iam delete-role --role-name $resource.Name 2>$null
                    Write-ColorOutput "  ✓ Deleted role: $($resource.Name)" "White"
                }
                "User" {
                    # Delete access keys
                    $keys = aws iam list-access-keys --user-name $resource.Name 2>$null | ConvertFrom-Json
                    if ($keys.AccessKeyMetadata) {
                        foreach ($key in $keys.AccessKeyMetadata) {
                            aws iam delete-access-key --user-name $resource.Name --access-key-id $key.AccessKeyId 2>$null
                        }
                    }
                    
                    # Detach managed policies
                    $attachedPolicies = aws iam list-attached-user-policies --user-name $resource.Name 2>$null | ConvertFrom-Json
                    if ($attachedPolicies.AttachedPolicies) {
                        foreach ($policy in $attachedPolicies.AttachedPolicies) {
                            aws iam detach-user-policy --user-name $resource.Name --policy-arn $policy.PolicyArn 2>$null
                        }
                    }
                    
                    aws iam delete-user --user-name $resource.Name 2>$null
                    Write-ColorOutput "  ✓ Deleted user: $($resource.Name)" "White"
                }
            }
        } catch {
            Write-ColorOutput "  ⚠️ Failed to delete $($resource.Type): $($resource.Name)" "Yellow"
        }
    }
    
    Write-ColorOutput "✅ Cleanup complete" "Green"
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

Write-ColorOutput "`n=====================================" "Cyan"
Write-ColorOutput " 🧪 IAM Detection Pipeline Test Suite" "Cyan"
Write-ColorOutput "=====================================" "Cyan"
Write-ColorOutput "Test Type: $TestType" "White"
Write-ColorOutput "Max Wait: ${WaitTimeSeconds}s" "White"
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMddHHmmss"

# Validate prerequisites
Write-ColorOutput "🔍 Validating prerequisites..." "Yellow"

# Check AWS CLI
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-TestResult "AWS CLI Check" "FAIL" "AWS CLI not installed"
    exit 1
}
Write-TestResult "AWS CLI Check" "PASS"

# Check AWS credentials
try {
    $identity = aws sts get-caller-identity --output json 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
    Write-TestResult "AWS Credentials" "PASS" "Account: $($identity.Account)"
} catch {
    Write-TestResult "AWS Credentials" "FAIL" "Invalid credentials"
    exit 1
}

# Check Security Hub
try {
    $securityHub = aws securityhub describe-hub 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Not enabled" }
    Write-TestResult "Security Hub Status" "PASS"
} catch {
    Write-TestResult "Security Hub Status" "FAIL" "Security Hub not enabled. Run: aws securityhub enable-security-hub"
    exit 1
}

# Check Config
try {
    $configRecorder = aws configservice describe-configuration-recorders 2>&1 | ConvertFrom-Json
    if ($configRecorder.ConfigurationRecorders.Count -eq 0) { throw "Not configured" }
    Write-TestResult "AWS Config Status" "PASS"
} catch {
    Write-TestResult "AWS Config Status" "WARN" "AWS Config not fully configured"
}

Write-Host ""

# ============================================================================
# TEST 1: Wildcard Policy Detection
# ============================================================================
Write-ColorOutput "📋 Test 1: Wildcard Policy Detection" "Cyan"
Write-ColorOutput "===========================================" "Cyan"

$policyName = "test-wildcard-policy-$timestamp"
$policyDocument = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Sid = "WildcardViolation"
            Effect = "Allow"
            Action = "*"
            Resource = "*"
        }
    )
} | ConvertTo-Json -Depth 10

try {
    Write-ColorOutput "Creating policy with wildcards..." "Yellow"
    $result = aws iam create-policy `
        --policy-name $policyName `
        --policy-document $policyDocument `
        --description "TEST POLICY - Safe to delete" | ConvertFrom-Json
    
    $policyArn = $result.Policy.Arn
    $script:createdResources += @{
        Type = "Policy"
        Name = $policyName
        Arn = $policyArn
    }
    
    Write-ColorOutput "✅ Created: $policyArn" "Green"
    
    # Wait for detection
    $detection = Wait-ForDetection -ResourceArn $policyArn -MaxWaitSeconds $WaitTimeSeconds -Service "SecurityHub"
    
    if ($detection.Detected) {
        Write-TestResult "Wildcard Policy Detection" "PASS" "Detected in $($detection.DetectionTime)s" $detection.DetectionTime
        
        # Get finding details
        $findings = aws securityhub get-findings `
            --filters "{`"ResourceId`": [{`"Value`": `"$policyArn`", `"Comparison`": `"EQUALS`"}]}" | ConvertFrom-Json
        
        Write-ColorOutput "`n  Finding Details:" "Cyan"
        $findings.Findings | ForEach-Object {
            Write-ColorOutput "    Title: $($_.Title)" "White"
            Write-ColorOutput "    Severity: $($_.Severity.Label)" $(
                switch ($_.Severity.Label) {
                    "CRITICAL" { "Red" }
                    "HIGH" { "Red" }
                    "MEDIUM" { "Yellow" }
                    default { "White" }
                }
            )
            Write-ColorOutput "    Status: $($_.Workflow.Status)" "White"
        }
    } else {
        Write-TestResult "Wildcard Policy Detection" "FAIL" "Not detected within ${WaitTimeSeconds}s" $detection.DetectionTime
    }
    
} catch {
    Write-TestResult "Wildcard Policy Detection" "FAIL" "Error: $($_.Exception.Message)"
}

# ============================================================================
# TEST 2: Overpermissive Trust Policy (Full Test Only)
# ============================================================================
if ($TestType -eq "full") {
    Write-Host ""
    Write-ColorOutput "📋 Test 2: Overpermissive Trust Policy" "Cyan"
    Write-ColorOutput "===========================================" "Cyan"
    
    $roleName = "test-overpermissive-role-$timestamp"
    $trustPolicy = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Principal = @{ AWS = "*" }
                Action = "sts:AssumeRole"
            }
        )
    } | ConvertTo-Json -Depth 10
    
    try {
        Write-ColorOutput "Creating role with wildcard principal..." "Yellow"
        $result = aws iam create-role `
            --role-name $roleName `
            --assume-role-policy-document $trustPolicy `
            --description "TEST ROLE - Safe to delete" | ConvertFrom-Json
        
        $roleArn = $result.Role.Arn
        $script:createdResources += @{
            Type = "Role"
            Name = $roleName
            Arn = $roleArn
        }
        
        Write-ColorOutput "✅ Created: $roleArn" "Green"
        
        $detection = Wait-ForDetection -ResourceArn $roleArn -MaxWaitSeconds $WaitTimeSeconds -Service "SecurityHub"
        
        if ($detection.Detected) {
            Write-TestResult "Trust Policy Detection" "PASS" "Detected in $($detection.DetectionTime)s" $detection.DetectionTime
        } else {
            Write-TestResult "Trust Policy Detection" "FAIL" "Not detected within ${WaitTimeSeconds}s" $detection.DetectionTime
        }
        
    } catch {
        Write-TestResult "Trust Policy Detection" "FAIL" "Error: $($_.Exception.Message)"
    }
}

# ============================================================================
# TEST 3: IAM Access Analyzer Check
# ============================================================================
Write-Host ""
Write-ColorOutput "📋 Test 3: IAM Access Analyzer" "Cyan"
Write-ColorOutput "===========================================" "Cyan"

try {
    $analyzers = aws accessanalyzer list-analyzers --output json 2>&1 | ConvertFrom-Json
    
    if ($analyzers.analyzers.Count -gt 0) {
        Write-TestResult "Access Analyzer Status" "PASS" "Found $($analyzers.analyzers.Count) analyzer(s)"
        
        # Check for findings
        foreach ($analyzer in $analyzers.analyzers) {
            $findings = aws accessanalyzer list-findings `
                --analyzer-arn $analyzer.arn `
                --filter "{`"status`": {`"eq`": [`"ACTIVE`"]}}" `
                --output json 2>$null | ConvertFrom-Json
            
            if ($findings.findings.Count -gt 0) {
                Write-ColorOutput "  ⚠️  Found $($findings.findings.Count) active finding(s) in $($analyzer.name)" "Yellow"
            } else {
                Write-ColorOutput "  ✓ No active findings in $($analyzer.name)" "Green"
            }
        }
    } else {
        Write-TestResult "Access Analyzer Status" "WARN" "No analyzers configured"
    }
} catch {
    Write-TestResult "Access Analyzer Status" "FAIL" "Error checking Access Analyzer"
}

# ============================================================================
# TEST 4: Config Rules Check
# ============================================================================
Write-Host ""
Write-ColorOutput "📋 Test 4: AWS Config Rules" "Cyan"
Write-ColorOutput "===========================================" "Cyan"

try {
    $rules = aws configservice describe-config-rules --output json 2>&1 | ConvertFrom-Json
    
    $iamRules = $rules.ConfigRules | Where-Object { $_.Source.SourceIdentifier -like "*IAM*" }
    
    if ($iamRules.Count -gt 0) {
        Write-TestResult "Config Rules Status" "PASS" "Found $($iamRules.Count) IAM-related rule(s)"
        
        foreach ($rule in $iamRules) {
            $compliance = aws configservice describe-compliance-by-config-rule `
                --config-rule-names $rule.ConfigRuleName --output json 2>$null | ConvertFrom-Json
            
            if ($compliance.ComplianceByConfigRules) {
                $status = $compliance.ComplianceByConfigRules[0].Compliance.ComplianceType
                $statusColor = if ($status -eq "COMPLIANT") { "Green" } else { "Yellow" }
                Write-ColorOutput "  $($rule.ConfigRuleName): $status" $statusColor
            }
        }
    } else {
        Write-TestResult "Config Rules Status" "WARN" "No IAM Config Rules found"
    }
} catch {
    Write-TestResult "Config Rules Status" "FAIL" "Error checking Config Rules"
}

# ============================================================================
# CLEANUP
# ============================================================================
if (-not $SkipCleanup) {
    Cleanup-TestResources
} else {
    Write-ColorOutput "`n⚠️  Skipping cleanup (resources remain)" "Yellow"
    Write-ColorOutput "Manually delete later:" "White"
    foreach ($resource in $script:createdResources) {
        Write-ColorOutput "  - $($resource.Type): $($resource.Name)" "White"
    }
}

# ============================================================================
# GENERATE TEST REPORT
# ============================================================================
Write-Host ""
Write-ColorOutput "=====================================" "Cyan"
Write-ColorOutput " 📊 TEST SUMMARY" "Cyan"
Write-ColorOutput "=====================================" "Cyan"

$passed = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$warnings = ($testResults | Where-Object { $_.Status -eq "WARN" }).Count
$total = $testResults.Count

Write-ColorOutput "Total Tests: $total" "White"
Write-ColorOutput "Passed: $passed" "Green"
Write-ColorOutput "Failed: $failed" $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-ColorOutput "Warnings: $warnings" $(if ($warnings -gt 0) { "Yellow" } else { "White" })

$avgDetectionTime = ($testResults | Where-Object { $_.DetectionTime -gt 0 } | Measure-Object -Property DetectionTime -Average).Average
if ($avgDetectionTime) {
    Write-ColorOutput "`nAverage Detection Time: $([math]::Round($avgDetectionTime, 1))s" "Cyan"
}

# Save report to file
$reportFile = "test-results-$timestamp.json"
$testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportFile -Encoding UTF8
Write-ColorOutput "`n📄 Detailed report: $reportFile" "Cyan"

Write-Host ""

# Exit with appropriate code
if ($failed -gt 0) {
    Write-ColorOutput "❌ TESTS FAILED" "Red"
    exit 1
} elseif ($warnings -gt 0) {
    Write-ColorOutput "⚠️  TESTS PASSED WITH WARNINGS" "Yellow"
    exit 0
} else {
    Write-ColorOutput "✅ ALL TESTS PASSED" "Green"
    exit 0
}