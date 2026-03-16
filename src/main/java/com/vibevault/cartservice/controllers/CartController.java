package com.vibevault.cartservice.controllers;

import com.vibevault.cartservice.dtos.cart.AddToCartRequestDto;
import com.vibevault.cartservice.dtos.cart.CartResponseDto;
import com.vibevault.cartservice.dtos.cart.UpdateQuantityRequestDto;
import com.vibevault.cartservice.models.Cart;
import com.vibevault.cartservice.services.CartService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/cart")
@RequiredArgsConstructor
public class CartController {

    private final CartService cartService;

    @GetMapping
    public CartResponseDto getCart(@AuthenticationPrincipal Jwt jwt) {
        Cart cart = cartService.getCart(jwt.getSubject());
        return CartResponseDto.fromCart(cart);
    }

    @PostMapping("/items")
    @ResponseStatus(HttpStatus.CREATED)
    public CartResponseDto addItem(@AuthenticationPrincipal Jwt jwt,
                                   @Valid @RequestBody AddToCartRequestDto request) {
        Cart cart = cartService.addItem(jwt.getSubject(), request.getProductId(), request.getQuantity());
        return CartResponseDto.fromCart(cart);
    }

    @PatchMapping("/items/{productId}")
    public CartResponseDto updateQuantity(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable String productId,
                                          @Valid @RequestBody UpdateQuantityRequestDto request) {
        Cart cart = cartService.updateItemQuantity(jwt.getSubject(), productId, request.getQuantity());
        return CartResponseDto.fromCart(cart);
    }

    @DeleteMapping("/items/{productId}")
    public CartResponseDto removeItem(@AuthenticationPrincipal Jwt jwt,
                                      @PathVariable String productId) {
        Cart cart = cartService.removeItem(jwt.getSubject(), productId);
        return CartResponseDto.fromCart(cart);
    }

    @DeleteMapping
    public CartResponseDto clearCart(@AuthenticationPrincipal Jwt jwt) {
        Cart cart = cartService.clearCart(jwt.getSubject());
        return CartResponseDto.fromCart(cart);
    }

    @PostMapping("/checkout")
    public CartResponseDto checkout(@AuthenticationPrincipal Jwt jwt) {
        Cart cart = cartService.initiateCheckout(jwt.getSubject());
        return CartResponseDto.fromCart(cart);
    }
}
