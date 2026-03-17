package com.vibevault.cartservice.services;

import com.vibevault.cartservice.configurations.RedisConfig;
import com.vibevault.cartservice.models.Cart;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class CartCacheServiceRedisImpl implements CartCacheService{

    private static final String CACHE_PREFIX = "cart:";
    private final RedisTemplate<String, Cart> cartRedisTemplate;

    public Cart get(String userId) {
        try {
            Cart cached = cartRedisTemplate.opsForValue().get(cacheKey(userId));
            if (cached != null) {
                log.debug("Cache hit for user: {}", userId);
            }
            return cached;
        } catch (Exception e) {
            log.warn("Redis read failed for user {}: {}", userId, e.getMessage());
            return null;
        }
    }

    public void put(String userId, Cart cart) {
        try {
            cartRedisTemplate.opsForValue().set(cacheKey(userId), cart, RedisConfig.CART_CACHE_TTL);
            log.debug("Cached cart for user: {}", userId);
        } catch (Exception e) {
            log.warn("Redis write failed for user {}: {}", userId, e.getMessage());
        }
    }

    public void evict(String userId) {
        try {
            cartRedisTemplate.delete(cacheKey(userId));
            log.debug("Evicted cache for user: {}", userId);
        } catch (Exception e) {
            log.warn("Redis evict failed for user {}: {}", userId, e.getMessage());
        }
    }

    private String cacheKey(String userId) {
        return CACHE_PREFIX + userId;
    }
}
