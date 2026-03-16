package com.vibevault.cartservice.advices;

import com.vibevault.cartservice.dtos.exceptions.ExceptionDto;
import com.vibevault.cartservice.exceptions.CartItemNotFoundException;
import com.vibevault.cartservice.exceptions.CartNotFoundException;
import com.vibevault.cartservice.exceptions.EmptyCartException;
import com.vibevault.cartservice.exceptions.InvalidQuantityException;
import com.vibevault.cartservice.exceptions.ProductNotFoundException;
import jakarta.servlet.http.HttpServletRequest;
import lombok.extern.slf4j.Slf4j;
import org.owasp.encoder.Encode;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.LocalDateTime;

@Slf4j
@RestControllerAdvice
public class ExceptionAdvices {

    @ExceptionHandler(CartNotFoundException.class)
    public ResponseEntity<ExceptionDto> handleCartNotFound(CartNotFoundException ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.NOT_FOUND, ex.getMessage(), request.getRequestURI(), "CART_NOT_FOUND");
    }

    @ExceptionHandler(CartItemNotFoundException.class)
    public ResponseEntity<ExceptionDto> handleCartItemNotFound(CartItemNotFoundException ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.NOT_FOUND, ex.getMessage(), request.getRequestURI(), "CART_ITEM_NOT_FOUND");
    }

    @ExceptionHandler(ProductNotFoundException.class)
    public ResponseEntity<ExceptionDto> handleProductNotFound(ProductNotFoundException ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.NOT_FOUND, ex.getMessage(), request.getRequestURI(), "PRODUCT_NOT_FOUND");
    }

    @ExceptionHandler(InvalidQuantityException.class)
    public ResponseEntity<ExceptionDto> handleInvalidQuantity(InvalidQuantityException ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.BAD_REQUEST, ex.getMessage(), request.getRequestURI(), "INVALID_QUANTITY");
    }

    @ExceptionHandler(EmptyCartException.class)
    public ResponseEntity<ExceptionDto> handleEmptyCart(EmptyCartException ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.BAD_REQUEST, ex.getMessage(), request.getRequestURI(), "EMPTY_CART");
    }

    @ExceptionHandler(org.springframework.web.bind.MethodArgumentNotValidException.class)
    public ResponseEntity<ExceptionDto> handleValidation(org.springframework.web.bind.MethodArgumentNotValidException ex, HttpServletRequest request) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ": " + error.getDefaultMessage())
                .reduce((a, b) -> a + "; " + b)
                .orElse("Validation failed");
        return buildResponse(HttpStatus.BAD_REQUEST, message, request.getRequestURI(), "VALIDATION_ERROR");
    }

    @ExceptionHandler(org.springframework.dao.OptimisticLockingFailureException.class)
    public ResponseEntity<ExceptionDto> handleOptimisticLock(Exception ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.CONFLICT, "Cart was modified concurrently, please retry", request.getRequestURI(), "CONCURRENT_MODIFICATION");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ExceptionDto> handleGenericException(Exception ex, HttpServletRequest request) {
        log.error("Unhandled exception at {}: {}", request.getRequestURI(), ex.getMessage(), ex);
        return buildResponse(HttpStatus.INTERNAL_SERVER_ERROR, "Internal server error", request.getRequestURI(), "INTERNAL_ERROR");
    }

    private ResponseEntity<ExceptionDto> buildResponse(HttpStatus status, String message, String path, String errorCode) {
        ExceptionDto dto = new ExceptionDto(
                status.toString(),
                Encode.forHtml(message),
                path,
                errorCode,
                LocalDateTime.now()
        );
        return new ResponseEntity<>(dto, status);
    }
}
