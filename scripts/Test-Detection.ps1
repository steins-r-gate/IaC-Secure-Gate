Write-Host "`n🧪 Testing IAM Detection Pipeline" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# Create test policy with violations
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$policyName = "test-wildcard-policy-$timestamp"

Write-Host "`nCreating test policy with wildcards..." -ForegroundColor Yellow

$policyDocument = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Action = "*"
            Resource = "*"
        }
    )
} | ConvertTo-Json -Depth 10

# Create the policy
try {
    $result = aws iam create-policy `
        --policy-name $policyName `
        --policy-document $policyDocument | ConvertFrom-Json
    
    $policyArn = $result.Policy.Arn
    Write-Host "✅ Created policy: $policyArn" -ForegroundColor Green
    
    Write-Host "`nWaiting 30 seconds for detection..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Check Config compliance
    Write-Host "`nChecking AWS Config compliance..." -ForegroundColor Yellow
    $resourceId = $policyArn.Split('/')[-1]
    $compliance = aws configservice describe-compliance-by-resource `
        --resource-type "AWS::IAM::Policy" `
        --resource-id $resourceId 2>$null | ConvertFrom-Json
    
    if ($compliance.ComplianceByResources) {
        Write-Host "Config Compliance Status: $($compliance.ComplianceByResources[0].Compliance.ComplianceType)" -ForegroundColor Cyan
    }
    
    # Check Security Hub findings
    Write-Host "`nChecking Security Hub findings..." -ForegroundColor Yellow
    $findings = aws securityhub get-findings `
        --filters "{`"ResourceId`": [{`"Value`": `"$policyArn`", `"Comparison`": `"EQUALS`"}]}" | ConvertFrom-Json
    
    if ($findings.Findings.Count -gt 0) {
        Write-Host "✅ Security Hub detected $($findings.Findings.Count) finding(s):" -ForegroundColor Green
        $findings.Findings | ForEach-Object {
            Write-Host "  - Title: $($_.Title)" -ForegroundColor Cyan
            Write-Host "    Severity: $($_.Severity.Label)" -ForegroundColor $(
                switch ($_.Severity.Label) {
                    "CRITICAL" { "Red" }
                    "HIGH" { "Red" }
                    "MEDIUM" { "Yellow" }
                    default { "Gray" }
                }
            )
        }
    } else {
        Write-Host "⚠️ No Security Hub findings yet (may take up to 5 minutes)" -ForegroundColor Yellow
    }
    
    # Cleanup
    Write-Host "`nCleaning up test policy..." -ForegroundColor Yellow
    aws iam delete-policy --policy-arn $policyArn
    Write-Host "✅ Test policy deleted" -ForegroundColor Green
    
    Write-Host "`n✅ Detection test complete!" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error during test: $_" -ForegroundColor Red
}
