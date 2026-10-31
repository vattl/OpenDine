package com.lanf.config;

import com.lanf.common.ApiException;
import com.lanf.entity.R;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.mybatis.spring.MyBatisSystemException;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 将 Spring 默认 400（JSON 反序列化失败等）转为统一 R 结构，便于前端展示。
 */
@RestControllerAdvice
public class GlobalApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalApiExceptionHandler.class);

    /**
     * 业务 API 异常：按异常携带的真实 HTTP 状态码返回（如版本冲突 409、无权限 403），
     * body 为 {code, error(稳定错误码), msg, data}，见系统设置协调文档 §1/§4。
     */
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<R> onApiException(ApiException ex) {
        log.warn("业务异常: error={}", ex.getErrorCode());
        R body = R.error(ex.getHttpStatus(), ex.getMessage());
        body.put("error", ex.getErrorCode());
        body.put("error_code", ex.getErrorCode());
        if (ex.getData() != null) {
            body.put("data", ex.getData());
        }
        return ResponseEntity.status(ex.getHttpStatus()).body(body);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public R onNotReadable(HttpMessageNotReadableException ex) {
        return safeError(400, "请求体格式错误", ex);
    }

    /**
     * MyBatis/JDBC 异常（如库表缺少 balance 列）时 Spring 默认 500 且 message 常为空，此处转为统一 R 便于排查。
     */
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ExceptionHandler(DataAccessException.class)
    public R onDataAccess(DataAccessException ex) {
        return buildPersistenceErrorResponse(ex, ex.getMostSpecificCause());
    }

    /** MyBatis 抛出的异常通常不继承 Spring DataAccessException，需单独处理以便返回可读 msg */
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ExceptionHandler(MyBatisSystemException.class)
    public R onMyBatisSystem(MyBatisSystemException ex) {
        return buildPersistenceErrorResponse(ex, ex.getMostSpecificCause());
    }

    private R buildPersistenceErrorResponse(Throwable logged, Throwable root) {
        return safeError(500, "数据访问失败，请联系管理员", logged != null ? logged : root);
    }

    /**
     * 其余未单独处理的异常，避免 Spring 默认错误体 message 为空、难以排查。
     */
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ExceptionHandler(Exception.class)
    public R onUnhandled(Exception ex) {
        return safeError(500, "服务器处理失败，请稍后重试", ex);
    }
    private R safeError(int code, String message, Throwable error) {
        String traceId = java.util.UUID.randomUUID().toString();
        String errorMsg = error != null ? error.getMessage() : "";
        log.error("request failed traceId={} type={} msg={}", traceId, (error != null ? error.getClass().getSimpleName() : "Unknown"), errorMsg, error);
        return R.error(code, message).put("traceId", traceId);
    }
}
