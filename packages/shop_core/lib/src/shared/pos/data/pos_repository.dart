import '../../tables/domain/dining_table.dart';
import '../domain/pos_models.dart';

class LocalKdsPersistenceException implements Exception {
  const LocalKdsPersistenceException({
    required this.cloudOrderId,
    required this.cloudOrderNo,
    required this.cause,
  });

  final int cloudOrderId;
  final String cloudOrderNo;
  final Object cause;

  @override
  String toString() => '云端订单 $cloudOrderNo 已创建成功，但本地 KDS 推送失败，请勿重复下单。原因：$cause';
}

abstract class PosRepository {
  Future<PosWorkspace> loadWorkspace(DiningTable table);

  Future<PosSubmissionResult> submitOrder({
    required String tableNumber,
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  });

  /// 打包下单：免桌台（tableNumber=打包）、dineInOrTakeOut=打包，
  /// 后端不校验桌号并按打包计费（与 /cashier/order/quickOrder 打包语义对齐）。
  Future<PosSubmissionResult> submitPickupOrder({
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  });

  Future<void> addDishes({
    required String orderNo,
    required String tableNumber,
    required List<PosCartLine> lines,
  });

  /// 退菜（POST /cashier/order/refundDish）。
  /// 后端要求现场敏感操作授权，新契约支持「审批令牌优先、现场账号密码兜底」：
  /// - [approvalToken]（/cashier/access/authorize 或扫码授权签发，120 秒单次强绑定）优先；
  /// - 未携带令牌时请求体带 authorization {account, password}
  ///   （授权员工须具备 order:operate:refund 且可访问当前门店）。
  /// [expectedVersion] 为订单 revision 乐观锁（省略保持兼容；409 冲突时审批令牌不消费）。
  /// 授权字段全空时不携带（旧调用方兼容）。
  Future<void> refundDish({
    required String orderNo,
    required int detailId,
    required int quantity,
    PosRefundStockAction stockAction = PosRefundStockAction.restore,
    String reason = '',
    String remark = '',
    String approvalToken = '',
    String account = '',
    String password = '',
    int expectedVersion = -1,
  });

  Future<void> giftDish({required String orderNo, required int detailId});

  /// 整单优惠，三种方式至少传一项（与后端 /cashier/order/discount 对齐）：
  /// - [discountAmount]：固定优惠金额（元），直接指定减免；
  /// - [payRate]：快速折扣实付倍率，如 0.9 = 9 折（优惠 = 原价 × (1-rate)）；
  /// - [wipeZero]：抹零，应付抹到整数元（优惠增加小数部分）。
  /// 后端 required authorization（SensitiveOperationAuthorization），
  /// 新契约支持审批令牌优先（[approvalToken]）；[expectedVersion] 为订单 revision
  /// 乐观锁（409 版本冲突时审批令牌不消费）。授权字段全空时不携带（旧调用方兼容）。
  Future<void> discountOrder({
    required String orderNo,
    double? discountAmount,
    double? payRate,
    bool? wipeZero,
    required String reason,
    String approvalToken = '',
    String account = '',
    String password = '',
    int expectedVersion = -1,
  });

  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
  });

  /// 反结账（按当前门店锁定订单并在事务内恢复为未结账）。
  ///
  /// 服务端幂等：重复调用不会重复入账。含现金/微信或支付宝临时收款码
  /// 实收的订单（含组合支付）由服务端拒绝，需先线下退款与账务核对。
  /// 原结账含余额分项时，按本金/赠送金分别退回钱包；桌台恢复 status=1。
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
  });

  Future<void> openTable(String tableNumber);

  Future<void> mergeTables({
    required String sourceTableNumber,
    required String targetTableNumber,
  });

  Future<void> transferTable({
    required String orderNo,
    required String targetTableNumber,
  });

  Future<void> clearTable(String tableNumber);

  /// 挂单（POST /cashier/order/hang）：未结账订单暂存，继续服务下一位顾客。
  Future<void> hangOrder({
    required String orderNo,
    String reason = '',
  });

  /// 取单/解挂（POST /cashier/order/unhang）：恢复挂起订单进入结算。
  Future<void> unhangOrder({required String orderNo});

  /// 当前门店挂单池（GET /cashier/order/hang-list）：按挂单时间升序。
  Future<HangListResult> loadHangList();

  /// 修改订单用餐人数（POST /cashier/order/updateDiners，1~999 人）。
  Future<void> updateOrderDiners({
    required String orderNo,
    required int diners,
  });

  /// 整桌结账（POST /cashier/table/checkout）：一键结清该桌全部未结订单。
  Future<TableCheckoutResult> checkoutTable({
    required String tableNumber,
    String paymentMethod = 'cash',
    double? cashAmount,
    String? idempotencyKey,
  });

  /// 桌台状态图（GET /cashier/table/statusMap）：桌号 -> status。
  Future<TableStatusMap> loadTableStatusMap();
}

abstract interface class PosCashCheckoutRepository {
  Future<void> checkoutCash({
    required String orderNo,
    required String paymentMethod,
    required PosCashSettlement settlement,
  });
}

abstract interface class PosPickupOrderRepository {
  Future<PosSubmissionResult> submitPickupOrder({
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  });
}

abstract interface class PosOrderKdsRebuildRepository {
  Future<PosSubmissionResult> loadOrderForLocalKds(int orderId);
}

class PosSubmissionRequestIdState {
  PosSubmissionRequestIdState(this._generate);

  final String Function() _generate;
  String? _fingerprint;
  String? _requestId;

  String forFingerprint(String fingerprint) {
    if (_requestId == null || _fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _requestId = _generate();
    }
    return _requestId!;
  }

  void markSucceeded() {
    _fingerprint = null;
    _requestId = null;
  }
}

abstract interface class PosOfflineCollectionRepository {
  Future<PosOfflineCollectionQr> createOfflineCollectionQr({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  });

  Future<void> confirmOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  });

  Future<void> cancelOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
  });

  Future<bool> checkOrderSettled(String orderNo);
}

abstract interface class PosBalanceCheckoutRepository {
  Future<void> checkoutByBalance({
    required String orderNo,
    required String openid,
    required String memberPhone,
  });
}

abstract interface class PosCombinedCheckoutRepository {
  Future<void> checkoutCombined({
    required String orderNo,
    required PosCheckoutSettlement settlement,
    String memberOpenid = '',
    String memberPhone = '',
    String collectionSessionId = '',
  });
}

abstract interface class PosOrderPrintRepository {
  Future<PosPrintResult> printCheckoutReceipt({
    required int orderId,
    String? orderNo,
  });

  Future<void> printServeTicket({
    required int orderId,
    int? detailId,
    int? quantity,
    List<Map<String, Object?>>? lines,
  });
}
