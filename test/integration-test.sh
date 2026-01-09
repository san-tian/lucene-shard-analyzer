#!/bin/bash
# Refactored Integration Test for Lucene Shard Analyzer Service
# Maps directly to requirements in project.md

set -e

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8080}"
SAMPLE_SHARD="${SAMPLE_SHARD:-test/sample-shard.tar}"
USE_K8S_EXEC="${USE_K8S_EXEC:-true}"

# UI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helpers
pass() { echo -e "${GREEN}  [PASS]${NC} $1"; }
fail() { echo -e "${RED}  [FAIL]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}  [INFO]${NC} $1"; }
header() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }
req() { echo -e "\n${BLUE}Requirement: $1${NC}"; }

echo "=========================================="
echo "  Requirement-Based Integration Testing"
echo "=========================================="
echo "Target URL: $BASE_URL"
echo "Sample Shard: $SAMPLE_SHARD"
echo "K8s Exec Mode: $USE_K8S_EXEC"

# ==========================================
# PART 1: TASK 1 REQUIREMENTS (Build & Ship)
# ==========================================
header "PART 1: TASK 1 - Build & Ship Verification"

# Req 1.1: Healthz Endpoint
req "1.1 - GET /healthz returns 200 OK with body 'ok'"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/healthz")
STATUS=$(echo "$HEALTH_RESPONSE" | tail -n 1)
BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

if [ "$STATUS" = "200" ] && [ "$BODY" = "ok" ]; then
    pass "Endpoint /healthz is responsive and correct"
else
    fail "/healthz returned status $STATUS and body '$BODY'"
fi

# Req 1.2: Info Endpoint Metadata
req "1.2 - GET /info returns version, git_sha, arch, hostname"
INFO_JSON=$(curl -s "$BASE_URL/info")
V=$(echo "$INFO_JSON" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
S=$(echo "$INFO_JSON" | grep -o '"git_sha":"[^"]*"' | cut -d'"' -f4)
A=$(echo "$INFO_JSON" | grep -o '"arch":"[^"]*"' | cut -d'"' -f4)
H=$(echo "$INFO_JSON" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)

[[ -n "$V" && "$V" != "unknown" ]] && pass "Version: $V" || fail "Version missing or unknown"
[[ -n "$S" && "$S" != "unknown" ]] && pass "Git SHA: $S" || fail "Git SHA missing or unknown"
[[ -n "$A" && "$A" != "unknown" ]] && pass "Arch: $A" || fail "Arch missing or unknown"
[[ -n "$H" && "$H" != "unknown" ]] && pass "Hostname: $H" || fail "Hostname missing"

# Extra: Security (Non-root user)
header "Extra Verification: Security"
if [ "$USE_K8S_EXEC" = "true" ]; then
    POD_NAME=$(kubectl get pods -l app=lucene-shard-analyzer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        UID_RUN=$(kubectl exec "$POD_NAME" -- id -u)
        if [ "$UID_RUN" -ne 0 ]; then
            pass "Service is running as non-root (UID $UID_RUN)"
        else
            echo -e "${YELLOW}  [WARN]${NC} Service is running as root (UID 0)"
        fi
    fi
else
    info "Skipping security check (USE_K8S_EXEC=false)"
fi

# ==========================================
# PART 2: TASK 2 REQUIREMENTS (K8s Deployment)
# ==========================================
header "PART 2: TASK 2 - K8s Deployment & LB Verification"

# Req 2.1: Multiple Instances
req "2.1 - Multiple Pods running (replicas >= 2)"
POD_COUNT=$(kubectl get pods -l app=lucene-shard-analyzer --no-headers | grep "Running" | wc -l | tr -d ' ')
if [ "$POD_COUNT" -ge 2 ]; then
    pass "$POD_COUNT replicas detected"
else
    fail "Only $POD_COUNT replicas found (need >= 2)"
fi

# Req 2.2: Even Traffic Distribution
req "2.2 - Traffic distributed across multiple Pods"
HOSTS_FILE=$(mktemp)
for i in {1..10}; do
    if [ "$USE_K8S_EXEC" = "true" ]; then
        POD=$(kubectl get pods -l app=lucene-shard-analyzer -o jsonpath='{.items[0].metadata.name}')
        H=$(kubectl exec "$POD" -- wget -qO- http://lucene-shard-analyzer/info | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    else
        H=$(curl -s "$BASE_URL/info" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    fi
    echo "$H" >> "$HOSTS_FILE"
    sleep 0.1
done

UNIQUE_COUNT=$(sort "$HOSTS_FILE" | uniq | wc -l | tr -d ' ')
if [ "$UNIQUE_COUNT" -ge 2 ]; then
    pass "Traffic hit $UNIQUE_COUNT different pods"
    sort "$HOSTS_FILE" | uniq -c
else
    fail "Traffic only hit 1 pod. Load balancing may not be effective via current access method."
fi
rm -f "$HOSTS_FILE"

# Req 2.3: Functional Analysis (Real Shard)
req "2.3 - POST /analyze with real shard returns successful JSON report"
if [ ! -f "$SAMPLE_SHARD" ]; then
    fail "Sample shard not found at $SAMPLE_SHARD. Cannot complete Req 2.3."
fi

info "Uploading real shard: $SAMPLE_SHARD"
RESP=$(curl -s -w "\n%{http_code}" -X POST -F "file=@$SAMPLE_SHARD" "$BASE_URL/analyze")
STATUS=$(echo "$RESP" | tail -n 1)
BODY=$(echo "$RESP" | sed '$d')

if [ "$STATUS" = "200" ]; then
    pass "Analysis successful (HTTP 200)"
    # Check for required fields as per project.md
    echo "$BODY" | grep -q '"summary"' && pass "Found 'summary'" || fail "Missing 'summary'"
    echo "$BODY" | grep -q '"segments"' && pass "Found 'segments' count" || fail "Missing 'segments' count"
    echo "$BODY" | grep -q '"docs"' && pass "Found 'docs' count" || fail "Missing 'docs' count"
    
    DOCS=$(echo "$BODY" | grep -o '"docs":[0-9]*' | head -n 1 | cut -d':' -f2)
    SEGS=$(echo "$BODY" | grep -o '"segments":[0-9]*' | head -n 1 | cut -d':' -f2)
    info "Stats: $SEGS segments, $DOCS documents found."
else
    fail "/analyze failed with status $STATUS. Body: $BODY"
fi

header "Final Results"
echo -e "${GREEN}All Requirements Met Successfully!${NC}"
echo "=========================================="
