#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COOKIE=$(mktemp)
curl -s -c "$COOKIE" -b "$COOKIE" -L --max-redirs 1 -o /dev/null "http://localhost:8081/oauth2/authorize?response_type=code&client_id=vibevault-client&redirect_uri=https://oauth.pstmn.io/v1/callback&scope=openid+profile+email+read+write"
CSRF=$(curl -s -c "$COOKIE" -b "$COOKIE" "http://localhost:8081/login" | grep -oP 'name="_csrf".*?value="\K[^"]+')
PASS_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('abcd@1234', safe=''))")
curl -s -D- -o /dev/null -c "$COOKIE" -b "$COOKIE" -X POST "http://localhost:8081/login" -d "username=admin@gmail.com&password=${PASS_ENC}&_csrf=${CSRF}" > /dev/null
AUTH_RESP=$(curl -s -D- -c "$COOKIE" -b "$COOKIE" "http://localhost:8081/oauth2/authorize?response_type=code&client_id=vibevault-client&redirect_uri=https://oauth.pstmn.io/v1/callback&scope=openid+profile+email+read+write&continue")
CODE=$(echo "$AUTH_RESP" | grep -i "^Location:" | tr -d '\r' | grep -oP 'code=\K[^&\s]+')
TOKEN=$(curl -s -X POST "http://localhost:8081/oauth2/token" -u "vibevault-client:abc@12345" -d "grant_type=authorization_code" -d "code=${CODE}" -d "redirect_uri=https://oauth.pstmn.io/v1/callback" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
rm -f "$COOKIE"

echo "Token obtained: ${TOKEN:0:30}..."

echo ""
echo "=== MongoDB Baseline Benchmark ==="
echo ""

k6 run --summary-trend-stats="min,avg,med,p(90),p(95),p(99),max" \
    -e BASE_URL="http://localhost:8082" \
    -e SETUP_URL="http://localhost:8080" \
    -e TOKEN="$TOKEN" \
    "$SCRIPT_DIR/cart-read-benchmark.js"
