#!/bin/bash
set -e

REGION="eu-west-1"
RESULTS_FILE="PHASE1-TESTING-RESULTS-$(date +%Y%m%d-%H%M%S).txt"

echo "=====================================================" | tee -a $RESULTS_FILE
echo "Phase 1 Validation Testing" | tee -a $RESULTS_FILE
echo "Started: $(date -Iseconds)" | tee -a $RESULTS_FILE
echo "=====================================================" | tee -a $RESULTS_FILE

# Function to convert seconds to human-readable
format_time() {
    local seconds=$1
    printf "%02d:%02d (mm:ss)" $((seconds/60)) $((seconds%60))
}

# Scenario 1: S3 Bucket with Public Read Access (Config Detection)
echo -e "\n[Scenario 1] S3 Bucket with Public Read Access (Config Detection)" | tee -a $RESULTS_FILE
echo "Creating S3 bucket with public read policy..." | tee -a $RESULTS_FILE
TEST1_START=$(date +%s)
BUCKET1_NAME="iac-secure-gate-test-config-$(date +%s)"

aws s3api create-bucket --bucket "$BUCKET1_NAME" --region $REGION --create-bucket-configuration LocationConstraint=$REGION
aws s3api delete-public-access-block --bucket "$BUCKET1_NAME"

# Create public read policy
cat > scripts/temp-config-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET1_NAME/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$BUCKET1_NAME" --policy file://scripts/temp-config-bucket-policy.json

echo "Waiting 30 seconds for Config to record the resource..." | tee -a $RESULTS_FILE
sleep 30

echo "Triggering Config rule evaluation..." | tee -a $RESULTS_FILE
aws configservice start-config-rules-evaluation --config-rule-names s3-bucket-public-read-prohibited --region $REGION

echo "Waiting for Config detection (checking every 30 seconds)..." | tee -a $RESULTS_FILE
while true; do
  # Check Config rule compliance for the bucket
  NON_COMPLIANT=$(aws configservice get-compliance-details-by-config-rule \
    --config-rule-name s3-bucket-public-read-prohibited \
    --region $REGION \
    --query "EvaluationResults[?EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId=='$BUCKET1_NAME'].ComplianceType" \
    --output text 2>/dev/null || echo "")

  if [ "$NON_COMPLIANT" == "NON_COMPLIANT" ]; then
    TEST1_END=$(date +%s)
    TEST1_MTTD=$((TEST1_END - TEST1_START))
    echo "✅ DETECTED! MTTD: $TEST1_MTTD seconds ($(format_time $TEST1_MTTD))" | tee -a $RESULTS_FILE
    break
  fi

  ELAPSED=$(($(date +%s) - TEST1_START))
  echo "  ⏳ Still waiting... (${ELAPSED}s elapsed)"

  # Timeout after 5 minutes
  if [ $ELAPSED -gt 300 ]; then
    echo "❌ TIMEOUT: No detection after 5 minutes" | tee -a $RESULTS_FILE
    TEST1_MTTD="TIMEOUT"
    break
  fi

  sleep 30
done

echo "Cleaning up test bucket..." | tee -a $RESULTS_FILE
aws s3api delete-bucket-policy --bucket "$BUCKET1_NAME" 2>/dev/null || true
aws s3api delete-bucket --bucket "$BUCKET1_NAME" 2>/dev/null || true
rm -f scripts/temp-config-bucket-policy.json
echo "" | tee -a $RESULTS_FILE

# Scenario 2: Wildcard IAM Policy
echo -e "\n[Scenario 2] Wildcard IAM Policy" | tee -a $RESULTS_FILE
echo "Creating wildcard policy..." | tee -a $RESULTS_FILE
TEST2_START=$(date +%s)
POLICY_ARN=$(aws iam create-policy \
  --policy-name test-wildcard-policy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --tags Key=Test,Value=Phase1Validation \
  --query 'Policy.Arn' \
  --output text)

echo "Waiting for Security Hub detection (checking every 60 seconds)..." | tee -a $RESULTS_FILE
while true; do
  FINDINGS=$(aws securityhub get-findings \
    --filters "{\"ResourceId\":[{\"Value\":\"$POLICY_ARN\",\"Comparison\":\"EQUALS\"}]}" \
    --region $REGION \
    --query 'length(Findings)' \
    --output text 2>/dev/null || echo "0")

  if [ "$FINDINGS" != "0" ]; then
    TEST2_END=$(date +%s)
    TEST2_MTTD=$((TEST2_END - TEST2_START))
    echo "✅ DETECTED! MTTD: $TEST2_MTTD seconds ($(format_time $TEST2_MTTD))" | tee -a $RESULTS_FILE
    break
  fi

  ELAPSED=$(($(date +%s) - TEST2_START))
  echo "  ⏳ Still waiting... (${ELAPSED}s elapsed)"

  # Timeout after 35 minutes
  if [ $ELAPSED -gt 2100 ]; then
    echo "❌ TIMEOUT: No detection after 35 minutes" | tee -a $RESULTS_FILE
    TEST2_MTTD="TIMEOUT"
    break
  fi

  sleep 60
done

echo "Cleaning up test policy..." | tee -a $RESULTS_FILE
aws iam delete-policy --policy-arn "$POLICY_ARN"
echo "" | tee -a $RESULTS_FILE

