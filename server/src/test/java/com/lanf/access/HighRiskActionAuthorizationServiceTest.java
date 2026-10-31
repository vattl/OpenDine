package com.lanf.access;

import com.lanf.access.model.AccessContext;
import com.lanf.access.model.AccessDecision;
import com.lanf.access.model.ApprovalRequirement;
import com.lanf.access.service.AccessDecisionService;
import com.lanf.access.service.ApprovalService;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import com.lanf.common.ApiException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class HighRiskActionAuthorizationServiceTest {

    private AccessDecisionService decisionService;
    private ApprovalService approvalService;
    private HighRiskActionAuthorizationService service;

    @BeforeEach
    void setUp() {
        decisionService = mock(AccessDecisionService.class);
        approvalService = mock(ApprovalService.class);
        service = new HighRiskActionAuthorizationService(decisionService, approvalService);
    }

    @Test
    void directExactPermissionAllowsWithoutSecondaryAuthorization() {
        when(decisionService.evaluate(any())).thenReturn(AccessDecision.allow("exact permission"));

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                Collections.emptyMap(), "order:operate:refund", "ORD-1", new BigDecimal("12.30")));

        assertTrue(result.isAllowed());
        assertEquals(9, result.getAuthorizedAdminId());
        verifyNoInteractions(approvalService);
        ArgumentCaptor<AccessContext> context = ArgumentCaptor.forClass(AccessContext.class);
        verify(decisionService).evaluate(context.capture());
        assertEquals("order:operate:refund", context.getValue().getPermissionCode());
        assertEquals("ORD-1", context.getValue().getResourceId());
        assertEquals(new BigDecimal("12.30"), context.getValue().getAmount());
        assertEquals("TERM-1", context.getValue().getTerminalId());
    }

    @Test
    void entryOnlyReturnsApprovalRequirementWithoutExecutingLegacyVerifier() {
        AccessDecision required = AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true)
                        .permission("order:operate:discount:approve").build(),
                "approval required");
        when(decisionService.evaluate(any())).thenReturn(required);

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                Collections.emptyMap(), "order:operate:discount", "ORD-2", new BigDecimal("5.00")));

        assertFalse(result.isAllowed());
        assertEquals(AccessDecision.Outcome.REQUIRE_APPROVAL, result.getDecision().getOutcome());
        assertEquals(40322, result.getCode());
        verifyNoInteractions(approvalService);
    }

    @Test
    void malformedCompatibilityCredentialsDenyInsteadOfLoopingApprovalPrompt() {
        Map<String, Object> body = new HashMap<>();
        body.put("authorization", Collections.singletonMap("account", "M1001"));
        when(decisionService.evaluate(any())).thenReturn(AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true)
                        .permission("order:operate:refund:approve").build(),
                "approval required"));

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                body, "order:operate:refund", "ORD-2B", null));

        assertFalse(result.isAllowed());
        assertEquals(401, result.getCode());
        assertEquals("ACCESS_CREDENTIALS_REQUIRED", result.getDecision().getReasonCode());
        verifyNoInteractions(approvalService);
    }

    @Test
    void suppliedApprovalTokenIsPassedToUnifiedDecisionAndNeverValidatedInParallel() {
        Map<String, Object> body = new HashMap<>();
        body.put("approvalToken", "strict-token");
        when(decisionService.evaluate(any())).thenReturn(AccessDecision.allow("approved"));

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                body, "order:operate:reopen", "ORD-3", null));

        assertTrue(result.isAllowed());
        ArgumentCaptor<AccessContext> context = ArgumentCaptor.forClass(AccessContext.class);
        verify(decisionService).evaluate(context.capture());
        assertEquals("strict-token", context.getValue().getApprovalToken());
        verifyNoInteractions(approvalService);
    }

    @Test
    void onsiteCredentialsIssueStrictTokenAndReenterUnifiedDecision() {
        Map<String, Object> authorization = new HashMap<>();
        authorization.put("account", "M1001");
        authorization.put("password", "secret");
        Map<String, Object> body = new HashMap<>();
        body.put("authorization", authorization);
        AccessDecision required = AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true)
                        .permission("order:operate:changePrice:approve").build(),
                "approval required");
        when(decisionService.evaluate(any())).thenReturn(required, AccessDecision.allow("approved"));
        Map<String, Object> issued = new LinkedHashMap<>();
        issued.put("approvalToken", "issued-token");
        issued.put("authorizerId", 22);
        when(approvalService.authorizeAndCreateToken(
                eq(9), eq(7), eq("order:operate:changePrice"), eq("ORDER"), eq("ORD-4"),
                eq(new BigDecimal("88.00")), isNull(), eq("M1001"), eq("secret"),
                eq("PASSWORD"), eq("REQ-1"), eq("TERM-1"), eq(2)))
                .thenReturn(issued);

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                body, "order:operate:changePrice", "ORD-4", new BigDecimal("88.00")));

        assertTrue(result.isAllowed());
        assertEquals(22, result.getAuthorizedAdminId());
        ArgumentCaptor<AccessContext> contexts = ArgumentCaptor.forClass(AccessContext.class);
        verify(decisionService, times(2)).evaluate(contexts.capture());
        assertNull(contexts.getAllValues().get(0).getApprovalToken());
        assertEquals("issued-token", contexts.getAllValues().get(1).getApprovalToken());
    }

    @Test
    void explicitDenyDoesNotAttemptOnsiteApproval() {
        Map<String, Object> authorization = new HashMap<>();
        authorization.put("account", "M1001");
        authorization.put("password", "secret");
        Map<String, Object> body = Collections.singletonMap("authorization", authorization);
        when(decisionService.evaluate(any()))
                .thenReturn(AccessDecision.deny("ACCESS_EXPLICIT_DENY", "blocked"));

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                body, "order:operate:refund", "ORD-5", null));

        assertFalse(result.isAllowed());
        assertEquals(AccessDecision.Outcome.DENY, result.getDecision().getOutcome());
        verifyNoInteractions(approvalService);
    }

    @Test
    void onsiteCredentialFailureReturnsStableDeny() {
        Map<String, Object> authorization = new HashMap<>();
        authorization.put("account", "M1001");
        authorization.put("password", "bad");
        Map<String, Object> body = Collections.singletonMap("authorization", authorization);
        when(decisionService.evaluate(any())).thenReturn(AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true).permission("order:operate:refund:approve").build(),
                "approval required"));
        when(approvalService.authorizeAndCreateToken(anyInt(), anyInt(), anyString(), anyString(),
                anyString(), nullable(BigDecimal.class), nullable(String.class), anyString(), anyString(),
                anyString(), anyString(), anyString(), eq(2)))
                .thenThrow(new ApiException(401, "ACCESS_INVALID_CREDENTIALS", "店长密码错误"));

        HighRiskActionAuthorizationService.Result result = service.authorize(request(
                body, "order:operate:refund", "ORD-6", null));

        assertFalse(result.isAllowed());
        assertEquals(401, result.getCode());
        assertEquals("ACCESS_INVALID_CREDENTIALS", result.getDecision().getReasonCode());
    }

    private static HighRiskActionAuthorizationService.Request request(
            Map<String, Object> body, String permission, String resourceId, BigDecimal amount) {
        return HighRiskActionAuthorizationService.Request.builder()
                .body(body)
                .operatorId(9)
                .shopId(7)
                .permissionCode(permission)
                .resourceType("ORDER")
                .resourceId(resourceId)
                .amount(amount)
                .terminalId("TERM-1")
                .requestId("REQ-1")
                .build();
    }
}
