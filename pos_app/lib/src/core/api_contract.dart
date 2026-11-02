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

const adminPermissionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/me/permissions',
  permissionCode: 'admin:manage',
  attachShopHeader: false,
);

/// 店长现场授权（POS Access Control v2）：收银员发起高风险/超限操作时，
/// 现场店长凭工号/用户名 + 密码或 PIN 验证后签发短时一次性审批 Token。
/// 接口映射权限码 cashier:operate（已登录收银员即可发起授权请求）。
const cashierAccessAuthorizeEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/access/authorize',
  permissionCode: 'cashier:operate',
);

/// 本门店最近授权人（GET /cashier/access/recent-authors?limit=10）：
/// 返回最近成功授权（APPROVED/CONSUMED）的店长/管理员去重列表（倒序），
/// 供收银端授权弹窗快捷选择历史账号/工号。
const cashierAccessRecentAuthorsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/access/recent-authors',
  permissionCode: 'cashier:operate',
);

/// 方案A·收银端出码：收银员触发敏感操作时生成动态授权二维码与短链
/// （POST /cashier/access/qr/create，返回 approvalCode + qrPayload），
/// 店长手机扫码无密审批，彻底避免收银台输入密码被偷看/监控。
const cashierAccessQrCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/access/qr/create',
  permissionCode: 'cashier:operate',
);

/// 方案A·收银端轮询：GET /cashier/access/qr/status?approvalCode=...
/// 获取店长移动端审批结果（PENDING/APPROVED/REJECTED/EXPIRED），
/// APPROVED 时返回一次性 approvalToken 供敏感操作原子核销。
const cashierAccessQrStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/access/qr/status',
  permissionCode: 'cashier:operate',
);

/// 方案A·店长端查详情：GET /admin/access/qr/details?approvalCode=...
/// 店长手机扫码唤起后查看申请门店、操作员、业务类型、金额与原因。
const adminAccessQrDetailsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/qr/details',
  permissionCode: 'access:view',
  attachShopHeader: false,
);

/// 方案A·店长端确认/驳回：POST /admin/access/qr/confirm
/// （body: approvalCode + action=AGREE|REJECT + rejectReason），同意时签发单次令牌。
const adminAccessQrConfirmEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/qr/confirm',
  permissionCode: 'access:view',
  attachShopHeader: false,
);

/// 权限中心审批记录分页（GET /admin/access/approvals，支持 status/bizType/shopId 过滤）。
const adminAccessApprovalsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/approvals',
  permissionCode: 'access:view',
  pageSizeLimit: 100,
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

const adminAdministratorUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/administrator/{id}',
  permissionCode: 'admin:manage',
);

const adminAdministratorRolesEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/administrator/{id}/roles',
  permissionCode: 'admin:manage',
);

const adminAdministratorShopsEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/administrator/{id}/shops',
  permissionCode: 'admin:manage',
);

const adminAdministratorDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/administrator/{id}',
  permissionCode: 'admin:manage',
);

const orderListEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/list',
  permissionCode: 'order:view',
  pageSizeLimit: 100,
  preserveEmptyStrings: true,
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

const cashierPrintDispatchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/print/dispatch',
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

const cashierShiftCashMovementEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/shift/cash-movement',
  permissionCode: 'cashier:operate',
);

AdminEndpoint cashierShiftReportEndpoint(int sessionId) => AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/report/$sessionId',
  permissionCode: 'cashier:operate',
);

const cashierShiftWorkbenchEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/workbench',
  permissionCode: 'cashier:operate',
);

const cashierShiftReportsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/shift/reports',
  permissionCode: 'cashier:operate',
);

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

const tableUpdateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/table/update',
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

const cashierOrderHangEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/hang',
  permissionCode: 'cashier:operate',
);

const cashierOrderUnhangEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/unhang',
  permissionCode: 'cashier:operate',
);

const cashierOrderHangListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/order/hang-list',
  permissionCode: 'cashier:operate',
);

const cashierTableStatusMapEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/table/statusMap',
  permissionCode: 'cashier:operate',
);

const cashierTableAreasEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/table/areas',
  permissionCode: 'cashier:operate',
);

const cashierTableBatchClearEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/batch-clear',
  permissionCode: 'cashier:operate',
);

const cashierTablePulseEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/table/pulse',
  permissionCode: 'cashier:operate',
);

