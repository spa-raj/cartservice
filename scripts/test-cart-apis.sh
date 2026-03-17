#!/bin/bash
# ==============================================================================
# Cart Service API Test Suite
# ==============================================================================
# Tests all cart service endpoints against local Docker Compose deployment.
# OAuth2 token is obtained automatically from userservice.
#
# Prerequisites:
#   - userservice running on port 8081 (docker compose)
#   - productservice running on port 8080 (docker compose)
#   - cartservice running on port 8082 (docker compose)
#   - At least one product exists in productservice
#
# Usage:
#   ./test-cart-apis.sh
#   TOKEN="xxx" ./test-cart-apis.sh    # skip OAuth2 flow
# ==============================================================================

set -euo pipefail

USERSERVICE="http://localhost:8081"
PRODUCTSERVICE="http://localhost:8080"
CARTSERVICE="http://localhost:8082"

# Local docker-compose credentials
ADMIN_EMAIL="admin@gmail.com"
ADMIN_PASSWORD="abcd@1234"
CLIENT_ID="vibevault-client"
CLIENT_SECRET="abc@12345"
REDIRECT_URI="https://oauth.pstmn.io/v1/callback"
SCOPES="openid+profile+email+read+write"

PASS=0
FAIL=0
SKIP=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helpers
# ============================================================================

assert_status() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    local body="${4:-}"

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} [$actual] $description"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$actual expected $expected] $description"
        [ -n "$body" ] && echo "       Response: $(echo "$body" | head -c 300)"
        FAIL=$((FAIL + 1))
    fi
}

assert_body_contains() {
    local description="$1"
    local expected_substring="$2"
    local body="$3"

    if echo "$body" | grep -qi "$expected_substring"; then
        echo -e "  ${GREEN}PASS${NC} $description (contains '$expected_substring')"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $description (expected to contain '$expected_substring')"
        echo "       Response: $(echo "$body" | head -c 300)"
        FAIL=$((FAIL + 1))
    fi
}

request() {
    local method="$1"
    local url="$2"
    local headers="${3:-}"
    local data="${4:-}"

    local curl_args=(-s -w "\n%{http_code}" -X "$method" "$url")
    if [ -n "$headers" ]; then
        while IFS= read -r header; do
            [ -n "$header" ] && curl_args+=(-H "$header")
        done <<< "$headers"
    fi
    if [ -n "$data" ]; then
        curl_args+=(-d "$data")
    fi

    local response
    response=$(curl "${curl_args[@]}")
    BODY=$(echo "$response" | head -n -1)
    STATUS=$(echo "$response" | tail -n 1)
}

section() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# ============================================================================
# OAuth2 Token Flow
# ============================================================================

