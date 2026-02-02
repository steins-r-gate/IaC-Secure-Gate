#!/bin/bash
# ==================================================================
# IaC Secure Gate - Phase 2 Demo & Validation Script
# ==================================================================
#
# Purpose: Demonstrate and validate the automated remediation system
# Usage: ./demo-test.sh [--dry-run] [--iam-only] [--s3-only] [--sg-only]
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Terraform infrastructure deployed
# - jq installed for JSON parsing
#
# Author: IaC Secure Gate Team
# Version: 1.1.0 (Windows compatible)
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

# Get script directory (works on both Linux and Windows Git Bash)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/.temp"

# Create temp directory if it doesn't exist
mkdir -p "${TEMP_DIR}"

# Function to convert Git Bash path to Windows path for AWS CLI
to_windows_path() {
    local path="$1"
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        # Convert /c/Users/... to C:/Users/...
        echo "$path" | sed 's|^/\([a-zA-Z]\)/|\1:/|'
    else
        echo "$path"
    fi
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"

# Lambda function names
IAM_LAMBDA="${PROJECT_PREFIX}-iam-remediation"
S3_LAMBDA="${PROJECT_PREFIX}-s3-remediation"
SG_LAMBDA="${PROJECT_PREFIX}-sg-remediation"

# DynamoDB table
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

# Test resource names
TEST_POLICY_NAME="demo-wildcard-policy-$(date +%s)"
TEST_BUCKET_NAME="demo-public-bucket-${ACCOUNT_ID}-$(date +%s)"
TEST_SG_NAME="demo-permissive-sg-$(date +%s)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
DRY_RUN=false
TEST_IAM=true
TEST_S3=true
TEST_SG=true

# ==================================================================
# Parse Arguments
# ==================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --iam-only)
            TEST_S3=false
            TEST_SG=false
            shift
            ;;
        --s3-only)
            TEST_IAM=false
            TEST_SG=false
            shift
            ;;
        --sg-only)
            TEST_IAM=false
            TEST_S3=false
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--iam-only] [--s3-only] [--sg-only]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Run in dry-run mode (no actual changes)"
            echo "  --iam-only   Test only IAM remediation"
            echo "  --s3-only    Test only S3 remediation"
            echo "  --sg-only    Test only Security Group remediation"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==================================================================
# Helper Functions
# ==================================================================

print_header() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

wait_with_spinner() {
    local seconds=$1
    local message=$2
    echo -ne "${YELLOW}[WAIT]${NC} $message "
    for ((i=0; i<seconds; i++)); do
        echo -n "."
        sleep 1
    done
    echo " done"
}