AdminEndpoint posOrderUpdateDinersPathEndpoint(String orderNo) => AdminEndpoint(
  method: 'PUT',
  path: '/api/pos/orders/$orderNo/diners',
  permissionCode: 'cashier:operate',
);

const cashierKdsAuthorityLeaseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/kds/authority/lease',
  permissionCode: 'cashier:operate',
);

const cashierKdsDeliveryLeaseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/kds/delivery/lease',
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

const cashierKdsDeliveryBusinessDayOrdersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/delivery/business-day/orders',
  permissionCode: 'cashier:operate',
);

const cashierKdsDeliveryBusinessDayOrdersDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/delivery/business-day/orders/detail',
  permissionCode: 'cashier:operate',
);

const cashierKdsOrderProjectionEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/kds/orders/{orderId}/projection',
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

const cashierManualRefundEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/refund',
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

const cashierOrderUpdateDinersEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/order/updateDiners',
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

const cashierWechatNativeOrdersEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/payment/wechat/native/orders',
  permissionCode: 'cashier:operate',
);

const cashierWechatNativeOrderQueryEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/payment/wechat/native/orders/{orderNo}',
  permissionCode: 'cashier:operate',
);

const cashierWechatNativeOrderCloseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/payment/wechat/native/orders/{orderNo}/close',
  permissionCode: 'cashier:operate',
);

const cashierWechatMicropayOrdersEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/payment/wechat/micropay/orders',
  permissionCode: 'cashier:operate',
);

const cashierWechatMicropayOrderQueryEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/payment/wechat/micropay/orders/{orderNo}',
  permissionCode: 'cashier:operate',
);

const cashierWechatMicropayOrderReverseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/payment/wechat/micropay/orders/{orderNo}/reverse',
  permissionCode: 'cashier:operate',
);

const cashierReceivableEligibleAccountsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/receivables/eligible-accounts',
  permissionCode: 'cashier:operate',
);

const cashierReceivableChargesEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/receivables/charges',
  permissionCode: 'cashier:operate',
);

const cashierReceivableClaimsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/receivables/claims',
  permissionCode: 'cashier:operate',
);

const cashierReceivableClaimDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/receivables/claims/{id}',
  permissionCode: 'cashier:operate',
);

const cashierReceivableCollectionsEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/receivables/claims/{id}/collections',
  permissionCode: 'cashier:operate',
);

const adminReceivableAccountsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/receivables/accounts',
  permissionCode: 'receivable:view',
);

const adminReceivableAccountCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/accounts',
  permissionCode: 'receivable:manage',
);

const adminReceivableAccountDetailEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/receivables/accounts/{id}',
  permissionCode: 'receivable:view',
);

const adminReceivableAccountUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/receivables/accounts/{id}',
  permissionCode: 'receivable:manage',
);

const adminReceivableAccountStatusEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/accounts/{id}/status',
  permissionCode: 'receivable:manage',
);

const adminReceivableAccountCloseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/accounts/{id}/close',
  permissionCode: 'receivable:manage',
);

const adminReceivableAccountDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/receivables/accounts/{id}',
  permissionCode: 'receivable:manage',
);

const adminReceivableAccountStatementEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/receivables/accounts/{id}/statement',
  permissionCode: 'receivable:view',
);

const adminReceivableClaimsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/receivables/claims',
  permissionCode: 'receivable:view',
);

const adminReceivableAgingEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/receivables/aging',
  permissionCode: 'receivable:view',
);

const adminReceivableClaimCollectEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/claims/{id}/collections',
  permissionCode: 'receivable:collect',
);

const adminReceivableClaimReverseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/claims/{id}/reverse',
  permissionCode: 'receivable:writeoff',
);

const adminReceivableClaimWriteOffEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/receivables/claims/{id}/write-off',
  permissionCode: 'receivable:writeoff',
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

const cashierTableCheckoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/table/checkout',
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

const customerDishListAllEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/dish/listAll',
  permissionCode: 'public',
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

const dishUploadImageEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/dish/uploadImage',
  permissionCode: 'dish:manage',
);

const aiStoreDishProfilesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/api/v1/ai/stores/{storeId}/dish-profiles',
  permissionCode: 'dish:manage',
);

const aiSingleDishProfileEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/api/v1/ai/stores/{storeId}/dish-profiles/{dishId}',
  permissionCode: 'dish:manage',
);

const aiSaveDishProfileEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/api/v1/ai/stores/{storeId}/dish-profiles/{dishId}',
  permissionCode: 'dish:manage',
);

const aiBatchDishProfilesEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/api/v1/ai/stores/{storeId}/dish-profiles/batch',
  permissionCode: 'dish:manage',
);

const aiAutoInitDishProfilesEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/api/v1/ai/stores/{storeId}/dish-profiles/auto-init',
  permissionCode: 'dish:manage',
);

const comboGetByDishIdEndpoint = comboByDishEndpoint;

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

// 系统设置按当前 OpenAPI 使用 POST + JSON 分页；保留上方旧常量，避免影响
// 尚未迁移的实时看板调用方。
const settingsTakeoutDeliveryListEndpoint = AdminEndpoint(
  method: 'POST',
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

const zsqAutoApiEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/config/zsq-auto-api',
  permissionCode: 'order:config',
);

const zsqAutoApiSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/config/zsq-auto-api',
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
  permissionCode: 'dish:manage|cashier:operate',
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

const dailyContextEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/context',
  permissionCode: 'daily:settle',
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

const dailyVoidStaleTakeoutEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/daily/void-stale-takeout-orders',
  permissionCode: 'daily:settle',
);

const dailyZReportEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/z-report',
  permissionCode: 'daily:settle',
);

const dailyZReportsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/z-reports',
  permissionCode: 'daily:settle',
);

const dailyReopenEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/daily/reopen',
  permissionCode: 'daily:settle',
);

const dailyAdjustmentsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/daily/adjustments',
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

const reconciliationOverviewEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/reconciliation/overview',
  permissionCode: 'daily:settle',
);

const reconciliationImportEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/reconciliation/import',
  permissionCode: 'daily:settle',
);

const reconciliationBatchesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/reconciliation/batches',
  permissionCode: 'daily:settle',
);

const reconciliationCasesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/reconciliation/cases',
  permissionCode: 'daily:settle',
);

const reconciliationResolveCaseEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/reconciliation/cases/{id}/resolve',
  permissionCode: 'daily:settle',
);

const migrationLedgerBackfillEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/migration/ledger/backfill',
  permissionCode: 'daily:settle',
);

const migrationLedgerShadowVerifyEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/migration/ledger/shadow-verify',
  permissionCode: 'daily:settle',
);

const migrationLedgerStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/migration/ledger/status',
  permissionCode: 'daily:settle',
);

const migrationLedgerCutoverEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/migration/ledger/cutover',
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

/// 商户订单列表（GET /admin/merchant/orders，支持 merchant_id、date、transac_status、page、page_size）
const merchantOrdersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/merchant/orders',
  permissionCode: 'report:view',
  pageSizeLimit: 500,
);

/// 商户订单营业日汇总（GET /admin/merchant/orders/summary，支持 merchant_id、date、transac_status）
const merchantOrdersSummaryEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/merchant/orders/summary',
  permissionCode: 'report:view',
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

/// 收银端营业状态切换（v1.2.219：与运营端 /order/ChangeBusiness 共用核心逻辑，
/// 含强制开班/交班/日结校验；force=1 需 admin:manage 权限逃生）。
const cashierShopBusinessEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/shop/business',
  permissionCode: 'cashier:operate',
);

const settingsOverviewEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/settings/overview',
  permissionCode: 'settings:view',
);

const settingsStoreEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/settings/store',
  permissionCode: 'settings:view',
);

const settingsStoreSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/settings/store',
  permissionCode: 'settings:manage',
  preserveEmptyCollections: true,
);

const settingsStoreOverrideEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/settings/store/override',
  permissionCode: 'settings:manage',
);

const offlineCollectUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/shop/offline-collect/upload',
  permissionCode: 'shop:manage',
);

const adminPrintDispatchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/dispatch',
  permissionCode: 'printing:manage',
);

const settingsPrintingDevicesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/devices',
  permissionCode: 'printing:view',
);

const settingsPrintingDeviceCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/devices',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingDeviceDetailEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/devices/$id',
  permissionCode: 'printing:view',
);

AdminEndpoint settingsPrintingDeviceUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/printing/devices/$id',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingDeviceDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/printing/devices/$id',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingDeviceTestEndpoint(int id) => AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/devices/$id/test',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingDeviceStatusEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/devices/$id/status',
  permissionCode: 'printing:view',
);

