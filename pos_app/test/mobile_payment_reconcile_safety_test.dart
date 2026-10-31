import 'package:admin_panel_flutter/src/features/mobile/presentation/payment_reconcile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentReconcilePage Safety Guard (POS-SDC-001)', () {
    testWidgets('production mode blocks mock financial numbers and shows upgrade view', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaymentReconcilePage(isDemoMode: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收款对账商用化升级中'), findsOneWidget);
      expect(find.textContaining('生产环境暂不展示模拟财务数据'), findsOneWidget);

      // Crucial: Must NOT leak ungrounded mock financial amounts
      expect(find.text('¥8,642.00'), findsNothing);
      expect(find.text('¥8,618.00'), findsNothing);
      expect(find.text('已对平'), findsNothing);
    });

    testWidgets('demo mode displays explicit demo watermark and avoids fake "已对平" claims', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaymentReconcilePage(isDemoMode: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reconcile-demo-banner')), findsOneWidget);
      expect(find.textContaining('【演示环境】当前为静态样例数据'), findsOneWidget);

      // Must NOT claim "已对平" without real third-party channel reconciliation
      expect(find.text('已对平'), findsNothing);
      expect(find.text('内部试算'), findsNWidgets(2));
    });
  });
}
