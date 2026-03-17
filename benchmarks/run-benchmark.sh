#!/bin/bash
# ==============================================================================
# Cart Read Benchmark — MongoDB vs Redis
# ==============================================================================
# Runs the same k6 benchmark twice:
#   1. With Redis (cache-aside active)
#   2. Without Redis (MongoDB direct reads)
#
# Prerequisites:
#   - All services running: userservice, productservice, cartservice, redis
#   - k6 installed locally (brew install k6 / snap install k6)
#   - OAuth2 token (auto-obtained)
#
# Usage:
#   ./benchmarks/run-benchmark.sh
#   TOKEN="xxx" ./benchmarks/run-benchmark.sh   # skip token flow
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERSERVICE="http://localhost:8081"
PRODUCTSERVICE="http://localhost:8080"
CARTSERVICE="http://localhost:8082"
RESULTS_DIR="${SCRIPT_DIR}/results"

ADMIN_EMAIL="admin@gmail.com"
ADMIN_PASSWORD="abcd@1234"
CLIENT_ID="vibevault-client"
CLIENT_SECRET="abc@12345"
REDIRECT_URI="https://oauth.pstmn.io/v1/callback"
SCOPES="openid+profile+email+read+write"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR"

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# Get OAuth2 token if not provided
if [ -z "${TOKEN:-}" ]; then
    echo -e "${CYAN}=== Getting OAuth2 token ===${NC}"
    set +e
    COOKIE=$(mktemp)
    curl -s -c "$COOKIE" -b "$COOKIE" -L --max-redirs 1 -o /dev/null \
        "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}"
    CSRF=$(curl -s -c "$COOKIE" -b "$COOKIE" "${USERSERVICE}/login" | grep -oP 'name="_csrf".*?value="\K[^"]+')
    PASS_ENC=$(urlencode "$ADMIN_PASSWORD")
    curl -s -D- -o /dev/null -c "$COOKIE" -b "$COOKIE" -X POST "${USERSERVICE}/login" \
        -d "username=${ADMIN_EMAIL}&password=${PASS_ENC}&_csrf=${CSRF}" > /dev/null
    AUTH_RESP=$(curl -s -D- -c "$COOKIE" -b "$COOKIE" \
        "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}&continue")
    AUTH_LOC=$(echo "$AUTH_RESP" | grep -i "^Location:" | tr -d '\r')
    CODE=$(echo "$AUTH_LOC" | grep -oP 'code=\K[^&\s]+' || true)
    if [ -z "$CODE" ]; then
        CONSENT_BODY=$(echo "$AUTH_RESP" | sed '1,/^\r$/d')
        STATE=$(echo "$CONSENT_BODY" | grep -oP 'name="state"[^>]*value="\K[^"]+' || true)
        CONSENT_RESP=$(curl -s -D- -o /dev/null -c "$COOKIE" -b "$COOKIE" -X POST "${USERSERVICE}/oauth2/authorize" \
            -d "client_id=${CLIENT_ID}&state=${STATE}&scope=read&scope=profile&scope=write&scope=email")
        CONSENT_LOC=$(echo "$CONSENT_RESP" | grep -i "^Location:" | tr -d '\r' || true)
        CODE=$(echo "$CONSENT_LOC" | grep -oP 'code=\K[^&\s]+' || true)
    fi
    TOKEN=$(curl -s -X POST "${USERSERVICE}/oauth2/token" -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -d "grant_type=authorization_code" -d "code=${CODE}" -d "redirect_uri=${REDIRECT_URI}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")
    rm -f "$COOKIE"
    set -e

    if [[ ! "$TOKEN" =~ ^eyJ ]]; then
        echo -e "${RED}Failed to get token${NC}"
        exit 1
    fi
    echo -e "${GREEN}Token obtained${NC}"
fi

# Ensure category exists
curl -s -X POST "$PRODUCTSERVICE/categories" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"name":"Electronics","description":"Electronic devices"}' > /dev/null 2>&1 || true

echo ""
echo "=============================================="
echo "  Cart Read Benchmark: Redis vs MongoDB"
echo "=============================================="

# --- Run 1: With Redis (cache-aside active) ---
echo ""
echo -e "${CYAN}=== Run 1: WITH Redis (cache-aside) ===${NC}"
echo "Redis container status:"
docker ps --filter "name=cartservice-redis" --format "  {{.Names}}: {{.Status}}"
echo ""

k6 run \
    --summary-trend-stats="min,avg,med,p(90),p(95),p(99),max" \
    -e BASE_URL="$CARTSERVICE" \
    -e SETUP_URL="$PRODUCTSERVICE" \
    -e TOKEN="$TOKEN" \
    "$SCRIPT_DIR/cart-read-benchmark.js" 2>&1 | tee "$RESULTS_DIR/redis-enabled.log"

echo ""

# --- Stop Redis ---
echo -e "${CYAN}=== Stopping Redis container ===${NC}"
docker stop cartservice-redis > /dev/null 2>&1
echo "Redis stopped. Cart service will fallback to MongoDB direct reads."
sleep 2

# --- Run 2: Without Redis (MongoDB direct) ---
echo ""
echo -e "${CYAN}=== Run 2: WITHOUT Redis (MongoDB direct) ===${NC}"
echo "Redis container status:"
docker ps --filter "name=cartservice-redis" --format "  {{.Names}}: {{.Status}}" || echo "  (not running)"
echo ""

k6 run \
    --summary-trend-stats="min,avg,med,p(90),p(95),p(99),max" \
    -e BASE_URL="$CARTSERVICE" \
    -e SETUP_URL="$PRODUCTSERVICE" \
    -e TOKEN="$TOKEN" \
    "$SCRIPT_DIR/cart-read-benchmark.js" 2>&1 | tee "$RESULTS_DIR/redis-disabled.log"

# --- Restart Redis ---
echo ""
echo -e "${CYAN}=== Restarting Redis ===${NC}"
docker start cartservice-redis > /dev/null 2>&1
echo "Redis restarted."

# --- Summary ---
echo ""
echo "=============================================="
echo "  Benchmark Complete"
echo "=============================================="
echo ""
echo "Results saved to:"
echo "  With Redis:    $RESULTS_DIR/redis-enabled.log"
echo "  Without Redis: $RESULTS_DIR/redis-disabled.log"
echo ""
echo "Compare get_cart_duration metrics between the two runs."
