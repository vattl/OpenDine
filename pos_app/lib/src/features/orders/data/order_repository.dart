import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../domain/admin_order.dart';
import '../domain/order_query.dart';

abstract class OrderRepository {
  Future<PagedOrders> listOrders(OrderQuery query, {required int shopId});

  Future<AdminOrder> loadOrderDetails(AdminOrder order);

  Future<PagedOrders> loadPhoneHistory(String phone, {required int shopId});

  Future<Object?> printReceipt(AdminOrder order);

  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  });

  Future<Object?> repushKdsTicket(AdminOrder order);

  Future<Object?> loadTakeoutDelivery(AdminOrder order);

  Future<void> refundLine(OrderLine line);

  Future<void> updateLineQuantity(OrderLine line, int quantity);

  Future<void> refundWechat(
    AdminOrder order, {
    required double amount,
    required String reason,
  });

  /// 删除订单（仅超级管理员）：服务端要求现场敏感操作授权，
  /// 优先携带 [approvalToken]（POST /cashier/access/authorize 签发），
  /// 否则回退 [account]/[password] 旧式现场授权。
  Future<void> deleteOrder(
    AdminOrder order, {
    String? account,
    String? password,
    String? approvalToken,
  });

  Future<AdminOrder> refundNormalLines(AdminOrder order);

  Future<AdminOrder> reprintKitchenTicket(AdminOrder order);
}