AdminEndpoint settingsPrintingDeviceClearQueueEndpoint(int id) => AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/devices/$id/clear-queue',
  permissionCode: 'printing:manage',
);

const settingsPrintingRulesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/rules',
  permissionCode: 'printing:view',
);

const settingsPrintingRulesSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/printing/rules',
  permissionCode: 'printing:manage',
);

const settingsPrintingJobsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/jobs',
  permissionCode: 'printing:view',
);

AdminEndpoint settingsPrintingJobReprintEndpoint(int id) => AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/jobs/$id/reprint',
  permissionCode: 'printing:manage',
);

const settingsPrintingPreviewGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/preview',
  permissionCode: 'printing:view',
);

const settingsPrintingPreviewPostEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/preview',
  permissionCode: 'printing:view',
);

const settingsPrintingPreviewExactEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/preview/exact',
  permissionCode: 'printing:view',
);

const settingsPrintingTemplatesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/templates',
  permissionCode: 'printing:view',
);

const settingsPrintingTemplatesMetaEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/templates/meta',
  permissionCode: 'printing:view',
);

const settingsPrintingTemplateCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/printing/templates',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingTemplateDetailEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/printing/templates/$id',
  permissionCode: 'printing:view',
);

AdminEndpoint settingsPrintingTemplateUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/printing/templates/$id',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingTemplateDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/printing/templates/$id',
  permissionCode: 'printing:manage',
);

AdminEndpoint settingsPrintingTemplateSetDefaultEndpoint(int id) =>
    AdminEndpoint(
      method: 'POST',
      path: '/admin/printing/templates/$id/set-default',
      permissionCode: 'printing:manage',
    );

AdminEndpoint settingsPaymentChannelImpactEndpoint(String code) =>
    AdminEndpoint(
      method: 'POST',
      path: '/admin/payment/channels/$code/impact',
      permissionCode: 'payment:manage',
    );

AdminEndpoint settingsPaymentChannelTestEndpoint(String code) => AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/channels/$code/test',
  permissionCode: 'payment:manage',
);

const settingsNotificationRulesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/notifications/rules',
  permissionCode: 'notifications:view',
);

const settingsNotificationRuleCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/notifications/rules',
  permissionCode: 'notifications:manage',
);

AdminEndpoint settingsNotificationRuleUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/notifications/rules/$id',
  permissionCode: 'notifications:manage',
);

AdminEndpoint settingsNotificationRuleDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/notifications/rules/$id',
  permissionCode: 'notifications:manage',
);

AdminEndpoint settingsNotificationRuleTestEndpoint(int id) => AdminEndpoint(
  method: 'POST',
  path: '/admin/notifications/rules/$id/test',
  permissionCode: 'notifications:manage',
);

const settingsNotificationDeliveriesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/notifications/deliveries',
  permissionCode: 'notifications:view',
);

const settingsFirstOrderCampaignsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/marketing/first-order/campaigns',
  permissionCode: 'marketing:firstorder:view',
);

const settingsFirstOrderRedemptionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/marketing/first-order/redemptions',
  permissionCode: 'marketing:firstorder:view',
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

AdminEndpoint settingsAccessEmployeeUpdateEndpoint(int adminId) =>
    AdminEndpoint(
      method: 'PUT',
      path: '/admin/access/employees/$adminId',
      permissionCode: 'access:manage',
    );

AdminEndpoint settingsAccessEmployeeDeleteEndpoint(int adminId) =>
    AdminEndpoint(
      method: 'DELETE',
      path: '/admin/access/employees/$adminId',
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

AdminEndpoint settingsAccessRoleUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/access/roles/$id',
  permissionCode: 'access:manage',
);

AdminEndpoint settingsAccessRoleDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/access/roles/$id',
  permissionCode: 'access:manage',
);

const settingsAccessEvaluateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/evaluate',
  permissionCode: 'access:view',
);

/// 员工账号状态变更（启用/停用/离职/锁定）：PUT /admin/access/employees/{id}/status。
AdminEndpoint settingsAccessEmployeeStatusEndpoint(int adminId) =>
    AdminEndpoint(
      method: 'PUT',
      path: '/admin/access/employees/$adminId/status',
      permissionCode: 'access:manage',
    );

