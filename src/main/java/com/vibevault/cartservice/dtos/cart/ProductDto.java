package com.vibevault.cartservice.dtos.cart;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ProductDto {
    private String id;
    private String name;
    private PriceDto price;

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class PriceDto {
        private BigDecimal price;
        private String currency;
    }
}
