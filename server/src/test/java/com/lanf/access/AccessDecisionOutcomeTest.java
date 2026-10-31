package com.lanf.access;

import com.lanf.access.model.AccessDecision;
import com.lanf.access.model.ApprovalRequirement;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AccessDecisionOutcomeTest {

    @Test
    void compatibilityFlagsStayConsistentWithThreeStateOutcome() {
        AccessDecision allow = AccessDecision.allow("ok");
        AccessDecision requireApproval = AccessDecision.approvalRequired(
                ApprovalRequirement.builder().required(true).permission("order:operate:refund:approve").build(),
                "approval required");
        AccessDecision deny = AccessDecision.deny("ACCESS_DENIED", "denied");

        assertEquals(AccessDecision.Outcome.ALLOW, allow.getOutcome());
        assertTrue(allow.isAllow());
        assertFalse(allow.isApprovalRequired());

        assertEquals(AccessDecision.Outcome.REQUIRE_APPROVAL, requireApproval.getOutcome());
        assertFalse(requireApproval.isAllow());
        assertTrue(requireApproval.isApprovalRequired());

        assertEquals(AccessDecision.Outcome.DENY, deny.getOutcome());
        assertFalse(deny.isAllow());
        assertFalse(deny.isApprovalRequired());
    }
}
