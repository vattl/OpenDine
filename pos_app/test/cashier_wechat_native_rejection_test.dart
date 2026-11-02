import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/wechat_native_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testOrder = PosOrder(
    id: 1,
    orderNo: 'ORD202610189999',
    tableNumber: 'B02',
    diners: 2,
    total: 158.00,
    grossAmount: 158.00,
    createdAt: DateTime(2026, 10, 18, 12, 30),
    lines: const [],
  );

  testWidgets('WechatNativeCheckoutDialog displays explicit rejection on code 40231', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WechatNativeCheckoutDialog(
            order: testOrder,
            createOrder: () async {
              throw const CashierWechatNativeException(
                code: 40231,
                message: '微信支付商户通道明确拒绝：商户号受限或风控阻断',
                wechatCode: 'MERCHANT_RESTRICTED',
              );
            },
            queryOrder: () async => throw UnimplementedError(),
            closeOrder: () async => throw UnimplementedError(),
          ),
        ),
      ),
    );

    // Pump to complete initial request
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify rejection title and guide are visible
    expect(find.text('微信下单明确拒绝 (code: 40231)'), findsOneWidget);
    expect(find.textContaining('微信支付商户通道明确拒绝'), findsOneWidget);

    // Verify retry button is NOT visible
    expect(find.widgetWithText(ElevatedButton, '重试出码'), findsNothing);

    // Verify change channel button is visible
    expect(find.text('返回并改用其他渠道'), findsOneWidget);
  });
}
