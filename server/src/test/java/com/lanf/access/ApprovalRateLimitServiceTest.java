package com.lanf.access;

import com.lanf.access.service.ApprovalRateLimitService;
import com.lanf.common.ApiException;
import com.lanf.entity.AccessApprovalRateLimit;
import com.lanf.mapper.AccessApprovalRateLimitMapper;
import com.lanf.security.SecurityAuditService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ApprovalRateLimitServiceTest {

    private final Map<String, AccessApprovalRateLimit> store = new HashMap<>();
    private AccessApprovalRateLimitMapper mapper;
    private ApprovalRateLimitService service;

    @BeforeEach
    void setUp() {
        mapper = mock(AccessApprovalRateLimitMapper.class);
        SecurityAuditService audit = mock(SecurityAuditService.class);
        Clock clock = Clock.fixed(Instant.parse("2026-10-23T04:00:00Z"), ZoneOffset.UTC);
        service = new ApprovalRateLimitService(mapper, audit, clock);

        when(mapper.insertIfAbsent(anyString(), anyString(), any(Date.class))).thenAnswer(invocation -> {
            String key = invocation.getArgument(0);
            String scope = invocation.getArgument(1);
            Date now = invocation.getArgument(2);
            store.computeIfAbsent(key, ignored -> {
                AccessApprovalRateLimit row = new AccessApprovalRateLimit();
                row.setLimitKey(key);
                row.setLimitScope(scope);
                row.setWindowStartedAt(now);
                row.setAttempts(0);
                return row;
            });
            return 1;
        });
        when(mapper.selectForUpdate(anyString())).thenAnswer(invocation -> store.get(invocation.getArgument(0)));
        doAnswer(invocation -> {
            AccessApprovalRateLimit row = store.get(invocation.getArgument(0));
            row.setWindowStartedAt(invocation.getArgument(1));
            row.setAttempts(invocation.getArgument(2));
            row.setBlockedUntil(invocation.getArgument(3));
            return 1;
        }).when(mapper).updateState(anyString(), any(Date.class), anyInt(), any());
        doAnswer(invocation -> {
            store.remove(invocation.getArgument(0));
            return 1;
        }).when(mapper).deleteByLimitKey(anyString());
    }

    @Test
    void requestLimitAllowsThresholdThenReturnsStructured429() {
        ApprovalRateLimitService anotherInstance = new ApprovalRateLimitService(
                mapper, mock(SecurityAuditService.class),
                Clock.fixed(Instant.parse("2026-10-23T04:00:00Z"), ZoneOffset.UTC));
        for (int i = 0; i < 5; i++) {
            service.acquireRequest(ApprovalRateLimitService.Scope.ONSITE_AUTHORIZE, 1, "operator:10");
            anotherInstance.acquireRequest(ApprovalRateLimitService.Scope.ONSITE_AUTHORIZE, 1, "operator:10");
        }
        ApiException ex = assertThrows(ApiException.class,
                () -> service.acquireRequest(ApprovalRateLimitService.Scope.ONSITE_AUTHORIZE, 1, "operator:10"));
        assertEquals(429, ex.getHttpStatus());
        assertEquals("ACCESS_APPROVAL_RATE_LIMITED", ex.getErrorCode());
        Map<?, ?> data = (Map<?, ?>) ex.getData();
        assertEquals("ONSITE_AUTHORIZE", data.get("rateLimitScope"));
        assertTrue(((Number) data.get("retryAfterSeconds")).longValue() >= 1L);
    }

    @Test
    void credentialFailureUsesHashedKeyAndSuccessClearsState() {
        String key = service.credentialKey(8, " Manager_01 ");
        assertFalse(key.contains("manager_01"));
        for (int i = 0; i < 5; i++) {
            service.recordCredentialFailure(8, " Manager_01 ", 5);
        }
        ApiException ex = assertThrows(ApiException.class,
                () -> service.assertCredentialAllowed(8, "manager_01", 5));
        assertEquals(429, ex.getHttpStatus());

        service.clearCredentialFailures(8, "manager_01");
        service.assertCredentialAllowed(8, "manager_01", 5);
    }
}
