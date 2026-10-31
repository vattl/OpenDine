package com.lanf.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.OrderClientRequest;
import com.lanf.entity.R;
import com.lanf.mapper.OrderClientRequestMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.Date;
import java.util.Map;
import java.util.function.Supplier;
import java.security.MessageDigest;
import com.fasterxml.jackson.databind.SerializationFeature;

/** Executes mobile cashier writes once and replays the first response for 24 hours. */
@Service
public class CashierClientRequestService {

    private static final long TTL_MILLIS = 24L * 60L * 60L * 1000L;
    private static final int MAX_KEY_LENGTH = 128;

    @Autowired
    private OrderClientRequestMapper requestMapper;
    @Autowired
    private ObjectMapper objectMapper;

    public R execute(Integer shopId, Integer adminId, String requestId,
                     String requestPath, Supplier<R> operation) {
        return execute(shopId, adminId, requestId, requestPath, null, operation);
    }

    public R execute(Integer shopId, Integer adminId, String requestId,
                     String requestPath, Object requestBody, Supplier<R> operation) {
        if (!StringUtils.hasText(requestId)) {
            return operation.get();
        }
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文");
        }
        String key = requestId.trim();
        if (key.length() > MAX_KEY_LENGTH) {
            return R.error(400, "X-Client-Request-Id 长度不能超过 128 个字符");
        }
        if (!key.matches("[A-Za-z0-9._:-]+")) {
            return R.error(400, "X-Client-Request-Id 格式不合法");
        }

        requestMapper.deleteExpiredKey(shopId, key);
        Date expiresAt = new Date(System.currentTimeMillis() + TTL_MILLIS);
        String fingerprint = fingerprint(requestBody);
        int inserted = requestMapper.insertProcessing(
                shopId, adminId, key, requestPath, fingerprint, expiresAt);
        OrderClientRequest record = requestMapper.lockByKey(shopId, key);
        if (record == null) {
            throw new IllegalStateException("幂等请求占位读取失败");
        }
        if (inserted == 0) {
            if (!requestPath.equals(record.getRequest_path())) {
                return R.error(409, "该幂等键已被其他接口使用");
            }
            if (StringUtils.hasText(record.getRequest_fingerprint())
                    && !record.getRequest_fingerprint().equals(fingerprint)) {
                return R.error(409, "相同 X-Client-Request-Id 的请求内容不一致");
            }
            if ("COMPLETED".equals(record.getStatus())
                    && StringUtils.hasText(record.getResponse_snapshot())) {
                return deserialize(record.getResponse_snapshot());
            }
            return R.error(409, "相同请求正在处理中，请稍后重试");
        }

        R response;
        try {
            response = operation.get();
        } catch (Exception ex) {
            requestMapper.deleteById(record.getId());
            throw ex;
        }

        if (response == null) {
            requestMapper.deleteById(record.getId());
            throw new IllegalStateException("业务接口返回为空");
        }
        if (!Integer.valueOf(0).equals(response.get("code"))) {
            requestMapper.deleteById(record.getId());
            return response;
        }
        String snapshot = serialize(response);
        if (requestMapper.complete(record.getId(), snapshot) != 1) {
            throw new IllegalStateException("幂等响应保存失败");
        }
        return response;
    }

    String fingerprint(Object requestBody) {
        try {
            Object value = requestBody != null ? requestBody : java.util.Collections.emptyMap();
            byte[] canonical = objectMapper.writer()
                    .with(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS)
                    .writeValueAsBytes(value);
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(canonical);
            StringBuilder out = new StringBuilder(digest.length * 2);
            for (byte b : digest) out.append(String.format("%02x", b & 0xff));
            return out.toString();
        } catch (Exception e) {
            throw new IllegalStateException("幂等请求指纹计算失败", e);
        }
    }

    private String serialize(R response) {
        try {
            return objectMapper.writeValueAsString(response);
        } catch (Exception e) {
            throw new IllegalStateException("幂等响应序列化失败", e);
        }
    }

    private R deserialize(String snapshot) {
        try {
            Map<String, Object> values = objectMapper.readValue(
                    snapshot, new TypeReference<Map<String, Object>>() { });
            R response = new R();
            response.clear();
            response.putAll(values);
            return response;
        } catch (Exception e) {
            throw new IllegalStateException("幂等响应读取失败", e);
        }
    }
}