/// 强制下线指定员工全部活跃会话：POST /admin/access/employees/{id}/force-logout。
AdminEndpoint settingsAccessEmployeeForceLogoutEndpoint(int adminId) =>
    AdminEndpoint(
      method: 'POST',
      path: '/admin/access/employees/$adminId/force-logout',
      permissionCode: 'access:manage',
    );

/// 查询员工最终有效权限（角色命中 + ALLOW/DENY 覆盖）：
/// GET /admin/access/employees/{id}/effective-permissions。
AdminEndpoint settingsAccessEffectivePermissionsEndpoint(int adminId) =>
    AdminEndpoint(
      method: 'GET',
      path: '/admin/access/employees/$adminId/effective-permissions',
      permissionCode: 'access:view',
    );

/// SoD 职责分离冲突预检：POST /admin/access/conflicts/check（body: permissionCodes）。
const settingsAccessConflictsCheckEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/conflicts/check',
  permissionCode: 'access:view',
);

/// 权限策略列表（按权限码过滤）：GET /admin/access/policies。
const settingsAccessPoliciesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/access/policies',
  permissionCode: 'access:view',
);

/// 创建权限策略（金额上限/折扣底线/显式覆盖等）：POST /admin/access/policies。
const settingsAccessPolicyCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/policies',
  permissionCode: 'access:manage',
);

/// 修改权限策略：PUT /admin/access/policies/{id}。
AdminEndpoint settingsAccessPolicyUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/access/policies/$id',
  permissionCode: 'access:manage',
);

/// 删除权限策略：DELETE /admin/access/policies/{id}。
AdminEndpoint settingsAccessPolicyDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/access/policies/$id',
  permissionCode: 'access:manage',
);

/// 绑定权限策略至角色（支持按门店定向生效）：POST /admin/access/policies/assign。
const settingsAccessPolicyAssignEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/access/policies/assign',
  permissionCode: 'access:manage',
);

/// 审批记录详情：GET /admin/access/approvals/{id}。
AdminEndpoint adminAccessApprovalDetailEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/access/approvals/$id',
  permissionCode: 'access:view',
);

const settingsInventorySuppliersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/suppliers',
  permissionCode: 'inventory:view',
);

const settingsInventorySupplierSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/inventory/suppliers',
  permissionCode: 'inventory:manage',
);

const settingsInventorySupplierUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/suppliers',
  permissionCode: 'inventory:manage',
);

const settingsInventorySupplierDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/inventory/suppliers',
  permissionCode: 'inventory:manage',
);

const settingsInventoryWarehousesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/warehouses',
  permissionCode: 'inventory:view',
);

const settingsInventoryWarehouseSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/inventory/warehouses',
  permissionCode: 'inventory:manage',
);

const settingsInventoryWarehouseUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/warehouses',
  permissionCode: 'inventory:manage',
);

const settingsInventoryBomsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/boms',
  permissionCode: 'inventory:view',
);

const settingsInventoryBomSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/inventory/boms',
  permissionCode: 'inventory:manage',
);

const settingsInventoryBomUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/boms',
  permissionCode: 'inventory:manage',
);

AdminEndpoint settingsInventoryBomActivateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/boms/$id/activate',
  permissionCode: 'inventory:manage',
);

const settingsInventoryPurchasesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/purchases',
  permissionCode: 'inventory:view',
);

const settingsInventoryPurchaseSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/inventory/purchases',
  permissionCode: 'inventory:manage',
);

const settingsInventoryPurchaseUpdateEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/purchases',
  permissionCode: 'inventory:manage',
);

const settingsInventoryTransfersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/transfers',
  permissionCode: 'inventory:view',
);

const settingsInventoryTransferSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/inventory/transfers',
  permissionCode: 'inventory:manage',
);

AdminEndpoint settingsInventoryTransferReceiveEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/inventory/transfers/$id/receive',
  permissionCode: 'inventory:manage',
);

const settingsInventoryBatchesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/inventory/batches',
  permissionCode: 'inventory:view',
);

/// 轮播图列表（全部，供后台管理；body 含 code、banners（Banner[]））。
const adminBannersEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/banners',
  permissionCode: 'banner:manage',
);

/// 新增轮播图（body Banner schema；响应含 bannerId）。
const adminBannerAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/addbanners',
  permissionCode: 'banner:manage',
);

