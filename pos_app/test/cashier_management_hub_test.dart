import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_detail_pages.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/printing_template_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_management_hub_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/domain/cashier_payment_config.dart';

class _FakeSettingsRepo implements CashierSettingsRepository {
  bool saveStoreSettingsCalled = false;
  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async =>
      const CashierSettingsOverview(shopId: 1, modules: []);

  @override
  Future<CashierBusinessSettings> loadBusinessSettings() async =>
      const CashierBusinessSettings(isOpen: true, isReviewed: true, shopId: 1);

  @override
  Future<CashierBusinessSettings> changeBusinessStatus(bool open, {bool force = false,
  }) async =>
      CashierBusinessSettings(isOpen: open, isReviewed: true, shopId: 1);

  @override
  Future<CashierStoreSettings> loadStoreSettings() async =>
      const CashierStoreSettings(
        module: 'store',
        source: 'SHOP',
        version: 1,
        basic: {
          'name': '老肥油边王（太原街旗舰店）',
          'code': 'SHOP_TYJ_001',
          'phone': '024-88992211',
          'address': '沈阳市太原街万达广场',
        },
        businessHours: [],
        businessDays: [1, 2, 3, 4, 5, 6, 7],
      );

  @override
  Future<ShopTakeoutConfig> loadTakeoutConfig() async =>
      const ShopTakeoutConfig(
        shopId: 1,
        enabled: 1,
        deliveryFee: 5.0,
        minOrderAmount: 30.0,
      );

  @override
  Future<ShopTakeoutConfig> saveTakeoutConfig(ShopTakeoutConfig config) async => config;

  @override
  Future<PagedCashierAccessEmployees> loadAccessEmployees({String keyword = '', int page = 1, int pageSize = 20,
  }) async =>
      const PagedCashierAccessEmployees(
        page: 1,
        pageSize: 20,
        total: 1,
        items: [
          CashierAccessEmployee(
            adminId: 1,
            userName: 'cashier01',
            displayName: '张晓峰',
            workNo: '0801',
            jobTitle: '资深收银员',
          ),
        ],
      );

  @override
  Future<List<CashierAccessPolicy>> loadAccessPolicies({String? permissionCode,
  }) async => const [];

  @override
  Future<List<PrintingTemplate>> loadPrintingTemplates({String? scenario, String? paperSize,
  }) async => const [];

  @override
  Future<List<CashierAccessAuditEntry>> loadAccessAudit({int page = 1, int pageSize = 20,
  }) async =>
      [
        CashierAccessAuditEntry(
          id: 1,
          title: '整单折扣',
          module: '收银',
          action: '折扣',
          detail: '整单让利 9 折，折扣金额 ¥32.00',
          time: DateTime(2026, 10, 28, 12, 0),
        ),
      ];

  @override
  Future<CashierSettingsSectionData> loadSettingsSection({required String module, required String section, int page = 1, int pageSize = 20,
  }) async {
    if (module == 'kds' && section == 'terminals') {
      return const CashierSettingsSectionData(
        raw: {},
        items: [
          {
            'code': 'KDS_01',
            'name': '热烤主档口屏幕',
            'ip': '192.168.1.102',
            'category_scope': '油边 / 烤串',
            'status': '在线',
          },
        ],
        total: 1,
        page: 1,
        pageSize: 20,
        source: 'SHOP',
        version: null,
      );
    }
    if (module == 'printer' && section == 'devices') {
      return const CashierSettingsSectionData(
        raw: {},
        items: [
          {
            'name': '前台 80mm 主收银打印机',
            'interface': 'USB + 局域网',
            'paper_size': '80 mm',
            'role': '结账小票',
            'features': '自动切纸',
            'status': '正常就绪',
          },
        ],
        total: 1,
        page: 1,
        pageSize: 20,
        source: 'SHOP',
        version: null,
      );
    }
    return const CashierSettingsSectionData(raw: {}, items: [], total: 0, page: 1, pageSize: 20, source: 'SHOP', version: null,
    );
  }

