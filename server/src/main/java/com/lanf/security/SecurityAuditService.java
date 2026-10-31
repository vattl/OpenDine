package com.lanf.security;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.OperationLog;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOperationLogService;
import com.lanf.util.AdminShopRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import javax.servlet.http.HttpServletRequest;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Persists security-relevant decisions without ever failing the protected request. */
@Service
public class SecurityAuditService {

    private static final Logger log = LoggerFactory.getLogger(SecurityAuditService.class);
    private static final int MAX_REASON_LENGTH = 255;
    private static final int MAX_TARGET_LENGTH = 64;

    /** access_denied 降噪窗口：同 shop+path+reason 在窗口内只落 1 条，避免拦截拒绝洪水刷屏审计日志 */
    private static final long DENY_DEDUP_WINDOW_MS = 60_000L;
    private static final int DENY_BUCKETS_MAX = 10_000;
    private final java.util.concurrent.ConcurrentHashMap<String, DenyBucket> denyBuckets =
            new java.util.concurrent.ConcurrentHashMap<>();

    /** 拒绝记录窗口桶：windowStartMs 起 60s 内的同键请求计数（含已落库的首条） */
    private static final class DenyBucket {
        long windowStartMs;
        long count;
    }

    private final IOperationLogService operationLogService;
    private final ObjectMapper objectMapper;

    @Autowired
    public SecurityAuditService(IOperationLogService operationLogService, ObjectMapper objectMapper) {
        this.operationLogService = operationLogService;
        this.objectMapper = objectMapper;
    }

    public void recordAccessDenied(HttpServletRequest request, Integer adminId, Integer shopId,
                                   int resultCode, String reasonCode, String requiredPermission) {
        String path = request == null ? null : request.getRequestURI();
        String key = (shopId == null ? "-" : shopId) + "|" + (path == null ? "-" : path)
                + "|" + (reasonCode == null ? "-" : reasonCode);
        long now = System.currentTimeMillis();
        DenyBucket[] evicted = new DenyBucket[1];
        DenyBucket bucket = denyBuckets.compute(key, (k, old) -> {
            if (old == null || now - old.windowStartMs >= DENY_DEDUP_WINDOW_MS) {
                evicted[0] = old;
                DenyBucket nb = new DenyBucket();
                nb.windowStartMs = now;
                nb.count = 1;
                return nb;
            }
            old.count++;
            return old;
        });
        if (denyBuckets.size() > DENY_BUCKETS_MAX) {
            expireDenyBuckets(now);
        }
        if (bucket.count > 1) {
            // 60s 窗口内同门店/路径/原因已记录：抑制本次落库，仅累计计数
            return;
        }
        long suppressed = evicted[0] == null ? 0 : Math.max(0, evicted[0].count - 1);
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("method", request == null ? null : request.getMethod());
        snapshot.put("path", path);
        if (requiredPermission != null && !requiredPermission.trim().isEmpty()) {
            snapshot.put("requiredPermission", requiredPermission.trim());
        }
        if (shopId != null) {
            snapshot.put("resolvedShopId", shopId);
        }
        if (suppressed > 0) {
            snapshot.put("suppressedCount", suppressed);
        }
        persist(request, shopId, "security", "access_denied",
                path, adminId, snapshot, null, "REJECTED", resultCode, reasonCode);
    }

    /** 惰性清理：移除已过窗口的桶，防长期运行 key 泄漏 */
    private void expireDenyBuckets(long now) {
        denyBuckets.entrySet().removeIf(e -> now - e.getValue().windowStartMs >= DENY_DEDUP_WINDOW_MS);
    }

    /** 测试辅助：清空降噪桶（@BeforeEach 调用，保证用例间独立） */
    void resetDenyBucketsForTest() {
        denyBuckets.clear();
    }

    /** Callers must pass identifiers/codes only; passwords, tokens and user PII must never be included. */
    public void recordPermissionChange(HttpServletRequest request, String action, String targetId,
                                       Map<String, ?> beforeState, Map<String, ?> afterState) {
        Integer adminId = requestAttributeInteger(request, SysInterceptor.ATTR_ADMIN_ID);
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        persist(request, shopId, "security", action, targetId, adminId,
                Collections.singletonMap("path", request == null ? null : request.getRequestURI()),
                beforeState, "SUCCESS", 0, "permission_configuration_changed", afterState);
    }

