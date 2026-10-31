package com.lanf.access.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;
import java.util.Map;

/**
 * 统一访问决策输出结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AccessDecision {
    public enum Outcome {
        ALLOW,
        REQUIRE_APPROVAL,
        DENY
    }

    private Outcome outcome;
    private boolean allow;

    private boolean permissionGranted;
    private boolean shopInScope;
    private boolean policyPassed;
    private boolean approvalRequired;

    private String reasonCode;
    private String explanation;

    private List<Map<String, Object>> matchedRoles;
    private List<Map<String, Object>> matchedPolicies;

    private ApprovalRequirement approval;

    public static AccessDecision allow(String explanation) {
        return AccessDecision.builder()
                .outcome(Outcome.ALLOW)
                .allow(true)
                .permissionGranted(true)
                .shopInScope(true)
                .policyPassed(true)
                .approvalRequired(false)
                .reasonCode("ALLOW")
                .explanation(explanation)
                .build();
    }

    public static AccessDecision deny(String reasonCode, String explanation) {
        return AccessDecision.builder()
                .outcome(Outcome.DENY)
                .allow(false)
                .reasonCode(reasonCode)
                .explanation(explanation)
                .build();
    }

    public static AccessDecision approvalRequired(ApprovalRequirement req, String explanation) {
        return AccessDecision.builder()
                .outcome(Outcome.REQUIRE_APPROVAL)
                .allow(false)
                .permissionGranted(true)
                .shopInScope(true)
                .policyPassed(false)
                .approvalRequired(true)
                .reasonCode("APPROVAL_REQUIRED")
                .explanation(explanation)
                .approval(req)
                .build();
    }
}
