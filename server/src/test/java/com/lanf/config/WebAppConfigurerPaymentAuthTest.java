package com.lanf.config;

import com.lanf.interceptor.SysInterceptor;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WebAppConfigurerPaymentAuthTest {

    @SuppressWarnings("unchecked")
    @Test
    void onlyOfflineCollectionJumpPageIsPublic() {
        List<String> paths = (List<String>) ReflectionTestUtils.getField(
                WebAppConfigurer.class, "EXCLUDE_PATHS");

        assertTrue(paths.contains("/pay/offline-collect/jump"));
        assertFalse(paths.contains("/pay/offline-collect/**"));
        assertFalse(paths.contains("/pay/offline-collect/temp-qrcode"));
        assertFalse(paths.contains("/pay/offline-collect/confirm"));
        assertFalse(paths.contains("/pay/offline-collect/cancel"));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/temp-qrcode")));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/confirm")));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/cancel")));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/temp-qrcode/")));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/confirm/")));
        assertTrue("cashier:operate".equals(ApiPermissionMapping.getRequiredPermission(
                "POST", "/pay/offline-collect/cancel/")));
    }

    @Test
    void readOnlyPosCatalogAllowsDishManagerOrCashier() {
        String categoryPermission = ApiPermissionMapping.getRequiredPermission(
                "GET", "/admin/category/listAll");
        String dishPermission = ApiPermissionMapping.getRequiredPermission(
                "POST", "/admin/dish/list");

        assertTrue("dish:manage|cashier:operate".equals(categoryPermission));
        assertTrue("dish:manage|cashier:operate".equals(dishPermission));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("dish:manage"), dishPermission));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("cashier:operate"), dishPermission));
        assertFalse(SysInterceptor.hasRequiredPermission(
                Collections.singleton("order:view"), dishPermission));
    }

    @Test
    void mobileAppReadAndTableOperationUseLeastPrivilegeAlternatives() {
        String announcement = ApiPermissionMapping.getRequiredPermission(
                "GET", "/admin/announcement/list");
        String tableOperation = ApiPermissionMapping.getRequiredPermission(
                "POST", "/cashier/table/clear");

        assertTrue("announcement:view|announcement:manage".equals(announcement));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("announcement:view"), announcement));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("announcement:manage"), announcement));
        assertTrue("cashier:operate|table:operate".equals(tableOperation));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("table:operate"), tableOperation));
        assertFalse(SysInterceptor.hasRequiredPermission(
                Collections.singleton("table:manage"), tableOperation));
    }

    @SuppressWarnings("unchecked")
    @Test
    void kdsReplicationRequiresAdminJwtCashierPermission() {
        List<String> paths = (List<String>) ReflectionTestUtils.getField(
                WebAppConfigurer.class, "EXCLUDE_PATHS");
        String required = ApiPermissionMapping.getRequiredPermission(
                "POST", "/admin/kds/replication/events");

        assertFalse(paths.contains("/admin/kds/replication/events"));
        assertTrue("cashier:operate".equals(required));
        assertTrue(SysInterceptor.hasRequiredPermission(
                Collections.singleton("cashier:operate"), required));
        assertFalse(SysInterceptor.hasRequiredPermission(
                Collections.singleton("kds:operate"), required));
    }
}
