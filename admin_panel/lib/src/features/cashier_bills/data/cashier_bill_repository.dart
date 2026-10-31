import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../domain/cashier_bill.dart';

class CashierBillResult {
  const CashierBillResult({
    required this.bills,
    required this.total,
    this.summary = const CashierBillSummary(),
  });

  final List<CashierBill> bills;
  final int total;
  final CashierBillSummary summary;
}

abstract class CashierBillRepository {
  Future<CashierBillResult> loadBills(CashierBillQuery query);

  Future<CashierBillSummary> loadSummary();

  Future<CashierBill> loadBillDetail(CashierBill bill);

  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  });

  Future<void> printKitchen({
    required String orderNo,
    List<String> categoryIds = const [],
  });

  /// 账单打印（结账状态约束）：已结账传 `checkout`（结账单），
  /// 未结账传 `pre_checkout`（预结单）；服务端对结账单强校验
  /// `transac_status = 'success'`，未结账打印结账单返回 400 ORDER_NOT_CHECKED_OUT。
  Future<void> printReceipt({
    required String orderNo,
    int? orderId,
    String scenario = 'checkout',
  });

  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  });

  Future<void> deleteBill(
    CashierBill bill, {
    String? account,
    String? password,
    String? approvalToken,
  });

  /// 校验管理账号密码（调用 POST /adminLogin），用于高危操作二次验证。
  Future<void> verifyPassword({
    required String username,
    required String password,
  });

  Future<void> refundOrder({
    required String orderNo,
    String? transactionId,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  });

  /// 现金/组合支付订单的人工退款（POST /cashier/order/refund，v1.2.211）。
  Future<void> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  });

  /// UI061: 申请生成电子发票二维码（POST /admin/order/invoice/qrcode）
  Future<CashierInvoiceResult> createInvoiceQrcode({
    required String orderNo,
    String? tableNumber,
    double? invoiceAmount,
    double? taxRate,
  });

  /// UI061: 查询电子发票状态与开具明细（GET /admin/order/invoice/status/{orderNo}）
  Future<CashierInvoiceDetails> loadInvoiceStatus(String orderNo);

  /// UI061: 获取全流程细粒度审计日志追踪时间线（GET /admin/order/audit-timeline/{orderNo}）
  Future<CashierAuditTimeline> loadAuditTimeline(String orderNo);
}
