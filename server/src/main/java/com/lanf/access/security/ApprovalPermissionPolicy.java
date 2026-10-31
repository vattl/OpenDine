package com.lanf.access.security;

import com.lanf.util.StringUtil;

import java.util.Set;

/** Canonical action-level permission policy for privileged approvals. */
public final class ApprovalPermissionPolicy {

    private static final String APPROVE_SUFFIX = ":approve";

    private ApprovalPermissionPolicy() {
    }

    public static String requiredPermission(String actionPermission) {
        if (StringUtil.isEmpty(actionPermission)) {
            throw new IllegalArgumentException("actionPermission must not be blank");
        }
        String normalized = actionPermission.trim();
        return normalized.endsWith(APPROVE_SUFFIX) ? normalized : normalized + APPROVE_SUFFIX;
    }

    public static boolean hasApprovalPermission(Set<String> permissions, String actionPermission) {
        return permissions != null && permissions.contains(requiredPermission(actionPermission));
    }
}
