import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_detail_pages.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/table_order_page.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeApprovalRepository implements AccessApprovalRepository {
  _FakeApprovalRepository()
    : client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: FakeHttpTransport(const {}),
        token: 'fake-token',
      );

  @override
  final AdminApiClient client;

  @override
  Future<CashierApprovalGrant> authorize({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    required String authorizerAccount,
    required String credential,
    String authMethod = 'PASSWORD',
    String? requestId,
    String? terminalId,
  }) async {
    return CashierApprovalGrant(
      approvalNo: 'APP-2026-TEST',
      approvalToken: 'fake-approval-token',
      permission: permission,
      operatorId: 1,
      authorizerId: 9,
      authorizerName: authorizerAccount,
      shopId: 1,
      expireSeconds: 120,
    );
  }

  @override
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async {
    return const AccessApprovalPage();
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async => null;

  @override
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async =>
      const [];

  @override
  Future<CashierQrApprovalRequest> createQrApproval({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    String? requestId,
    String? terminalId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalStatus> pollQrApprovalStatus(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalDetails> loadQrApprovalDetails(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalConfirmResult> confirmQrApproval({
    required String approvalCode,
    required String action,
    String? rejectReason,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierAccessEvaluation> evaluate({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async => const CashierAccessEvaluation(
    allow: true,
    approvalRequired: false,
    outcome: AuthorizationOutcome.allow,
  );
}

class _FakeBillRepo implements CashierBillRepository {
  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    return CashierBillResult(
      bills: [
        CashierBill.fromJson({
          'id': 1,
          'order_no': 'A00012122',
          'table_number': '40',
          'transac_status': 'success',
          'sett_amount': 400.0,
          'pay_amount_wechat': 400.0,
          'order_type': '堂食',
        }),
      ],
      total: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepo implements CashierSettingsRepository {
  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async =>
      const CashierSettingsOverview(
        shopId: 1,
        modules: [
          CashierSettingsModule(
            module: 'store',
            permission: '',
            permitted: true,
            source: 'SYSTEM',
            summary: '基础资料',
            alerts: 0,
          ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePaymentRepo implements CashierPaymentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  Future<PosWorkspace> loadWorkspace(DiningTable table) async {
    return PosWorkspace(
      table: table,
      categories: const [],
      dishes: const [],
      currentOrder: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Dark mode visual adaptation tests', () {
    testWidgets(
      'CashierBillPage table header uses dark background and light text in dark mode',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: CashierAppTheme.light(),
            darkTheme: CashierAppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: CashierBillPage(
              repository: _FakeBillRepo(),
              approvalRepository: _FakeApprovalRepository(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final headerTitleText = tester.widget<Text>(find.text('账单号'));
        expect(headerTitleText.style?.color, const Color(0xfff2f2f2));

        final headerContainer = tester.widget<Container>(
          find.ancestor(
            of: find.text('账单号'),
            matching: find.byType(Container),
          ).first,
        );
        final decoration = headerContainer.decoration as BoxDecoration?;
        expect(decoration?.color, const Color(0xff1f1f1f));
      },
    );

    testWidgets(
      'CashierSettingsPage root and tiles adapt to dark mode with high contrast',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: CashierAppTheme.light(),
            darkTheme: CashierAppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: Scaffold(
              body: CashierSettingsPage(
                repository: _FakeSettingsRepo(),
                paymentRepository: _FakePaymentRepo(),
                storeName: '西湖测试店',
                kdsAvailable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final coloredBoxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
        expect(coloredBoxes.any((box) => box.color == const Color(0xff232323)), isTrue);

        final storeText = tester.widget<Text>(find.text('店铺信息'));
        expect(storeText.style?.color, const Color(0xfff2f2f2));

        final icon = tester.widget<Icon>(find.byIcon(Icons.storefront_outlined));
        expect(icon.color, const Color(0xfff2f2f2));
      },
    );

    testWidgets(
      'SettingsDetailPage top bar and navigation items adapt to dark mode',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: CashierAppTheme.light(),
            darkTheme: CashierAppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: Scaffold(
              body: SettingsDetailPage(
                repository: _FakeSettingsRepo(),
                paymentRepository: _FakePaymentRepo(),
                destination: SettingsDestination.store,
                storeName: '西湖测试店',
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final containers = tester.widgetList<Container>(find.byType(Container));
        expect(
          containers.any((c) => (c.decoration as BoxDecoration?)?.color == const Color(0xff2d2d2d)),
          isTrue,
        );

        final materials = tester.widgetList<Material>(find.byType(Material));
        expect(
          materials.any((m) => m.color == const Color(0xff1e3a5f)),
          isTrue,
        );
      },
    );

    testWidgets(
      'TableOrderPage uses dark canvas in dark mode',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: CashierAppTheme.light(),
            darkTheme: CashierAppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: TableOrderPage(
              table: const DiningTable(
                id: 1,
                number: '01',
                people: 4,
                status: TableStatus.pending,
              ),
              repository: _FakePosRepo(),
              approvalRepository: _FakeApprovalRepository(),
            ),
          ),
        );
        await tester.pump();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, const Color(0xff232323));
      },
    );
  });
}
