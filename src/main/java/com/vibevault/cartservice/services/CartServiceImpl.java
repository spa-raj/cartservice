package com.vibevault.cartservice.services;

import com.vibevault.cartservice.dtos.cart.ProductDto;
import com.vibevault.cartservice.exceptions.CartItemNotFoundException;
import com.vibevault.cartservice.exceptions.CartNotFoundException;
import com.vibevault.cartservice.exceptions.EmptyCartException;
import com.vibevault.cartservice.exceptions.InvalidQuantityException;
import com.vibevault.cartservice.models.Cart;
import com.vibevault.cartservice.models.CartItem;
import com.vibevault.cartservice.repositories.CartRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
public class CartServiceImpl implements CartService {

    private final CartRepository cartRepository;
    private final ProductValidationService productValidationService;

    @Override
    public Cart getCart(String userId) {
        return cartRepository.findByUserId(userId)
                .orElse(Cart.builder().userId(userId).items(new ArrayList<>()).build());
    }

    @Override
    public Cart addItem(String userId, String productId, int quantity) {
        if (quantity < 1) {
            throw new InvalidQuantityException("Quantity must be at least 1");
        }

        ProductDto product = productValidationService.getProduct(productId);
        String resolvedProductId = product.getId();

        Cart cart = cartRepository.findByUserId(userId)
                .orElse(Cart.builder().userId(userId).items(new ArrayList<>()).build());

        Optional<CartItem> existingItem = cart.getItems().stream()
                .filter(item -> item.getProductId().equals(resolvedProductId))
                .findFirst();

        if (existingItem.isPresent()) {
            existingItem.get().setQuantity(existingItem.get().getQuantity() + quantity);
        } else {
            CartItem newItem = CartItem.builder()
                    .productId(resolvedProductId)
                    .productName(product.getName())
                    .quantity(quantity)
                    .price(product.getPrice().getPrice())
                    .currency(product.getPrice().getCurrency())
                    .addedAt(LocalDateTime.now())
                    .build();
            cart.getItems().add(newItem);
        }

        return cartRepository.save(cart);
    }

    @Override
    public Cart updateItemQuantity(String userId, String productId, int quantity) {
        if (quantity < 0) {
            throw new InvalidQuantityException("Quantity cannot be negative");
        }

        Cart cart = cartRepository.findByUserId(userId)
                .orElseThrow(() -> new CartNotFoundException("Cart not found for user: " + userId));

        if (quantity == 0) {
            return removeItem(userId, productId);
        }

        CartItem item = cart.getItems().stream()
                .filter(i -> i.getProductId().equals(productId))
                .findFirst()
                .orElseThrow(() -> new CartItemNotFoundException("Product " + productId + " not found in cart"));

        item.setQuantity(quantity);
        return cartRepository.save(cart);
    }

    @Override
    public Cart removeItem(String userId, String productId) {
        Cart cart = cartRepository.findByUserId(userId)
                .orElseThrow(() -> new CartNotFoundException("Cart not found for user: " + userId));

        boolean removed = cart.getItems().removeIf(item -> item.getProductId().equals(productId));
        if (!removed) {
            throw new CartItemNotFoundException("Product " + productId + " not found in cart");
        }

        return cartRepository.save(cart);
    }

    @Override
    public Cart clearCart(String userId) {
        Cart cart = cartRepository.findByUserId(userId)
                .orElseThrow(() -> new CartNotFoundException("Cart not found for user: " + userId));

        cart.getItems().clear();
        return cartRepository.save(cart);
    }

    @Override
    public Cart initiateCheckout(String userId) {
        Cart cart = cartRepository.findByUserId(userId)
                .orElseThrow(() -> new CartNotFoundException("Cart not found for user: " + userId));

        if (cart.getItems().isEmpty()) {
            throw new EmptyCartException("Cart is empty, cannot checkout");
        }

        log.info("Checkout initiated for user: {} with {} items", userId, cart.getTotalItems());
        return cart;
    }
}
