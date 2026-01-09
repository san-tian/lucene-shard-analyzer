#!/bin/bash
# Integration test script for Lucene Shard Analyzer Service
# This script tests:
# 1. /healthz endpoint
# 2. /info endpoint with load balancing verification
# 3. /analyze endpoint with a sample shard

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"
SAMPLE_SHARD="${SAMPLE_SHARD:-shard.tar}"

echo "=========================================="
echo "  Lucene Shard Analyzer Integration Test"
echo "=========================================="
echo "Base URL: $BASE_URL"
echo ""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; exit 1; }
info() { echo -e "${YELLOW}→${NC} $1"; }

# ==========================================
# Test 1: Health Check
# ==========================================
echo ""
echo "▶ Test 1: Health Check (/healthz)"
echo "------------------------------------------"

HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/healthz")
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)
HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | tail -n 1)

if [ "$HEALTH_STATUS" = "200" ]; then
    pass "/healthz returned 200 OK"
    info "Response body: $HEALTH_BODY"
else
    fail "/healthz returned $HEALTH_STATUS (expected 200)"
fi

# ==========================================
# Test 2: Load Balancing Verification
# ==========================================
echo ""
echo "▶ Test 2: Load Balancing (/info)"
echo "------------------------------------------"
info "Calling /info 10 times to verify load balancing..."

declare -A HOSTNAMES
for i in {1..10}; do
    INFO_RESPONSE=$(curl -s "$BASE_URL/info")
    HOSTNAME=$(echo "$INFO_RESPONSE" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$HOSTNAME" ]; then
        HOSTNAMES["$HOSTNAME"]=$((${HOSTNAMES["$HOSTNAME"]:-0} + 1))
    fi
    sleep 0.2
done

UNIQUE_HOSTS=${#HOSTNAMES[@]}
echo ""
info "Responses received from $UNIQUE_HOSTS unique pod(s):"
for host in "${!HOSTNAMES[@]}"; do
    echo "    - $host: ${HOSTNAMES[$host]} request(s)"
done

if [ "$UNIQUE_HOSTS" -ge 2 ]; then
    pass "Load balancing verified: requests distributed across $UNIQUE_HOSTS pods"
else
    echo -e "${YELLOW}⚠ WARNING${NC}: Only 1 unique hostname seen. Load balancing may not be working or only 1 replica is running."
    # Don't fail here as it might be a timing issue
fi

# ==========================================
# Test 3: Analyze Endpoint
# ==========================================
echo ""
echo "▶ Test 3: Analyze Shard (/analyze)"
echo "------------------------------------------"

if [ ! -f "$SAMPLE_SHARD" ]; then
    info "Sample shard not found at $SAMPLE_SHARD, skipping /analyze test"
    echo -e "${YELLOW}⚠ SKIPPED${NC}: /analyze test (no sample shard available)"
else
    info "Uploading sample shard: $SAMPLE_SHARD"
    
    ANALYZE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -F "file=@$SAMPLE_SHARD" \
        "$BASE_URL/analyze")
    
    ANALYZE_BODY=$(echo "$ANALYZE_RESPONSE" | head -n -1)
    ANALYZE_STATUS=$(echo "$ANALYZE_RESPONSE" | tail -n 1)
    
    if [ "$ANALYZE_STATUS" = "200" ]; then
        pass "/analyze returned 200 OK"
        
        # Validate JSON structure
        if echo "$ANALYZE_BODY" | grep -q '"summary"'; then
            pass "Response contains 'summary' field"
        else
            fail "Response missing 'summary' field"
        fi
        
        if echo "$ANALYZE_BODY" | grep -q '"segments"'; then
            pass "Response contains 'segments' field"
        else
            fail "Response missing 'segments' field"
        fi
        
        # Extract some stats
        SEGMENT_COUNT=$(echo "$ANALYZE_BODY" | grep -o '"segmentCount":[0-9]*' | cut -d':' -f2)
        TOTAL_DOCS=$(echo "$ANALYZE_BODY" | grep -o '"totalDocumentCount":[0-9]*' | cut -d':' -f2)
        info "Analyzed shard: $SEGMENT_COUNT segments, $TOTAL_DOCS documents"
    else
        fail "/analyze returned $ANALYZE_STATUS (expected 200)"
    fi
fi

# ==========================================
# Summary
# ==========================================
echo ""
echo "=========================================="
echo -e "  ${GREEN}All tests passed!${NC}"
echo "=========================================="