/// 删除轮播图（path id）。
AdminEndpoint adminBannerDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/order/delete_banners/$id',
  permissionCode: 'banner:manage',
);

/// 更新轮播图（path id，body Banner 含 status/type 等；2.1.25 新增，
/// 支持快捷启用/禁用）。openapi 已补录。
AdminEndpoint adminBannerUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/order/update_banners/$id',
  permissionCode: 'banner:manage',
);

/// 轮播图图片上传（multipart 字段 file；响应 code 0 时 msg 为可访问相对路径，
/// 如 /image/avatar/{uuid}.png）。openapi 未收录该端点，服务端
/// AdminOrderController.uploadBannerFile 为真实实现，以服务端为准补录。
const adminBannerUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/uploadBannerFile',
  permissionCode: 'banner:manage',
);

/// 活动弹窗列表（全部，返回 popup 数组）。openapi 未收录管理端弹窗端点，
/// 以服务端 ActivityController 真实实现为准补录；服务端无权限码映射，按 public 处理。
const activityPopupListEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/activity/getAllPopup',
  permissionCode: 'public',
);

/// 活动弹窗详情（body {id}，返回 popup）。服务端无权限码映射，按 public 处理。
const activityPopupDetailEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/activity/getCarouselDetail',
  permissionCode: 'public',
);

/// 新增活动弹窗（body ActivityPopup，banner:manage）。
const activityPopupAddEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/activity/addPopup',
  permissionCode: 'banner:manage',
);

/// 更新活动弹窗（body 全量 ActivityPopup 含 id，banner:manage）。
const activityPopupUpdateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/activity/updatePopup',
  permissionCode: 'banner:manage',
);

/// 删除活动弹窗（body {id}，banner:manage）。
const activityPopupDeleteEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/activity/deletePopup',
  permissionCode: 'banner:manage',
);

const settingsReportExportsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/reports/exports',
  permissionCode: 'report:view',
);

const settingsReportExportCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/reports/exports',
  permissionCode: 'report:export',
);

AdminEndpoint settingsReportExportDownloadEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/reports/exports/$id/download',
  permissionCode: 'report:view',
);

const settingsLogsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/logs',
  permissionCode: 'log:view',
);

const settingsLogArchiveSearchEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/logs/archive-search',
  permissionCode: 'log:archive',
);

AdminEndpoint settingsLogArchiveSearchDetailEndpoint(String jobId) =>
    AdminEndpoint(
      method: 'GET',
      path: '/admin/logs/archive-search/$jobId',
      permissionCode: 'log:view',
    );

const settingsLogExportEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/logs/exports',
  permissionCode: 'log:export',
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

/// 上传微信商户 PEM 私钥（返回 privateKeyRef 服务器路径，供新增商户配置引用）。
const paymentPrivateKeyUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/private-key/upload',
  permissionCode: 'payment:config:write',
);

/// 上传微信支付平台公钥或平台证书（返回 platformPubKeyRef 服务器路径与 materialType，供商户配置引用）。
const paymentPlatformPublicKeyUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/platform-public-key/upload',
  permissionCode: 'payment:config:write',
);

/// 上传并绑定指定商户的微信 PEM 私钥（立即更新该商户 private_key_ref）。
AdminEndpoint paymentMerchantPrivateKeyUploadEndpoint(int id) =>
    AdminEndpoint(
      method: 'POST',
      path: '/admin/payment/merchants/$id/private-key/upload',
      permissionCode: 'payment:config:write',
    );

/// 全类型统一证书上传端点（支持 CLIENT_CERT_P12, PRIVATE_KEY, PLATFORM_PUBLIC_KEY, ALIPAY_*）。
const paymentCertificateUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/certificate/upload',
  permissionCode: 'payment:config:write',
);

/// 指定商户直绑统一证书上传端点。
AdminEndpoint paymentMerchantCertificateUploadEndpoint(int id) =>
    AdminEndpoint(
      method: 'POST',
      path: '/admin/payment/merchants/$id/certificate/upload',
      permissionCode: 'payment:config:write',
    );

/// 支付回调 URL 模板（只读：wechatPayNotify/wechatRefundNotify/alipayPayNotify）。
const paymentNotifyUrlsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/notify-urls',
  permissionCode: 'payment:config:read',
);

/// 商户分流路由规则列表与查询（GET /admin/payment/routing-rules）。
const paymentRoutingRulesEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/routing-rules',
  permissionCode: 'payment:config:read',
);

