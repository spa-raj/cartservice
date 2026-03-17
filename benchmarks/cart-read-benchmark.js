import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8082';
const TOKEN = __ENV.TOKEN || '';
const SETUP_URL = __ENV.SETUP_URL || 'http://localhost:8080';  // productservice

// Custom metrics
const getCartLatency = new Trend('get_cart_duration', true);
const errors = new Counter('errors');

// ---------------------------------------------------------------------------
// Scenarios — ramp from 1 → 5 → 15 VUs (same as OpenSearch benchmark)
// ---------------------------------------------------------------------------
export const options = {
  scenarios: {
    cart_read: {
      executor: 'ramping-vus',
      exec: 'getCart',
      startVUs: 1,
      stages: [
        { duration: '15s', target: 1 },   // warm-up
        { duration: '30s', target: 5 },    // ramp to 5
        { duration: '30s', target: 5 },    // hold 5
        { duration: '30s', target: 15 },   // ramp to 15
        { duration: '30s', target: 15 },   // hold 15
        { duration: '15s', target: 0 },    // ramp down
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
  },
};

// ---------------------------------------------------------------------------
// Setup — populate cart with items before benchmark
// ---------------------------------------------------------------------------
export function setup() {
  if (!TOKEN) {
    console.error('TOKEN env var is required. Get an OAuth2 token first.');
    return { token: '' };
  }

  const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json',
  };

  // Clear existing cart
  http.del(`${BASE_URL}/cart`, null, { headers: { 'Authorization': `Bearer ${TOKEN}` } });

  // Create test products in productservice
  const timestamp = Date.now();
  const productIds = [];

  for (let i = 1; i <= 5; i++) {
    const productRes = http.post(`${SETUP_URL}/products`, JSON.stringify({
      name: `BenchProduct-${i}-${timestamp}`,
      description: `Benchmark test product ${i}`,
      price: 100 * i + 99.99,
      currency: 'INR',
      categoryName: 'Electronics',
    }), { headers });

    if (productRes.status === 200) {
      const product = JSON.parse(productRes.body);
      productIds.push(product.id);
    }
  }

  // Ensure category exists
  http.post(`${SETUP_URL}/categories`, JSON.stringify({
    name: 'Electronics',
    description: 'Electronic devices',
  }), { headers });

  // Add products to cart
  for (const productId of productIds) {
    http.post(`${BASE_URL}/cart/items`, JSON.stringify({
      productId: productId,
      quantity: Math.floor(Math.random() * 3) + 1,
    }), { headers });
  }

  // Trigger one GET to populate Redis cache
  http.get(`${BASE_URL}/cart`, { headers: { 'Authorization': `Bearer ${TOKEN}` } });

  console.log(`Setup complete: ${productIds.length} products added to cart`);
  return { token: TOKEN };
}

// ---------------------------------------------------------------------------
// Benchmark: GET /cart (measures cache-aside performance)
// ---------------------------------------------------------------------------
export function getCart(data) {
  if (!data.token) {
    sleep(1);
    return;
  }

  const res = http.get(`${BASE_URL}/cart`, {
    headers: { 'Authorization': `Bearer ${data.token}` },
  });

  const ok = check(res, {
    'GET /cart status 200': (r) => r.status === 200,
    'Cart has items': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.totalItems > 0;
      } catch (_) {
        return false;
      }
    },
  });

  getCartLatency.add(res.timings.duration);
  if (!ok) errors.add(1);

  sleep(0.5);
}

// ---------------------------------------------------------------------------
// Teardown — clean up
// ---------------------------------------------------------------------------
export function teardown(data) {
  if (data.token) {
    http.del(`${BASE_URL}/cart`, null, {
      headers: { 'Authorization': `Bearer ${data.token}` },
    });
    console.log('Teardown: cart cleared');
  }
}
