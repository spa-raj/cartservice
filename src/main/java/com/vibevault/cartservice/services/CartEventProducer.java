package com.vibevault.cartservice.services;

import com.vibevault.cartservice.constants.KafkaTopics;
import com.vibevault.cartservice.events.CartEvent;
import com.vibevault.cartservice.events.CartEventType;
import com.vibevault.cartservice.models.Cart;
import com.vibevault.cartservice.models.CartItem;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class CartEventProducer {

    private final KafkaTemplate<String, CartEvent> kafkaTemplate;

    public void sendItemAdded(String userId, String productId, int quantity) {
        send(CartEvent.builder()
                .eventId(UUID.randomUUID().toString())
                .eventType(CartEventType.ITEM_ADDED)
                .userId(userId)
                .productId(productId)
                .quantity(quantity)
                .timestamp(LocalDateTime.now())
                .build());
    }

    public void sendItemRemoved(String userId, String productId) {
        send(CartEvent.builder()
                .eventId(UUID.randomUUID().toString())
                .eventType(CartEventType.ITEM_REMOVED)
                .userId(userId)
                .productId(productId)
                .timestamp(LocalDateTime.now())
                .build());
    }

    public void sendCartCleared(String userId) {
        send(CartEvent.builder()
                .eventId(UUID.randomUUID().toString())
                .eventType(CartEventType.CART_CLEARED)
                .userId(userId)
                .timestamp(LocalDateTime.now())
                .build());
    }

    public void sendCheckoutInitiated(String userId, List<CartItem> items) {
        send(CartEvent.builder()
                .eventId(UUID.randomUUID().toString())
                .eventType(CartEventType.CHECKOUT_INITIATED)
                .userId(userId)
                .items(items)
                .timestamp(LocalDateTime.now())
                .build());
    }

    private void send(CartEvent event) {
        try {
            kafkaTemplate.send(KafkaTopics.CART_EVENTS, event.getUserId(), event);
            log.debug("Cart event sent: {} for user {}", event.getEventType(), event.getUserId());
        } catch (Exception e) {
            log.warn("Failed to send cart event {} for user {}: {}",
                    event.getEventType(), event.getUserId(), e.getMessage());
        }
    }
}
