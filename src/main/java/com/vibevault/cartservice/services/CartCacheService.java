package com.vibevault.cartservice.services;

import com.vibevault.cartservice.models.Cart;

public interface CartCacheService {
    Cart get(String userId);
    void put(String userId, Cart cart);
    void evict(String userId);
}