    /** Records a successful high-privilege business operation. Snapshot values must not contain secrets or PII. */
    public void recordPrivilegedAction(HttpServletRequest request, Integer shopId, String module,
                                       String action, String targetId, Integer adminId,
                                       Map<String, ?> snapshot, String reason) {
        persist(request, shopId, module, action, targetId, adminId,
                snapshot, null, "SUCCESS", 0, reason);
    }

    /** Records a successful high-privilege business operation with before/after state snapshots (audit aspect). */
    public void recordPrivilegedActionWithState(HttpServletRequest request, Integer shopId, String module,
                                                String action, String targetId, Integer adminId,
                                                Map<String, ?> snapshot, Map<String, ?> beforeState,
                                                Map<String, ?> afterState, String reason) {
        persist(request, shopId, module, action, targetId, adminId, snapshot,
                beforeState, "SUCCESS", 0, reason, afterState);
    }

    /** Records a failed high-privilege business operation (audit aspect); persist never throws. */
    public void recordFailed(HttpServletRequest request, Integer shopId, String module, String action,
                             String targetId, Integer adminId, Map<String, ?> snapshot, String reason) {
        persist(request, shopId, module, action, targetId, adminId, snapshot,
                null, "FAILED", 500, reason, null);
    }

    /** Persists an expected security rejection independently from the rejected business transaction. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordRejected(HttpServletRequest request, Integer shopId, String module, String action,
                               String targetId, Integer adminId, Map<String, ?> snapshot,
                               int resultCode, String reason) {
        persist(request, shopId, module, action, targetId, adminId, snapshot,
                null, "REJECTED", resultCode, reason, null);
    }

    private void persist(HttpServletRequest request, Integer shopId, String module, String action,
                         String targetId, Integer adminId, Map<String, ?> snapshot,
                         Map<String, ?> beforeState, String resultStatus, Integer resultCode,
                         String reason) {
        persist(request, shopId, module, action, targetId, adminId, snapshot,
                beforeState, resultStatus, resultCode, reason, null);
    }

    private void persist(HttpServletRequest request, Integer shopId, String module, String action,
                         String targetId, Integer adminId, Map<String, ?> snapshot,
                         Map<String, ?> beforeState, String resultStatus, Integer resultCode,
                         String reason, Map<String, ?> afterState) {
        OperationLog row = new OperationLog();
        row.setShop_id(shopId);
        row.setModule(module);
        row.setAction(action);
        row.setTarget_id(truncate(targetId, MAX_TARGET_LENGTH));
        row.setAdmin_id(adminId);
        row.setIp(clientIp(request));
        row.setRequest_snapshot(toJson(snapshot));
        row.setBefore_state(toJson(beforeState));
        row.setAfter_state(toJson(afterState));
        row.setResult_status(resultStatus);
        row.setResult_code(resultCode);
        row.setReason(truncate(reason, MAX_REASON_LENGTH));
        row.setTrace_id(resolveTraceId(request));
        try {
            operationLogService.save(row);
        } catch (RuntimeException e) {
            log.error("安全审计日志持久化失败: action={}, targetId={}, adminId={}, traceId={}, error={}",
                    action, row.getTarget_id(), adminId, row.getTrace_id(), e.getMessage());
        }
    }

    private String toJson(Map<String, ?> value) {
        if (value == null || value.isEmpty()) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            return "{\"serializationError\":true}";
        }
    }

    private static String clientIp(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        return truncate(request.getRemoteAddr(), 64);
    }

    private static Integer requestAttributeInteger(HttpServletRequest request, String name) {
        Object value = request == null ? null : request.getAttribute(name);
        return value instanceof Integer ? (Integer) value : null;
    }

    private static String requestAttributeString(HttpServletRequest request, String name) {
        Object value = request == null ? null : request.getAttribute(name);
        return value == null ? null : value.toString();
    }

    private static String resolveTraceId(HttpServletRequest request) {
        String traceId = requestAttributeString(request, SysInterceptor.ATTR_TRACE_ID);
        if (traceId == null && request != null) {
            traceId = request.getHeader("X-Trace-Id");
        }
        if (traceId == null || traceId.trim().isEmpty()) {
            traceId = UUID.randomUUID().toString().replace("-", "");
            if (request != null) {
                request.setAttribute(SysInterceptor.ATTR_TRACE_ID, traceId);
            }
        }
        return truncate(traceId.trim(), 128);
    }

    private static String truncate(String value, int limit) {
        if (value == null || value.length() <= limit) {
            return value;
        }
        return value.substring(0, limit);
    }
}
