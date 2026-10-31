package com.lanf.integration.web;

import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.web.dto.ApiResult;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

@org.springframework.core.annotation.Order(org.springframework.core.Ordered.HIGHEST_PRECEDENCE)
@RestControllerAdvice(assignableTypes = {ZsqAuthController.class, ZsqOrderController.class})
public class GlobalExceptionHandler {

    @ExceptionHandler(org.springframework.web.server.ResponseStatusException.class)
    public ResponseEntity<ApiResult<Void>> handleStatus(org.springframework.web.server.ResponseStatusException e) {
        return ResponseEntity.status(e.getStatus()).body(ApiResult.fail(e.getStatus().value(), e.getReason()));
    }

    @ExceptionHandler(ZsqApiException.class)
    public ResponseEntity<ApiResult<Void>> handleZsq(ZsqApiException e) {
        int code = e.getCode() > 0 ? e.getCode() : 502;
        HttpStatus status = code == 403 ? HttpStatus.FORBIDDEN : HttpStatus.BAD_GATEWAY;
        return ResponseEntity.status(status).body(ApiResult.fail(code, "配送服务暂时不可用"));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResult<Void> handleValid(MethodArgumentNotValidException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining("; "));
        return ApiResult.fail(400, msg);
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResult<Void> handleOther(Exception e) {
        return ApiResult.fail(500, "服务器错误");
    }
}
