package com.vibevault.cartservice.services;

import com.vibevault.cartservice.dtos.cart.ProductDto;
import com.vibevault.cartservice.exceptions.ProductNotFoundException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.time.Duration;

@Slf4j
@Service
public class ProductValidationService {

    private final RestClient restClient;

    public ProductValidationService(@Value("${vibevault.productservice.url}") String productServiceUrl) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(3));
        factory.setReadTimeout(Duration.ofSeconds(5));

        this.restClient = RestClient.builder()
                .baseUrl(productServiceUrl)
                .requestFactory(factory)
                .build();
    }

    public ProductDto getProduct(String productId) {
        return restClient.get()
                .uri("/products/{productId}", productId)
                .retrieve()
                .onStatus(status -> status.value() == 404, (request, response) -> {
                    throw new ProductNotFoundException("Product not found: " + productId);
                })
                .body(ProductDto.class);
    }
}
