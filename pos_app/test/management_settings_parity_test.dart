import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_management_hub_page.dart';

class _OverviewRepository extends Fake implements CashierSettingsRepository {
  _OverviewRepository(this.overview);

  final CashierSettingsOverview overview;

  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async => overview;
}

class _PaymentRepository extends Fake implements CashierPaymentRepository {}

void main() {
  testWidgets(
    'management navigation uses the shared 15 destination catalogue and permissions',
    (tester) async {
      final repository = _OverviewRepository(
        const CashierSettingsOverview(
          shopId: 7,
          modules: [
            CashierSettingsModule(
              module: 'payment',
              permission: 'payment:view',
              permitted: false,
              source: 'SHOP',
              summary: '不可见',
              alerts: 0,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierManagementHubPage(
              repository: repository,
              paymentRepository: _PaymentRepository(),
              storeName: '测试店',
              kdsAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('12 模块'), findsOneWidget);
      expect(find.byKey(const Key('manage-nav-coupon')), findsOneWidget);
      expect(find.byKey(const Key('manage-nav-version')), findsNothing);
      expect(find.byKey(const Key('manage-nav-api-console')), findsOneWidget);
      expect(find.byKey(const Key('manage-nav-payment')), findsNothing);
    },
  );
}