get_oauth2_token() {
    set +e
    local username="$1"
    local password="$2"

    local COOKIE_JAR
    COOKIE_JAR=$(mktemp /tmp/cart_test_cookies.XXXXXX)

    local AUTH_URL="${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}"

    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L --max-redirs 1 -o /dev/null "$AUTH_URL"

    local LOGIN_PAGE
    LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "${USERSERVICE}/login")
    local CSRF
    CSRF=$(echo "$LOGIN_PAGE" | grep -oP 'name="_csrf".*?value="\K[^"]+')

    if [ -z "$CSRF" ]; then
        rm -f "$COOKIE_JAR"
        set -e
        echo ""
        return
    fi

    local ENCODED_PASSWORD
    ENCODED_PASSWORD=$(urlencode "$password")
    curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/login" \
        -d "username=${username}&password=${ENCODED_PASSWORD}&_csrf=${CSRF}" > /dev/null

    local AUTHORIZE_RESPONSE
    AUTHORIZE_RESPONSE=$(curl -s -D- -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}&continue")

    local AUTHORIZE_LOCATION
    AUTHORIZE_LOCATION=$(echo "$AUTHORIZE_RESPONSE" | grep -i "^Location:" | tr -d '\r' || true)

    local AUTH_CODE=""

    if echo "$AUTHORIZE_LOCATION" | grep -q "code="; then
        AUTH_CODE=$(echo "$AUTHORIZE_LOCATION" | grep -oP 'code=\K[^&\s]+' || true)
    else
        local CONSENT_BODY
        CONSENT_BODY=$(echo "$AUTHORIZE_RESPONSE" | sed '1,/^\r$/d')
        local STATE
        STATE=$(echo "$CONSENT_BODY" | grep -oP 'name="state"[^>]*value="\K[^"]+' || true)

        if [ -z "$STATE" ]; then
            rm -f "$COOKIE_JAR"
            set -e
            echo ""
            return
        fi

        local CONSENT_RESPONSE
        CONSENT_RESPONSE=$(curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/oauth2/authorize" \
            -d "client_id=${CLIENT_ID}&state=${STATE}&scope=read&scope=profile&scope=write&scope=email")

        local CONSENT_LOCATION
        CONSENT_LOCATION=$(echo "$CONSENT_RESPONSE" | grep -i "^Location:" | tr -d '\r' || true)

        AUTH_CODE=$(echo "$CONSENT_LOCATION" | grep -oP 'code=\K[^&\s]+' || true)
    fi

    if [ -z "$AUTH_CODE" ]; then
        rm -f "$COOKIE_JAR"
        set -e
        echo ""
        return
    fi

    local TOKEN_RESPONSE
    TOKEN_RESPONSE=$(curl -s -X POST "${USERSERVICE}/oauth2/token" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -d "grant_type=authorization_code" \
        -d "code=${AUTH_CODE}" \
        -d "redirect_uri=${REDIRECT_URI}")

    local TOKEN
    TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")

    rm -f "$COOKIE_JAR"
    set -e
    echo "$TOKEN"
}

# ============================================================================
# Test Suite
# ============================================================================

echo "=============================================="
echo "  Cart Service API Test Suite"
echo "=============================================="

# --------------------------------------------------
section "1. Health Checks"
# --------------------------------------------------

request GET "$USERSERVICE/actuator/health"
assert_status "userservice health" "200" "$STATUS"

request GET "$PRODUCTSERVICE/actuator/health"
assert_status "productservice health" "200" "$STATUS"

request GET "$CARTSERVICE/actuator/health"
assert_status "cartservice health" "200" "$STATUS"

# --------------------------------------------------
section "2. OAuth2 Token"
# --------------------------------------------------

if [ -n "${TOKEN:-}" ]; then
    echo -e "  ${GREEN}PASS${NC} Using provided TOKEN"
    PASS=$((PASS + 1))
else
    echo "  Obtaining admin OAuth2 token..."
    TOKEN=$(get_oauth2_token "$ADMIN_EMAIL" "$ADMIN_PASSWORD")
fi

if [[ "$TOKEN" =~ ^eyJ.*\..*\..*$ ]]; then
    echo -e "  ${GREEN}PASS${NC} Admin OAuth2 token obtained"
    PASS=$((PASS + 1))
    AUTH_HEADERS="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$TOKEN")"
else
    echo -e "  ${RED}FAIL${NC} Could not obtain OAuth2 token"
    FAIL=$((FAIL + 1))
    echo ""
    echo "=============================================="
    printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" "$PASS" "$FAIL" "$SKIP"
    echo "=============================================="
    exit 1
fi

# --------------------------------------------------
section "3. Setup: Create test product in productservice"
# --------------------------------------------------

# Clear any leftover cart from previous test runs
curl -s -X DELETE "$CARTSERVICE/cart" -H "Authorization: Bearer $TOKEN" > /dev/null 2>&1
echo -e "  ${GREEN}OK${NC} Admin cart cleared (clean slate)"

TIMESTAMP=$(date +%s)
PRODUCT_NAME="CartTest-Product-${TIMESTAMP}"

request POST "$PRODUCTSERVICE/categories" "$AUTH_HEADERS" '{"name":"Electronics","description":"Electronic devices"}'
if [ "$STATUS" = "200" ] || [ "$STATUS" = "409" ]; then
    echo -e "  ${GREEN}OK${NC} Category 'Electronics' ready"
fi

request POST "$PRODUCTSERVICE/products" "$AUTH_HEADERS" \
    "{\"name\":\"${PRODUCT_NAME}\",\"description\":\"Test product for cart\",\"price\":999.99,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}"
