package com.lanf.access.service;

import com.lanf.access.model.AccessContext;
import com.lanf.access.model.AccessDecision;
import com.lanf.common.ApiException;
import lombok.Builder;
import lombok.Getter;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.util.Map;

/**
 * Single orchestration boundary for high-risk order actions.
 *
 * <p>Controllers provide authoritative request context and consume one of the three outcomes.
 * Compatibility credentials are converted to a strict, one-time approval token and then sent
 * back through {@link AccessDecisionService}; they never form a parallel authorization path.</p>
 */
@Service
public class HighRiskActionAuthorizationService {

    private static final int STRICT_BINDING_VERSION = 2;
    private static final int APPROVAL_REQUIRED_CODE = 40322;

    private final AccessDecisionService accessDecisionService;
    private final ApprovalService approvalService;

    public HighRiskActionAuthorizationService(AccessDecisionService accessDecisionService,
                                              ApprovalService approvalService) {
        this.accessDecisionService = accessDecisionService;
        this.approvalService = approvalService;
    }

    public Result authorize(Request request) {
        if (request == null) {
            return Result.denied(400,
                    AccessDecision.deny("ACCESS_CONTEXT_REQUIRED", "缺少高风险操作授权上下文"));
        }

        String suppliedToken = text(request.getBody(), "approvalToken", "approval_token");
        AccessContext context = accessContext(request, suppliedToken);
        AccessDecision initial = accessDecisionService.evaluate(context);
        if (isAllowed(initial)) {
            return Result.allowed(initial, request.getOperatorId());
        }
        if (!requiresApproval(initial)) {
            return Result.denied(403, initial);
        }

        Credentials credentials = credentials(request.getBody());
        if (credentials == null) {
            if (hasAuthorizationPayload(request.getBody())) {
                return Result.denied(401, AccessDecision.deny(
                        "ACCESS_CREDENTIALS_REQUIRED", "请输入有效的授权员工账号和密码/PIN"));
            }
            return Result.denied(APPROVAL_REQUIRED_CODE, initial);
        }

        try {
            Map<String, Object> issued = approvalService.authorizeAndCreateToken(
                    request.getOperatorId(),
                    request.getShopId(),
                    request.getPermissionCode(),
                    request.getResourceType(),
                    request.getResourceId(),
                    request.getAmount(),
                    text(request.getBody(), "reason", "remark"),
                    credentials.account,
                    credentials.credential,
                    credentials.authMethod,
                    request.getRequestId(),
                    request.getTerminalId(),
                    STRICT_BINDING_VERSION
            );
            String issuedToken = issued == null ? null : value(issued.get("approvalToken"));
            if (!StringUtils.hasText(issuedToken)) {
                return Result.denied(503, AccessDecision.deny(
                        "ACCESS_TOKEN_ISSUE_FAILED", "现场授权未生成可用的一次性令牌"));
            }
            AccessDecision approved = accessDecisionService.evaluate(accessContext(request, issuedToken));
            if (!isAllowed(approved)) {
                return Result.denied(requiresApproval(approved) ? APPROVAL_REQUIRED_CODE : 403, approved);
            }
            return Result.allowed(approved, integer(issued.get("authorizerId"), request.getOperatorId()));
        } catch (ApiException ex) {
            return Result.denied(ex.getHttpStatus(),
                    AccessDecision.deny(ex.getErrorCode(), ex.getMessage()));
        }
    }

    private static AccessContext accessContext(Request request, String approvalToken) {
        return AccessContext.builder()
                .adminId(request.getOperatorId())
                .shopId(request.getShopId())
                .permissionCode(request.getPermissionCode())
                .resourceType(request.getResourceType())
                .resourceId(request.getResourceId())
                .amount(request.getAmount())
                .discountRate(request.getDiscountRate())
                .orderStatus(request.getOrderStatus())
                .paymentStatus(request.getPaymentStatus())
                .terminalId(request.getTerminalId())
                .requestId(request.getRequestId())
                .approvalToken(approvalToken)
                .attributes(request.getAttributes())
                .build();
    }

    private static boolean isAllowed(AccessDecision decision) {
        return decision != null && decision.getOutcome() == AccessDecision.Outcome.ALLOW
                && decision.isAllow();
    }

    private static boolean requiresApproval(AccessDecision decision) {
        return decision != null && decision.getOutcome() == AccessDecision.Outcome.REQUIRE_APPROVAL;
    }

    @SuppressWarnings("unchecked")
    private static Credentials credentials(Map<String, Object> body) {
        if (body == null || !(body.get("authorization") instanceof Map)) {
            return null;
        }
        Map<String, Object> authorization = (Map<String, Object>) body.get("authorization");
        String account = text(authorization, "account", "authorizerAccount", "authorizer_account");
        String pin = text(authorization, "pin");
        String password = text(authorization, "password", "credential");
        String credential = StringUtils.hasText(pin) ? pin : password;
        if (!StringUtils.hasText(account) || !StringUtils.hasText(credential)
                || account.length() > 128 || credential.length() > 512) {
            return null;
        }
        return new Credentials(account, credential,
                StringUtils.hasText(pin) ? "PIN" : "PASSWORD");
    }

    private static boolean hasAuthorizationPayload(Map<String, Object> body) {
        return body != null && body.containsKey("authorization");
    }

    private static String text(Map<String, Object> values, String... keys) {
        if (values == null) {
            return null;
        }
        for (String key : keys) {
            String candidate = value(values.get(key));
            if (StringUtils.hasText(candidate)) {
                return candidate.trim();
            }
        }
        return null;
    }

    private static String value(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Integer integer(Object value, Integer fallback) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        if (value != null) {
            try {
                return Integer.valueOf(String.valueOf(value));
            } catch (NumberFormatException ignored) {
                // Fall through to the authenticated operator for audit attribution.
            }
        }
        return fallback;
    }

    private static final class Credentials {
        private final String account;
        private final String credential;
        private final String authMethod;

        private Credentials(String account, String credential, String authMethod) {
            this.account = account;
            this.credential = credential;
            this.authMethod = authMethod;
        }
    }

    @Getter
    @Builder
    public static class Request {
        private Map<String, Object> body;
        private Integer operatorId;
        private Integer shopId;
        private String permissionCode;
        private String resourceType;
        private String resourceId;
        private BigDecimal amount;
        private BigDecimal discountRate;
        private String orderStatus;
        private String paymentStatus;
        private String terminalId;
        private String requestId;
        private Map<String, Object> attributes;
    }

    @Getter
    public static class Result {
        private final boolean allowed;
        private final int code;
        private final AccessDecision decision;
        private final Integer authorizedAdminId;

        private Result(boolean allowed, int code, AccessDecision decision, Integer authorizedAdminId) {
            this.allowed = allowed;
            this.code = code;
            this.decision = decision;
            this.authorizedAdminId = authorizedAdminId;
        }

        private static Result allowed(AccessDecision decision, Integer authorizedAdminId) {
            return new Result(true, 0, decision, authorizedAdminId);
        }

        private static Result denied(int code, AccessDecision decision) {
            return new Result(false, code, decision, null);
        }
    }
}
