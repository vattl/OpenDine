package com.lanf.audit;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.audit.aspect.AuditLogAspect;
import com.lanf.audit.diff.DiffProvider;
import com.lanf.audit.diff.NoopDiffProvider;
import com.lanf.audit.diff.OrderRefundDiffProvider;
import com.lanf.security.SecurityAuditService;
import org.aspectj.lang.ProceedingJoinPoint;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationContext;
import org.springframework.test.util.ReflectionTestUtils;

import org.springframework.mock.web.MockMultipartFile;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

/**
 * AuditLogAspect 行为单测：
 * 成功记 SUCCESS + 前后状态；异常记 FAILED 且原样抛出；审计异常不阻断业务；SpEL target 解析与降级。
 */
public class AuditLogAspectTest {

    private SecurityAuditService securityAuditService;
    private ApplicationContext applicationContext;
    private AuditLogAspect aspect;

    @Before
    public void setUp() {
        securityAuditService = mock(SecurityAuditService.class);
        applicationContext = mock(ApplicationContext.class);
        aspect = new AuditLogAspect();
        ReflectionTestUtils.setField(aspect, "securityAuditService", securityAuditService);
        ReflectionTestUtils.setField(aspect, "applicationContext", applicationContext);
        ReflectionTestUtils.setField(aspect, "objectMapper", new ObjectMapper());
    }

    @Test
    public void successRecordsSuccessWithSnapshot() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("orderNo", "ORD-TEST-001");
        body.put("amount", 1.0);
        when(pjp.getArgs()).thenReturn(new Object[]{body});

        aspect.around(pjp, auditLog("cashier", "cashier_checkout", "#p0['orderNo'] ?: #p0['order_no']"));

        ArgumentCaptor<Map> snap = ArgumentCaptor.forClass(Map.class);
        verify(securityAuditService).recordPrivilegedActionWithState(
                isNull(), isNull(), eq("cashier"), eq("cashier_checkout"),
                eq("ORD-TEST-001"), isNull(), snap.capture(), isNull(), isNull(), isNull());
        assertTrue(snap.getValue().get("args").toString().contains("ORD-TEST-001"));
        verify(securityAuditService, never()).recordFailed(any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    public void failureRecordsFailedAndRethrows() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        RuntimeException ex = new RuntimeException("boom");
        when(pjp.proceed()).thenThrow(ex);
        when(pjp.getArgs()).thenReturn(new Object[]{Collections.singletonMap("orderNo", "ORD-TEST-002")});

        try {
            aspect.around(pjp, auditLog("refund", "refund_apply", "#p0['orderNo']"));
            fail("应原样抛出业务异常");
        } catch (RuntimeException e) {
            assertEquals("boom", e.getMessage());
        }
        verify(securityAuditService).recordFailed(
                isNull(), isNull(), eq("refund"), eq("refund_apply"),
                eq("ORD-TEST-002"), isNull(), anyMap(), eq("boom"));
        verify(securityAuditService, never())
                .recordPrivilegedActionWithState(any(), any(), any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    public void auditFailureNeverBlocksBusiness() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");
        when(pjp.getArgs()).thenReturn(new Object[]{Collections.singletonMap("orderNo", "ORD-TEST-003")});
        doThrow(new RuntimeException("db-down")).when(securityAuditService)
                .recordPrivilegedActionWithState(any(), any(), any(), any(), any(), any(), any(), any(), any(), any());

        Object result = aspect.around(pjp, auditLog("cashier", "cashier_checkout", "#p0['orderNo']"));
        assertEquals("ok", result);
    }

    @Test
    public void diffProviderCapturesBeforeAndAfter() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");
        when(pjp.getArgs()).thenReturn(new Object[]{Collections.singletonMap("orderNo", "ORD-TEST-004")});
        OrderRefundDiffProvider diff = mock(OrderRefundDiffProvider.class);
        when(applicationContext.getBean(OrderRefundDiffProvider.class)).thenReturn(diff);
        when(diff.captureBefore("ORD-TEST-004")).thenReturn(Collections.singletonMap("refundAmount", 0.0));
        when(diff.captureAfter("ORD-TEST-004")).thenReturn(Collections.singletonMap("refundAmount", 1.0));

        aspect.around(pjp, auditLog("refund", "refund_settle", "#p0['orderNo']", OrderRefundDiffProvider.class));

        ArgumentCaptor<Map> before = ArgumentCaptor.forClass(Map.class);
        ArgumentCaptor<Map> after = ArgumentCaptor.forClass(Map.class);
        verify(securityAuditService).recordPrivilegedActionWithState(
                isNull(), isNull(), eq("refund"), eq("refund_settle"),
                eq("ORD-TEST-004"), isNull(), anyMap(), before.capture(), after.capture(), isNull());
        assertEquals(0.0, before.getValue().get("refundAmount"));
        assertEquals(1.0, after.getValue().get("refundAmount"));
    }

    @Test
    public void targetSpelMissingKeyDegradesToNull() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");
        when(pjp.getArgs()).thenReturn(new Object[]{Collections.singletonMap("other", "x")});

        aspect.around(pjp, auditLog("cashier", "cashier_discount", "#p0['orderNo'] ?: #p0['order_no']"));

        verify(securityAuditService).recordPrivilegedActionWithState(
                isNull(), isNull(), eq("cashier"), eq("cashier_discount"),
                isNull(), isNull(), anyMap(), isNull(), isNull(), isNull());
    }

    private static AuditLog auditLog(String module, String action, String target) {
        return auditLog(module, action, target, NoopDiffProvider.class);
    }

    private static AuditLog auditLog(final String module, final String action, final String target,
                                     final Class<? extends DiffProvider> diff) {
        return new AuditLog() {
            @Override
            public Class<? extends java.lang.annotation.Annotation> annotationType() {
                return AuditLog.class;
            }

            @Override
            public String module() {
                return module;
            }

            @Override
            public String action() {
                return action;
            }

            @Override
            public String target() {
                return target;
            }

            @Override
            public Class<? extends DiffProvider> diff() {
                return diff;
            }
        };
    }

    @Test
    public void multipartFileArg_sanitizedWithoutSerializingRawBytes() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");

        MockMultipartFile file = new MockMultipartFile(
                "file", "app-v2.1.0.apk", "application/vnd.android.package-archive", new byte[]{1, 2, 3, 4, 5});
        when(pjp.getArgs()).thenReturn(new Object[]{file, "android", "pos"});

        aspect.around(pjp, auditLog("admin", "admin_app_version_upload", "#p0.originalFilename"));

        ArgumentCaptor<Map> snap = ArgumentCaptor.forClass(Map.class);
        verify(securityAuditService).recordPrivilegedActionWithState(
                isNull(), isNull(), eq("admin"), eq("admin_app_version_upload"),
                eq("app-v2.1.0.apk"), isNull(), snap.capture(), isNull(), isNull(), isNull());

        String argsLog = snap.getValue().get("args").toString();
        assertTrue(argsLog.contains("MultipartFile"));
        assertTrue(argsLog.contains("app-v2.1.0.apk"));
        assertTrue(argsLog.contains("size"));
        assertFalse(argsLog.contains("[serialization-error]"));
    }
}