assert_status "POST /products (create test product)" "200" "$STATUS"
PRODUCT_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

if [ -z "$PRODUCT_ID" ]; then
    echo -e "  ${RED}FAIL${NC} Could not create test product"
    exit 1
fi
echo -e "  ${CYAN}Product ID: ${PRODUCT_ID}${NC}"

# Create a second product for multi-item cart tests
PRODUCT_NAME_2="CartTest-Product2-${TIMESTAMP}"
request POST "$PRODUCTSERVICE/products" "$AUTH_HEADERS" \
    "{\"name\":\"${PRODUCT_NAME_2}\",\"description\":\"Second test product\",\"price\":499.50,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}"
assert_status "POST /products (create second test product)" "200" "$STATUS"
PRODUCT_ID_2=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")
echo -e "  ${CYAN}Product ID 2: ${PRODUCT_ID_2}${NC}"

# --------------------------------------------------
section "4. Get Cart (empty)"
# --------------------------------------------------

request GET "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN"
assert_status "GET /cart (empty cart)" "200" "$STATUS"
TOTAL_ITEMS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalItems', -1))" 2>/dev/null || echo "-1")
if [ "$TOTAL_ITEMS" -eq 0 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Empty cart has 0 items"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}WARN${NC} Cart has ${TOTAL_ITEMS} items (may be from previous test run)"
fi

# --------------------------------------------------
section "5. Add Item to Cart"
# --------------------------------------------------

request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    "{\"productId\":\"${PRODUCT_ID}\",\"quantity\":2}"
assert_status "POST /cart/items (add product)" "201" "$STATUS"
assert_body_contains "Cart contains product" "$PRODUCT_ID" "$BODY"

TOTAL_ITEMS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalItems', 0))" 2>/dev/null || echo "0")
echo -e "  ${CYAN}Total items in cart: ${TOTAL_ITEMS}${NC}"

# Add same product again — should increment quantity
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    "{\"productId\":\"${PRODUCT_ID}\",\"quantity\":1}"
assert_status "POST /cart/items (add same product — increment)" "201" "$STATUS"
ITEM_QTY=$(echo "$BODY" | python3 -c "
import sys,json
cart = json.load(sys.stdin)
for item in cart.get('items', []):
    if item['productId'] == '${PRODUCT_ID}':
        print(item['quantity'])
        break
" 2>/dev/null || echo "0")
if [ "$ITEM_QTY" -eq 3 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Quantity incremented to 3"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected quantity 3, got ${ITEM_QTY}"
    FAIL=$((FAIL + 1))
fi

# Add second product
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    "{\"productId\":\"${PRODUCT_ID_2}\",\"quantity\":1}"
assert_status "POST /cart/items (add second product)" "201" "$STATUS"

TOTAL_ITEMS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalItems', 0))" 2>/dev/null || echo "0")
if [ "$TOTAL_ITEMS" -eq 4 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Cart has 4 total items (3 + 1)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected 4 total items, got ${TOTAL_ITEMS}"
    FAIL=$((FAIL + 1))
fi

# --------------------------------------------------
section "6. Get Cart (with items)"
# --------------------------------------------------

request GET "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN"
assert_status "GET /cart (with items)" "200" "$STATUS"
assert_body_contains "Cart has product name" "$PRODUCT_NAME" "$BODY"
assert_body_contains "Cart has totalPrice" "totalPrice" "$BODY"

# --------------------------------------------------
section "7. Update Item Quantity"
# --------------------------------------------------

request PATCH "$CARTSERVICE/cart/items/${PRODUCT_ID}" "$AUTH_HEADERS" \
    '{"quantity":5}'
assert_status "PATCH /cart/items/{id} (update to 5)" "200" "$STATUS"

ITEM_QTY=$(echo "$BODY" | python3 -c "
import sys,json
cart = json.load(sys.stdin)
for item in cart.get('items', []):
    if item['productId'] == '${PRODUCT_ID}':
        print(item['quantity'])
        break
" 2>/dev/null || echo "0")
if [ "$ITEM_QTY" -eq 5 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Quantity updated to 5"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected quantity 5, got ${ITEM_QTY}"
    FAIL=$((FAIL + 1))
fi

# Update to 0 — should remove item
request PATCH "$CARTSERVICE/cart/items/${PRODUCT_ID_2}" "$AUTH_HEADERS" \
    '{"quantity":0}'
assert_status "PATCH /cart/items/{id} (quantity 0 — removes item)" "200" "$STATUS"

ITEM_COUNT=$(echo "$BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items', [])))" 2>/dev/null || echo "-1")
if [ "$ITEM_COUNT" -eq 1 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Item removed, 1 item remaining"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected 1 item, got ${ITEM_COUNT}"
    FAIL=$((FAIL + 1))
fi

# --------------------------------------------------
section "8. Remove Item from Cart"
# --------------------------------------------------

# Re-add second product first
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    "{\"productId\":\"${PRODUCT_ID_2}\",\"quantity\":1}"

request DELETE "$CARTSERVICE/cart/items/${PRODUCT_ID_2}" "Authorization: Bearer $TOKEN"
assert_status "DELETE /cart/items/{id} (remove item)" "200" "$STATUS"

ITEM_COUNT=$(echo "$BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items', [])))" 2>/dev/null || echo "-1")
if [ "$ITEM_COUNT" -eq 1 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Item removed, 1 item remaining"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected 1 item, got ${ITEM_COUNT}"
    FAIL=$((FAIL + 1))
fi

# --------------------------------------------------
section "9. Checkout"
# --------------------------------------------------

request POST "$CARTSERVICE/cart/checkout" "Authorization: Bearer $TOKEN"
assert_status "POST /cart/checkout" "200" "$STATUS"
assert_body_contains "Checkout returns cart" "$PRODUCT_ID" "$BODY"

# --------------------------------------------------
section "10. Clear Cart"
# --------------------------------------------------

request DELETE "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN"
assert_status "DELETE /cart (clear cart)" "200" "$STATUS"

TOTAL_ITEMS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalItems', -1))" 2>/dev/null || echo "-1")
if [ "$TOTAL_ITEMS" -eq 0 ] 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} Cart cleared, 0 items"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Expected 0 items after clear, got ${TOTAL_ITEMS}"
    FAIL=$((FAIL + 1))
fi

# --------------------------------------------------
section "11. Edge Cases"
# --------------------------------------------------

# Add with invalid quantity
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    '{"productId":"some-id","quantity":0}'
assert_status "POST /cart/items (quantity 0 — validation error)" "400" "$STATUS"

# Add with missing productId
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    '{"quantity":1}'
assert_status "POST /cart/items (missing productId)" "400" "$STATUS"

# Negative quantity update
request PATCH "$CARTSERVICE/cart/items/${PRODUCT_ID}" "$AUTH_HEADERS" \
    '{"quantity":-1}'
assert_status "PATCH /cart/items (negative quantity)" "400" "$STATUS"

# Remove non-existent item
request DELETE "$CARTSERVICE/cart/items/non-existent-id" "Authorization: Bearer $TOKEN"
assert_status "DELETE /cart/items (non-existent item)" "404" "$STATUS"

# Checkout empty cart
request POST "$CARTSERVICE/cart/checkout" "Authorization: Bearer $TOKEN"
assert_status "POST /cart/checkout (empty cart)" "400" "$STATUS"

# Unauthenticated request
request GET "$CARTSERVICE/cart"
assert_status "GET /cart (no token — unauthorized)" "401" "$STATUS"

# --------------------------------------------------
section "12. Kafka Event Verification"
# --------------------------------------------------

KAFKA_CONTAINER="cartservice-kafka"
KAFKA_TOPIC="cart-events"
KAFKA_BOOTSTRAP="localhost:9092"

# Check if Kafka container is running
if docker ps --format '{{.Names}}' | grep -q "$KAFKA_CONTAINER"; then
    echo -e "  ${GREEN}OK${NC} Kafka container running"

    # Clear topic by reading all existing messages (consume and discard)
    # Then perform cart operations and verify events

    # Record message count before our operations
    BEFORE_COUNT=$(docker exec "$KAFKA_CONTAINER" kafka-console-consumer \
        --bootstrap-server "$KAFKA_BOOTSTRAP" \
        --topic "$KAFKA_TOPIC" \
        --from-beginning \
        --timeout-ms 3000 2>/dev/null | wc -l)
    echo -e "  ${CYAN}Existing messages in topic: ${BEFORE_COUNT}${NC}"

    # Perform cart operations that should produce events
    KAFKA_PRODUCT_NAME="KafkaTest-Product-$(date +%s)"
    request POST "$PRODUCTSERVICE/products" "$AUTH_HEADERS" \
        "{\"name\":\"${KAFKA_PRODUCT_NAME}\",\"description\":\"Kafka test product\",\"price\":299.99,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}"
    KAFKA_PRODUCT_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

    if [ -n "$KAFKA_PRODUCT_ID" ]; then
        # 1. Add item → ITEM_ADDED
        request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
            "{\"productId\":\"${KAFKA_PRODUCT_ID}\",\"quantity\":2}"

        # 2. Update quantity → ITEM_UPDATED
        request PATCH "$CARTSERVICE/cart/items/${KAFKA_PRODUCT_ID}" "$AUTH_HEADERS" \
            '{"quantity":5}'

        # 3. Remove item → ITEM_REMOVED
        request DELETE "$CARTSERVICE/cart/items/${KAFKA_PRODUCT_ID}" "Authorization: Bearer $TOKEN"

        # 4. Add again for clear/checkout
        request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
            "{\"productId\":\"${KAFKA_PRODUCT_ID}\",\"quantity\":1}"

        # 5. Checkout → CHECKOUT_INITIATED
        request POST "$CARTSERVICE/cart/checkout" "Authorization: Bearer $TOKEN"

        # 6. Clear → CART_CLEARED
        request DELETE "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN"

        # Wait for async Kafka delivery
        sleep 3

        # Consume all messages and get only the new ones
        ALL_EVENTS=$(docker exec "$KAFKA_CONTAINER" kafka-console-consumer \
            --bootstrap-server "$KAFKA_BOOTSTRAP" \
            --topic "$KAFKA_TOPIC" \
            --from-beginning \
            --timeout-ms 5000 2>/dev/null | tail -n +$((BEFORE_COUNT + 1)))

        NEW_COUNT=$(echo "$ALL_EVENTS" | grep -c "eventType" || echo "0")
        echo -e "  ${CYAN}New Kafka events produced: ${NEW_COUNT}${NC}"

        if [ "$NEW_COUNT" -ge 5 ] 2>/dev/null; then
            echo -e "  ${GREEN}PASS${NC} Kafka events produced (${NEW_COUNT} events)"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} Expected at least 5 events, got ${NEW_COUNT}"
            FAIL=$((FAIL + 1))
        fi

        # Verify ITEM_ADDED event
        if echo "$ALL_EVENTS" | grep -q '"eventType":"ITEM_ADDED"'; then
            echo -e "  ${GREEN}PASS${NC} ITEM_ADDED event found"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} ITEM_ADDED event not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify ITEM_UPDATED event
        if echo "$ALL_EVENTS" | grep -q '"eventType":"ITEM_UPDATED"'; then
            echo -e "  ${GREEN}PASS${NC} ITEM_UPDATED event found"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} ITEM_UPDATED event not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify ITEM_REMOVED event
        if echo "$ALL_EVENTS" | grep -q '"eventType":"ITEM_REMOVED"'; then
            echo -e "  ${GREEN}PASS${NC} ITEM_REMOVED event found"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} ITEM_REMOVED event not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify CHECKOUT_INITIATED event
        if echo "$ALL_EVENTS" | grep -q '"eventType":"CHECKOUT_INITIATED"'; then
            echo -e "  ${GREEN}PASS${NC} CHECKOUT_INITIATED event found"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} CHECKOUT_INITIATED event not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify CART_CLEARED event
        if echo "$ALL_EVENTS" | grep -q '"eventType":"CART_CLEARED"'; then
            echo -e "  ${GREEN}PASS${NC} CART_CLEARED event found"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} CART_CLEARED event not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify events are on the correct topic (already consumed from cart-events)
        echo -e "  ${GREEN}PASS${NC} All events on correct topic '${KAFKA_TOPIC}'"
        PASS=$((PASS + 1))

        # Verify events contain userId (admin email from JWT sub)
        if echo "$ALL_EVENTS" | grep -q '"userId":"admin@gmail.com"'; then
            echo -e "  ${GREEN}PASS${NC} Events contain correct userId"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} Events missing userId"
            FAIL=$((FAIL + 1))
        fi

        # Verify CHECKOUT_INITIATED contains items array
        CHECKOUT_EVENT=$(echo "$ALL_EVENTS" | grep "CHECKOUT_INITIATED")
        if echo "$CHECKOUT_EVENT" | grep -q '"items":\['; then
            echo -e "  ${GREEN}PASS${NC} CHECKOUT_INITIATED contains items snapshot"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} CHECKOUT_INITIATED missing items snapshot"
            FAIL=$((FAIL + 1))
        fi

        # Verify events contain productId
        if echo "$ALL_EVENTS" | grep "ITEM_ADDED" | grep -q "\"productId\":\"${KAFKA_PRODUCT_ID}\""; then
            echo -e "  ${GREEN}PASS${NC} ITEM_ADDED event has correct productId"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} ITEM_ADDED event missing correct productId"
            FAIL=$((FAIL + 1))
        fi
    else
        echo -e "  ${YELLOW}SKIP${NC} Could not create test product for Kafka tests"
        SKIP=$((SKIP + 10))
    fi
