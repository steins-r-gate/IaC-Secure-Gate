#!/bin/bash
# ==================================================================
# IaC Secure Gate - E2E Test: S3 Public Bucket
# ==================================================================
# Measures MTTD and MTTR for S3 public access detection & remediation
# Usage: ./e2e-test-s3.sh [--timeout 20]
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

TIMEOUT_MINUTES=20
POLL_INTERVAL=10

# Resource naming
TIMESTAMP=$(date +%s)
TEST_BUCKET_NAME="e2e-test-bucket-${ACCOUNT_ID}-${TIMESTAMP}"
BUCKET_ARN=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Results
MTTD_SECONDS="N/A"
MTTR_SECONDS="N/A"
DETECTION_STATUS="NOT_STARTED"
REMEDIATION_STATUS="NOT_STARTED"

# ==================================================================
# Parse Arguments
# ==================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT_MINUTES="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--timeout MINUTES] [--debug]"
            echo "  --timeout  Detection timeout in minutes (default: 20)"
            echo "  --debug    Show additional debug information"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# ==================================================================
# Helper Functions
# ==================================================================

get_timestamp() { date +%s; }

format_duration() {
    local seconds=$1
    if [ -z "$seconds" ] || [ "$seconds" = "N/A" ]; then
        echo "N/A"
        return
    fi
    local minutes=$((seconds / 60))
    local remaining=$((seconds % 60))
    if [ $minutes -gt 0 ]; then
        echo "${minutes}m ${remaining}s"
    else
        echo "${seconds}s"
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_time() { echo -e "${MAGENTA}[TIME]${NC} $1"; }
print_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

cleanup() {
    echo ""
    print_step "Cleaning up test resources..."

    if aws s3api head-bucket --bucket "${TEST_BUCKET_NAME}" 2>/dev/null; then
        aws s3 rb "s3://${TEST_BUCKET_NAME}" --force 2>/dev/null || true
        print_success "S3 bucket deleted"
    fi
}

trap cleanup EXIT

# ==================================================================
# Main Test
# ==================================================================

print_header "E2E TEST: S3 PUBLIC BUCKET"

echo -e "Account:  ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:   ${CYAN}${REGION}${NC}"
echo -e "Timeout:  ${CYAN}${TIMEOUT_MINUTES} minutes${NC}"
echo -e "Resource: ${CYAN}${TEST_BUCKET_NAME}${NC}"
echo ""

# ----------------------------------------------
# Step 1: Create the violation
# ----------------------------------------------
print_step "Creating S3 bucket with public access enabled..."
START_TIME=$(get_timestamp)

# Create bucket
aws s3api create-bucket \
    --bucket "${TEST_BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null

BUCKET_ARN="arn:aws:s3:::${TEST_BUCKET_NAME}"
print_success "Bucket created: ${TEST_BUCKET_NAME}"

# Disable public access block (makes it vulnerable)
print_step "Disabling public access block..."
aws s3api put-public-access-block \
    --bucket "${TEST_BUCKET_NAME}" \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

print_success "Public access block disabled (bucket is now vulnerable)"
print_time "Violation created at: $(date -u +"%H:%M:%S UTC")"
echo ""

# ----------------------------------------------
# Step 2: Wait for Security Hub detection
# ----------------------------------------------
print_step "Waiting for Security Hub detection..."
print_debug "Bucket ARN: ${BUCKET_ARN}"

TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
ELAPSED=0
DETECTION_TIME=""

# S3 findings can use different ResourceId formats, try multiple approaches
while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
    # Try 1: Search by bucket ARN
    FINDING=$(aws securityhub get-findings \
        --filters "{
            \"ResourceId\": [{\"Value\": \"${BUCKET_ARN}\", \"Comparison\": \"EQUALS\"}],
            \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
            \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
        }" \
        --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")

    if [ "$FINDING" = "None" ] || [ -z "$FINDING" ] || [ "$FINDING" = "null" ]; then
        # Try 2: Search by bucket name with CONTAINS
        FINDING=$(aws securityhub get-findings \
            --filters "{
                \"ResourceId\": [{\"Value\": \"${TEST_BUCKET_NAME}\", \"Comparison\": \"CONTAINS\"}],
                \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
                \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}],
                \"Type\": [{\"Value\": \"Software and Configuration Checks\", \"Comparison\": \"PREFIX\"}]
            }" \
            --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")
    fi

    if [ "$FINDING" != "None" ] && [ -n "$FINDING" ] && [ "$FINDING" != "null" ]; then
        DETECTION_TIME=$(get_timestamp)
        MTTD_SECONDS=$((DETECTION_TIME - START_TIME))
        DETECTION_STATUS="SUCCESS"
        echo ""
        print_success "Finding detected!"
        print_time "MTTD: $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS}s)"
        print_debug "Finding ID: ${FINDING}"
        break
    fi

    # Debug: Show any S3-related findings
    if [ "$DEBUG" = "true" ] && [ $((ELAPSED % 60)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo ""
        print_debug "Checking for any recent S3 findings..."
        aws securityhub get-findings \
            --filters "{
                \"ResourceType\": [{\"Value\": \"AwsS3Bucket\", \"Comparison\": \"EQUALS\"}],
                \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
            }" \
            --query "Findings[*].{Id:Id,Resource:Resources[0].Id}" --output table --region "${REGION}" 2>/dev/null | head -10 || true
    fi

    # Progress indicator
    printf "\r  Elapsed: $(format_duration $ELAPSED) / $(format_duration $TIMEOUT_SECONDS)..."
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$DETECTION_STATUS" != "SUCCESS" ]; then
    echo ""
    print_warning "Detection timeout after ${TIMEOUT_MINUTES} minutes"
    print_warning "S3 bucket public access may take longer to be detected by Security Hub"
    print_warning "Consider running the demo-test.sh script for direct Lambda invocation testing"
    DETECTION_STATUS="TIMEOUT"
fi

echo ""

# ----------------------------------------------
# Step 3: Wait for remediation (DynamoDB record)
# ----------------------------------------------
if [ "$DETECTION_STATUS" = "SUCCESS" ]; then
    print_step "Waiting for auto-remediation..."

    REMEDIATION_TIMEOUT=180
    ELAPSED=0

    while [ $ELAPSED -lt $REMEDIATION_TIMEOUT ]; do
        RECORD=$(aws dynamodb scan \
            --table-name "${DYNAMODB_TABLE}" \
            --filter-expression "contains(resource_arn, :pattern)" \
            --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_BUCKET_NAME}\"}}" \
            --query "Items[0].finding_id.S" --output text --region "${REGION}" 2>/dev/null || echo "None")

        if [ "$RECORD" != "None" ] && [ -n "$RECORD" ] && [ "$RECORD" != "null" ]; then
            REMEDIATION_TIME=$(get_timestamp)
            MTTR_SECONDS=$((REMEDIATION_TIME - DETECTION_TIME))
            REMEDIATION_STATUS="SUCCESS"
            echo ""
            print_success "Remediation confirmed!"
            print_time "MTTR: $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS}s)"
            break
        fi

        printf "\r  Waiting for DynamoDB record: ${ELAPSED}s / ${REMEDIATION_TIMEOUT}s..."
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done

    if [ "$REMEDIATION_STATUS" != "SUCCESS" ]; then
        echo ""
        print_warning "Remediation not confirmed within ${REMEDIATION_TIMEOUT}s"
        REMEDIATION_STATUS="TIMEOUT"
    fi
