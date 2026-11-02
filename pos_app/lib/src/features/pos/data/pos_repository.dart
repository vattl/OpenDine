import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../../tables/domain/dining_table.dart';
import '../domain/hang_order_models.dart';
import '../domain/pos_models.dart';

export '../domain/hang_order_models.dart';

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

class CashierWechatNativeException implements Exception {
  const CashierWechatNativeException({
    required this.code,
    required this.message,
    this.wechatCode,
    this.requestId,
  });

  final int code;
  final String message;
  final String? wechatCode;
  final String? requestId;

  bool get isConflictOrPending => code == 40931;
  bool get isOrderAlreadyPaid => code == 40934;
  bool get isUncertainNeedQuery => code == 50331;
  bool get isPaidCannotClose => code == 40933;
  bool get isExplicitRejection => code == 40231;

  @override
  String toString() => message;
}

class CashierReceivableException implements Exception {
  const CashierReceivableException({
    required this.code,
    required this.message,
  });

  final int code;
  final String message;

  bool get isAccountLimitExceeded => code == 422;
  bool get isStateConflict => code == 409;
  bool get isPermissionDenied => code == 403;

  @override
  String toString() => message;
}

class CashierWechatMicropayException implements Exception {
  const CashierWechatMicropayException({
    required this.code,
    required this.message,
  });

  final int code;
  final String message;

  bool get isCodeFormatInvalid => code == 40031;
  bool get isConflictOrPending => code == 40941;
  bool get isLocalSettlementPending => code == 40942;
  bool get isOrderAlreadyPaidCannotReverse => code == 40943;
  bool get isNotMatured15s => code == 40944;
  bool get isWechatPayDenied => code == 40241;
  bool get isUncertainNeedQuery => code == 50341;
  bool get isReverseUncertain => code == 50343;

  @override
  String toString() => message;
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

  Future<int?> addDishes({
    required String orderNo,
    required String tableNumber,
    required List<PosCartLine> lines,
    String? clientRequestId,
    int? expectedVersion,
  });

  Future<int?> refundDish({
    required String orderNo,
    required int detailId,
    required int quantity,
    PosRefundStockAction? stockAction,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  });

  /// 人工退款（线下退回现金）：已支付订单按现金渠道剩余退款，
  /// 可选 [refundAmount] 指定部分金额，[reason] 为备注追加到订单。
  Future<CashierManualRefundResult> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  });

  Future<int?> giftDish({
    required String orderNo,
    required int detailId,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  });

  Future<int?> discountOrder({
    required String orderNo,
    required double discountAmount,
    required String reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  });

  /// 修改就餐人数（POST /cashier/order/updateDiners，v1.2.297）。
  /// 支持未结账与当日已结账订单，人数必须为 1 ~ 999 之间正整数。
  Future<void> updateDiners({
    required String orderNo,
    required int diners,
  });

  /// 校验管理账号密码（调用 POST /adminLogin），用于高危操作二次验证。
  Future<void> verifyPassword({
    required String username,
    required String password,
  });

  /// 挂单：把未结订单挂起（POST /cashier/order/hang），桌台释放；
  /// 返回挂单号（服务端未返回时为 null），挂起订单可经挂单池找回继续操作。
  Future<String?> hangOrder({required String orderNo, String? reason});

  /// 取单：取回已挂起订单（POST /cashier/order/unhang），复位挂单状态准备结算。
  Future<bool> unhangOrder({required String orderNo});

  /// 获取当前门店所有挂单列表（GET /cashier/order/hang-list）。
  Future<List<HangOrderSummary>> getHangList();

  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
    bool force = false,
    String? approvalToken,
  });

  /// 反结账（按当前门店锁定订单并在事务内恢复为未结账）。
  ///
  /// 服务端幂等：重复调用不会重复入账。含现金/微信或支付宝临时收款码
  /// 实收的订单（含组合支付）由服务端拒绝，需先线下退款与账务核对。
  /// 原结账含余额分项时，按本金/赠送金分别退回钱包；桌台恢复 status=1。
  Future<void> unCheckout({required String orderNo, required String reason});

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

  Future<PosTableCheckoutResult> checkoutTable({
    required String tableNumber,
    String paymentMethod = 'cash',
    double? cashAmount,
    bool force = false,
    String? approvalToken,
  });
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
  /// 打印前台小票（前台整单 FULL_ORDER，未结账桌台可正常打印；
  /// 结账单/预结单属账单页场景，走 CashierBillRepository.printReceipt）。
  Future<PosPrintResult> printFrontTicket({
    required int orderId,
    String? orderNo,
  });
}

