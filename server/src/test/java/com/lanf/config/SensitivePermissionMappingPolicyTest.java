package com.lanf.config;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 一致性护栏：收银敏感操作接口的【入口】权限码必须保持基础码 cashier:operate，
 * 敏感码（order:operate:changePrice / discount / refund）只能由控制器内二次授权校验。
 *
 * <p>依据：docs/API.md §4「cashier:operate + 现场授权员工敏感码」、
 * docs/changes/POS-sensitive-operation-authorization-20261005.md。
 * 该断言防止内置兜底映射再次退化为"当前登录人需敏感码"（2026-09-07 回归，见
 * docs/db_migration_sensitive_permission_rollback.sql）。</p>
 */
class SensitivePermissionMappingPolicyTest {

    /** 敏感接口与其入口基础码的契约映射（与 docs/API.md §4 对齐）。 */
    private static final Map<String, String> SENSITIVE_ENDPOINTS = new LinkedHashMap<>();

    static {
        SENSITIVE_ENDPOINTS.put("/cashier/order/updatePrice", "cashier:operate");
        SENSITIVE_ENDPOINTS.put("/cashier/order/discount", "cashier:operate");
        SENSITIVE_ENDPOINTS.put("/cashier/order/refund", "cashier:operate");
        SENSITIVE_ENDPOINTS.put("/cashier/order/refundDish", "cashier:operate");
    }

    @Test
    void sensitiveEndpointsEntryCodeMustRemainBaseCashierPermission() {
        for (Map.Entry<String, String> e : SENSITIVE_ENDPOINTS.entrySet()) {
            String required = ApiPermissionMapping.getRequiredPermission("POST", e.getKey());
            assertEquals(e.getValue(), required,
                    "敏感接口入口权限码必须为基础码（当前登录人），敏感码应仅由二次授权校验: " + e.getKey());
        }
    }

    @Test
    void sensitiveCodesMustNotAppearAsEntryPermissionForSensitiveEndpoints() {
        for (Map.Entry<String, String> e : SENSITIVE_ENDPOINTS.entrySet()) {
            String required = ApiPermissionMapping.getRequiredPermission("POST", e.getKey());
            if (required != null) {
                boolean isSensitiveCode = required.contains("changePrice")
                        || required.contains(":discount")
                        || required.contains(":refund");
                assertEquals(false, isSensitiveCode,
                        "敏感码不得作为接口入口权限码: " + e.getKey() + " -> " + required);
            }
        }
    }
}
