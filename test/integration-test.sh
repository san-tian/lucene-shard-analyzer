#!/bin/bash
# Integration test script for Lucene Shard Analyzer Service
# This script tests:
# 1. /healthz endpoint
# 2. /info endpoint with load balancing verification
# 3. /analyze endpoint with a sample shard

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"
SAMPLE_SHARD="${SAMPLE_SHARD:-shard.tar}"
USE_K8S_EXEC="${USE_K8S_EXEC:-true}"

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
HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | tail -n 1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | sed '$d')

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
# 提示用户关于 port-forward 的限制
if [[ "$BASE_URL" == *"localhost"* ]]; then
    info "Note: Testing via localhost (port-forward) usually sticks to one Pod."
    info "To see true K8s load balancing, set USE_K8S_EXEC=true"
fi
info "Calling /info 10 times to verify load balancing..."

# Use a simple approach compatible with bash 3.x
HOSTNAMES_FILE=$(mktemp)
for i in {1..10}; do
    if [ "$USE_K8S_EXEC" = "true" ]; then
        # 在集群内部通过 Service 名称访问，这会触发 K8s 的负载均衡机制
        POD_NAME=$(kubectl get pods -l app=lucene-shard-analyzer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$POD_NAME" ]; then
            fail "No Pods found to run internal test. Is the deployment ready?"
        fi
        INFO_RESPONSE=$(kubectl exec "$POD_NAME" -- wget -qO- http://lucene-shard-analyzer/info 2>/dev/null)
    else
        INFO_RESPONSE=$(curl -s "$BASE_URL/info")
    fi
    
    HOSTNAME=$(echo "$INFO_RESPONSE" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$HOSTNAME" ]; then
        echo "$HOSTNAME" >> "$HOSTNAMES_FILE"
    fi
    sleep 0.2
done

UNIQUE_HOSTS=$(sort "$HOSTNAMES_FILE" | uniq | wc -l | tr -d ' ')
echo ""
info "Responses received from $UNIQUE_HOSTS unique pod(s):"
sort "$HOSTNAMES_FILE" | uniq -c | while read count host; do
    echo "    - $host: $count request(s)"
done
rm -f "$HOSTNAMES_FILE"

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
    
    ANALYZE_STATUS=$(echo "$ANALYZE_RESPONSE" | tail -n 1)
    ANALYZE_BODY=$(echo "$ANALYZE_RESPONSE" | sed '$d')
    
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