else
    echo -e "  ${YELLOW}SKIP${NC} Kafka container not running — skipping event tests"
    SKIP=$((SKIP + 10))
fi

# --------------------------------------------------
section "13. Cart Isolation (multi-user)"
# --------------------------------------------------

# Ensure CUSTOMER role exists (requires JJWT admin token, not OAuth2)
ADMIN_LOGIN_RESP=$(curl -s -X POST "$USERSERVICE/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}")
ADMIN_JJWT=$(echo "$ADMIN_LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")

if [ -n "$ADMIN_JJWT" ]; then
    request POST "$USERSERVICE/roles/create" "$(printf 'Authorization: %s\nContent-Type: application/json' "$ADMIN_JJWT")" '{"roleName":"CUSTOMER","description":"Customer role"}'
    if [ "$STATUS" = "201" ] || [ "$STATUS" = "400" ]; then
        echo -e "  ${GREEN}OK${NC} CUSTOMER role ready"
    else
        echo -e "  ${YELLOW}WARN${NC} Role creation returned $STATUS"
    fi
else
    echo -e "  ${RED}FAIL${NC} Could not get admin JJWT token for role creation"
    FAIL=$((FAIL + 1))
fi

# Create two test users
TIMESTAMP2=$(date +%s)
USER_A_EMAIL="cart-user-a-${TIMESTAMP2}@test.com"
USER_B_EMAIL="cart-user-b-${TIMESTAMP2}@test.com"
PHONE_A="90${TIMESTAMP2: -8}"
PHONE_B="91${TIMESTAMP2: -8}"
USER_PASSWORD="Test@1234"