abstract interface class PosKitchenPrintRepository {
  Future<void> reprintKitchenTicket({required String orderNo});
}

enum PosReceiptPrintType {
  front('full_order'),
  kitchen('kitchen'),
  preCheckout('pre_checkout'),
  checkout('checkout');

  const PosReceiptPrintType(this.scenario);

  final String scenario;
}

/// 桌台明细统一票据打印能力。
///
/// 服务端仍负责校验订单状态；调用方同时根据当前桌台状态提前禁用
/// 不适用的预结单或结账单，避免无效请求和误打。
abstract interface class PosReceiptPrintRepository {
  Future<PosPrintResult> printReceiptTicket({
    required PosReceiptPrintType type,
    required int orderId,
    required String orderNo,
  });
}

abstract interface class PosPrintPreviewRepository {
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    int? deviceId,
    String paperSize = '58mm',
    bool isAddDishes = false,
    String? customContent,
  });
}

abstract interface class PosWechatNativeCheckoutRepository {
  /// 创建或复用微信 Native 动态支付二维码
  /// POST /cashier/payment/wechat/native/orders
  Future<PosWechatNativeOrder> createWechatNativeOrder({
    required String orderNo,
    String? terminalId,
  });

  /// 主动查询微信 Native 支付状态并补偿入账
  /// GET /cashier/payment/wechat/native/orders/{orderNo}
  Future<PosWechatNativeStatus> queryWechatNativeOrder({
    required String orderNo,
  });

  /// 关闭未支付的微信 Native 支付单
  /// POST /cashier/payment/wechat/native/orders/{orderNo}/close
  Future<PosWechatNativeCloseResult> closeWechatNativeOrder({
    required String orderNo,
  });
}

abstract interface class PosWechatMicropayCheckoutRepository {
  /// 扫描微信付款码发起扣款 (商家扫顾客)
  /// POST /cashier/payment/wechat/micropay/orders
  Future<PosWechatMicropayOrder> payWechatMicropay({
    required String orderNo,
    required String authCode,
    String? terminalId,
  });

  /// 主动查询微信付款码支付状态并补偿入账
  /// GET /cashier/payment/wechat/micropay/orders/{orderNo}
  Future<PosWechatMicropayStatus> queryWechatMicropayOrder({
    required String orderNo,
  });

  /// 撤销微信付款码交易 (创建满 15 秒后)
  /// POST /cashier/payment/wechat/micropay/orders/{orderNo}/reverse
  Future<PosWechatMicropayReverseResult> reverseWechatMicropayOrder({
    required String orderNo,
  });
}

/// 人工退款结果：本次退款金额、累计退款总额、订单现金渠道剩余（元）。
class CashierManualRefundResult {
  const CashierManualRefundResult({
    required this.orderNo,
    required this.refundAmount,
    required this.refundTotal,
    required this.cashRemaining,
  });

  final String orderNo;
  final double refundAmount;
  final double refundTotal;
  final double cashRemaining;

  factory CashierManualRefundResult.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;
    return CashierManualRefundResult(
      orderNo: (data['order_no'] ?? data['orderNo'] ?? '') as String,
      refundAmount: ((data['refund_amount'] ?? 0) as num).toDouble(),
      refundTotal: ((data['refund_total'] ?? 0) as num).toDouble(),
      cashRemaining: ((data['cash_remaining'] ?? 0) as num).toDouble(),
    );
  }
}

/// 客户挂账与应收回款仓库接口 (WI-023 / v1.2.298)
abstract interface class PosReceivableRepository {
  /// 查询当前门店可用于挂账的授信账户
  /// GET /cashier/receivables/eligible-accounts
  Future<List<PosReceivableEligibleAccount>> loadEligibleAccounts();

  /// 将未结订单转为应收挂账
  /// POST /cashier/receivables/charges
  Future<PosReceivableClaim> chargeReceivable({
    required String orderNo,
    required int accountId,
    required String requestId,
    String? note,
  });

  /// 查询当前门店应收单
  /// GET /cashier/receivables/claims
  Future<List<PosReceivableClaim>> loadReceivableClaims({
    int? accountId,
    String? status,
    int page = 1,
    int pageSize = 20,
  });

  /// 查询单笔应收详情
  /// GET /cashier/receivables/claims/{id}
  Future<PosReceivableClaim> loadReceivableClaimDetail(int id);

  /// 登记应收回款
  /// POST /cashier/receivables/claims/{id}/collections
  Future<PosReceivableLedger> collectReceivable({
    required int claimId,
    required int amountFen,
    required String channel,
    required String requestId,
    String? note,
    int? drawerSessionId,
  });
}
