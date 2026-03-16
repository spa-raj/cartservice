package com.vibevault.cartservice.dtos.cart;

import com.vibevault.cartservice.models.Cart;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartResponseDto {
    private String cartId;
    private String userId;
    private List<CartItemResponseDto> items;
    private int totalItems;
    private BigDecimal totalPrice;

    public static CartResponseDto fromCart(Cart cart) {
        List<CartItemResponseDto> itemDtos = cart.getItems().stream()
                .map(CartItemResponseDto::fromCartItem)
                .toList();

        return CartResponseDto.builder()
                .cartId(cart.getId())
                .userId(cart.getUserId())
                .items(itemDtos)
                .totalItems(cart.getTotalItems())
                .totalPrice(cart.getTotalPrice())
                .build();
    }
}
