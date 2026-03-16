package com.vibevault.cartservice.services;

import com.vibevault.cartservice.dtos.cart.ProductDto;
import com.vibevault.cartservice.exceptions.ProductNotFoundException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Slf4j
@Service
public class ProductValidationService {

    private final RestClient restClient;

    public ProductValidationService(@Value("${vibevault.productservice.url}") String productServiceUrl) {
        this.restClient = RestClient.builder()
                .baseUrl(productServiceUrl)
                .build();
    }

    public ProductDto getProduct(String productId) {
        return restClient.get()
                .uri("/products/{productId}", productId)
                .retrieve()
                .onStatus(HttpStatusCode::is4xxClientError, (request, response) -> {
                    throw new ProductNotFoundException("Product not found: " + productId);
                })
                .body(ProductDto.class);
    }
}
