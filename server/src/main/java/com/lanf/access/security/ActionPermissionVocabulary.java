package com.lanf.access.security;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Canonical vocabulary for sensitive business actions.
 *
 * <p>The entry permission only allows an operator to start the action and request approval.
 * It never substitutes for the execute permission or the exact approval permission.</p>
 */
public final class ActionPermissionVocabulary {

    public static final String CASHIER_ENTRY_PERMISSION = "cashier:operate";

    private static final Map<String, ActionPermission> BY_EXECUTE_PERMISSION;

    static {
        Map<String, ActionPermission> entries = new LinkedHashMap<>();
        register(entries, "REFUND", "order:operate:refund");
        register(entries, "CHANGE_PRICE", "order:operate:changePrice");
        register(entries, "DISCOUNT", "order:operate:discount");
        register(entries, "REOPEN", "order:operate:reopen");
        BY_EXECUTE_PERMISSION = Collections.unmodifiableMap(entries);
    }

    private ActionPermissionVocabulary() {
    }

    public static ActionPermission findByExecutePermission(String permissionCode) {
        if (permissionCode == null) {
            return null;
        }
        return BY_EXECUTE_PERMISSION.get(permissionCode.trim());
    }

    public static Map<String, ActionPermission> entries() {
        return BY_EXECUTE_PERMISSION;
    }

    private static void register(Map<String, ActionPermission> entries, String action, String executePermission) {
        entries.put(executePermission, new ActionPermission(
                action,
                CASHIER_ENTRY_PERMISSION,
                executePermission,
                executePermission + ":approve"));
    }

    public static final class ActionPermission {
        private final String action;
        private final String entryPermission;
        private final String executePermission;
        private final String approvalPermission;

        private ActionPermission(String action, String entryPermission,
                                 String executePermission, String approvalPermission) {
            this.action = action;
            this.entryPermission = entryPermission;
            this.executePermission = executePermission;
            this.approvalPermission = approvalPermission;
        }

        public String getAction() {
            return action;
        }

        public String getEntryPermission() {
            return entryPermission;
        }

        public String getExecutePermission() {
            return executePermission;
        }

        public String getApprovalPermission() {
            return approvalPermission;
        }
    }
}
