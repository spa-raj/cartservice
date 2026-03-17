#!/bin/bash
# ==============================================================================
# Cart Demo — Adds items and shows MongoDB documents
# ==============================================================================
# Adds products to cart and displays the MongoDB cart document with items.
# Useful for screenshots and demos.
#
# Prerequisites:
#   - userservice, productservice, cartservice running (docker compose)
#
# Usage:
#   ./scripts/demo-cart-with-items.sh
# ==============================================================================

set -euo pipefail

USERSERVICE="http://localhost:8081"
PRODUCTSERVICE="http://localhost:8080"
CARTSERVICE="http://localhost:8082"

ADMIN_EMAIL="admin@gmail.com"
ADMIN_PASSWORD="abcd@1234"
CLIENT_ID="vibevault-client"
CLIENT_SECRET="abc@12345"
REDIRECT_URI="https://oauth.pstmn.io/v1/callback"
SCOPES="openid+profile+email+read+write"
MONGO_CONTAINER="cartservice-mongodb"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# Get OAuth2 token
echo -e "${CYAN}=== Getting OAuth2 token ===${NC}"
set +e
COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L --max-redirs 1 -o /dev/null \
    "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}"
CSRF=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "${USERSERVICE}/login" | grep -oP 'name="_csrf".*?value="\K[^"]+')
ENCODED_PASS=$(urlencode "$ADMIN_PASSWORD")
curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/login" \
    -d "username=${ADMIN_EMAIL}&password=${ENCODED_PASS}&_csrf=${CSRF}" > /dev/null
AUTH_RESP=$(curl -s -D- -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}&continue")
AUTH_LOC=$(echo "$AUTH_RESP" | grep -i "^Location:" | tr -d '\r')
AUTH_CODE=$(echo "$AUTH_LOC" | grep -oP 'code=\K[^&\s]+' || true)

if [ -z "$AUTH_CODE" ]; then
    CONSENT_BODY=$(echo "$AUTH_RESP" | sed '1,/^\r$/d')
    STATE=$(echo "$CONSENT_BODY" | grep -oP 'name="state"[^>]*value="\K[^"]+' || true)
    CONSENT_RESP=$(curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/oauth2/authorize" \
        -d "client_id=${CLIENT_ID}&state=${STATE}&scope=read&scope=profile&scope=write&scope=email")
    CONSENT_LOC=$(echo "$CONSENT_RESP" | grep -i "^Location:" | tr -d '\r' || true)
    AUTH_CODE=$(echo "$CONSENT_LOC" | grep -oP 'code=\K[^&\s]+' || true)
fi

TOKEN=$(curl -s -X POST "${USERSERVICE}/oauth2/token" \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d "grant_type=authorization_code" \
    -d "code=${AUTH_CODE}" \
    -d "redirect_uri=${REDIRECT_URI}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")
rm -f "$COOKIE_JAR"
set -e

if [[ ! "$TOKEN" =~ ^eyJ ]]; then
    echo "Failed to get token"
    exit 1
fi
echo -e "${GREEN}Token obtained${NC}"

AUTH_HEADERS="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$TOKEN")"

# Clear existing cart
echo -e "\n${CYAN}=== Clearing existing cart ===${NC}"
curl -s -X DELETE "$CARTSERVICE/cart" -H "Authorization: Bearer $TOKEN" > /dev/null 2>&1 || true

# Create products
echo -e "\n${CYAN}=== Creating products ===${NC}"
TIMESTAMP=$(date +%s)

curl -s -X POST "$PRODUCTSERVICE/categories" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"name":"Electronics","description":"Electronic devices"}' > /dev/null 2>&1 || true

curl -s -X POST "$PRODUCTSERVICE/categories" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"name":"Clothing","description":"Apparel"}' > /dev/null 2>&1 || true

PROD1_RESP=$(curl -s -X POST "$PRODUCTSERVICE/products" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"Wireless Headphones ${TIMESTAMP}\",\"description\":\"Noise cancelling bluetooth headphones\",\"price\":2999.00,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}")
PROD1_ID=$(echo "$PROD1_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
echo -e "  ${GREEN}Created:${NC} Wireless Headphones (${PROD1_ID})"

PROD2_RESP=$(curl -s -X POST "$PRODUCTSERVICE/products" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"Cotton T-Shirt ${TIMESTAMP}\",\"description\":\"Premium organic cotton\",\"price\":799.00,\"currency\":\"INR\",\"categoryName\":\"Clothing\"}")
PROD2_ID=$(echo "$PROD2_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
echo -e "  ${GREEN}Created:${NC} Cotton T-Shirt (${PROD2_ID})"

PROD3_RESP=$(curl -s -X POST "$PRODUCTSERVICE/products" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"Leather Wallet ${TIMESTAMP}\",\"description\":\"Genuine leather RFID blocking\",\"price\":1499.99,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}")
PROD3_ID=$(echo "$PROD3_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
echo -e "  ${GREEN}Created:${NC} Leather Wallet (${PROD3_ID})"

# Add items to cart
echo -e "\n${CYAN}=== Adding items to cart ===${NC}"

curl -s -X POST "$CARTSERVICE/cart/items" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"productId\":\"${PROD1_ID}\",\"quantity\":2}" > /dev/null
echo -e "  ${GREEN}Added:${NC} Wireless Headphones x2"

curl -s -X POST "$CARTSERVICE/cart/items" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"productId\":\"${PROD2_ID}\",\"quantity\":3}" > /dev/null
echo -e "  ${GREEN}Added:${NC} Cotton T-Shirt x3"

curl -s -X POST "$CARTSERVICE/cart/items" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"productId\":\"${PROD3_ID}\",\"quantity\":1}" > /dev/null
echo -e "  ${GREEN}Added:${NC} Leather Wallet x1"

# Show cart via API (this triggers Redis cache population)
echo -e "\n${CYAN}=== Cart API Response ===${NC}"
curl -s "$CARTSERVICE/cart" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Show Redis cached keys and values
REDIS_CONTAINER="cartservice-redis"
echo -e "\n${CYAN}=== Redis Cached Cart ===${NC}"
echo -e "  ${GREEN}Keys:${NC}"
docker exec "$REDIS_CONTAINER" redis-cli KEYS "cart:*"
echo ""
echo -e "  ${GREEN}Cached value for admin:${NC}"
docker exec "$REDIS_CONTAINER" redis-cli GET "cart:admin@gmail.com" | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
if raw and raw != '(nil)':
    try:
        data = json.loads(raw)
        print(json.dumps(data, indent=2))
    except:
        print(raw[:500])
else:
    print('(no cached value)')
" 2>/dev/null
echo ""
echo -e "  ${GREEN}TTL remaining:${NC}"
docker exec "$REDIS_CONTAINER" redis-cli TTL "cart:admin@gmail.com"

# Show MongoDB document
echo -e "\n${CYAN}=== MongoDB Cart Document ===${NC}"
docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "db.getSiblingDB('cartservice').carts.find({userId: 'admin@gmail.com'}).pretty()"

# Show Kafka events
echo -e "\n${CYAN}=== Recent Kafka Events (last 5) ===${NC}"
docker exec cartservice-kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic cart-events \
    --from-beginning \
    --timeout-ms 3000 2>/dev/null | tail -5 | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        event = json.loads(line.strip())
        print(json.dumps(event, indent=2))
    except:
        print(line.strip())
" 2>/dev/null || echo "(no events)"