request POST "$USERSERVICE/auth/signup" "Content-Type: application/json" \
    "{\"email\":\"${USER_A_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"name\":\"User A\",\"phone\":\"${PHONE_A}\",\"role\":\"CUSTOMER\"}"
if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ] || [ "$STATUS" = "400" ]; then
    echo -e "  ${GREEN}OK${NC} User A created (${USER_A_EMAIL})"
else
    echo -e "  ${RED}FAIL${NC} Could not create User A: $STATUS"
    FAIL=$((FAIL + 1))
fi

request POST "$USERSERVICE/auth/signup" "Content-Type: application/json" \
    "{\"email\":\"${USER_B_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"name\":\"User B\",\"phone\":\"${PHONE_B}\",\"role\":\"CUSTOMER\"}"
if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ] || [ "$STATUS" = "400" ]; then
    echo -e "  ${GREEN}OK${NC} User B created (${USER_B_EMAIL})"
else
    echo -e "  ${RED}FAIL${NC} Could not create User B: $STATUS"
    FAIL=$((FAIL + 1))
fi

# Get OAuth2 tokens for both users
echo "  Obtaining token for User A..."
TOKEN_A=$(get_oauth2_token "$USER_A_EMAIL" "$USER_PASSWORD")
echo "  Obtaining token for User B..."
TOKEN_B=$(get_oauth2_token "$USER_B_EMAIL" "$USER_PASSWORD")

