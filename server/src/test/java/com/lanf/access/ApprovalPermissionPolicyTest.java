package com.lanf.access;

import com.lanf.access.security.ApprovalPermissionPolicy;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ApprovalPermissionPolicyTest {

    @Test
    void derivesAndAcceptsOnlyExactActionApprovalPermission() {
        assertEquals("order:operate:refund:approve",
                ApprovalPermissionPolicy.requiredPermission(" order:operate:refund "));
        assertTrue(ApprovalPermissionPolicy.hasApprovalPermission(
                Collections.singleton("order:operate:refund:approve"), "order:operate:refund"));
        assertFalse(ApprovalPermissionPolicy.hasApprovalPermission(
                new HashSet<>(Arrays.asList("access:approve", "refund:approve", "order:operate", "admin:manage")),
                "order:operate:refund"));
    }
}
