import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import 'cashier_kds_delivery_models.dart';

/// KDS 云端投递通道客户端（openapi v1.2.189 / v1.2.278 收银机端）。
///
/// 覆盖 9 个端点：authority 租约（获取/续租）、bootstrap 分页快照、
/// 增量事件拉取、营业日订单快照与明细回填、单订单投影、累计 ACK、投递状态。
/// 所有请求携带门店头（X-Shop-Id，由 AdminApiClient 注入）与收银设备身份头：
/// `X-Cashier-Device-Code`、`X-Cashier-Authority-Epoch`、`X-Cashier-Lease-Token`
/// （后两者为 null 时不发送，适用于 ACQUIRE 首租）。
///
/// 409（authority epoch/lease 失效、cursor 过期）由 AdminApiClient 抛
/// ApiException（code 409x），调用方（调度层）应重新获取租约或触发 bootstrap。
class CashierKdsDeliveryClient {
  CashierKdsDeliveryClient({
    required this.client,
    required this.deviceCode,
    this.authorityEpoch,
    this.leaseToken,
  });

  final AdminApiClient client;
  final String deviceCode;

  /// 当前 authority 纪元；null 表示尚未获取（ACQUIRE 时忽略）。
  int? authorityEpoch;

  /// 当前租约令牌；null 表示尚未获取（ACQUIRE 时忽略）。
  String? leaseToken;

  Map<String, String> get _identityHeaders {
    final epoch = authorityEpoch;
    final token = leaseToken;
    return <String, String>{
      'X-Cashier-Device-Code': deviceCode,
      if (epoch != null) 'X-Cashier-Authority-Epoch': '$epoch',
      if (token != null) 'X-Cashier-Lease-Token': token,
    };
  }

  /// 获取或接管本店 KDS 主收银 authority（ACQUIRE）。
  Future<CashierKdsLeaseResult> acquireLease({String? clientVersion}) {
    return _lease(
      CashierKdsLeaseRequest(
        action: 'ACQUIRE',
        clientVersion: clientVersion,
      ),
    );
  }

  /// 续租（RENEW），必须携带当前 token 与 epoch。
  Future<CashierKdsLeaseResult> renewLease({
    required int authorityEpoch,
    required String leaseToken,
    String? clientVersion,
  }) {
    return _lease(
      CashierKdsLeaseRequest(
        action: 'RENEW',
        authorityEpoch: authorityEpoch,
        leaseToken: leaseToken,
        clientVersion: clientVersion,
      ),
    );
  }

  Future<CashierKdsLeaseResult> _lease(CashierKdsLeaseRequest request) async {
    final response = await client.post(
      cashierKdsAuthorityLeaseEndpoint,
      body: request.toJson(),
      headers: _identityHeaders,
    );
    final result = CashierKdsLeaseResult.fromJson(_dataMap(response));
    // 成功后同步本地权威身份，供后续请求头使用。
    authorityEpoch = result.authorityEpoch;
    leaseToken = result.leaseToken;
    return result;
  }

  /// 分页重建当前门店活跃厨房订单（新设备/磁盘恢复/接管/cursor 过期）。
  ///
  /// 首次请求不传 [nextPageToken]；响应固定 [CashierKdsBootstrapResult.baseCursor]。
  /// 全部页面提交 SQLite 后，以 afterCursor=baseCursor 追赶增量。
  Future<CashierKdsBootstrapResult> bootstrap({
    String? nextPageToken,
    int limit = 100,
  }) async {
    final response = await client.get(
      cashierKdsDeliveryBootstrapEndpoint,
      query: {
        if (nextPageToken != null && nextPageToken.isNotEmpty)
          'nextPageToken': nextPageToken,
        'limit': limit,
      },
      headers: _identityHeaders,
    );
    return CashierKdsBootstrapResult.fromJson(_dataMap(response));
  }

  /// 按持久 cursor 拉取厨房投递事件（至少一次返回，事件可能重复）。
  ///
  /// 客户端必须按 eventId 与 projectionVersion 幂等；只有 SQLite Inbox、
  /// 订单投影、LAN Outbox 与 checkpoint 在同一事务提交后，才能推进 cursor
  /// 并调用 [ack]。
  Future<CashierKdsEventsResult> fetchEvents({
    required int afterCursor,
    int limit = 100,
  }) async {
    final response = await client.get(
      cashierKdsDeliveryEventsEndpoint,
      query: {'afterCursor': afterCursor, 'limit': limit},
      headers: _identityHeaders,
    );
    return CashierKdsEventsResult.fromJson(_dataMap(response));
  }

  /// 获取当前营业时段完整订单快照（open_time/close_time 动态窗口）。
  Future<CashierKdsBusinessDayOrdersResult> businessDayOrders({
    String? cursor,
    int limit = 200,
  }) async {
    final response = await client.get(
      cashierKdsDeliveryBusinessDayOrdersEndpoint,
      query: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
      },
      headers: _identityHeaders,
    );
    return CashierKdsBusinessDayOrdersResult.fromJson(_dataMap(response));
  }

  /// 分页回填营业时间内全量订单及厨房完成状态（不生成投递事件、不推进 ACK）。
  Future<CashierKdsBusinessDayDetailResult> businessDayOrdersDetail({
    String? cursor,
    int limit = 200,
  }) async {
    final response = await client.get(
      cashierKdsDeliveryBusinessDayOrdersDetailEndpoint,
      query: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': limit,
      },
      headers: _identityHeaders,
    );
    return CashierKdsBusinessDayDetailResult.fromJson(_dataMap(response));
  }

  /// 获取单笔正式订单的最新完整厨房投影（无副作用；404 表示不存在/非本店）。
  Future<CashierKdsOrderProjection> orderProjection({
    required int orderId,
  }) async {
    final response = await client.get(
      cashierKdsOrderProjectionEndpoint.withPathParams({'orderId': '$orderId'}),
      headers: _identityHeaders,
    );
    return CashierKdsOrderProjection.fromJson(_dataMap(response));
  }

  /// 累计确认已事务落地的投递 cursor（throughCursor 必须在本地事务提交后上报）。
  Future<CashierKdsAckResult> ack({
    required int throughCursor,
    String? lastEventId,
    int? localCommittedAtMs,
  }) async {
    final response = await client.post(
      cashierKdsDeliveryAckEndpoint,
      body: {
        'throughCursor': throughCursor,
        if (lastEventId != null && lastEventId.isNotEmpty)
          'lastEventId': lastEventId,
        if (localCommittedAtMs != null) 'localCommittedAtMs': localCommittedAtMs,
      },
      headers: _identityHeaders,
    );
    return CashierKdsAckResult.fromJson(_dataMap(response));
  }

  /// 查询投递通道状态（head/ack/min 游标、lag、authority 在线情况）。
  Future<CashierKdsDeliveryStatusResult> deliveryStatus() async {
    final response = await client.get(
      cashierKdsDeliveryStatusEndpoint,
      headers: _identityHeaders,
    );
    return CashierKdsDeliveryStatusResult.fromJson(_dataMap(response));
  }

  static Map<String, Object?> _dataMap(Object? value) {
    final map = value is Map ? value.cast<String, Object?>() : const <String, Object?>{};
    // client 已解包 data；兼容未解包（顶层含 data 字段）场景。
    if (map['data'] is Map) return map['data'] as Map<String, Object?>;
    return map;
  }
}