fi

# ----------------------------------------------
# Step 4: Verify remediation
# ----------------------------------------------
if [ "$REMEDIATION_STATUS" = "SUCCESS" ]; then
    echo ""
    print_step "Verifying bucket was remediated..."

    PUBLIC_ACCESS=$(aws s3api get-public-access-block --bucket "${TEST_BUCKET_NAME}" \
        --query "PublicAccessBlockConfiguration.BlockPublicAcls" --output text 2>/dev/null || echo "false")

    if [ "$PUBLIC_ACCESS" = "True" ] || [ "$PUBLIC_ACCESS" = "true" ]; then
        print_success "Public access is now blocked"
    else
        print_warning "Public access block status: ${PUBLIC_ACCESS}"
    fi
fi

# ==================================================================
# Results Summary
# ==================================================================

print_header "TEST RESULTS"

TOTAL_SECONDS="N/A"
if [ "$MTTD_SECONDS" != "N/A" ] && [ "$MTTR_SECONDS" != "N/A" ]; then
    TOTAL_SECONDS=$((MTTD_SECONDS + MTTR_SECONDS))
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           S3 PUBLIC BUCKET - E2E TEST RESULTS             ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Resource: ${CYAN}${TEST_BUCKET_NAME}${NC}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}MTTD:${NC} $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS} seconds)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}MTTR:${NC} $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS} seconds)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}Total:${NC} $(format_duration $TOTAL_SECONDS)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  Detection:   ${DETECTION_STATUS}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  Remediation: ${REMEDIATION_STATUS}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}                                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Targets: MTTD < 15min, MTTR < 5min                        ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Save results
RESULTS_FILE="${RESULTS_DIR}/e2e-s3-results-$(date +%Y%m%d-%H%M%S).txt"
cat > "${RESULTS_FILE}" << EOF
IaC Secure Gate - E2E Test Results: S3 Public Bucket
=====================================================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Account: ${ACCOUNT_ID}
Region: ${REGION}

Resource: ${TEST_BUCKET_NAME}
Bucket ARN: ${BUCKET_ARN}

Results:
--------
MTTD (Mean Time to Detect):    $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS} seconds)
MTTR (Mean Time to Remediate): $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS} seconds)
Total E2E Time:                $(format_duration $TOTAL_SECONDS)

Status:
- Detection:   ${DETECTION_STATUS}
- Remediation: ${REMEDIATION_STATUS}

Target Metrics:
- MTTD Target: < 15 minutes (900 seconds)
- MTTR Target: < 5 minutes (300 seconds)

Notes:
- S3 bucket public access detection depends on AWS Config rules
- Detection time can vary based on Config evaluation frequency
EOF

print_success "Results saved to: ${RESULTS_FILE}"
echo ""