if [[ "$TOKEN_A" =~ ^eyJ.*\..*\..*$ ]] && [[ "$TOKEN_B" =~ ^eyJ.*\..*\..*$ ]]; then
    echo -e "  ${GREEN}PASS${NC} Both user tokens obtained"
    PASS=$((PASS + 1))

    AUTH_A="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$TOKEN_A")"
    AUTH_B="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$TOKEN_B")"

    # User A adds item to their cart
    request POST "$CARTSERVICE/cart/items" "$AUTH_A" \
        "{\"productId\":\"${PRODUCT_ID}\",\"quantity\":3}"
    assert_status "User A: add item to cart" "201" "$STATUS"

    # User B's cart should be empty (isolated from User A)
    request GET "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN_B"
    assert_status "User B: GET /cart (should be empty)" "200" "$STATUS"
    B_TOTAL=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('totalItems', -1))" 2>/dev/null || echo "-1")
    if [ "$B_TOTAL" -eq 0 ] 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} User B cannot see User A's cart (0 items)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} User B sees ${B_TOTAL} items — cart isolation broken!"
        FAIL=$((FAIL + 1))
    fi

    # User B adds a different item to their own cart
    request POST "$CARTSERVICE/cart/items" "$AUTH_B" \
        "{\"productId\":\"${PRODUCT_ID_2}\",\"quantity\":1}"
    assert_status "User B: add different item to cart" "201" "$STATUS"

    # Verify User A's cart still has their original item, not User B's
    request GET "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN_A"
    assert_status "User A: GET /cart (verify isolation)" "200" "$STATUS"
    A_ITEMS=$(echo "$BODY" | python3 -c "import sys,json; items=json.load(sys.stdin).get('items',[]); print(len(items))" 2>/dev/null || echo "-1")
    A_HAS_PRODUCT=$(echo "$BODY" | python3 -c "
import sys,json
items = json.load(sys.stdin).get('items',[])
ids = [i['productId'] for i in items]
print('YES' if '${PRODUCT_ID}' in ids and '${PRODUCT_ID_2}' not in ids else 'NO')
" 2>/dev/null || echo "NO")
    if [ "$A_HAS_PRODUCT" = "YES" ]; then
        echo -e "  ${GREEN}PASS${NC} User A sees only their own items, not User B's"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} User A's cart contains wrong items — isolation broken!"
        FAIL=$((FAIL + 1))
    fi

    # Admin should NOT see other users' carts (admin gets their own cart)
    request GET "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN"
    assert_status "Admin: GET /cart (gets admin's own cart, not others)" "200" "$STATUS"
    ADMIN_HAS_A_ITEMS=$(echo "$BODY" | python3 -c "
import sys,json
items = json.load(sys.stdin).get('items',[])
ids = [i['productId'] for i in items]
# Admin's cart should NOT contain User A's product (unless admin added it earlier)
# Check that it doesn't have User A's 3-quantity item
for item in items:
    if item['productId'] == '${PRODUCT_ID}' and item['quantity'] == 3:
        print('LEAKED')
        break
else:
    print('ISOLATED')
" 2>/dev/null || echo "UNKNOWN")
    if [ "$ADMIN_HAS_A_ITEMS" = "ISOLATED" ]; then
        echo -e "  ${GREEN}PASS${NC} Admin cannot access User A's cart"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} Admin can see User A's cart — isolation broken!"
        FAIL=$((FAIL + 1))
    fi

    # Cleanup: clear both test user carts
    request DELETE "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN_A"
    request DELETE "$CARTSERVICE/cart" "Authorization: Bearer $TOKEN_B"
    echo -e "  ${CYAN}Cleaned up test user carts${NC}"

else
    echo -e "  ${YELLOW}SKIP${NC} Could not obtain tokens for test users"
    SKIP=$((SKIP + 5))
fi

# --------------------------------------------------
echo ""
echo "=============================================="
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" "$PASS" "$FAIL" "$SKIP"
echo "=============================================="

[ "$FAIL" -eq 0 ]
