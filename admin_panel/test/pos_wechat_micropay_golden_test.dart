import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/wechat_micropay_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture production wechat micropay dialog golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final testOrder = PosOrder(
      id: 108,
      orderNo: 'ORD202610160008',
      tableNumber: 'A08',
      diners: 2,
      total: 168.00,
      createdAt: DateTime.now(),
      lines: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: CashierAppTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1120),
          body: Center(
            child: WechatMicropayCheckoutDialog(
              order: testOrder,
              isAndroidTabletWithCameraOverride: true,
              payMicropay: (code) async => const PosWechatMicropayOrder(
                orderNo: 'ORD202610160008',
                outTradeNo: 'OUT_ORD202610160008',
                amountFen: 16800,
                status: 'USERPAYING',
                tradeState: 'USERPAYING',
              ),
              queryOrder: () async => const PosWechatMicropayStatus(
                orderNo: 'ORD202610160008',
                outTradeNo: 'OUT_ORD202610160008',
                amountFen: 16800,
                status: 'USERPAYING',
                tradeState: 'USERPAYING',
              ),
              reverseOrder: () async => const PosWechatMicropayReverseResult(reversed: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(
        '../design/prototypes/UI041-cashier-wechat-micropay/_shots/production_wechat_micropay.png',
      ),
    );
  });
}
