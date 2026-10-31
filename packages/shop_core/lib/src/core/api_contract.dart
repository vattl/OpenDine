class AdminEndpoint {
  const AdminEndpoint({
    required this.method,
    required this.path,
    required this.permissionCode,
    this.attachShopHeader = true,
    this.pageSizeLimit,
    this.preserveEmptyStrings = false,
    this.preserveEmptyCollections = false,
  });

  final String method;
  final String path;
  final String permissionCode;
  final bool attachShopHeader;
  final int? pageSizeLimit;
  final bool preserveEmptyStrings;
  final bool preserveEmptyCollections;

  /// 替换路径中的 `{name}` 占位符（如 `/orders/{orderId}/projection`）。
  AdminEndpoint withPathParams(Map<String, String> params) {
    var resolved = path;
    for (final entry in params.entries) {
      resolved = resolved.replaceAll('{${entry.key}}', entry.value);
    }
    return AdminEndpoint(
      method: method,
      path: resolved,
      permissionCode: permissionCode,
      attachShopHeader: attachShopHeader,
      pageSizeLimit: pageSizeLimit,
      preserveEmptyStrings: preserveEmptyStrings,
      preserveEmptyCollections: preserveEmptyCollections,
    );
  }
}

class AdminRequest {
  const AdminRequest({
    required this.endpoint,
    required this.body,
    required this.headers,
  });

  final AdminEndpoint endpoint;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}

const shopHeaderExcludedPaths = {
  '/adminLogin',
  '/admin/me/permissions',
  '/admin/me/shops',
  '/admin/shop/list',
};

Map<String, Object?> compactBody(Map<String, Object?> input) {
  return Map.fromEntries(
    input.entries.where((entry) {
      final value = entry.value;
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is Iterable) return value.isNotEmpty;
      if (value is Map) return value.isNotEmpty;
      return true;
    }),
  );
}

Map<String, String> adminHeaders({
  required String token,
  required int shopId,
  required AdminEndpoint endpoint,
}) {
  final headers = <String, String>{'Authorization': 'Bearer $token'};
  if (endpoint.attachShopHeader &&
      !shopHeaderExcludedPaths.contains(endpoint.path)) {
    headers['X-Shop-Id'] = '$shopId';
  }
  return headers;
}

const getUserInfoEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/getUserInfo',
  permissionCode: 'user:view',
  pageSizeLimit: 100,
);

const adminLoginEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/adminLogin',
  permissionCode: 'public',
  attachShopHeader: false,
);

const cashierKdsReplicationEventEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/replication/events',
  permissionCode: 'kds:sync',
);

const cashierKdsReplicationBatchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/replication/events/batch',
  permissionCode: 'kds:sync',
);

const cashierKdsAuthorityConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/kds/authority/config-snapshot',
  permissionCode: 'kds:sync',
);

const cashierKdsAuthorityDeviceEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/authority/device',
  permissionCode: 'kds:config',
);

const cashierKdsDeliveryLeaseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/kds/authority/lease',
  permissionCode: 'cashier:operate',
);
const cashierKdsDeliveryBootstrapEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/delivery/bootstrap',
  permissionCode: 'cashier:operate',
);
const cashierKdsDeliveryEventsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/delivery/events',
  permissionCode: 'cashier:operate',
);
const cashierKdsDeliveryAckEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/kds/delivery/ack',
  permissionCode: 'cashier:operate',
);
const cashierKdsDeliveryStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/delivery/status',
  permissionCode: 'cashier:operate',
);

/// 单笔订单最新完整厨房投影（人工修复/版本冲突恢复用）。
/// 调用时将 `{orderId}` 替换为云端正式订单 ID。
const cashierKdsOrderProjectionEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/orders/{orderId}/projection',
  permissionCode: 'cashier:operate',
);

const adminPermissionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/me/permissions',
  permissionCode: 'admin:manage',
  attachShopHeader: false,
);

const adminMeShopsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/me/shops',
  permissionCode: 'shop:manage',
  attachShopHeader: false,
);

const adminModifyPasswordEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/modifyPassword',
  permissionCode: 'admin:password',
);

const adminShopListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/shop/list',
  permissionCode: 'shop:manage',
  attachShopHeader: false,
);

const adminShopSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/shop/save',
  permissionCode: 'shop:manage',
);

const adminAdministratorListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/administrator/list',
  permissionCode: 'admin:manage',
  pageSizeLimit: 100,
);

const adminAdministratorCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/administrator/create',
  permissionCode: 'admin:manage',
);

const orderListEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/list',
  permissionCode: 'order:view',
  pageSizeLimit: 100,
  preserveEmptyStrings: true,
);

/// 商户订单列表：按 merchantId + 营业日（24 小时窗口）查询订单，
/// 运营后台/商户数据专用（默认商户号 "1" 自营收银订单）。
/// 需携带门店上下文（X-Shop-Id 当前选中门店），拦截器按门店过滤订单。
const merchantOrdersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/merchant/orders',
  permissionCode: 'report:view',
);

const cashierOrderTodayEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/order/today',
  permissionCode: 'cashier:operate',
);

const cashierOrderSearchEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/order/search',
  permissionCode: 'cashier:operate',
);

const cashierPrintKitchenEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/print/kitchen',
  permissionCode: 'cashier:operate',
);

const cashierOrderUnCheckoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/unCheckout',
  permissionCode: 'cashier:operate',
);

const cashierShiftCurrentEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/current',
  permissionCode: 'cashier:operate',
);

const cashierShiftStartEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/shift/start',
  permissionCode: 'cashier:operate',
);

const cashierShiftHandoverEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/shift/handover',
  permissionCode: 'cashier:operate',
);

/// 钱箱班次综合报表：GET /cashier/shift/report/{sessionId}（仅已交班可查）。
AdminEndpoint cashierShiftReportEndpoint(int sessionId) => AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/report/$sessionId',
  permissionCode: 'cashier:operate',
);

/// 记录钱箱人工现金事件（POST /cashier/shift/cash-movement）：
/// CASH_IN 加钞 / CASH_OUT 支出 / CASH_DROP 投库。
const cashierShiftCashMovementEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/shift/cash-movement',
  permissionCode: 'cashier:operate',
);

/// 已交班班次现金流水（GET /cashier/shift/{sessionId}/cash-events，仅 CLOSED 班次可查）。
AdminEndpoint cashierShiftCashEventsEndpoint(int sessionId) => AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/$sessionId/cash-events',
  permissionCode: 'cashier:operate',
);

const orderDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/orderDetail/list',
  permissionCode: 'order:view',
);

const orderPrintContentEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/order/printContent',
  permissionCode: 'order:view',
);

const orderTodayCountEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/todayCount',
  permissionCode: 'order:view',
);

const orderTodayUnsettledAmountEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/todayUnsettledAmount',
  permissionCode: 'order:view',
);

const tableListEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/table/list',
  permissionCode: 'table:manage',
  pageSizeLimit: 100,
);

const tableAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/table/add',
  permissionCode: 'table:manage',
);

const tableDeleteEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/table/delete',
  permissionCode: 'table:manage',
);

const tableOutEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/table/out',
  permissionCode: 'table:manage',
);

const tableStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/table/status',
  permissionCode: 'table:manage',
);

const cashierQuickOrderEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/quickOrder',
  permissionCode: 'cashier:operate',
);

AdminEndpoint cashierOrderKdsDetailsEndpoint(int orderId) => AdminEndpoint(
  method: 'GET',
  path: '/cashier/orders/$orderId/details',
  permissionCode: 'cashier:operate',
);

const cashierAddDishesEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/addDishes',
  permissionCode: 'cashier:operate',
);

const cashierRefundDishEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/refundDish',
  permissionCode: 'cashier:operate',
);

const cashierUpdatePriceEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/updatePrice',
  permissionCode: 'cashier:operate',
);

const cashierDiscountEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/discount',
  permissionCode: 'cashier:operate',
);

/// 挂单（POST /cashier/order/hang）。
const cashierOrderHangEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/hang',
  permissionCode: 'cashier:operate',
);

/// 取单/解挂（POST /cashier/order/unhang）。
const cashierOrderUnhangEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/unhang',
  permissionCode: 'cashier:operate',
);

/// 当前门店挂单池列表（GET /cashier/order/hang-list）。
const cashierOrderHangListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/order/hang-list',
  permissionCode: 'cashier:operate',
);

/// 修改订单用餐人数（POST /cashier/order/updateDiners）。
const cashierOrderUpdateDinersEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/updateDiners',
  permissionCode: 'cashier:operate',
);

/// 人工退款（POST /cashier/order/refund）：已支付订单的线下现金/组合退款。
const cashierOrderRefundEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/refund',
  permissionCode: 'cashier:operate',
);

/// 整桌结账（POST /cashier/table/checkout）：一键结清该桌全部未结订单。
const cashierTableCheckoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/checkout',
  permissionCode: 'cashier:operate',
);

/// 桌台状态图（GET /cashier/table/statusMap）：桌号 -> status。
const cashierTableStatusMapEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/table/statusMap',
  permissionCode: 'cashier:operate',
);

const cashierCheckoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/checkout',
  permissionCode: 'cashier:operate',
);

const publicPaymentCapabilitiesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/config/payment-capabilities',
  permissionCode: 'public',
);

const cashierPrintContentEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/order/printContent',
  permissionCode: 'cashier:operate',
);

const offlineCollectTempQrcodeEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/pay/offline-collect/temp-qrcode',
  permissionCode: 'cashier:operate',
);

const offlineCollectConfirmEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/pay/offline-collect/confirm',
  permissionCode: 'cashier:operate',
);

const offlineCollectCancelEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/pay/offline-collect/cancel',
  permissionCode: 'cashier:operate',
);

const orderPayByBalanceEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/order/payByBalance',
  permissionCode: 'cashier:operate',
);

const cashierTableOpenEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/open',
  permissionCode: 'cashier:operate',
);

const cashierTableMergeEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/merge',
  permissionCode: 'cashier:operate',
);

const cashierTableTransferEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/transfer',
  permissionCode: 'cashier:operate',
);

const cashierTableClearEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/clear',
  permissionCode: 'cashier:operate',
);

const orderReprintKitchenEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/reprint-kitchen',
  permissionCode: 'order:operate',
);

const orderRefundEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/refund',
  permissionCode: 'order:operate',
);

const orderReassignOpenidByPhoneEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/reassignOpenidByPhone',
  permissionCode: 'order:operate',
);

const orderReceivingEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/receiving',
  permissionCode: 'order:operate',
);

const orderReceEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/rece',
  permissionCode: 'order:operate',
);

const orderCheckoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/checkout',
  permissionCode: 'order:operate',
);

const orderChangeIdEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/changeId',
  permissionCode: 'order:config',
);

const orderAutoAcceptGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/auto-accept',
  permissionCode: 'order:config',
);

const orderAutoAcceptSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/auto-accept',
  permissionCode: 'order:config',
);

const orderDetailDeleteMenuEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/orderDetail/delete_menu',
  permissionCode: 'order:operate',
);

const orderDetailUpdateQuantityEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/orderDetail/updateQuantity',
  permissionCode: 'order:operate',
);

const kdsTicketRepushEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/ticket/repush',
  permissionCode: 'kds:config',
);

const takeoutDeliveryDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/takeout/delivery/detail',
  permissionCode: 'order:view',
);

const takeoutDeliveryTrackingEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/takeout/delivery/tracking',
  permissionCode: 'order:view',
);

const takeoutDeliveryStatusEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/takeout/delivery/status',
  permissionCode: 'order:operate',
);

const takeoutZsqDispatchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/takeout/delivery/zsq/dispatch',
  permissionCode: 'order:operate',
);

const takeoutZsqRedispatchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/takeout/delivery/zsq/redispatch',
  permissionCode: 'order:operate',
);

const takeoutZsqSyncEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/takeout/delivery/zsq/sync',
  permissionCode: 'order:operate',
);

const reportDashboardEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/dashboard',
  permissionCode: 'report:view',
);

const dashboardEndpoint = reportDashboardEndpoint;

const dishListEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/list',
  permissionCode: 'dish:manage',
  pageSizeLimit: 100,
);

const dishUpdateOnSaleEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/updateOnSale',
  permissionCode: 'dish:manage',
);

const dishUpdateSaleStatusEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/updateSaleStatus',
  permissionCode: 'dish:manage',
);

const dishHqTemplateListEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/hqTemplateList',
  permissionCode: 'dish:manage',
  pageSizeLimit: 100,
);

const dishImportFromHqEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/importFromHq',
  permissionCode: 'dish:manage',
);

const dishSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/save',
  permissionCode: 'dish:manage',
);

const dishDeleteEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/dish/delete',
  permissionCode: 'dish:manage',
);

const dishSortEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/sort',
  permissionCode: 'dish:manage',
);

const memberRechargeListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/member/recharge/list',
  permissionCode: 'user:view',
);

const memberRechargeEndpoint = memberRechargeListEndpoint;

const takeoutDeliveryListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/takeout/delivery/list',
  permissionCode: 'order:view',
  pageSizeLimit: 100,
);

const takeoutConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/takeout/config',
  permissionCode: 'order:view',
);

const takeoutConfigSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/takeout/config/save',
  permissionCode: 'order:config',
);

const categoryListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/category/list',
  permissionCode: 'dish:manage',
  pageSizeLimit: 100,
);

const categoryListAllEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/category/listAll',
  permissionCode: 'dish:manage',
);

const categoryAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/category/add',
  permissionCode: 'dish:manage',
);

const categoryUpdateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/category/update',
  permissionCode: 'dish:manage',
);

const categoryDeleteEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/category/delete',
  permissionCode: 'dish:manage',
);

const categorySortEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/category/sort',
  permissionCode: 'dish:manage',
);

const unitListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/unit/listAll',
  permissionCode: 'dish:manage',
);

const unitAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/unit/add',
  permissionCode: 'dish:manage',
);

const comboByDishEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/combo/getByDishId',
  permissionCode: 'dish:manage',
);

const comboSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/combo/save',
  permissionCode: 'dish:manage',
);

const couponListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/list',
  permissionCode: 'coupon:manage',
  pageSizeLimit: 100,
);

const couponGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/get',
  permissionCode: 'coupon:manage',
);

const couponAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/add',
  permissionCode: 'coupon:manage',
);

const couponUpdateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/update',
  permissionCode: 'coupon:manage',
);

const couponDeleteEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/delete',
  permissionCode: 'coupon:manage',
);

const couponRedeemCodeCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/redeem-code/create',
  permissionCode: 'coupon:manage',
);

const couponRedeemCodeListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/redeem-code/list',
  permissionCode: 'coupon:manage',
  pageSizeLimit: 100,
);

const couponUserCouponListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/user-coupon/list',
  permissionCode: 'coupon:manage',
  pageSizeLimit: 100,
);

const couponUserCouponGrantEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/user-coupon/grant',
  permissionCode: 'coupon:manage',
);

const couponBatchSendEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/batch-send',
  permissionCode: 'coupon:manage',
);

const activityListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/banners',
  permissionCode: 'banner:manage',
);

const activityAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/addbanners',
  permissionCode: 'banner:manage',
);

const announcementListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/announcement/list',
  permissionCode: 'announcement:view',
  pageSizeLimit: 100,
);

const announcementGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/announcement/get',
  permissionCode: 'announcement:view',
);

const announcementAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/announcement/add',
  permissionCode: 'announcement:manage',
);

const announcementUpdateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/announcement/update',
  permissionCode: 'announcement:manage',
);

const announcementDeleteEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/announcement/delete',
  permissionCode: 'announcement:manage',
);

const dailySummaryEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/summary',
  permissionCode: 'daily:settle',
);

const dailySettleEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/daily/settle',
  permissionCode: 'daily:settle',
);

const dailyPrecheckEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/pre-check',
  permissionCode: 'daily:settle',
);

const dailyZReportEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/z-report',
  permissionCode: 'daily:settle',
);

const dailyIncomeEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/income',
  permissionCode: 'daily:settle',
);

const dailyByChannelEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/byChannel',
  permissionCode: 'daily:settle',
);

const dailyGrossProfitEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/grossProfit',
  permissionCode: 'daily:settle',
);

/// 日结工作台统一上下文聚合（GET /admin/daily/context）：
/// 单请求返回 stat_date / is_already_settled / can_settle / summary /
/// channels / channel_details / blockers / warnings /
/// voidable_stale_pack_takeout / precheck_token（daily:settle|report:view）。
const dailyContextEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/context',
  permissionCode: 'daily:settle',
);

/// 作废目标营业日内超时未支付的打包/外卖单（POST /admin/daily/void-stale-takeout-orders）。
const dailyVoidStaleTakeoutOrdersEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/daily/void-stale-takeout-orders',
  permissionCode: 'daily:settle',
);

/// 按营业日时序查询历史 Z 报表与日结状态（GET /admin/daily/z-reports）。
const dailyZReportsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/z-reports',
  permissionCode: 'daily:settle',
);

const analyticsBusinessEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/business',
  permissionCode: 'statistics:view',
);

const analyticsBusinessTrendEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/business/trend',
  permissionCode: 'statistics:view',
);

const analyticsDishesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/dishes',
  permissionCode: 'statistics:view',
);
const statisticsCategorySalesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/statisticsCategorySales',
  permissionCode: 'statistics:view',
);

const analyticsCustomersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/customers',
  permissionCode: 'statistics:view',
);

const analyticsMembersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/members',
  permissionCode: 'statistics:view',
);

const analyticsMarketingEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/analytics/marketing',
  permissionCode: 'statistics:view',
);

const stockPrepPlanEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/stock-prep/plan/list',
  permissionCode: 'material:manage',
  pageSizeLimit: 100,
);

const materialListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/material/list',
  permissionCode: 'material:manage',
  pageSizeLimit: 100,
);

const materialSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/material/save',
  permissionCode: 'material:manage',
);

const materialInboundEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/material/inbound',
  permissionCode: 'material:manage',
);

const materialOutboundEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/material/outbound',
  permissionCode: 'material:manage',
);

const materialAlertEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/material/alert',
  permissionCode: 'material:manage',
);

const reportInventoryEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/inventory',
  permissionCode: 'report:view',
);

const stockPrepBomListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/stock-prep/bom/list',
  permissionCode: 'material:manage',
);

const stockPrepBomSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/stock-prep/bom/save',
  permissionCode: 'material:manage',
);

const stockPrepConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/stock-prep/config',
  permissionCode: 'material:manage',
);

const stockPrepConfigSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/stock-prep/config/save',
  permissionCode: 'material:manage',
);

const stockPrepPlanGenerateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/stock-prep/plan/generate',
  permissionCode: 'material:manage',
);

const settingsBusinessEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/order/Business',
  permissionCode: 'order:view',
);

const settingsChangeBusinessEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/order/ChangeBusiness',
  permissionCode: 'order:config',
);

const feieyunConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/config/feieyun',
  permissionCode: 'order:view',
);

const feieyunConfigSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/config/feieyun',
  permissionCode: 'admin:manage',
);

const feieyunShopConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/config/feieyun/shop',
  permissionCode: 'admin:manage',
);

const feieyunShopConfigSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/config/feieyun/shop',
  permissionCode: 'admin:manage',
);

const paymentMethodListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment-method/list',
  permissionCode: 'order:operate',
);

const paymentMethodSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment-method/save',
  permissionCode: 'order:operate',
);

const paymentCapabilitiesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/capabilities',
  permissionCode: 'payment:config:read',
);

const paymentCapabilitiesSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/payment/capabilities',
  permissionCode: 'payment:config:write',
  preserveEmptyCollections: true,
);

const paymentNinefoldEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/ninefold',
  permissionCode: 'payment:config:read',
);

const paymentNinefoldSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/payment/ninefold',
  permissionCode: 'payment:config:write',
);

const paymentMerchantsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/merchants',
  permissionCode: 'payment:config:read',
);

const paymentMerchantEditFormEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/merchants/edit-form',
  permissionCode: 'payment:config:read',
);

const paymentMerchantSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/payment/merchants/save',
  permissionCode: 'payment:config:write',
  preserveEmptyStrings: true,
);

AdminEndpoint paymentMerchantDetailEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/merchants/$id',
  permissionCode: 'payment:config:read',
);

AdminEndpoint paymentMerchantDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/payment/merchants/$id',
  permissionCode: 'payment:config:write',
);

const paymentWechatAuditEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/wechat/pay-auth-audit',
  permissionCode: 'payment:config:read',
);

const operationLogEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/log/operation',
  permissionCode: 'log:view',
  pageSizeLimit: 100,
);

const orderLogEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/log/{orderId}',
  permissionCode: 'log:view',
);

const rbacRolesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/rbac/roles',
  permissionCode: 'admin:manage',
);

const rbacRolesSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/rbac/roles',
  permissionCode: 'admin:manage',
);

const rbacPermissionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/rbac/permissions',
  permissionCode: 'admin:manage',
);

const rbacPermissionsSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/rbac/permissions',
  permissionCode: 'admin:manage',
);

const rbacApiPermissionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/rbac/api-permissions',
  permissionCode: 'admin:manage',
);

const rbacApiPermissionsSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/rbac/api-permissions',
  permissionCode: 'admin:manage',
);

const kdsConfigEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/kds/config/get',
  permissionCode: 'kds:config',
);

const kdsConfigSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/config/save',
  permissionCode: 'kds:config',
);

const kdsServeTicketPrintEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/ticket/print-serve',
  permissionCode: 'kds:config',
);

const kdsStationListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/kds/station/list',
  permissionCode: 'kds:config',
);

const kdsStationSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/station/save',
  permissionCode: 'kds:config',
);

const kdsStationInitFiveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/station/init-five',
  permissionCode: 'kds:config',
);

const kdsDeviceListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/kds/device/list',
  permissionCode: 'kds:config',
);

const kdsDeviceBindEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/device/bind',
  permissionCode: 'kds:config',
);

const kdsDishScreenListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/kds/dish-screen/list',
  permissionCode: 'kds:config',
);

const kdsDishScreenBindEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/dish-screen/bind',
  permissionCode: 'kds:config',
);

const memberRechargeCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/member/recharge',
  permissionCode: 'user:points',
);

const memberBalanceDeductEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/member/balance/deduct',
  permissionCode: 'user:points',
);

const memberConsumptionEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/member/consumption',
  permissionCode: 'user:view',
);

const memberProfileEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/member/profile',
  permissionCode: 'user:view',
);

const reportDailyEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/daily',
  permissionCode: 'report:view',
);

const reportWeeklyEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/weekly',
  permissionCode: 'report:view',
);

const reportMonthlyEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/monthly',
  permissionCode: 'report:view',
);

const reportDishRankingEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/dishRanking',
  permissionCode: 'report:view',
);

const reportCashierPerformanceEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/cashierPerformance',
  permissionCode: 'report:view',
);

const pushDeviceRegisterEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/push/device/register',
  permissionCode: 'public',
);

const pushDeviceUnregisterEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/push/device/unregister',
  permissionCode: 'public',
  attachShopHeader: false,
);

const pushPreferenceEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/push/preference',
  permissionCode: 'public',
);

const appVersionEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/app/version',
  permissionCode: 'public',
  attachShopHeader: false,
);

const reportShopProfitEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/shopProfit',
  permissionCode: 'report:view',
);

const settingsAccessEmployeesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/employees',
  permissionCode: 'access:view',
);

const settingsAccessEmployeeCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/employees',
  permissionCode: 'access:manage',
);

const settingsAccessRolesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/roles',
  permissionCode: 'access:view',
);

const settingsAccessRoleCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/roles',
  permissionCode: 'access:manage',
);

const settingsAccessEvaluateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/evaluate',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：变更员工账号状态（ACTIVE/DISABLED/RESIGNED）。
const settingsAccessEmployeeStatusEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/access/employees/{id}/status',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：强制下线员工（递增 tokenVersion，使既有 JWT 全部失效）。
const settingsAccessEmployeeForceLogoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/employees/{id}/force-logout',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：删除员工账号（有业务记录返 409 ACCESS_EMPLOYEE_HAS_RECORDS）。
const settingsAccessEmployeeDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/access/employees/{id}',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：查询员工最终有效权限（角色权限 + ALLOW/DENY 显式覆盖）。
const settingsAccessEmployeeEffectivePermissionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/employees/{id}/effective-permissions',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：职责分离 (SoD) 冲突预检。
const settingsAccessConflictsCheckEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/conflicts/check',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：更新角色（乐观锁 version，不匹配返 409）。
const settingsAccessRoleUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/access/roles/{id}',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：删除角色（被员工引用返 409 ROLE_IN_USE）。
const settingsAccessRoleDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/access/roles/{id}',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：权限策略列表。
const settingsAccessPoliciesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/policies',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：创建权限策略。
const settingsAccessPolicyCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/policies',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：更新权限策略。
const settingsAccessPolicyUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/access/policies/{id}',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：删除权限策略。
const settingsAccessPolicyDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/access/policies/{id}',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：绑定权限策略至角色（roleId + policyId）。
const settingsAccessPolicyAssignEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/policies/assign',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：审批流水列表（分页）。
const settingsAccessApprovalsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/approvals',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：审批流水详情。
const settingsAccessApprovalDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/approvals/{id}',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：店长手机查看扫码审批详情。
const settingsAccessQrDetailsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/qr/details',
  permissionCode: 'access:view',
);

/// v1.2.278 权限中心 v2：店长手机审批（AGREE/REJECT）。
const settingsAccessQrConfirmEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/qr/confirm',
  permissionCode: 'access:manage',
);

/// v1.2.278 权限中心 v2：收银端现场授权（密码/PIN，签发 120s 一次性审批 Token）。
const cashierAccessAuthorizeEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/access/authorize',
  permissionCode: 'order:config',
);

/// v1.2.278 权限中心 v2：收银端生成动态二维码（扫码授权）。
const cashierAccessQrCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/access/qr/create',
  permissionCode: 'order:config',
);

/// v1.2.278 权限中心 v2：收银端轮询二维码状态（PENDING/APPROVED/REJECTED/EXPIRED）。
const cashierAccessQrStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/access/qr/status',
  permissionCode: 'order:config',
);

/// 本门店最近授权人（GET /cashier/access/recent-authors）：授权弹窗快捷填入账号。
const cashierAccessRecentAuthorsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/access/recent-authors',
  permissionCode: 'cashier:operate',
);