/// 商户分流路由规则新建（POST /admin/payment/routing-rules）。
const paymentRoutingRuleCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/routing-rules',
  permissionCode: 'payment:config:write',
);

/// 商户分流路由规则详情（GET /admin/payment/routing-rules/$id）。
AdminEndpoint paymentRoutingRuleDetailEndpoint(int id) => AdminEndpoint(
  method: 'GET',
  path: '/admin/payment/routing-rules/$id',
  permissionCode: 'payment:config:read',
);

/// 商户分流路由规则编辑（PUT /admin/payment/routing-rules/$id）。
AdminEndpoint paymentRoutingRuleUpdateEndpoint(int id) => AdminEndpoint(
  method: 'PUT',
  path: '/admin/payment/routing-rules/$id',
  permissionCode: 'payment:config:write',
);

/// 商户分流路由规则删除（DELETE /admin/payment/routing-rules/$id）。
AdminEndpoint paymentRoutingRuleDeleteEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/payment/routing-rules/$id',
  permissionCode: 'payment:config:write',
);

/// 商户分流路由规则优先级重排（PUT /admin/payment/routing-rules/sort）。
const paymentRoutingRulesSortEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/payment/routing-rules/sort',
  permissionCode: 'payment:config:write',
);

/// 商户分流路由规则现场试算模拟器（POST /admin/payment/routing-rules/simulate）。
const paymentRoutingRulesSimulateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/payment/routing-rules/simulate',
  permissionCode: 'payment:config:read',
);

/// 邀请好友首单余额返利规则（enabled/rewardPercent）。
const marketingInviteRewardEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/config/invite-first-order-balance-reward',
  permissionCode: 'order:config',
);

const marketingInviteRewardSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/config/invite-first-order-balance-reward',
  permissionCode: 'order:config',
);

/// 邀请海报配置（backgroundPath + qr{x,y,size}）。
const marketingInvitePosterEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/config/invite-poster',
  permissionCode: 'admin:manage',
);

const marketingInvitePosterSaveEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/config/invite-poster',
  permissionCode: 'admin:manage',
);

/// 首单活动列表（status/page/pageSize，items 含 stats{redemptions,restorations}）。
const marketingFirstOrderCampaignsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/marketing/first-order/campaigns',
  permissionCode: 'marketing:firstorder:view',
);

AdminEndpoint marketingFirstOrderCampaignDetailEndpoint(int id) =>
    AdminEndpoint(
      method: 'GET',
      path: '/admin/marketing/first-order/campaigns/$id',
      permissionCode: 'marketing:firstorder:view',
    );

/// 创建首单活动（body 必填 name/campaignType/startTime/endTime；
/// 同店时间窗重叠返回 409 FIRST_ORDER_RULE_CONFLICT，data.conflicts 列冲突活动）。
const marketingFirstOrderCampaignCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/marketing/first-order/campaigns',
  permissionCode: 'marketing:firstorder:manage',
);

/// 更新首单活动（body 必填 version 乐观锁；404 不存在；409 VERSION_CONFLICT/RULE_CONFLICT）。
AdminEndpoint marketingFirstOrderCampaignUpdateEndpoint(int id) =>
    AdminEndpoint(
      method: 'PUT',
      path: '/admin/marketing/first-order/campaigns/$id',
      permissionCode: 'marketing:firstorder:manage',
    );

/// 首单资格判定（body: customerId 必填，orderAmount/shopId 可选）。
const marketingFirstOrderEligibilityEvaluateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/marketing/first-order/eligibility/evaluate',
  permissionCode: 'marketing:firstorder:view',
);

/// 批量删除兑换码（body: {ids: []}）。
const couponRedeemCodeDeleteEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/redeem-code/delete',
  permissionCode: 'coupon:manage',
);

/// 生成兑换码小程序二维码（返回 image/png 二进制；收银端展示以本地二维码兜底）。
const couponRedeemCodeQrcodeEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/coupon/redeem-code/qrcode',
  permissionCode: 'coupon:manage',
);

/// Excel 上传 openid 批量发券（multipart: couponId + file）。
const couponUserCouponBatchGrantExcelEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/user-coupon/batch-grant-excel',
  permissionCode: 'coupon:manage',
);