# Scenario 3: External Access Detection (Public S3 Bucket)
echo -e "\n[Scenario 3] External Access Detection (Public S3 Bucket)" | tee -a $RESULTS_FILE
echo "Creating S3 bucket with public access..." | tee -a $RESULTS_FILE
TEST3_START=$(date +%s)
BUCKET_NAME="iac-secure-gate-test-public-$(date +%s)"

aws s3api create-bucket --bucket "$BUCKET_NAME" --region $REGION --create-bucket-configuration LocationConstraint=$REGION
aws s3api delete-public-access-block --bucket "$BUCKET_NAME"

# Create public bucket policy
cat > scripts/temp-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file://scripts/temp-bucket-policy.json

ANALYZER_ARN=$(aws accessanalyzer list-analyzers --region $REGION \
  --query 'analyzers[0].arn' \
  --output text)

echo "Waiting for Access Analyzer detection (checking every 30 seconds)..." | tee -a $RESULTS_FILE
while true; do
  FINDINGS=$(aws accessanalyzer list-findings \
    --analyzer-arn "$ANALYZER_ARN" \
    --region $REGION \
    --filter "{\"resource\":{\"eq\":[\"arn:aws:s3:::$BUCKET_NAME\"]}}" \
    --query 'length(findings)' \
    --output text 2>/dev/null || echo "0")

  if [ "$FINDINGS" != "0" ]; then
    TEST3_END=$(date +%s)
    TEST3_MTTD=$((TEST3_END - TEST3_START))
    echo "✅ DETECTED! MTTD: $TEST3_MTTD seconds ($(format_time $TEST3_MTTD))" | tee -a $RESULTS_FILE
    break
  fi

  ELAPSED=$(($(date +%s) - TEST3_START))
  echo "  ⏳ Still waiting... (${ELAPSED}s elapsed)"

  # Timeout after 5 minutes
  if [ $ELAPSED -gt 300 ]; then
    echo "❌ TIMEOUT: No detection after 5 minutes" | tee -a $RESULTS_FILE
    TEST3_MTTD="TIMEOUT"
    break
  fi

  sleep 30
done

echo "Cleaning up test bucket..." | tee -a $RESULTS_FILE
aws s3api delete-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null || true
aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null || true
rm -f scripts/temp-bucket-policy.json
echo "" | tee -a $RESULTS_FILE

# Summary
echo -e "\n=====================================================" | tee -a $RESULTS_FILE
echo "PHASE 1 TESTING SUMMARY" | tee -a $RESULTS_FILE
echo "=====================================================" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE
echo "Scenario 1 (S3 Bucket Public Read - Config):" | tee -a $RESULTS_FILE
echo "  Expected MTTD: 1-3 minutes" | tee -a $RESULTS_FILE
echo "  Actual MTTD:   $TEST1_MTTD seconds" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE
echo "Scenario 2 (Wildcard IAM Policy):" | tee -a $RESULTS_FILE
echo "  Expected MTTD: 15-30 minutes" | tee -a $RESULTS_FILE
echo "  Actual MTTD:   $TEST2_MTTD seconds" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE
echo "Scenario 3 (Public S3 Bucket Detection):" | tee -a $RESULTS_FILE
echo "  Expected MTTD: 1-3 minutes" | tee -a $RESULTS_FILE
echo "  Actual MTTD:   $TEST3_MTTD seconds" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE
echo "Results saved to: $RESULTS_FILE" | tee -a $RESULTS_FILE
echo "Testing completed: $(date -Iseconds)" | tee -a $RESULTS_FILE
echo "=====================================================" | tee -a $RESULTS_FILE

# Success criteria check
echo -e "\nSUCCESS CRITERIA CHECK:" | tee -a $RESULTS_FILE
ALL_PASSED=true

if [ "$TEST1_MTTD" != "TIMEOUT" ] && [ "$TEST1_MTTD" -lt 180 ]; then
  echo "✅ Scenario 1: PASSED (MTTD < 3 min)" | tee -a $RESULTS_FILE
else
  echo "❌ Scenario 1: FAILED" | tee -a $RESULTS_FILE
  ALL_PASSED=false
fi

if [ "$TEST2_MTTD" != "TIMEOUT" ] && [ "$TEST2_MTTD" -lt 1800 ]; then
  echo "✅ Scenario 2: PASSED (MTTD < 30 min)" | tee -a $RESULTS_FILE
else
  echo "❌ Scenario 2: FAILED" | tee -a $RESULTS_FILE
  ALL_PASSED=false
fi

if [ "$TEST3_MTTD" != "TIMEOUT" ] && [ "$TEST3_MTTD" -lt 180 ]; then
  echo "✅ Scenario 3: PASSED (MTTD < 3 min)" | tee -a $RESULTS_FILE
else
  echo "❌ Scenario 3: FAILED" | tee -a $RESULTS_FILE
  ALL_PASSED=false
fi

if [ "$ALL_PASSED" = true ]; then
  echo -e "\n🎉 ALL TESTS PASSED! Phase 1 detection baseline is working as expected." | tee -a $RESULTS_FILE
  exit 0
else
  echo -e "\n⚠️  SOME TESTS FAILED. Review results above." | tee -a $RESULTS_FILE
  exit 1
fi
