import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/unified_print_models.dart';

/// 统一出票与补打调度服务封装
class UnifiedPrintService {
  const UnifiedPrintService(this.client);

  final AdminApiClient client;

  /// 统一出票调度
  /// [isAdmin] 为 true 时走管理端 `/admin/printing/dispatch`，否则走收银端 `/cashier/print/dispatch`
  Future<UnifiedPrintResult> dispatch(
    UnifiedPrintRequest request, {
    bool isAdmin = false,
  }) async {
    final endpoint =
        isAdmin ? adminPrintDispatchEndpoint : cashierPrintDispatchEndpoint;
    final response = await client.post(
      endpoint,
      body: request.toJson(),
    );

    final map = _asMap(response);
    final data = (map['data'] is Map<String, dynamic>)
        ? map['data'] as Map<String, dynamic>
        : (map['data'] is Map)
        ? (map['data'] as Map).cast<String, dynamic>()
        : map;

    return UnifiedPrintResult.fromJson(data);
  }

  /// 极简补打厨房单
  Future<UnifiedPrintResult> reprintKitchenOrder({
    required String orderNo,
    int? orderId,
    List<int> cidList = const [],
    String? reason,
    int? deviceId,
    int? copies,
    bool isAdmin = false,
  }) {
    return dispatch(
      UnifiedPrintRequest(
        orderNo: orderNo,
        orderId: orderId,
        scenario: UnifiedPrintScenario.kitchen,
        isReprint: true,
        cidList: cidList,
        reason: reason,
        deviceId: deviceId,
        copies: copies,
      ),
      isAdmin: isAdmin,
    );
  }

  /// 重印结账收据 / 账单
  Future<UnifiedPrintResult> reprintReceipt({
    String? orderNo,
    int? orderId,
    bool preCheckout = false,
    int? deviceId,
    int? copies,
    bool isAdmin = false,
  }) {
    return dispatch(
      UnifiedPrintRequest(
        orderNo: orderNo,
        orderId: orderId,
        scenario: preCheckout
            ? UnifiedPrintScenario.preCheckout
            : UnifiedPrintScenario.checkout,
        isReprint: true,
        deviceId: deviceId,
        copies: copies,
      ),
      isAdmin: isAdmin,
    );
  }

  /// 补打交接班小票
  Future<UnifiedPrintResult> reprintShiftTicket({
    required int shiftId,
    int? deviceId,
    int? copies,
    bool isAdmin = false,
  }) {
    return dispatch(
      UnifiedPrintRequest(
        scenario: UnifiedPrintScenario.shift,
        shiftId: shiftId,
        isReprint: true,
        deviceId: deviceId,
        copies: copies,
      ),
      isAdmin: isAdmin,
    );
  }

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return const {};
  }
}