/// 解除用户券与订单号占用（后台纠错，body: {userCouponId}）。
const couponUserCouponUnbindEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/user-coupon/unbind',
  permissionCode: 'coupon:manage',
);

/// 作废用户券（仅未使用，body: {userCouponId}）。
const couponUserCouponVoidEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/coupon/user-coupon/void',
  permissionCode: 'coupon:manage',
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

AdminEndpoint rbacPermissionDeleteByIdEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/rbac/permissions/$id',
  permissionCode: 'admin:manage',
);

AdminEndpoint rbacApiPermissionDeleteByIdEndpoint(int id) => AdminEndpoint(
  method: 'DELETE',
  path: '/admin/rbac/api-permissions/$id',
  permissionCode: 'admin:manage',
);

const rbacApiPermissionsReloadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/rbac/api-permissions/reload',
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

const kdsDevicePairingTicketEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/device/pairing-ticket',
  permissionCode: 'kds:config',
);

const kdsDeviceUnbindEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/kds/device/unbind',
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

/// 会员看板统计：会员总数、今日新增、储值总额、积分发放（v1.2.231）。
const memberStatsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/member/stats',
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

const adminAppVersionsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/app/versions',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const adminAppVersionSaveEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/app/version/save',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const adminAppVersionToggleEnabledEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/app/version/toggle-enabled',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const adminAppVersionDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/app/version/{id}',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const adminAppVersionUploadEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/app/version/upload',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const adminAppVersionVerifyUrlEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/app/version/verify-url',
  permissionCode: 'admin:super',
  attachShopHeader: false,
);

const reportShopProfitEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/report/shopProfit',
  permissionCode: 'report:view',
);

/// UI061: 电子发票开具二维码生成
const orderInvoiceQrcodeEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/order/invoice/qrcode',
  permissionCode: 'order:operate',
);

/// UI061: 电子发票开具状态与明细查询
const orderInvoiceStatusEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/invoice/status/{orderNo}',
  permissionCode: 'order:view',
);

/// UI061: 全流程细粒度审计日志追踪
const orderAuditTimelineEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/order/audit-timeline/{orderNo}',
  permissionCode: 'order:view',
);

/// UI061: 会员大数据画像智能标签推荐
const memberPersonaTagsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/member/persona-tags',
  permissionCode: 'user:view',
);

const adminShopNotificationConfigGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/shop/notification-config',
  permissionCode: 'order:config',
);

const adminShopNotificationConfigPutEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/shop/notification-config',
  permissionCode: 'order:config',
);

const adminNotificationsChannelStatsEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/notifications/channel-stats',
  permissionCode: 'order:view',
);

const adminNotificationsTestPushEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/notifications/test-push',
  permissionCode: 'order:config',
);

const cashierNotificationsSyncEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/cashier/notifications/sync',
  permissionCode: 'cashier:operate',
);

const cashierNotificationsAckEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/cashier/notifications/ack',
  permissionCode: 'cashier:operate',
);

/// 微信订阅消息场景与模板配置查询 (GET /admin/subscribe/scenes)
const adminSubscribeScenesGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/subscribe/scenes',
  permissionCode: 'settings:view|order:view',
);

/// 微信订阅消息场景模板新增 (POST /admin/subscribe/scenes)
const adminSubscribeSceneCreateEndpoint = AdminEndpoint(
  method: 'POST',
  path: '/admin/subscribe/scenes',
  permissionCode: 'settings:manage|order:operate',
);

/// 微信订阅消息指定场景模板配置更新 (PUT /admin/subscribe/scenes/{sceneCode})
const adminSubscribeScenePutEndpoint = AdminEndpoint(
  method: 'PUT',
  path: '/admin/subscribe/scenes/{sceneCode}',
  permissionCode: 'settings:manage|order:operate',
);

/// 微信订阅消息场景模板删除 (DELETE /admin/subscribe/scenes/{sceneCode})
const adminSubscribeSceneDeleteEndpoint = AdminEndpoint(
  method: 'DELETE',
  path: '/admin/subscribe/scenes/{sceneCode}',
  permissionCode: 'settings:manage|order:operate',
);

/// 微信订阅消息下发审计日志查询 (GET /admin/subscribe/logs)
const adminSubscribeLogsGetEndpoint = AdminEndpoint(
  method: 'GET',
  path: '/admin/subscribe/logs',
  permissionCode: 'settings:view|order:view',
);