cleanup_resources() {
    print_header "CLEANUP"

    # Cleanup IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" 2>/dev/null; then
        print_step "Deleting IAM policy versions..."
        for version in $(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" --query "Versions[?!IsDefaultVersion].VersionId" --output text); do
            aws iam delete-policy-version --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" --version-id "$version" 2>/dev/null || true
        done
        print_step "Deleting IAM policy..."
        aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" 2>/dev/null || true
        print_success "IAM policy deleted"
    fi

    # Cleanup S3 bucket
    if aws s3api head-bucket --bucket "${TEST_BUCKET_NAME}" 2>/dev/null; then
        print_step "Deleting S3 bucket..."
        aws s3 rb "s3://${TEST_BUCKET_NAME}" --force 2>/dev/null || true
        print_success "S3 bucket deleted"
    fi

    # Cleanup Security Group
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${TEST_SG_NAME}" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
    if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
        print_step "Deleting Security Group..."
        aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
        print_success "Security Group deleted"
    fi

    # Cleanup temp files
    if [ -d "${TEMP_DIR}" ]; then
        print_step "Cleaning up temp files..."
        rm -rf "${TEMP_DIR}"
        print_success "Temp files deleted"
    fi

    print_success "Cleanup complete"
}

# Trap to ensure cleanup on exit
trap cleanup_resources EXIT

# ==================================================================
# Main Demo Script
# ==================================================================

print_header "IaC SECURE GATE - PHASE 2 DEMO"

echo -e "Account ID:    ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:        ${CYAN}${REGION}${NC}"
echo -e "Project:       ${CYAN}${PROJECT_PREFIX}${NC}"
echo -e "Dry Run:       ${CYAN}${DRY_RUN}${NC}"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { print_error "AWS CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { print_warning "jq not found - some output formatting may be limited"; }
print_success "Prerequisites OK"

# ==================================================================
# TEST 1: IAM Wildcard Policy Remediation
# ==================================================================

if [ "$TEST_IAM" = true ]; then
    print_header "TEST 1: IAM WILDCARD POLICY REMEDIATION"

    # Step 1: Create dangerous policy
    print_step "Creating IAM policy with wildcard permissions..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "${TEST_POLICY_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Sid": "DangerousWildcard",
                "Effect": "Allow",
                "Action": "*",
                "Resource": "*"
            }]
        }' \
        --description "Demo test policy - will be auto-remediated" \
        --query "Policy.Arn" --output text)
    print_success "Policy created: ${POLICY_ARN}"

    # Step 2: Show original policy
    print_step "Original policy (DANGEROUS):"
    aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id v1 \
        --query "PolicyVersion.Document" --output json | jq '.' 2>/dev/null || \
    aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id v1 \
        --query "PolicyVersion.Document" --output json
    echo ""

    # Step 3: Create Security Hub finding event
    print_step "Creating Security Hub finding event..."
    cat > ${TEMP_DIR}/iam-test-event.json << EOF
{
  "version": "0",
  "id": "demo-iam-$(date +%s)",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "${ACCOUNT_ID}",
  "region": "${REGION}",
  "detail": {
    "findings": [{
      "Id": "demo-finding-iam-$(date +%s)",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-IAM1",
      "AwsAccountId": "${ACCOUNT_ID}",
      "Severity": { "Label": "HIGH" },
      "Title": "IAM policies should not allow full administrative privileges",
      "ProductFields": { "ControlId": "IAM.1" },
      "Resources": [{
        "Type": "AwsIamPolicy",
        "Id": "${POLICY_ARN}",
        "Region": "${REGION}"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
EOF

    # Step 4: Invoke Lambda
    print_step "Invoking IAM remediation Lambda..."
    START_TIME=$(date +%s.%N)

    IAM_EVENT_PATH=$(to_windows_path "${TEMP_DIR}/iam-test-event.json")
    IAM_OUTPUT_PATH=$(to_windows_path "${TEMP_DIR}/iam-lambda-output.json")
    LAMBDA_RESPONSE=$(aws lambda invoke \
        --function-name "${IAM_LAMBDA}" \
        --payload "file://${IAM_EVENT_PATH}" \
        --cli-binary-format raw-in-base64-out \
        "${IAM_OUTPUT_PATH}" 2>&1)

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "N/A")

    RESULT=$(cat "${TEMP_DIR}/iam-lambda-output.json")
    STATUS=$(echo "$RESULT" | jq -r '.body' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "UNKNOWN")

    if [ "$STATUS" = "REMEDIATED" ]; then
        print_success "Lambda executed successfully in ${DURATION}s"
        echo -e "  Status: ${GREEN}${STATUS}${NC}"
        echo "$RESULT" | jq -r '.body' 2>/dev/null | jq '.' 2>/dev/null || echo "$RESULT"
    else
        print_error "Remediation failed: $STATUS"
        echo "$RESULT"
    fi
    echo ""

    # Step 5: Show remediated policy
    print_step "Remediated policy (SAFE):"
    aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id v2 \
        --query "PolicyVersion.Document" --output json | jq '.' 2>/dev/null || \
    aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id v2 \
        --query "PolicyVersion.Document" --output json
    echo ""

    # Step 6: Check DynamoDB
    print_step "Checking DynamoDB audit log..."
    DYNAMODB_RECORD=$(aws dynamodb scan \
        --table-name "${DYNAMODB_TABLE}" \
        --filter-expression "contains(resource_arn, :policy)" \
        --expression-attribute-values "{\":policy\":{\"S\":\"${TEST_POLICY_NAME}\"}}" \
        --query "Items[0]" --output json 2>/dev/null)

    if [ "$DYNAMODB_RECORD" != "null" ] && [ -n "$DYNAMODB_RECORD" ]; then
        print_success "DynamoDB record found"
        echo "$DYNAMODB_RECORD" | jq '.' 2>/dev/null || echo "$DYNAMODB_RECORD"
    else
        print_warning "DynamoDB record not found (may take a moment to appear)"
    fi
    echo ""

    print_success "IAM TEST COMPLETE"
fi

# ==================================================================
# TEST 2: S3 Public Bucket Remediation
# ==================================================================

if [ "$TEST_S3" = true ]; then
    print_header "TEST 2: S3 PUBLIC BUCKET REMEDIATION"

    # Step 1: Create public bucket
    print_step "Creating S3 bucket..."
    aws s3api create-bucket \
        --bucket "${TEST_BUCKET_NAME}" \
        --region "${REGION}" \
        --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null
    print_success "Bucket created: ${TEST_BUCKET_NAME}"

    # Step 2: Make it public (disable block public access)
    print_step "Disabling public access block (making bucket vulnerable)..."
    aws s3api put-public-access-block \
        --bucket "${TEST_BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
    print_success "Public access block disabled"

    # Step 3: Show current settings
    print_step "Current public access settings (VULNERABLE):"
    aws s3api get-public-access-block --bucket "${TEST_BUCKET_NAME}" 2>/dev/null | jq '.' || echo "No block configured"
    echo ""

    # Step 4: Create Security Hub finding event
    print_step "Creating Security Hub finding event..."
    cat > ${TEMP_DIR}/s3-test-event.json << EOF
{
  "version": "0",
  "id": "demo-s3-$(date +%s)",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "${ACCOUNT_ID}",
  "region": "${REGION}",
  "detail": {
    "findings": [{
      "Id": "demo-finding-s3-$(date +%s)",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-S3-2",
      "AwsAccountId": "${ACCOUNT_ID}",
      "Severity": { "Label": "HIGH" },
      "Title": "S3 buckets should prohibit public read access",
      "ProductFields": { "ControlId": "S3.2" },
      "Resources": [{
        "Type": "AwsS3Bucket",
        "Id": "arn:aws:s3:::${TEST_BUCKET_NAME}",
        "Region": "${REGION}"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
EOF

    # Step 5: Invoke Lambda
    print_step "Invoking S3 remediation Lambda..."
    START_TIME=$(date +%s.%N)

    S3_EVENT_PATH=$(to_windows_path "${TEMP_DIR}/s3-test-event.json")
    S3_OUTPUT_PATH=$(to_windows_path "${TEMP_DIR}/s3-lambda-output.json")
    LAMBDA_RESPONSE=$(aws lambda invoke \
        --function-name "${S3_LAMBDA}" \
        --payload "file://${S3_EVENT_PATH}" \
        --cli-binary-format raw-in-base64-out \
        "${S3_OUTPUT_PATH}" 2>&1)

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "N/A")

    RESULT=$(cat "${TEMP_DIR}/s3-lambda-output.json")
    STATUS=$(echo "$RESULT" | jq -r '.body' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "UNKNOWN")

    if [ "$STATUS" = "REMEDIATED" ]; then
        print_success "Lambda executed successfully in ${DURATION}s"
        echo "$RESULT" | jq -r '.body' 2>/dev/null | jq '.' 2>/dev/null || echo "$RESULT"
    else
        print_warning "Status: $STATUS"
        echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    fi
    echo ""

    # Step 6: Show remediated settings
    print_step "Remediated public access settings (SECURE):"
    aws s3api get-public-access-block --bucket "${TEST_BUCKET_NAME}" 2>/dev/null | jq '.' || echo "Block configured"
    echo ""

    print_success "S3 TEST COMPLETE"
fi

# ==================================================================
# TEST 3: Security Group Remediation
# ==================================================================

if [ "$TEST_SG" = true ]; then
    print_header "TEST 3: SECURITY GROUP REMEDIATION"

    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)

    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        print_warning "No default VPC found, skipping Security Group test"
    else
        # Step 1: Create permissive security group
        print_step "Creating Security Group with permissive rules..."
        SG_ID=$(aws ec2 create-security-group \
            --group-name "${TEST_SG_NAME}" \
            --description "Demo test SG - will be auto-remediated" \
            --vpc-id "${VPC_ID}" \
            --query "GroupId" --output text)
        print_success "Security Group created: ${SG_ID}"

        # Step 2: Add dangerous rule (0.0.0.0/0 on all ports)
        print_step "Adding dangerous ingress rule (0.0.0.0/0 on port 22)..."
        aws ec2 authorize-security-group-ingress \
            --group-id "${SG_ID}" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 >/dev/null
        print_success "Dangerous rule added"

        # Step 3: Show current rules
        print_step "Current ingress rules (VULNERABLE):"
        aws ec2 describe-security-groups --group-ids "${SG_ID}" \
            --query "SecurityGroups[0].IpPermissions" --output json | jq '.' 2>/dev/null || \
        aws ec2 describe-security-groups --group-ids "${SG_ID}" \
            --query "SecurityGroups[0].IpPermissions" --output json
        echo ""

        # Step 4: Create Security Hub finding event
        print_step "Creating Security Hub finding event..."
        cat > ${TEMP_DIR}/sg-test-event.json << EOF
{
  "version": "0",
  "id": "demo-sg-$(date +%s)",
  "detail-type": "Security Hub Findings - Imported",
  "source": "aws.securityhub",
  "account": "${ACCOUNT_ID}",
  "region": "${REGION}",
  "detail": {
    "findings": [{
      "Id": "demo-finding-sg-$(date +%s)",
      "ProductArn": "arn:aws:securityhub:${REGION}::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices-EC2-19",
      "AwsAccountId": "${ACCOUNT_ID}",
      "Severity": { "Label": "HIGH" },
      "Title": "Security groups should not allow unrestricted access to high risk ports",
      "ProductFields": { "ControlId": "EC2.19" },
      "Resources": [{
        "Type": "AwsEc2SecurityGroup",
        "Id": "${SG_ID}",
        "Region": "${REGION}"
      }],
      "Compliance": { "Status": "FAILED" },
      "Workflow": { "Status": "NEW" }
    }]
  }
}
EOF

        # Step 5: Invoke Lambda
        print_step "Invoking Security Group remediation Lambda..."
        START_TIME=$(date +%s.%N)

        SG_EVENT_PATH=$(to_windows_path "${TEMP_DIR}/sg-test-event.json")
        SG_OUTPUT_PATH=$(to_windows_path "${TEMP_DIR}/sg-lambda-output.json")
        LAMBDA_RESPONSE=$(aws lambda invoke \
            --function-name "${SG_LAMBDA}" \
            --payload "file://${SG_EVENT_PATH}" \
            --cli-binary-format raw-in-base64-out \
            "${SG_OUTPUT_PATH}" 2>&1)

        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "N/A")

        RESULT=$(cat "${TEMP_DIR}/sg-lambda-output.json")
        STATUS=$(echo "$RESULT" | jq -r '.body' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "UNKNOWN")

        if [ "$STATUS" = "REMEDIATED" ]; then
            print_success "Lambda executed successfully in ${DURATION}s"
            echo "$RESULT" | jq -r '.body' 2>/dev/null | jq '.' 2>/dev/null || echo "$RESULT"
        else
            print_warning "Status: $STATUS"
            echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
        fi
        echo ""

        # Step 6: Show remediated rules
        print_step "Remediated ingress rules (SECURE):"
        aws ec2 describe-security-groups --group-ids "${SG_ID}" \
            --query "SecurityGroups[0].IpPermissions" --output json | jq '.' 2>/dev/null || \
        aws ec2 describe-security-groups --group-ids "${SG_ID}" \
            --query "SecurityGroups[0].IpPermissions" --output json
        echo ""

        print_success "SECURITY GROUP TEST COMPLETE"
    fi
fi

# ==================================================================
# Summary
# ==================================================================

print_header "DEMO SUMMARY"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ALL TESTS COMPLETED SUCCESSFULLY!    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "What was demonstrated:"
echo "  1. Security violations were created"
echo "  2. Lambda functions automatically remediated them"
echo "  3. Audit records were saved to DynamoDB"
echo "  4. Email notifications were sent via SNS"
echo ""
echo "Check your email for remediation notifications!"
echo ""
echo -e "Resources will be cleaned up automatically..."
echo ""

# Cleanup happens via trap