  @override
  Future<CashierStoreSettings> saveStoreSettings({
    required int version,
    Map<String, Object?>? basic,
    List<Map<String, Object?>>? businessHours,
    List<int>? businessDays,
  }) async {
    saveStoreSettingsCalled = true;
    return CashierStoreSettings(
      module: 'store',
      source: 'SHOP',
      version: version,
      basic: basic ?? {},
      businessHours: businessHours ?? [],
      businessDays: businessDays ?? [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePaymentRepo implements CashierPaymentRepository {
  @override
  Future<PaymentMerchantCollection> loadMerchants(PaymentChannel channel) async => const PaymentMerchantCollection();
  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async =>
      const CashierPaymentCapabilities(
        targetShopId: 1,
        cashier: PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          alipay: true,
          balance: true,
        ),
      );

  @override
  Future<CashierPaymentCapabilities> saveCapabilities(CashierPaymentCapabilities capabilities,
  ) async => capabilities;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('management preserves initial dirty detail across the compact breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CashierManagementHubPage(
      repository: _FakeSettingsRepo(), paymentRepository: _FakePaymentRepo(),
      storeName: '测试门店', kdsAvailable: true,
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '老肥油边王（太原街旗舰店）'), '跨尺寸未保存');
    await tester.binding.setSurfaceSize(const Size(800, 768));
    await tester.pumpAndSettle();
    expect(find.text('跨尺寸未保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('跨尺寸未保存'), findsOneWidget);
    });

  testWidgets('retained inactive settings do not intercept navigation back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigation = GlobalKey<NavigatorState>();
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    final repository = _FakeSettingsRepo();
    final payment = _FakePaymentRepo();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigation, home: const Scaffold(body: Text('根页面'))));
    navigation.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body:
      ValueListenableBuilder<bool>(valueListenable: active, builder: (_, enabled, child) => Stack(children: [
        const Text('当前业务页面'), Offstage(offstage: !enabled, child: TickerMode(enabled: enabled, child: child!)),
      ]), child: CashierManagementHubPage(repository: repository, paymentRepository: payment, storeName: '门店', kdsAvailable: true)))));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '老肥油边王（太原街旗舰店）'), '隐藏未保存');
    active.value = false;
    await tester.pumpAndSettle();
    await navigation.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('根页面'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('payment capability changes are preserved when leaving is cancelled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CashierManagementHubPage(
      repository: _FakeSettingsRepo(), paymentRepository: _FakePaymentRepo(),
      storeName: '测试门店', kdsAvailable: true, initialDestination: SettingsDestination.payment,
    ))));
    await tester.pumpAndSettle();
    final switchFinder = find.byType(SwitchListTile).first;
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.tap(find.byKey(const Key('manage-nav-store')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
  });

  testWidgets('settings system back opens only one unsaved changes dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashierSettingsPage(
            repository: _FakeSettingsRepo(),
            paymentRepository: _FakePaymentRepo(),
            storeName: '测试门店',
            kdsAvailable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '老肥油边王（太原街旗舰店）'),
      '未保存',
    );
    final context = tester.element(find.byType(SettingsDetailPage));
    await Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('未保存'), findsOneWidget);
  });

  testWidgets(
    'management exposes all destinations and shares settings sections',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeSettingsRepo();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashierManagementHubPage(
            repository: repository,
            paymentRepository: _FakePaymentRepo(),
            storeName: '测试门店',
              kdsAvailable: true,
              permissions: const {'admin:super'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('15 模块'), findsOneWidget);
      expect(find.byType(SettingsDetailPage), findsOneWidget);
      for (final destination in SettingsDestination.values) {
        final id = destination == SettingsDestination.apiConsole
            ? 'api-console'
            : destination.name;
        expect(find.byKey(Key('manage-nav-$id')), findsOneWidget);
      }
      expect(
        find.byKey(const Key('settings-section-business-day')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-section-notice')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('manage-module-search')),
        '优惠券',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manage-nav-coupon')), findsOneWidget);
      expect(find.byKey(const Key('manage-nav-store')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'management preserves dirty store input when module switch is cancelled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierManagementHubPage(
              repository: _FakeSettingsRepo(),
              paymentRepository: _FakePaymentRepo(),
              storeName: '测试门店',
            kdsAvailable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '老肥油边王（太原街旗舰店）'),
        '修改未保存',
      );
      await tester.tap(find.byKey(const Key('manage-nav-delivery')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('修改未保存'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-section-notice')), findsOneWidget);
    expect(find.text('修改未保存'), findsOneWidget);
  },
  );
}
