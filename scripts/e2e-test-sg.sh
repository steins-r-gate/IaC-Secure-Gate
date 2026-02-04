#!/bin/bash
# ==================================================================
# IaC Secure Gate - E2E Test: Security Group Open Access
# ==================================================================
# Measures MTTD and MTTR for Security Group 0.0.0.0/0 detection & remediation
# Usage: ./e2e-test-sg.sh [--timeout 20]
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

TIMEOUT_MINUTES=20
POLL_INTERVAL=10

# Resource naming
TIMESTAMP=$(date +%s)
TEST_SG_NAME="e2e-test-sg-${TIMESTAMP}"
TEST_SG_ID=""
VPC_ID=""

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

    if [ -n "$TEST_SG_ID" ]; then
        aws ec2 delete-security-group --group-id "$TEST_SG_ID" --region "${REGION}" 2>/dev/null || true
        print_success "Security Group deleted"
    fi
}

trap cleanup EXIT

# ==================================================================
# Main Test
# ==================================================================

print_header "E2E TEST: SECURITY GROUP OPEN ACCESS"

echo -e "Account:  ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:   ${CYAN}${REGION}${NC}"
echo -e "Timeout:  ${CYAN}${TIMEOUT_MINUTES} minutes${NC}"
echo ""

# ----------------------------------------------
# Step 0: Get default VPC
# ----------------------------------------------
print_step "Finding default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" --output text --region "${REGION}" 2>/dev/null || echo "None")

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    print_error "No default VPC found in ${REGION}"
    print_warning "Security Group test requires a VPC"
    exit 1
fi

print_success "Using VPC: ${VPC_ID}"
echo ""

# ----------------------------------------------
# Step 1: Create the violation
# ----------------------------------------------
print_step "Creating Security Group with open SSH access (0.0.0.0/0)..."
START_TIME=$(get_timestamp)

TEST_SG_ID=$(aws ec2 create-security-group \
    --group-name "${TEST_SG_NAME}" \
    --description "E2E test - open SSH to 0.0.0.0/0" \
    --vpc-id "${VPC_ID}" \
    --query "GroupId" --output text --region "${REGION}")

print_success "Security Group created: ${TEST_SG_ID}"

# Add dangerous rule
print_step "Adding ingress rule: SSH (port 22) from 0.0.0.0/0..."
aws ec2 authorize-security-group-ingress \
    --group-id "${TEST_SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "${REGION}" >/dev/null

print_success "Dangerous rule added (SSH open to internet)"
print_time "Violation created at: $(date -u +"%H:%M:%S UTC")"
echo ""

# Show current rules
print_debug "Current ingress rules:"
if [ "$DEBUG" = "true" ]; then
    aws ec2 describe-security-groups --group-ids "${TEST_SG_ID}" \
        --query "SecurityGroups[0].IpPermissions" --output json --region "${REGION}" 2>/dev/null || true
fi

# ----------------------------------------------
# Step 2: Wait for Security Hub detection
# ----------------------------------------------
print_step "Waiting for Security Hub detection..."
print_debug "Security Group ID: ${TEST_SG_ID}"

TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
ELAPSED=0
DETECTION_TIME=""

# Security Groups can be referenced by ID or ARN in findings
SG_ARN="arn:aws:ec2:${REGION}:${ACCOUNT_ID}:security-group/${TEST_SG_ID}"

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
    # Try 1: Search by SG ID directly
    FINDING=$(aws securityhub get-findings \
        --filters "{
            \"ResourceId\": [{\"Value\": \"${TEST_SG_ID}\", \"Comparison\": \"EQUALS\"}],
            \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
            \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
        }" \
        --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")

    if [ "$FINDING" = "None" ] || [ -z "$FINDING" ] || [ "$FINDING" = "null" ]; then
        # Try 2: Search by SG ARN
        FINDING=$(aws securityhub get-findings \
            --filters "{
                \"ResourceId\": [{\"Value\": \"${SG_ARN}\", \"Comparison\": \"EQUALS\"}],
                \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
                \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
            }" \
            --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")
    fi

    if [ "$FINDING" = "None" ] || [ -z "$FINDING" ] || [ "$FINDING" = "null" ]; then
        # Try 3: Search by SG ID with CONTAINS
        FINDING=$(aws securityhub get-findings \
            --filters "{
                \"ResourceId\": [{\"Value\": \"${TEST_SG_ID}\", \"Comparison\": \"CONTAINS\"}],
                \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
                \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}],
                \"ResourceType\": [{\"Value\": \"AwsEc2SecurityGroup\", \"Comparison\": \"EQUALS\"}]
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

    # Debug: Show any SG-related findings
    if [ "$DEBUG" = "true" ] && [ $((ELAPSED % 60)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo ""
        print_debug "Checking for any recent Security Group findings..."
        aws securityhub get-findings \
            --filters "{
                \"ResourceType\": [{\"Value\": \"AwsEc2SecurityGroup\", \"Comparison\": \"EQUALS\"}],
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
    print_warning "Security Group violations may take longer to be detected"
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
            --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_SG_ID}\"}}" \
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
    print_step "Verifying Security Group was remediated..."

    RULES=$(aws ec2 describe-security-groups --group-ids "${TEST_SG_ID}" \
        --query "SecurityGroups[0].IpPermissions" --output json --region "${REGION}" 2>/dev/null || echo "[]")

    # Check if 0.0.0.0/0 rule was removed
    if echo "$RULES" | grep -q "0.0.0.0/0"; then
        print_warning "0.0.0.0/0 rule may still be present"
        echo "$RULES"
    else
        print_success "Dangerous 0.0.0.0/0 rule has been removed"
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
echo -e "${GREEN}║       SECURITY GROUP OPEN ACCESS - E2E TEST RESULTS       ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Resource: ${CYAN}${TEST_SG_ID}${NC}"
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
RESULTS_FILE="${RESULTS_DIR}/e2e-sg-results-$(date +%Y%m%d-%H%M%S).txt"
cat > "${RESULTS_FILE}" << EOF
IaC Secure Gate - E2E Test Results: Security Group Open Access
===============================================================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Account: ${ACCOUNT_ID}
Region: ${REGION}

Resource: ${TEST_SG_NAME}
Security Group ID: ${TEST_SG_ID}
VPC: ${VPC_ID}

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
- Security Group detection depends on AWS Config rules
- Detection time can vary based on Config evaluation frequency
EOF

print_success "Results saved to: ${RESULTS_FILE}"
echo ""
