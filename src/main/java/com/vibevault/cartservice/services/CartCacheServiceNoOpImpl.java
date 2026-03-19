package com.vibevault.cartservice.services;

import com.vibevault.cartservice.models.Cart;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@ConditionalOnMissingBean(RedisConnectionFactory.class)
public class CartCacheServiceNoOpImpl implements CartCacheService {

    @Override
    public Cart get(String userId) {
        return null;
    }

    @Override
    public void put(String userId, Cart cart) {
        // no-op
    }

    @Override
    public void evict(String userId) {
        // no-op
    }
}
