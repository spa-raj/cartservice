# VibeVault Cart Service

Shopping cart microservice for the VibeVault e-commerce platform.

## Tech Stack

- **Runtime:** Java 21, Spring Boot 4.1.0-M2
- **Database:** MongoDB (Atlas free tier / local Docker)
- **Messaging:** Apache Kafka (producer)
- **Auth:** OAuth2 Resource Server (JWT from userservice)
- **Infrastructure:** AWS EKS, Helm, GitHub Actions CI/CD

## API Endpoints

All endpoints require OAuth2 authentication. Cart is scoped to the authenticated user.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/cart` | Get current user's cart |
| `POST` | `/cart/items` | Add item to cart |
| `PATCH` | `/cart/items/{productId}` | Update item quantity |
| `DELETE` | `/cart/items/{productId}` | Remove item from cart |
| `DELETE` | `/cart` | Clear entire cart |
| `POST` | `/cart/checkout` | Initiate checkout |

## Kafka Events

Produces to `cart-events` topic:

| Event | Trigger |
|-------|---------|
| `ITEM_ADDED` | Product added or quantity increased |
| `ITEM_REMOVED` | Product removed from cart |
| `CART_CLEARED` | All items removed |
| `CHECKOUT_INITIATED` | User initiates checkout (full cart snapshot) |

## Local Development

### Prerequisites
- Java 21
- Docker & Docker Compose
- userservice running on port 8081
- productservice running on port 8080

### Run
```bash
docker compose up -d    # MongoDB + Kafka
./mvnw spring-boot:run
```

Cart service runs on port **8082**.

## Architecture

```
Client → Cart Service → MongoDB (cart storage)
                     → Kafka (cart events)
                     → Product Service (product validation)
                     ← User Service (JWT validation)
```

## Related Services

- [userservice](https://github.com/spa-raj/userservice) — Authentication & user management
- [productservice](https://github.com/spa-raj/productservice) — Product catalog & search
- [vibevault-infra](https://github.com/spa-raj/vibevault-infra) — Terraform infrastructure
