package com.vibevault.cartservice.dtos.cart;

import jakarta.validation.constraints.Min;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class UpdateQuantityRequestDto {
    @Min(value = 0, message = "Quantity cannot be negative")
    private int quantity;
}
