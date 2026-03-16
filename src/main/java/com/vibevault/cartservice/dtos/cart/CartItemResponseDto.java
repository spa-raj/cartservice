package com.vibevault.cartservice.dtos.cart;

import com.vibevault.cartservice.models.CartItem;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartItemResponseDto {
    private String productId;
    private String productName;
    private int quantity;
    private BigDecimal price;
    private String currency;
    private BigDecimal subtotal;

    public static CartItemResponseDto fromCartItem(CartItem item) {
        return CartItemResponseDto.builder()
                .productId(item.getProductId())
                .productName(item.getProductName())
                .quantity(item.getQuantity())
                .price(item.getPrice())
                .currency(item.getCurrency())
                .subtotal(item.getPrice().multiply(BigDecimal.valueOf(item.getQuantity())))
                .build();
    }
}
