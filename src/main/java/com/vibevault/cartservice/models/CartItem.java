package com.vibevault.cartservice.models;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartItem {
    private String productId;
    private String productName;
    private int quantity;
    private double price;
    private LocalDateTime addedAt;
}
