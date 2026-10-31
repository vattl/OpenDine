package com.lanf.config;

import java.util.ArrayList;
import java.util.List;

/**
 * 接口-权限映射（与 {@code docs/init_api_permission.sql}、拦截器一致）。
 * 按 path_pattern 匹配，不区分 HTTP 方法；未列出的后台路径由拦截器失败关闭。
 */
public final class ApiPermissionMapping {

    private static final String METHOD_GET = "GET";
    private static final String METHOD_POST = "POST";
    private static final String METHOD_DELETE = "DELETE";
    private static final String METHOD_PUT = "PUT";

    private static final List<Entry> RAW = new ArrayList<>();
    private static final List<Entry> MAPPINGS = new ArrayList<>();

    static {
        // 管理员
        add(METHOD_POST, "/admin/modifyPassword", "admin:password");
        add(METHOD_GET, "/admin/administrator/list", "admin:manage");
        add(METHOD_POST, "/admin/administrator/create", "admin:manage");
        add(METHOD_PUT, "/admin/administrator/", "admin:manage");
        add(METHOD_DELETE, "/admin/administrator/", "admin:manage");

        // 员工与权限 (access)
        add(METHOD_GET, "/admin/access/employees", "access:view|admin:manage");
        add(METHOD_POST, "/admin/access/employees", "access:manage|admin:manage");
        add(METHOD_PUT, "/admin/access/employees/", "access:manage|admin:manage");
        add(METHOD_DELETE, "/admin/access/employees/", "access:manage|admin:manage");
        add(METHOD_GET, "/admin/access/roles", "access:view|admin:manage");
        add(METHOD_POST, "/admin/access/roles", "access:manage|admin:manage");
        add(METHOD_PUT, "/admin/access/roles/", "access:manage|admin:manage");
        add(METHOD_DELETE, "/admin/access/roles/", "access:manage|admin:manage");
        add(METHOD_POST, "/admin/access/evaluate", "access:view|access:manage");
        add(METHOD_POST, "/admin/access/conflicts/check", "access:view|access:manage");
        add(METHOD_GET, "/admin/access/policies", "access:view|access:manage");
        add(METHOD_POST, "/admin/access/policies", "access:manage");
        add(METHOD_PUT, "/admin/access/policies/", "access:manage");
        add(METHOD_DELETE, "/admin/access/policies/", "access:manage");
        add(METHOD_POST, "/admin/access/policies/assign", "access:manage");
        add(METHOD_GET, "/admin/access/approvals", "access:view|access:manage");
        add(METHOD_GET, "/admin/access/approvals/", "access:view|access:manage");
        add(METHOD_POST, "/cashier/access/authorize", "cashier:operate");
        add(METHOD_GET, "/cashier/access/recent-authors", "cashier:operate");
        add(METHOD_POST, "/cashier/access/qr/create", "cashier:operate");
        add(METHOD_GET, "/cashier/access/qr/status", "cashier:operate");
        add(METHOD_GET, "/admin/access/qr/details", "access:view|admin:manage");
        add(METHOD_POST, "/admin/access/qr/confirm", "access:view|access:manage");

        // RBAC
        add(METHOD_GET, "/admin/rbac/roles", "admin:manage");
        add(METHOD_POST, "/admin/rbac/roles", "admin:manage");
        add(METHOD_DELETE, "/admin/rbac/roles/", "admin:manage");
        add(METHOD_PUT, "/admin/rbac/roles/", "admin:manage");
        add(METHOD_GET, "/admin/rbac/permissions", "admin:manage");
        add(METHOD_POST, "/admin/rbac/permissions", "admin:manage");
        add(METHOD_DELETE, "/admin/rbac/permissions/", "admin:manage");
        add(METHOD_GET, "/admin/rbac/api-permissions", "admin:manage");
        add(METHOD_POST, "/admin/rbac/api-permissions", "admin:manage");
        add(METHOD_DELETE, "/admin/rbac/api-permissions/", "admin:manage");

        // 系统配置
                                        add(METHOD_GET, "/admin/config/invite-poster", "admin:manage");
        add(METHOD_PUT, "/admin/config/invite-poster", "admin:manage");
        add(METHOD_GET, "/admin/config/wechat-prepay-ninefold", "order:config");
        add(METHOD_PUT, "/admin/config/wechat-prepay-ninefold", "order:config");
        add(METHOD_GET, "/admin/config/invite-first-order-balance-reward", "order:config");
        add(METHOD_PUT, "/admin/config/invite-first-order-balance-reward", "order:config");
        add(METHOD_GET, "/admin/config/zsq-auto-api", "order:config");
        add(METHOD_PUT, "/admin/config/zsq-auto-api", "order:config");

        // 分类 / 菜品 / 单位 / 套餐
        add(METHOD_POST, "/admin/category/list", "dish:manage");
        // Cashiers need the read-only menu catalog to open a table and order,
        // while all category write operations remain limited to dish managers.
        add(METHOD_GET, "/admin/category/listAll", "dish:manage|cashier:operate");
        add(METHOD_POST, "/admin/category/add", "dish:manage");
        add(METHOD_POST, "/admin/category/update", "dish:manage");
        add(METHOD_POST, "/admin/category/sort", "dish:manage");
        add(METHOD_GET, "/admin/category/delete", "dish:manage");
        // This is the cashier POS catalog query, not a dish-management write.
        add(METHOD_POST, "/admin/dish/list", "dish:manage|cashier:operate");
        add(METHOD_POST, "/admin/dish/hqTemplateList", "dish:manage");
        add(METHOD_POST, "/admin/dish/importFromHq", "dish:manage");
        add(METHOD_POST, "/admin/dish/save", "dish:manage");
        add(METHOD_GET, "/admin/dish/delete", "dish:manage");
        add(METHOD_POST, "/admin/dish/updateOnSale", "dish:manage");
        add(METHOD_POST, "/admin/dish/updateSaleStatus", "dish:manage");
        add(METHOD_POST, "/admin/dish/sort", "dish:manage");
        add(METHOD_POST, "/admin/dish/uploadImage", "dish:manage");
        add(METHOD_GET, "/admin/unit/listAll", "dish:manage");
        add(METHOD_POST, "/admin/unit/add", "dish:manage");
        add(METHOD_GET, "/admin/combo/getByDishId", "dish:manage|dish:manage:dish|dish:manage:combo");
        add(METHOD_POST, "/admin/combo/save", "dish:manage|dish:manage:dish|dish:manage:combo");

        // 订单
        add(METHOD_POST, "/admin/order/list", "order:view");
        add(METHOD_GET, "/admin/orderDetail/list", "order:view");
        add(METHOD_GET, "/admin/order/log/", "log:view");
        add(METHOD_POST, "/admin/order/receiving", "order:operate");
        add(METHOD_POST, "/admin/order/rece", "order:operate");
        add(METHOD_POST, "/admin/order/checkout", "order:operate");
        add(METHOD_POST, "/admin/order/force-checkout", "admin:manage");
        add(METHOD_POST, "/admin/order/reassignOpenidByPhone", "order:operate");
        add(METHOD_POST, "/admin/order/refund", "order:operate");
        add(METHOD_POST, "/admin/order/manualDiscount", "order:operate");
        add(METHOD_POST, "/admin/order/reprint-kitchen", "order:operate");
        add(METHOD_POST, "/admin/order/invoice/qrcode", "order:operate|order:invoice:create");
        add(METHOD_GET, "/admin/order/invoice/status/", "order:view|order:invoice:view");
        add(METHOD_GET, "/admin/order/invoice/list", "order:view|order:invoice:view");
        add(METHOD_POST, "/admin/order/invoice/issue", "order:operate|order:invoice:operate");
        add(METHOD_POST, "/admin/order/invoice/reject", "order:operate|order:invoice:operate");
        add(METHOD_GET, "/admin/order/audit-timeline/", "order:view");
        add(METHOD_POST, "/admin/order/updateDiners", "cashier:operate|order:operate");
        add(METHOD_POST, "/admin/order/commands", "cashier:operate|order:operate");
        add(METHOD_GET, "/admin/merchant/orders", "order:view");
        add(METHOD_GET, "/admin/merchant/orders/summary", "order:view");
        add(METHOD_POST, "/admin/orderDetail/delete_menu", "order:operate");
        add(METHOD_POST, "/admin/orderDetail/updateQuantity", "order:operate");
        add(METHOD_GET, "/admin/order/auto-accept", "order:config");
        add(METHOD_POST, "/admin/order/auto-accept", "order:config");
        add(METHOD_GET, "/admin/order/banners", "banner:manage");
        add(METHOD_POST, "/admin/order/addbanners", "banner:manage");
        add(METHOD_PUT, "/admin/order/update_banners/", "banner:manage");
        add(METHOD_POST, "/admin/order/uploadBannerFile", "banner:manage");
        add(METHOD_DELETE, "/admin/order/delete_banners/", "banner:manage");

        // Historical management routes kept for client compatibility. They are
        // explicitly intercepted even though their prefixes also host C APIs.
        add(METHOD_POST, "/order/ChangeBusiness", "order:config");
        add(METHOD_POST, "/order/ChangeIsReview", "order:config");
        add(METHOD_POST, "/order/notice", "order:operate");
        add(METHOD_GET, "/order/printContent", "order:view");
        add(METHOD_POST, "/order/autoAcceptAndPrint", "order:operate");
        add(METHOD_DELETE, "/order/delete/*", "order:operate");
        add(METHOD_POST, "/activity/updatePopup", "banner:manage");
        add(METHOD_POST, "/activity/addPopup", "banner:manage");
        add(METHOD_GET, "/activity/getAllPopup", "banner:manage");
        add(METHOD_POST, "/activity/deletePopup", "banner:manage");
        add(METHOD_GET, "/admin/order/salesvolume", "statistics:view");
        add(METHOD_GET, "/admin/order/statisticsCategorySales", "statistics:view");
        add(METHOD_POST, "/admin/order/statisticsCategorySales", "statistics:view");
        add(METHOD_GET, "/admin/order/statisticsDishSales", "statistics:view");
        add(METHOD_POST, "/admin/order/statisticsDishSales", "statistics:view");
        add(METHOD_POST, "/admin/order/getUserInfo", "user:view");
        add(METHOD_POST, "/admin/order/getAllUser", "user:view");
        add(METHOD_POST, "/admin/order/getOneUserInfo", "user:view");
        add(METHOD_POST, "/admin/order/addPoints", "user:points");
        add(METHOD_GET, "/admin/order/todayCount", "order:view");
        add(METHOD_GET, "/admin/order/todayUnsettledAmount", "order:view");
        add(METHOD_POST, "/admin/coupon/", "coupon:manage");
        add(METHOD_POST, "/admin/coupon/user-coupon/batch-grant-excel", "coupon:manage");

        // 外卖
        add(METHOD_GET, "/admin/takeout/config", "order:view");
        add(METHOD_POST, "/admin/takeout/config/save", "order:operate");
        add(METHOD_POST, "/admin/takeout/delivery/list", "order:view");
        add(METHOD_GET, "/admin/takeout/delivery/detail", "order:view");
        add(METHOD_GET, "/admin/takeout/delivery/tracking", "order:view");
        add(METHOD_POST, "/admin/takeout/delivery/status", "order:operate");
        add(METHOD_POST, "/admin/takeout/delivery/zsq/dispatch", "order:operate");
        add(METHOD_POST, "/admin/takeout/delivery/zsq/redispatch", "order:operate");
        add(METHOD_POST, "/admin/takeout/delivery/zsq/sync", "order:operate");

        // 公告
        add(METHOD_GET, "/admin/announcement/list", "announcement:view|announcement:manage");
        add(METHOD_GET, "/admin/announcement/get", "announcement:view|announcement:manage");
        add(METHOD_POST, "/admin/announcement/add", "announcement:manage");
        add(METHOD_POST, "/admin/announcement/update", "announcement:manage");
        add(METHOD_GET, "/admin/announcement/delete", "announcement:manage");

        // 桌台
        add(METHOD_POST, "/admin/table/list", "table:manage");
        add(METHOD_POST, "/admin/table/add", "table:manage");
        add(METHOD_POST, "/admin/table/update", "table:manage");
        add(METHOD_GET, "/admin/table/delete", "table:manage");
        add(METHOD_GET, "/admin/table/out", "table:manage");
        add(METHOD_GET, "/admin/table/status", "table:manage");
        add(METHOD_GET, "/admin/table/qrcode", "table:manage|cashier:operate|table:operate");
        add(METHOD_POST, "/admin/table/open", "cashier:operate|table:operate");

        // 会员 / 用户统计
        add(METHOD_POST, "/admin/member/list", "user:view");
        add(METHOD_GET, "/admin/member/list", "user:view");
        add(METHOD_POST, "/admin/member/recharge", "user:points");
        add(METHOD_GET, "/admin/member/recharge/list", "user:view");
        add(METHOD_POST, "/admin/member/balance/deduct", "user:points");
        add(METHOD_GET, "/admin/member/consumption", "user:view");
        add(METHOD_GET, "/admin/member/profile", "user:view");
        add(METHOD_GET, "/admin/member/stats", "user:view");
        add(METHOD_GET, "/admin/member/persona-tags", "user:view");
        add(METHOD_GET, "/admin/config/member-balance-cross-shop", "shop:manage|admin:manage");
        add(METHOD_GET, "/admin/report/member/cross-shop-clearing", "report:view|finance:view");
        add(METHOD_GET, "/admin/user/sevenDays", "user:view");
        add(METHOD_GET, "/admin/user/lastMonth", "user:view");
        add(METHOD_GET, "/admin/user/thisMonth", "user:view");
        add(METHOD_GET, "/admin/user/scope", "user:view");
        add(METHOD_POST, "/admin/user/scope", "user:view");

        // 门店
        add(METHOD_GET, "/admin/shop/list", "shop:manage");
        add(METHOD_POST, "/admin/shop/save", "shop:manage");
        add(METHOD_POST, "/admin/shop/offline-collect/upload", "shop:manage");

        // 跨平台客户端版本策略（仅超级管理员）
        add(METHOD_GET, "/admin/app/versions", "admin:super");
        add(METHOD_POST, "/admin/app/version/save", "admin:super");
        add(METHOD_POST, "/admin/app/version/upload", "admin:super");
        add(METHOD_POST, "/admin/app/version/toggle-enabled", "admin:super");
        add(METHOD_DELETE, "/admin/app/version/*", "admin:super");

        // 报表 / 分析 / 日结 / 物料 / 备货
        add(METHOD_GET, "/admin/analytics/business", "statistics:view");
        add(METHOD_GET, "/admin/analytics/business/trend", "statistics:view");
        add(METHOD_GET, "/admin/analytics/dishes", "statistics:view");
        add(METHOD_GET, "/admin/analytics/customers", "statistics:view");
        add(METHOD_GET, "/admin/analytics/members", "statistics:view");
        add(METHOD_GET, "/admin/analytics/marketing", "statistics:view");
        add(METHOD_GET, "/admin/report/daily", "report:view");
        add(METHOD_GET, "/admin/report/weekly", "report:view");
        add(METHOD_GET, "/admin/report/monthly", "report:view");
        add(METHOD_GET, "/admin/report/dishRanking", "report:view");
        add(METHOD_GET, "/admin/report/cashierPerformance", "report:view");
        add(METHOD_GET, "/admin/report/shopProfit", "report:view");
        add(METHOD_GET, "/admin/report/compare", "report:view");
        add(METHOD_GET, "/admin/report/repurchase/", "report:view");
        add(METHOD_GET, "/admin/report/dashboard", "report:view");
        add(METHOD_GET, "/admin/report/recharge/list", "report:view");
        add(METHOD_GET, "/admin/receivables/accounts", "receivable:view|receivable:manage");
        add(METHOD_GET, "/admin/receivables/accounts/*", "receivable:view|receivable:manage");
        add(METHOD_POST, "/admin/receivables/accounts/*/status", "receivable:manage");
        add(METHOD_POST, "/admin/receivables/accounts/*/close", "receivable:manage");
        add(METHOD_GET, "/admin/receivables/accounts/*/statement", "receivable:view");
        add(METHOD_GET, "/admin/receivables/claims", "receivable:view");
        add(METHOD_POST, "/admin/receivables/claims/*/collections", "receivable:collect");
        add(METHOD_POST, "/admin/receivables/claims/*/reverse", "receivable:writeoff");
        add(METHOD_POST, "/admin/receivables/claims/*/write-off", "receivable:writeoff");
        add(METHOD_GET, "/admin/receivables/aging", "receivable:view");
        add(METHOD_GET, "/admin/report/inventory", "material:manage");
        add(METHOD_GET, "/admin/report/stockPrepForecast", "statistics:view");
        add(METHOD_GET, "/admin/report/stockPrepForecast/latest", "statistics:view");
        add(METHOD_GET, "/admin/report/stockPrepForecast/trainingRows", "statistics:view");
        add(METHOD_GET, "/admin/report/stockPrepForecast/run/", "statistics:view");
        add(METHOD_POST, "/admin/report/stockPrepForecast/run/", "statistics:view");
        add(METHOD_POST, "/admin/daily/settle", "daily:settle");
        add(METHOD_GET, "/admin/daily/context", "daily:settle|report:view");
        add(METHOD_GET, "/admin/daily/summary", "daily:settle");
        add(METHOD_GET, "/admin/daily/income", "daily:settle");
        add(METHOD_GET, "/admin/daily/byChannel", "daily:settle");
        add(METHOD_GET, "/admin/daily/grossProfit", "report:view");
        add(METHOD_GET, "/admin/daily/pre-check", "daily:settle");
        add(METHOD_POST, "/admin/daily/void-stale-takeout-orders", "daily:settle|order:operate");
        add(METHOD_GET, "/admin/daily/z-report", "daily:settle");
        add(METHOD_GET, "/admin/daily/z-reports", "daily:settle");
        add(METHOD_POST, "/admin/daily/adjustments", "daily:settle");
        add(METHOD_GET, "/admin/daily/adjustments", "daily:settle");
        add(METHOD_POST, "/admin/daily/reopen", "daily:settle");
        add(METHOD_POST, "/admin/reconciliation/import", "daily:settle");
        add(METHOD_GET, "/admin/reconciliation/overview", "daily:settle|report:view");
        add(METHOD_GET, "/admin/reconciliation/batches", "daily:settle|report:view");
        add(METHOD_GET, "/admin/reconciliation/cases", "daily:settle|report:view");
        add(METHOD_POST, "/admin/reconciliation/cases/", "daily:settle");
        add(METHOD_POST, "/admin/migration/ledger/backfill", "daily:settle");
        add(METHOD_GET, "/admin/migration/ledger/shadow-verify", "daily:settle|report:view");
        add(METHOD_GET, "/admin/migration/ledger/status", "daily:settle|report:view");
        add(METHOD_POST, "/admin/migration/ledger/cutover", "daily:settle");
        add(METHOD_GET, "/admin/material/list", "material:manage");
        add(METHOD_POST, "/admin/material/save", "material:manage");
        add(METHOD_POST, "/admin/material/inbound", "material:manage");
        add(METHOD_POST, "/admin/material/outbound", "material:manage");
        add(METHOD_GET, "/admin/material/alert", "material:manage");
        add(METHOD_GET, "/admin/stock-prep/bom/list", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/bom/save", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/bom/delete", "material:manage");
        add(METHOD_GET, "/admin/stock-prep/config", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/config/save", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/plan/generate", "material:manage");
        add(METHOD_GET, "/admin/stock-prep/plan/list", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/plan/update", "material:manage");
        add(METHOD_POST, "/admin/stock-prep/plan/batchStatus", "material:manage");
        add(METHOD_GET, "/admin/log/operation", "log:view");

        // 第三方
        add(METHOD_POST, "/admin/third/order/sync", "order:operate");
        add(METHOD_POST, "/admin/third/order/statusPush", "order:operate");
        add(METHOD_GET, "/admin/third/reconciliation", "order:view");

        // KDS
        add(METHOD_GET, "/admin/kds/station/list", "kds:config");
        add(METHOD_POST, "/admin/kds/station/save", "kds:config");
        add(METHOD_GET, "/admin/kds/station/delete", "kds:config");
        add(METHOD_POST, "/admin/kds/station/init-five", "kds:config");
        add(METHOD_POST, "/admin/kds/station/category/bind", "kds:config");
        add(METHOD_GET, "/admin/kds/station/category/list", "kds:config");
        add(METHOD_POST, "/admin/kds/dish-screen/bind", "kds:config");
        add(METHOD_GET, "/admin/kds/dish-screen/list", "kds:config");
        add(METHOD_GET, "/admin/kds/config/get", "kds:config");
        add(METHOD_POST, "/admin/kds/config/save", "kds:config");
        add(METHOD_GET, "/admin/kds/device/list", "kds:config");
        add(METHOD_POST, "/admin/kds/device/bind", "kds:config");
        add(METHOD_POST, "/admin/kds/device/proxy-login", "cashier:operate|kds:config");
        add(METHOD_POST, "/admin/kds/device/pairing-ticket", "cashier:operate|kds:config");
        add(METHOD_POST, "/admin/kds/device/proxy-command", "cashier:operate|kds:config");
        add(METHOD_POST, "/admin/kds/device/unbind", "kds:config");
        add(METHOD_POST, "/admin/kds/device/delete", "kds:config");
        add(METHOD_GET, "/admin/kds/device/delete", "kds:config");
        add(METHOD_DELETE, "/admin/kds/device/delete", "kds:config");
        add(METHOD_POST, "/admin/kds/ticket/repush", "kds:config");
        add(METHOD_POST, "/admin/kds/ticket/print-serve", "cashier:operate|kds:config");
        add(METHOD_POST, "/admin/kds/replication/events", "cashier:operate");
        add(METHOD_POST, "/admin/kds/replication/events/batch", "cashier:operate");
        add(METHOD_GET, "/admin/kds/replication/dead-letters", "kds:config");
        add(METHOD_POST, "/admin/kds/replication/dead-letters/", "kds:config");
        add(METHOD_GET, "/admin/kds/authority/config-snapshot", "cashier:operate");
        add(METHOD_POST, "/admin/kds/authority/device", "kds:config");

        // 线上支付配置
        add(METHOD_GET, "/admin/payment/capabilities", "payment:config:read");
        add(METHOD_PUT, "/admin/payment/capabilities", "payment:config:write");
        add(METHOD_GET, "/admin/payment/ninefold", "payment:config:read");
        add(METHOD_PUT, "/admin/payment/ninefold", "payment:config:write");
        add(METHOD_GET, "/admin/payment/merchants", "payment:config:read");
        add(METHOD_GET, "/admin/payment/merchants/", "payment:config:read");
        add(METHOD_GET, "/admin/payment/merchants/edit-form", "payment:config:read");
        add(METHOD_POST, "/admin/payment/merchants", "payment:config:write");
        add(METHOD_PUT, "/admin/payment/merchants/save", "payment:config:write");
        add(METHOD_PUT, "/admin/payment/merchants/", "payment:config:write");
        add(METHOD_DELETE, "/admin/payment/merchants/", "payment:config:write");
        add(METHOD_GET, "/admin/payment/merchant-policy", "payment:config:read");
        add(METHOD_PUT, "/admin/payment/merchant-policy", "payment:config:write");
        add(METHOD_POST, "/admin/payment/private-key/upload", "payment:config:write");
        add(METHOD_POST, "/admin/payment/platform-public-key/upload", "payment:config:write");
        add(METHOD_POST, "/admin/payment/certificate/upload", "payment:config:write");
        add(METHOD_POST, "/admin/payment/merchants/", "payment:config:write");
        add(METHOD_GET, "/admin/payment/notify-urls", "payment:config:read");
        add(METHOD_GET, "/admin/payment/wechat/pay-auth-audit", "payment:config:read");
        add(METHOD_GET, "/admin/payment/routing-rules", "payment:config:read");
        add(METHOD_POST, "/admin/payment/routing-rules", "payment:config:write");
        add(METHOD_GET, "/admin/payment/routing-rules/", "payment:config:read");
        add(METHOD_PUT, "/admin/payment/routing-rules/", "payment:config:write");
        add(METHOD_DELETE, "/admin/payment/routing-rules/", "payment:config:write");
        add(METHOD_PUT, "/admin/payment/routing-rules/sort", "payment:config:write");
        add(METHOD_POST, "/admin/payment/routing-rules/simulate", "payment:config:read");

        // 收银端
        add(METHOD_POST, "/cashier/order/quickOrder", "cashier:operate");
        add(METHOD_POST, "/cashier/order/addDishes", "cashier:operate");
        add(METHOD_POST, "/cashier/order/refundDish", "cashier:operate");
        add(METHOD_POST, "/cashier/order/refund", "cashier:operate");
        add(METHOD_POST, "/cashier/order/updatePrice", "cashier:operate");
        add(METHOD_POST, "/cashier/order/discount", "cashier:operate");
        add(METHOD_POST, "/cashier/order/checkout", "cashier:operate");
        add(METHOD_POST, "/cashier/order/force-checkout", "admin:manage");
        add(METHOD_POST, "/cashier/order/hang", "cashier:operate");
        add(METHOD_POST, "/cashier/order/unhang", "cashier:operate");
        add(METHOD_GET, "/cashier/order/hang-list", "cashier:operate");
        add(METHOD_POST, "/cashier/order/unCheckout", "cashier:operate");
        add(METHOD_POST, "/cashier/payment/wechat/native/orders", "cashier:operate");
        add(METHOD_GET, "/cashier/payment/wechat/native/orders/", "cashier:operate");
        add(METHOD_POST, "/cashier/payment/wechat/native/orders/", "cashier:operate");
        add(METHOD_POST, "/cashier/payment/wechat/micropay/orders", "cashier:operate");
        add(METHOD_GET, "/cashier/payment/wechat/micropay/orders/", "cashier:operate");
        add(METHOD_POST, "/cashier/payment/wechat/micropay/orders/", "cashier:operate");
        add(METHOD_GET, "/cashier/receivables/eligible-accounts", "receivable:view");
        add(METHOD_POST, "/cashier/receivables/charges", "receivable:charge");
        add(METHOD_GET, "/cashier/receivables/claims", "receivable:view");
        add(METHOD_GET, "/cashier/receivables/claims/*", "receivable:view");
        add(METHOD_POST, "/cashier/receivables/claims/*/collections", "receivable:collect");
        add(METHOD_GET, "/cashier/order/today", "cashier:operate");
        add(METHOD_GET, "/cashier/order/search", "cashier:operate");
        add(METHOD_GET, "/cashier/order/printContent", "cashier:operate");
        add(METHOD_GET, "/cashier/orders/", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/", "cashier:operate");
        add(METHOD_POST, "/cashier/kds/authority/lease", "cashier:operate");
        add(METHOD_POST, "/cashier/kds/delivery/lease", "cashier:operate");
        add(METHOD_POST, "/admin/cashier/kds/authority/lease", "cashier:operate");
        add(METHOD_POST, "/admin/cashier/kds/delivery/lease", "cashier:operate");
        add(METHOD_POST, "/api/admin/cashier/kds/delivery/lease", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/delivery/bootstrap", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/delivery/bootstrap", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/delivery/bootstrap", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/delivery/business-day/orders", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/delivery/business-day/orders/detail", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/delivery/business-day/orders/detail", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/delivery/business-day/orders/detail", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/delivery/business-day/orders", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/delivery/business-day/orders", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/delivery/events", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/delivery/events", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/delivery/events", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/orders/", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/orders/", "cashier:operate");
        add(METHOD_POST, "/cashier/kds/delivery/ack", "cashier:operate");
        add(METHOD_POST, "/admin/cashier/kds/delivery/ack", "cashier:operate");
        add(METHOD_POST, "/api/admin/cashier/kds/delivery/ack", "cashier:operate");
        add(METHOD_GET, "/cashier/kds/delivery/status", "cashier:operate");
        add(METHOD_GET, "/admin/cashier/kds/delivery/status", "cashier:operate");
        add(METHOD_GET, "/api/admin/cashier/kds/delivery/status", "cashier:operate");
        add(METHOD_POST, "/cashier/table/open", "cashier:operate|table:operate");
        add(METHOD_POST, "/cashier/table/merge", "cashier:operate|table:operate");
        add(METHOD_POST, "/cashier/table/transfer", "cashier:operate|table:operate");
        add(METHOD_POST, "/cashier/table/clear", "cashier:operate|table:operate");
        add(METHOD_POST, "/cashier/table/checkout", "cashier:operate|table:operate");
        add(METHOD_GET, "/cashier/table/statusMap", "cashier:operate");
        add(METHOD_GET, "/api/pos/table-areas", "cashier:operate|table:view");
        add(METHOD_GET, "/cashier/table/areas", "cashier:operate|table:view");
        add(METHOD_PUT, "/api/pos/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_POST, "/api/pos/tables/batch-clear", "cashier:operate|table:operate");
        add(METHOD_POST, "/cashier/table/batch-clear", "cashier:operate|table:operate");
        add(METHOD_GET, "/api/pos/tables/pulse", "cashier:operate|table:view");
        add(METHOD_GET, "/cashier/table/pulse", "cashier:operate|table:view");
        add(METHOD_POST, "/cashier/print/kitchen", "cashier:operate");
        add(METHOD_POST, "/cashier/print/dispatch", "cashier:operate");
        add(METHOD_POST, "/cashier/shift/start", "cashier:operate");
        add(METHOD_POST, "/cashier/shift/handover", "cashier:operate");
        add(METHOD_GET, "/cashier/shift/current", "cashier:operate");
        add(METHOD_GET, "/cashier/shift/workbench", "cashier:operate");
        add(METHOD_GET, "/cashier/shift/reports", "cashier:operate");
        add(METHOD_GET, "/cashier/shift/*/cash-events", "cashier:operate");
        add(METHOD_GET, "/cashier/shift/report/*", "cashier:operate");
        add(METHOD_POST, "/cashier/shift/cash-movement", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/temp-qrcode", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/confirm", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/cancel", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/temp-qrcode/", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/confirm/", "cashier:operate");
        add(METHOD_POST, "/pay/offline-collect/cancel/", "cashier:operate");

        // 打印设置
        add(METHOD_GET, "/admin/printing/devices", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/devices", "printing:manage");
        add(METHOD_GET, "/admin/printing/devices/", "printing:view|printing:manage");
        add(METHOD_PUT, "/admin/printing/devices/", "printing:manage");
        add(METHOD_DELETE, "/admin/printing/devices/", "printing:manage");
        add(METHOD_POST, "/admin/printing/devices/*/test", "printing:manage");
        add(METHOD_GET, "/admin/printing/devices/*/status", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/devices/*/clear-queue", "printing:manage");
        add(METHOD_GET, "/admin/printing/preview", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/preview", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/preview/exact", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/dispatch", "printing:manage");
        add(METHOD_GET, "/admin/printing/rules", "printing:view|printing:manage");
        add(METHOD_PUT, "/admin/printing/rules", "printing:manage");
        add(METHOD_GET, "/admin/printing/jobs", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/jobs/*/reprint", "printing:manage");
        add(METHOD_GET, "/admin/printing/templates", "printing:view|printing:manage");
        add(METHOD_GET, "/admin/printing/templates/", "printing:view|printing:manage");
        add(METHOD_POST, "/admin/printing/templates", "printing:manage");
        add(METHOD_PUT, "/admin/printing/templates/", "printing:manage");
        add(METHOD_DELETE, "/admin/printing/templates/", "printing:manage");
        add(METHOD_POST, "/admin/printing/templates/*/set-default", "printing:manage");


        // 营销 / 首单立减活动
        add(METHOD_GET, "/admin/marketing/first-order/campaigns", "marketing:firstorder:view|marketing:firstorder:manage");
        add(METHOD_POST, "/admin/marketing/first-order/campaigns", "marketing:firstorder:view|marketing:firstorder:manage");
        add(METHOD_PUT, "/admin/marketing/first-order/campaigns/", "marketing:firstorder:manage");
        add(METHOD_POST, "/admin/marketing/first-order/eligibility/evaluate", "marketing:firstorder:view");
        add(METHOD_GET, "/admin/marketing/first-order/redemptions", "marketing:firstorder:view");

        // 高级库存 (BOM / 批次 / 采购 / 供应商 / 调拨 / 仓库)
        add(METHOD_GET, "/admin/inventory/batches", "inventory:view");
        add(METHOD_GET, "/admin/inventory/boms", "inventory:view|inventory:manage");
        add(METHOD_POST, "/admin/inventory/boms", "inventory:view|inventory:manage");
        add(METHOD_PUT, "/admin/inventory/boms/", "inventory:manage");
        add(METHOD_GET, "/admin/inventory/purchases", "inventory:view|inventory:manage");
        add(METHOD_POST, "/admin/inventory/purchases", "inventory:view|inventory:manage");
        add(METHOD_PUT, "/admin/inventory/purchases/", "inventory:manage");
        add(METHOD_GET, "/admin/inventory/suppliers", "inventory:view|inventory:manage");
        add(METHOD_POST, "/admin/inventory/suppliers", "inventory:view|inventory:manage");
        add(METHOD_PUT, "/admin/inventory/suppliers/", "inventory:manage");
        add(METHOD_DELETE, "/admin/inventory/suppliers", "inventory:manage");
        add(METHOD_GET, "/admin/inventory/transfers", "inventory:view|inventory:manage");
        add(METHOD_POST, "/admin/inventory/transfers", "inventory:view|inventory:manage");
        add(METHOD_PUT, "/admin/inventory/transfers/", "inventory:manage");
        add(METHOD_GET, "/admin/inventory/warehouses", "inventory:view|inventory:manage");
        add(METHOD_POST, "/admin/inventory/warehouses", "inventory:view|inventory:manage");
        add(METHOD_PUT, "/admin/inventory/warehouses/", "inventory:manage");

        // 日志归档与导出
        add(METHOD_GET, "/admin/logs", "log:view");
        add(METHOD_POST, "/admin/logs/archive-search", "log:archive");
        add(METHOD_GET, "/admin/logs/archive-search/", "log:archive");
        add(METHOD_POST, "/admin/logs/exports", "log:export");

        // 通知规则与投递日志
        add(METHOD_GET, "/admin/notifications/rules", "notifications:view|notifications:manage");
        add(METHOD_POST, "/admin/notifications/rules", "notifications:view|notifications:manage");
        add(METHOD_PUT, "/admin/notifications/rules/", "notifications:manage");
        add(METHOD_DELETE, "/admin/notifications/rules/", "notifications:manage");
        add(METHOD_GET, "/admin/notifications/deliveries", "notifications:view");
        add(METHOD_GET, "/admin/shop/notification-config", "shop:manage|order:config|settings:view|cashier:operate");
        add(METHOD_PUT, "/admin/shop/notification-config", "shop:manage|order:config|settings:manage");
        add(METHOD_GET, "/cashier/notifications/sync", "cashier:operate|order:view");
        add(METHOD_POST, "/cashier/notifications/ack", "cashier:operate|order:operate");
        add(METHOD_GET, "/api/v1/notifications/sync", "cashier:operate|order:view");
        add(METHOD_POST, "/api/v1/notifications/ack", "cashier:operate|order:operate");

        // 微信订阅消息场景与发送审计
        add(METHOD_GET, "/admin/subscribe/scenes", "settings:view|order:view");
        add(METHOD_PUT, "/admin/subscribe/scenes/", "settings:manage|order:operate");
        add(METHOD_GET, "/admin/subscribe/logs", "settings:view|order:view");
        add("*", "/admin/subscribe/", "settings:manage|order:operate");

        // 报表异步导出与系统设置
        add(METHOD_POST, "/admin/reports/exports", "report:export");
        add(METHOD_GET, "/admin/reports/exports", "report:export");
        add(METHOD_GET, "/admin/reports/exports/", "report:export");
        add(METHOD_GET, "/admin/settings/overview", "settings:view");
        add(METHOD_GET, "/admin/settings/store", "settings:view|settings:manage");
        add(METHOD_PUT, "/admin/settings/store", "settings:view|settings:manage");
        add(METHOD_DELETE, "/admin/settings/store/override", "settings:manage");

        // 支付渠道运营 (停用影响判定与测试交易)
        add(METHOD_POST, "/admin/payment/channels/", "payment:view|payment:manage");

        // 收银端扩展与移动/桌面 POS 别名
        add(METHOD_POST, "/cashier/shop/business", "cashier:operate|shop:manage");
        add(METHOD_GET, "/api/pos/orders/hang-list", "cashier:operate");
        add(METHOD_GET, "/api/pos/hang-list", "cashier:operate");
        add(METHOD_GET, "/api/pos/orders/today", "cashier:operate");
        add(METHOD_GET, "/api/pos/today", "cashier:operate");
        add(METHOD_GET, "/api/pos/orders/search", "cashier:operate");
        add(METHOD_GET, "/api/pos/search", "cashier:operate");
        add(METHOD_GET, "/api/pos/orders/printContent", "cashier:operate");
        add(METHOD_GET, "/api/pos/printContent", "cashier:operate");
        add(METHOD_POST, "/api/pos/tables/open", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/open", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/tables/merge", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/merge", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/tables/transfer", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/transfer", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/tables/clear", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/clear", "cashier:operate|table:operate");
        add(METHOD_GET, "/api/pos/tables/statusMap", "cashier:operate");
        add(METHOD_GET, "/api/pos/statusMap", "cashier:operate");
        add(METHOD_GET, "/cashier/table/table-areas", "cashier:operate|table:view");
        add(METHOD_GET, "/cashier/table/tables/areas", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/tables/areas", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/tables/table-areas", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/tables/tables/areas", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/areas", "cashier:operate|table:view");
        add(METHOD_POST, "/cashier/table/tables/batch-clear", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/tables/tables/batch-clear", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/batch-clear", "cashier:operate|table:operate");
        add(METHOD_GET, "/cashier/table/tables/pulse", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/tables/tables/pulse", "cashier:operate|table:view");
        add(METHOD_GET, "/api/pos/pulse", "cashier:operate|table:view");

        // 飞鹅云打印扩展
        add(METHOD_POST, "/api/feieyun/print", "printing:manage|cashier:operate");
        add(METHOD_POST, "/api/feieyun/print-label", "printing:manage|cashier:operate");
        add(METHOD_GET, "/api/feieyun/order-status", "printing:manage|cashier:operate");
        add(METHOD_GET, "/api/feieyun/printer-status", "printing:manage|cashier:operate");
        add(METHOD_POST, "/api/feieyun/add-printer", "printing:manage");
        add(METHOD_GET, "/user/notifications/sync", "user:notification|cashier:operate");
        add(METHOD_POST, "/user/notifications/ack", "user:notification|cashier:operate");

        // 统一通知监控与运维扩展 (WI-080)
        add(METHOD_GET, "/admin/notifications/channel-stats", "notifications:view|notifications:manage");
        add(METHOD_GET, "/cashier/notifications/channel-stats", "notifications:view|cashier:operate");
        add(METHOD_POST, "/admin/notifications/test-push", "notifications:manage");
        add(METHOD_POST, "/cashier/notifications/test-push", "notifications:manage|cashier:operate");
        add(METHOD_POST, "/admin/notifications/cleanup", "notifications:manage|admin:super");

        // 移动/桌面 POS 收银与订单写操作别名 (WI-080)
        add(METHOD_POST, "/api/pos/orders/quickOrder", "cashier:operate");
        add(METHOD_POST, "/api/pos/quickOrder", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/quickOrder", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/addDishes", "cashier:operate");
        add(METHOD_POST, "/api/pos/addDishes", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/addDishes", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/refundDish", "cashier:operate");
        add(METHOD_POST, "/api/pos/refundDish", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/refundDish", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/refund", "cashier:operate");
        add(METHOD_POST, "/api/pos/refund", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/refund", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/updatePrice", "cashier:operate");
        add(METHOD_POST, "/api/pos/updatePrice", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/updatePrice", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/discount", "cashier:operate");
        add(METHOD_POST, "/api/pos/discount", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/discount", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/checkout", "cashier:operate");
        add(METHOD_POST, "/api/pos/checkout", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/checkout", "cashier:operate");
        add(METHOD_POST, "/api/pos/tables/checkout", "cashier:operate|table:operate");
        add(METHOD_POST, "/api/pos/orders/force-checkout", "admin:manage");
        add(METHOD_POST, "/api/pos/force-checkout", "admin:manage");
        add(METHOD_POST, "/cashier/orders/force-checkout", "admin:manage");
        add(METHOD_POST, "/api/pos/orders/hang", "cashier:operate");
        add(METHOD_POST, "/api/pos/hang", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/hang", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/unhang", "cashier:operate");
        add(METHOD_POST, "/api/pos/unhang", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/unhang", "cashier:operate");
        add(METHOD_POST, "/api/pos/orders/unCheckout", "cashier:operate");
        add(METHOD_POST, "/api/pos/unCheckout", "cashier:operate");
        add(METHOD_POST, "/cashier/orders/unCheckout", "cashier:operate");
        add(METHOD_POST, "/cashier/order/updateDiners", "cashier:operate|order:operate");
        add(METHOD_POST, "/cashier/orders/updateDiners", "cashier:operate|order:operate");
        add(METHOD_POST, "/api/pos/orders/updateDiners", "cashier:operate|order:operate");
        add(METHOD_POST, "/api/pos/updateDiners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/order/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/order/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/orders/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/api/pos/orders/orders/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/api/pos/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/order/order/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/cashier/orders/order/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/api/pos/orders/order/*/diners", "cashier:operate|order:operate");
        add(METHOD_PUT, "/api/pos/order/*/diners", "cashier:operate|order:operate");

        java.util.LinkedHashMap<String, String> byPath = new java.util.LinkedHashMap<>();
        for (Entry e : RAW) {
            byPath.merge(e.pathPattern, e.permissionCode, DbApiPermissionMapping::mergePermissionCode);
        }
        for (java.util.Map.Entry<String, String> e : byPath.entrySet()) {
            MAPPINGS.add(new Entry(e.getKey(), e.getValue()));
        }
        MAPPINGS.sort((a, b) -> Integer.compare(b.pathPattern.length(), a.pathPattern.length()));
        RAW.clear();
    }

    private static void add(String method, String pathPattern, String permissionCode) {
        RAW.add(new Entry(pathPattern, permissionCode));
    }

    public static String getRequiredPermission(String path) {
        if (path == null) {
            path = "";
        }
        String normalizedPath = path.split("\\?")[0].trim();
        for (Entry e : MAPPINGS) {
            if (DbApiPermissionMapping.matchesPath(e.pathPattern, normalizedPath)) {
                return e.permissionCode;
            }
        }
        return null;
    }

    /**
     * Reviewed route inventory used by migrations and CI drift checks.
     * This snapshot is not consulted by the runtime interceptor.
     */
    public static java.util.Map<String, String> inventory() {
        java.util.Map<String, String> snapshot = new java.util.LinkedHashMap<>();
        for (Entry entry : MAPPINGS) {
            snapshot.put(entry.pathPattern, entry.permissionCode);
        }
        return java.util.Collections.unmodifiableMap(snapshot);
    }

    /** @deprecated 仅按路径匹配，请使用 {@link #getRequiredPermission(String)} */
    @Deprecated
    public static String getRequiredPermission(String method, String path) {
        return getRequiredPermission(path);
    }

    private static class Entry {
        final String pathPattern;
        final String permissionCode;

        Entry(String pathPattern, String permissionCode) {
            this.pathPattern = pathPattern;
            this.permissionCode = permissionCode;
        }
    }
}
