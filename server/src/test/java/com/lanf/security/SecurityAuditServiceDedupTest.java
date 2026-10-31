package com.lanf.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.OperationLog;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOperationLogService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * D029 access_denied 降噪：同 shop+path+reason 在 60s 窗口内只落 1 条，
 * 窗口结束后下一条携带 suppressedCount。
 */
class SecurityAuditServiceDedupTest {

    private IOperationLogService logs;
    private SecurityAuditService service;

    @BeforeEach
    void setUp() {
        logs = mock(IOperationLogService.class);
        service = new SecurityAuditService(logs, new ObjectMapper());
    }

    private MockHttpServletRequest request(String path) {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        request.setAttribute(SysInterceptor.ATTR_TRACE_ID, "trace-1");
        request.setRemoteAddr("127.0.0.1");
        return request;
    }

    @Test
    @DisplayName("同门店/路径/原因 60s 窗口内多次拒绝只落库 1 条")
    void repeatDeniesWithinWindowAreSuppressed() {
        MockHttpServletRequest req = request("/cashier/kds/authority/lease");
        service.recordAccessDenied(req, null, 5, 401, "invalid_kds_device_token", "kds:device");
        service.recordAccessDenied(req, null, 5, 401, "invalid_kds_device_token", "kds:device");
        service.recordAccessDenied(req, null, 5, 401, "invalid_kds_device_token", "kds:device");
        verify(logs, times(1)).save(org.mockito.ArgumentMatchers.any(OperationLog.class));
    }

    @Test
    @DisplayName("窗口过期后同键拒绝重新落库，并携带上一窗口 suppressedCount")
    void nextWindowPersistsWithSuppressedCount() {
        MockHttpServletRequest req = request("/adminLogin");
        service.recordAccessDenied(req, null, null, 401, "bad_credentials", "admin:login");
        service.recordAccessDenied(req, null, null, 401, "bad_credentials", "admin:login");
        // 模拟 60s 窗口过期：把桶的窗口起始时间拨回 2 分钟前（保留桶计数）
        expireDenyBucketsNow();
        service.recordAccessDenied(req, null, null, 401, "bad_credentials", "admin:login");

        ArgumentCaptor<OperationLog> captor = ArgumentCaptor.forClass(OperationLog.class);
        verify(logs, times(2)).save(captor.capture());
        String second = captor.getAllValues().get(1).getRequest_snapshot();
        assertTrue(second.contains("suppressedCount"), "第二条应携带上一窗口抑制计数，实际=" + second);
    }

    @SuppressWarnings("unchecked")
    private void expireDenyBucketsNow() {
        try {
            java.lang.reflect.Field f = SecurityAuditService.class.getDeclaredField("denyBuckets");
            f.setAccessible(true);
            java.util.concurrent.ConcurrentHashMap<String, Object> buckets =
                    (java.util.concurrent.ConcurrentHashMap<String, Object>) f.get(service);
            for (Object b : buckets.values()) {
                java.lang.reflect.Field wf = b.getClass().getDeclaredField("windowStartMs");
                wf.setAccessible(true);
                wf.setLong(b, System.currentTimeMillis() - 120_000L);
            }
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @Test
    @DisplayName("不同路径的拒绝分别计数、分别落库")
    void differentPathsAreDedupedIndependently() {
        service.recordAccessDenied(request("/a"), null, 1, 401, "denied", "perm:a");
        service.recordAccessDenied(request("/b"), null, 1, 401, "denied", "perm:b");
        verify(logs, times(2)).save(org.mockito.ArgumentMatchers.any(OperationLog.class));
    }
}
