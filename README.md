# VibeVault Cart Service

Shopping cart microservice for the VibeVault e-commerce platform.

## Tech Stack

- **Runtime:** Java 21, Spring Boot 4.0.3
- **Database:** MongoDB (Atlas free tier / local Docker)
- **Caching:** Redis (cache-aside pattern, 30min TTL)
- **Messaging:** Apache Kafka (producer, KRaft mode)
- **Auth:** OAuth2 Resource Server (JWT from userservice)
- **Infrastructure:** AWS EKS, Helm, GitHub Actions CI/CD

## API Endpoints

All endpoints require OAuth2 authentication. Cart is scoped to the authenticated user (userId from JWT `sub` claim).

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| `GET` | `/cart` | Get current user's cart | 200 |
| `POST` | `/cart/items` | Add item to cart | 201 |
| `PATCH` | `/cart/items/{productId}` | Update item quantity | 200 |
| `DELETE` | `/cart/items/{productId}` | Remove item from cart | 200 |
| `DELETE` | `/cart` | Clear entire cart | 200 |
| `POST` | `/cart/checkout` | Initiate checkout | 200 |

## Kafka Events

Produces to `cart-events` topic (key: `userId` for per-user ordering):

| Event | Trigger |
|-------|---------|
| `ITEM_ADDED` | Product added to cart |
| `ITEM_UPDATED` | Item quantity changed |
| `ITEM_REMOVED` | Product removed from cart |
| `CART_CLEARED` | All items removed |
| `CHECKOUT_INITIATED` | User initiates checkout (full cart snapshot) |

## Redis Caching

Cache-aside pattern for cart reads:
- **Read:** Redis hit → return cached. Miss → MongoDB → cache in Redis → return.
- **Write:** MongoDB update → evict Redis cache.
- **TTL:** 30 minutes. Graceful degradation — service works without Redis.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8082` | Server port |
| `MONGODB_URI` | `mongodb://localhost:27017/cartservice` | MongoDB connection string |
| `ISSUER_URI` | `http://localhost:8081` | OAuth2 issuer for JWT validation |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker address |
| `PRODUCT_SERVICE_URL` | `http://localhost:8080` | ProductService URL for cart item validation |
| `REDIS_HOST` | `localhost` | Redis host (disabled in docker-compose and EKS) |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_HEALTH_ENABLED` | `true` | Set to `false` when Redis is not deployed |

## Local Development

### Prerequisites
- Java 21
- Docker & Docker Compose
- userservice running on port 8081
- productservice running on port 8080

### Run
```bash
docker network create vibevault-network 2>/dev/null; true
docker compose up -d    # MongoDB + Kafka + cartservice (Redis disabled)
```

Cart service runs on port **8082**.

### Test
```bash
./scripts/test-cart-apis.sh        # 52 tests (CRUD, Kafka, isolation)
./scripts/demo-cart-with-items.sh  # Demo with API, Redis, MongoDB output
```

### Benchmark
```bash
./benchmarks/run-benchmark.sh      # Redis vs MongoDB comparison
```

## Architecture

```
Client → Cart Service → MongoDB Atlas (cart storage)
                     → Redis (cart cache, local dev only — graceful degradation without it)
                     → Kafka (cart events, KRaft)
                     → Product Service (product validation via RestClient)
                     ← User Service (JWT validation via OAuth2)
```

> Redis is available in local Docker dev. On EKS, Redis is not deployed — the cache layer degrades gracefully and all reads go directly to MongoDB. Benchmark showed MongoDB (6.2ms) outperforms Redis (8.21ms) with co-located containers.

## Key Design Decisions

- **BigDecimal for prices** — avoids floating-point precision errors
- **@Version for optimistic locking** — prevents concurrent cart modification conflicts (409 Conflict)
- **Fire-and-forget Kafka** — cart operations succeed even if Kafka is down
- **Product validation** — calls productservice on add (3s connect, 5s read timeout)
- **Jackson 3** — `JacksonJsonSerializer` for Kafka, `GenericJacksonJsonRedisSerializer` for Redis
- **Spring Boot 4.x** — uses `spring.mongodb.*` prefix (not `spring.data.mongodb.*`)

## Related Services

- [userservice](https://github.com/spa-raj/userservice) — Authentication & user management
- [productservice](https://github.com/spa-raj/productservice) — Product catalog & search
- [vibevault-infra](https://github.com/spa-raj/vibevault-infra) — Terraform infrastructure
