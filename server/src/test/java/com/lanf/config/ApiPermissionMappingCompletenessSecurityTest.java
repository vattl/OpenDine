package com.lanf.config;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class ApiPermissionMappingCompletenessSecurityTest {

    @Test
    void protectedControllerRoutesHaveExplicitBuiltInPermissions() {
        Map<String, String> expected = new LinkedHashMap<>();
        expected.put("/admin/coupon/list", "coupon:manage");
        expected.put("/admin/coupon/user-coupon/grant", "coupon:manage");
        expected.put("/admin/coupon/redeem-code/qrcode", "coupon:manage");
        expected.put("/admin/order/todayCount", "order:view");
        expected.put("/admin/order/todayUnsettledAmount", "order:view");
        expected.put("/admin/report/repurchase/weekly", "report:view");
        expected.put("/admin/report/repurchase/monthly", "report:view");
        expected.put("/admin/report/repurchase/newCustomer", "report:view");
        expected.put("/admin/table/open", "cashier:operate|table:operate");
        expected.put("/admin/table/update", "table:manage");
        expected.put("/cashier/order/hang", "cashier:operate");
        expected.put("/cashier/order/unhang", "cashier:operate");
        expected.put("/cashier/order/hang-list", "cashier:operate");
        expected.put("/cashier/orders/123/details", "cashier:operate");
        expected.put("/cashier/kds/bootstrap", "cashier:operate");
        expected.put("/cashier/kds/events", "cashier:operate");
        expected.put("/cashier/kds/delivery/orders/123/projection", "cashier:operate");
        expected.put("/cashier/kds/ack", "cashier:operate");
        expected.put("/cashier/kds/status", "cashier:operate");
        expected.put("/admin/cashier/kds/bootstrap", "cashier:operate");
        expected.put("/api/admin/cashier/kds/bootstrap", "cashier:operate");
        expected.put("/cashier/payment/wechat/native/orders", "cashier:operate");
        expected.put("/cashier/payment/wechat/native/orders/ORDER-1", "cashier:operate");
        expected.put("/cashier/payment/wechat/native/orders/ORDER-1/close", "cashier:operate");
        expected.put("/cashier/payment/wechat/micropay/orders", "cashier:operate");
        expected.put("/cashier/payment/wechat/micropay/orders/ORDER-1", "cashier:operate");
        expected.put("/cashier/payment/wechat/micropay/orders/ORDER-1/reverse", "cashier:operate");
        expected.put("/cashier/receivables/eligible-accounts", "receivable:view");
        expected.put("/cashier/receivables/charges", "receivable:charge");
        expected.put("/cashier/receivables/claims/31", "receivable:view");
        expected.put("/cashier/receivables/claims/31/collections", "receivable:collect");
        expected.put("/admin/receivables/accounts", "receivable:view|receivable:manage");
        expected.put("/admin/receivables/accounts/11/statement", "receivable:view");
        expected.put("/admin/receivables/claims/31/collections", "receivable:collect");
        expected.put("/admin/receivables/claims/31/reverse", "receivable:writeoff");
        expected.put("/admin/receivables/claims/31/write-off", "receivable:writeoff");
        expected.put("/admin/receivables/aging", "receivable:view");
        expected.put("/admin/app/versions", "admin:super");
        expected.put("/admin/app/version/save", "admin:super");
        expected.put("/admin/app/version/upload", "admin:super");
        expected.put("/admin/app/version/toggle-enabled", "admin:super");
        expected.put("/admin/app/version/31", "admin:super");
        // Newly audited and fine-grained routes (WI-072)
        expected.put("/admin/combo/getByDishId", "dish:manage|dish:manage:dish|dish:manage:combo");
        expected.put("/admin/combo/save", "dish:manage|dish:manage:dish|dish:manage:combo");
        expected.put("/admin/order/invoice/qrcode", "order:operate|order:invoice:create");
        expected.put("/admin/order/invoice/status/INV-1", "order:view|order:invoice:view");
        expected.put("/admin/order/invoice/list", "order:view|order:invoice:view");
        expected.put("/admin/order/invoice/issue", "order:operate|order:invoice:operate");
        expected.put("/admin/order/invoice/reject", "order:operate|order:invoice:operate");
        expected.put("/admin/order/updateDiners", "cashier:operate|order:operate");
        expected.put("/admin/order/commands", "cashier:operate|order:operate");
        expected.put("/admin/merchant/orders", "order:view");
        expected.put("/admin/marketing/first-order/campaigns", "marketing:firstorder:view|marketing:firstorder:manage");
        expected.put("/admin/marketing/first-order/redemptions", "marketing:firstorder:view");
        expected.put("/admin/inventory/batches", "inventory:view");
        expected.put("/admin/inventory/boms", "inventory:view|inventory:manage");
        expected.put("/admin/inventory/purchases", "inventory:view|inventory:manage");
        expected.put("/admin/inventory/transfers", "inventory:view|inventory:manage");
        expected.put("/admin/inventory/warehouses", "inventory:view|inventory:manage");
        expected.put("/admin/logs", "log:view");
        expected.put("/admin/logs/archive-search", "log:archive");
        expected.put("/admin/logs/exports", "log:export");
        expected.put("/admin/notifications/rules", "notifications:view|notifications:manage");
        expected.put("/admin/notifications/deliveries", "notifications:view");
        expected.put("/admin/reports/exports", "report:export");
        expected.put("/admin/settings/overview", "settings:view");
        expected.put("/admin/settings/store", "settings:view|settings:manage");
        expected.put("/admin/settings/store/override", "settings:manage");
        expected.put("/admin/payment/channels/wechat/test", "payment:view|payment:manage");
        expected.put("/cashier/shop/business", "cashier:operate|shop:manage");
        expected.put("/api/pos/tables/open", "cashier:operate|table:operate");
        expected.put("/api/pos/orders/today", "cashier:operate");
        expected.put("/api/feieyun/print", "printing:manage|cashier:operate");
        // Newly audited and completed routes (WI-080)
        expected.put("/admin/notifications/channel-stats", "notifications:view|notifications:manage");
        expected.put("/cashier/notifications/channel-stats", "notifications:view|cashier:operate");
        expected.put("/admin/notifications/test-push", "notifications:manage");
        expected.put("/cashier/notifications/test-push", "notifications:manage|cashier:operate");
        expected.put("/admin/notifications/cleanup", "notifications:manage|admin:super");
        expected.put("/api/pos/orders/quickOrder", "cashier:operate");
        expected.put("/api/pos/orders/addDishes", "cashier:operate");
        expected.put("/api/pos/orders/checkout", "cashier:operate");
        expected.put("/api/pos/tables/checkout", "cashier:operate|table:operate");
        expected.put("/cashier/order/updateDiners", "cashier:operate|order:operate");
        expected.put("/api/pos/orders/updateDiners", "cashier:operate|order:operate");

        for (Map.Entry<String, String> entry : expected.entrySet()) {
            assertEquals(entry.getValue(), ApiPermissionMapping.getRequiredPermission(entry.getKey()),
                    "接口缺少权限映射：" + entry.getKey());
        }
    }

    @Test
    void exactBuiltInPathDoesNotAuthorizeSimilarPrefix() {
        assertNull(ApiPermissionMapping.getRequiredPermission("/admin/config/feieyun-legacy"));
        assertNull(ApiPermissionMapping.getRequiredPermission("/admin/app/version"));
        assertEquals("admin:manage",
                ApiPermissionMapping.getRequiredPermission("/admin/administrator/7/roles"));
    }
}
