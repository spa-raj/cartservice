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

## Local Development

### Prerequisites
- Java 21
- Docker & Docker Compose
- userservice running on port 8081
- productservice running on port 8080

### Run
```bash
docker network create vibevault-network 2>/dev/null; true
docker compose up -d    # MongoDB + Redis + Kafka + cartservice
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
Client → Cart Service → MongoDB (cart storage)
                     → Redis (cart cache, 30min TTL)
                     → Kafka (cart events)
                     → Product Service (product validation via RestClient)
                     ← User Service (JWT validation via OAuth2)
```

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
