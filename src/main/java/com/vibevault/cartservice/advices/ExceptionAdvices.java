package com.vibevault.cartservice.advices;

import com.vibevault.cartservice.dtos.exceptions.ExceptionDto;
import com.vibevault.cartservice.exceptions.CartItemNotFoundException;
import com.vibevault.cartservice.exceptions.CartNotFoundException;
import com.vibevault.cartservice.exceptions.InvalidQuantityException;
import com.vibevault.cartservice.exceptions.ProductNotFoundException;
import jakarta.servlet.http.HttpServletRequest;
import org.owasp.encoder.Encode;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.LocalDateTime;

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

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ExceptionDto> handleGenericException(Exception ex, HttpServletRequest request) {
        return buildResponse(HttpStatus.INTERNAL_SERVER_ERROR, ex.getMessage(), request.getRequestURI(), "INTERNAL_ERROR");
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
