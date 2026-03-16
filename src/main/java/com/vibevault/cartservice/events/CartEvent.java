package com.vibevault.cartservice.events;

import com.vibevault.cartservice.models.CartItem;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartEvent {
    private String eventId;
    private CartEventType eventType;
    private String userId;
    private String productId;
    private Integer quantity;
    private List<CartItem> items;
    private LocalDateTime timestamp;
}
