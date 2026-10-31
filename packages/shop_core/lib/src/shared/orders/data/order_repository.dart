import '../domain/admin_order.dart';
import '../domain/order_query.dart';

abstract class OrderRepository {
  Future<PagedOrders> listOrders(OrderQuery query, {required int shopId});

  Future<AdminOrder> loadOrderDetails(AdminOrder order);

  /// 按订单号直接加载订单详情（不走 id）。
  ///
  /// 走 `GET /admin/table/status?orderNo=`，响应 orderList[0] 含 goods_list 明细，
  /// 字段与 AdminOrder/OrderLine 兼容。桌台页已有台号绑定的未结订单号时，
  /// 免去「先查列表拿 id 再查详情」的两次请求。
  Future<AdminOrder> loadOrderDetailsByOrderNo(
    String orderNo, {
    required int shopId,
  });

  Future<PagedOrders> loadPhoneHistory(String phone, {required int shopId});

  Future<Object?> printReceipt(AdminOrder order);

  Future<Object?> repushKdsTicket(AdminOrder order);

  Future<Object?> loadTakeoutDelivery(AdminOrder order);

  Future<void> refundLine(OrderLine line);

  Future<void> updateLineQuantity(OrderLine line, int quantity);

  /// 微信退款（POST /admin/order/refund，商户 API v3）。
  /// 后端 required authorization：审批令牌（approvalToken）或现场授权
  /// {account, password} 二选一；[approvalToken] 存在时优先携带令牌，
  /// 否则携带授权员工账号密码（授权员工须具备 order:operate:refund 且可访问当前门店）。
  /// 授权字段全空时不携带 authorization（旧调用方兼容）。
  Future<void> refundWechat(
    AdminOrder order, {
    required double amount,
    required String reason,
    String approvalToken = '',
    String account = '',
    String password = '',
  });

  /// 强制删除订单（DELETE /order/delete/{id}，仅 super_admin 可调）。
  /// 新契约支持审批令牌优先（[approvalToken]，由 /cashier/access/authorize 或扫码授权签发）；
  /// 未携带令牌时 body 携带 authorization {account, password}（account 为授权员工工号/用户名，
  /// 需同时具备 order:delete 与门店权限）。[terminalId] 为收银终端标识（Header 未携带
  /// X-Terminal-Id 时兜底）。
  Future<void> deleteOrder(
    AdminOrder order, {
    String approvalToken = '',
    String? account,
    required String password,
    String terminalId = '',
  });

  /// 人工现金退款（POST /cashier/order/refund）：已支付订单的线下现金/组合退款。
  /// 默认退「现金列剩余 ∩ 剩余可退」全部；现金列清零时拒绝。
  /// [approvalToken] 优先；未携带时带 authorization {account, password}。
  Future<Map<String, Object?>> refundCash(
    AdminOrder order, {
    double? refundAmount,
    String reason = '',
    String approvalToken = '',
    String account = '',
    String password = '',
  });

  /// 切换订单商户 ID（1↔2）：仅未结账订单可切，已付款订单后端拒绝
  /// （POST /admin/order/changeId，body 传订单主键 id，权限 order:config）。
  Future<void> changeOrderMerchantId(int orderId);

  /// 商户订单列表：按商户号 + 营业日（24 小时窗口）查询，运营后台/商户数据维度
  /// （GET /admin/merchant/orders）。默认商户号 "1"（自营收银订单）。
  Future<MerchantOrdersResult> fetchMerchantOrders({
    String merchantId = '1',
    String? date,
    String transacStatus = 'success',
    int page = 1,
    int pageSize = 500,
  });

  Future<AdminOrder> refundNormalLines(AdminOrder order);

  Future<AdminOrder> reprintKitchenTicket(AdminOrder order);
}
