package com.vibevault.cartservice.services;

import com.vibevault.cartservice.models.Cart;

public interface CartService {
    Cart getCart(String userId);
    Cart addItem(String userId, String productId, int quantity);
    Cart updateItemQuantity(String userId, String productId, int quantity);
    Cart removeItem(String userId, String productId);
    Cart clearCart(String userId);
    Cart initiateCheckout(String userId);
}
