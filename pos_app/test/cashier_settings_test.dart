import 'package:admin_panel_flutter/src/features/cashier_settings/domain/subscribe_template.dart';
import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/crash_log.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/domain/cashier_payment_config.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_payment_config_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/real_cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/printing_template_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_printing_template_designer_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_receipt_preview_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_access_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_delivery_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_detail_pages.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_log_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_interaction_log.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('cashier settings models', () {
    test('parses business, payment method, and shift response fields', () {
      final business = CashierBusinessSettings.fromJson({
        'business': 1,
        'isReview': 'true',
        'shopId': '8',
      });
      final payment = CashierPaymentMethod.fromJson({
        'id': 3,
        'code': 'custom_pay',
        'name': '自定义支付',
        'sort_order': '12',
        'enabled': 1,
      });
      final shift = CashierSettingsShift.fromJson({
        'id': 9,
        'admin_id': 4,
        'shop_id': 8,
        'start_time': '2026-07-20T08:30:00',
        'start_cash': '200.50',
        'order_count': '6',
        'total_amount': 320,
      });

      expect(business.isOpen, isTrue);
      expect(business.isReviewed, isTrue);
      expect(business.shopId, 8);
      expect(payment.code, 'custom_pay');
      expect(payment.sortOrder, 12);
      expect(payment.enabled, isTrue);
      expect(shift.adminId, 4);
      expect(shift.orderCount, 6);
      expect(shift.startCash, 200.5);
    });

    test('takeout delivery record parses actual_delivery_fee (v1.2.279)', () {
      final record = TakeoutDeliveryRecord.fromJson({
        'order_id': 1001,
        'order_no': 'T20261009001',
        'delivery_fee': 8.0,
        'actual_delivery_fee': 5.5,
      });
      expect(record.orderId, 1001);
      expect(record.deliveryFee, 8.0);
      expect(record.actualDeliveryFee, 5.5);

      // 兼容语义别名 zsq_actual_fee。
      final alias = TakeoutDeliveryRecord.fromJson({
        'order_id': 1002,
        'delivery_fee': 8.0,
        'zsq_actual_fee': 6.2,
      });
      expect(alias.actualDeliveryFee, 6.2);

      // 缺省回退 null。
      final missing = TakeoutDeliveryRecord.fromJson({'order_id': 1003});
      expect(missing.actualDeliveryFee, isNull);
    });
  });

  test(
    'business switch sends OpenAPI bus field with current shop header',
    () async {
      final transport = FakeHttpTransport({
        'POST /cashier/shop/business': jsonEncode({'code': 0}),
        'POST /order/Business': jsonEncode({
          'code': 0,
          'business': false,
          'isReview': true,
          'shopId': 8,
        }),
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final result = await repository.changeBusinessStatus(false);

      expect(result.isOpen, isFalse);
      expect(jsonDecode(transport.requests.first.body!), {'bus': '0'});
      expect(transport.requests.first.headers['X-Shop-Id'], '8');
      expect(transport.requests.last.headers['X-Shop-Id'], '8');
    },
  );

  test('changeBusinessStatus sends force=1 when force is requested', () async {
    final transport = FakeHttpTransport({
      'POST /cashier/shop/business': jsonEncode({'code': 0}),
      'POST /order/Business': jsonEncode({
        'code': 0,
        'business': true,
        'isReview': true,
        'shopId': 8,
      }),
    });
    final repository = RealCashierSettingsRepository(
      AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 8,
      ),
    );

    final result = await repository.changeBusinessStatus(true, force: true);

    expect(result.isOpen, isTrue);
    final changeRequest = transport.requests.first;
    expect(changeRequest.uri.path, '/cashier/shop/business');
    expect(jsonDecode(changeRequest.body!), {'bus': '1', 'force': '1'});
  });

  test(
    'repository loads the production settings overview and section data',
    () async {
      final transport = FakeHttpTransport({
        'GET /admin/settings/overview': jsonEncode({
          'code': 0,
          'shopId': 8,
          'modules': [
            {
              'module': 'printing',
              'permission': 'printing:view',
              'permitted': true,
              'source': 'SHOP',
              'summary': '2 台设备',
              'alerts': 1,
            },
          ],
        }),
        'GET /admin/printing/devices': jsonEncode({
          'code': 0,
          'page': 1,
          'pageSize': 20,
          'total': 1,
          'items': [
            {
              'id': 9,
              'name': '后厨打印机',
              'transport': 'LAN',
              'status': 'ONLINE',
              'version': 3,
            },
          ],
        }),
        'POST /admin/takeout/delivery/list': jsonEncode({
          'code': 0,
          'page': 1,
          'pageSize': 20,
          'total': 0,
          'items': [],
        }),
        'GET /admin/announcement/list': jsonEncode({
          'code': 0,
          'page': 1,
          'pageSize': 20,
          'total': 1,
          'list': [
            {'id': 12, 'title': '线上新春营业公告', 'content': '正文内容', 'status': 1},
          ],
        }),
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final overview = await repository.loadSettingsOverview();
      final section = await repository.loadSettingsSection(
        module: 'printer',
        section: 'devices',
      );
      await repository.loadSettingsSection(
        module: 'delivery',
        section: 'records',
      );
      final noticeSection = await repository.loadSettingsSection(
        module: 'store',
        section: 'notice',
      );

      expect(overview.shopId, 8);
      expect(overview.modules.single.module, 'printing');
      expect(overview.modules.single.permitted, isTrue);
      expect(overview.modules.single.alerts, 1);
      expect(section.total, 1);
      expect(section.items.single['name'], '后厨打印机');
      expect(noticeSection.total, 1);
      expect(noticeSection.items.single['title'], '线上新春营业公告');
      expect(
        transport.requests.any((r) => r.uri.path == '/admin/announcement/list'),
        isTrue,
      );
      expect(transport.requests[1].uri.queryParameters, {
        'page': '1',
        'pageSize': '20',
      });
      expect(transport.requests[2].method, 'POST');
      expect(jsonDecode(transport.requests[2].body!), {
        'page': 1,
        'pageSize': 20,
      });
      expect(
        transport.requests.every(
          (request) => request.headers['X-Shop-Id'] == '8',
        ),
        isTrue,
      );
    },
  );

  test(
    'RealCashierSettingsRepository loads and manages printing templates with unwrapped responses',
    () async {
      final listResponse = jsonEncode({
        'code': 0,
        'shopId': 8,
        'templates': [
          {
            'id': 101,
            'shopId': 8,
            'templateCode': 'tpl_order_custom',
            'templateName': '招牌堂食结账单',
            'scenario': 'ORDER',
            'paperSize': '80mm',
            'isSystem': false,
            'isDefault': true,
            'version': 2,
            'templateJson':
                '{"paperSize":"80mm","scenario":"ORDER","blocks":[]}',
          },
        ],
        'data': [
          {
            'id': 101,
            'shopId': 8,
            'templateCode': 'tpl_order_custom',
            'templateName': '招牌堂食结账单',
            'scenario': 'ORDER',
            'paperSize': '80mm',
            'isSystem': false,
            'isDefault': true,
            'version': 2,
            'templateJson':
                '{"paperSize":"80mm","scenario":"ORDER","blocks":[]}',
          },
        ],
      });

      final singleResponse = jsonEncode({
        'code': 0,
        'template': {
          'id': 101,
          'shopId': 8,
          'templateCode': 'tpl_order_custom',
          'templateName': '招牌堂食结账单',
          'scenario': 'ORDER',
          'paperSize': '80mm',
          'isSystem': false,
          'isDefault': true,
          'version': 2,
          'templateJson': '{"paperSize":"80mm","scenario":"ORDER","blocks":[]}',
        },
        'data': {
          'id': 101,
          'shopId': 8,
          'templateCode': 'tpl_order_custom',
          'templateName': '招牌堂食结账单',
          'scenario': 'ORDER',
          'paperSize': '80mm',
          'isSystem': false,
          'isDefault': true,
          'version': 2,
          'templateJson': '{"paperSize":"80mm","scenario":"ORDER","blocks":[]}',
        },
        'version': 2,
      });

      final transport = FakeHttpTransport({
        'GET /admin/printing/templates/meta': jsonEncode({
          'code': 0,
          'data': {
            'scenarios': [
              {
                'code': 'PACKING',
                'name': '打包单',
                'description': '打包/到店自提订单的独立核餐凭条',
                'paperSizes': ['58mm', '80mm'],
                'allowedBlocks': ['HEADER', 'DISH_ITEMS', 'REMARK'],
              },
            ],
            'parametersByScenario': {
              'PACKING': [
                {'name': 'pickupCode', 'tag': '{取餐码}'},
              ],
            },
          },
        }),
        'GET /admin/printing/templates': listResponse,
        'GET /admin/printing/templates/101': singleResponse,
        'POST /admin/printing/templates': singleResponse,
        'PUT /admin/printing/templates/101': singleResponse,
        'DELETE /admin/printing/templates/101': jsonEncode({
          'code': 0,
          'msg': '已删除',
        }),
        'POST /admin/printing/templates/101/set-default': singleResponse,
      });

      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final meta = await repository.getPrintingTemplateMeta();
      expect(meta.scenarios.single.code, 'PACKING');
      expect(meta.scenarios.single.ruleCode, 'packing');
      expect(meta.parametersFor('PACKING').single.tag, '{取餐码}');

      final templates = await repository.loadPrintingTemplates(
        scenario: 'ORDER',
        paperSize: '80mm',
      );
      expect(templates.length, 1);
      expect(templates.first.id, 101);
      expect(templates.first.templateName, '招牌堂食结账单');
      expect(templates.first.isDefault, isTrue);

      final detail = await repository.getPrintingTemplate(101);
      expect(detail.id, 101);
      expect(detail.templateName, '招牌堂食结账单');

      final created = await repository.createPrintingTemplate(
        templateName: '招牌堂食结账单',
        scenario: 'ORDER',
        paperSize: '80mm',
      );
      expect(created.id, 101);

      final updated = await repository.updatePrintingTemplate(
        id: 101,
        version: 1,
        templateName: '招牌堂食结账单',
      );
      expect(updated.id, 101);

      final deleted = await repository.deletePrintingTemplate(101);
      expect(deleted, isTrue);

      final defaulted = await repository.setDefaultPrintingTemplate(101);
      expect(defaulted.id, 101);
    },
  );

  test(
    'store settings writes use version locking and confirmed inheritance restore',
    () async {
      final storeResponse = jsonEncode({
        'code': 0,
        'module': 'store',
        'source': 'SHOP',
        'version': 5,
        'businessHours': [
          {
            'days': [0, 1, 2, 3, 4, 5, 6],
            'open': '16:00',
            'close': '23:59',
            'enabled': true,
          },
        ],
        'businessDays': [1, 2, 3, 4, 5, 6, 0],
      });
      final transport = FakeHttpTransport({
        'PUT /admin/settings/store': storeResponse,
        'DELETE /admin/settings/store/override': storeResponse,
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final saved = await repository.saveStoreSettings(
        version: 4,
        businessHours: const [
          {
            'days': [0, 1, 2, 3, 4, 5, 6],
            'open': '16:00',
            'close': '23:59',
            'enabled': true,
          },
        ],
        businessDays: const [1, 2, 3, 4, 5, 6, 0],
      );
      final inherited = await repository.restoreStoreSettings(
        version: saved.version,
      );

      expect(saved.version, 5);
      expect(inherited.source, 'SHOP');
      expect(jsonDecode(transport.requests.first.body!), {
        'version': 4,
        'businessHours': [
          {
            'days': [0, 1, 2, 3, 4, 5, 6],
            'open': '16:00',
            'close': '23:59',
            'enabled': true,
          },
        ],
        'businessDays': [1, 2, 3, 4, 5, 6, 0],
      });
      expect(transport.requests.last.uri.queryParameters, {
        'module': 'store',
        'version': '5',
        'confirm': 'true',
      });
    },
  );

  test(
    'saveStoreSettings with basic-only payload omits business hours/days',
    () async {
      final storeResponse = jsonEncode({
        'code': 0,
        'module': 'store',
        'source': 'SHOP',
        'version': 6,
        'basic': {'shopId': 8, 'settleTime': '03:30', 'settle_time': '03:30'},
        'businessHours': <Object>[],
        'businessDays': <Object>[],
      });
      final transport = FakeHttpTransport({
        'PUT /admin/settings/store': storeResponse,
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final saved = await repository.saveStoreSettings(
        version: 5,
        basic: const {'settleTime': '03:30'},
      );

      expect(saved.basic['settleTime'], '03:30');
      final body =
          jsonDecode(transport.requests.single.body!) as Map<String, Object?>;
      expect(body['version'], 5);
      expect(body['basic'], <String, Object?>{'settleTime': '03:30'});
      expect(body.containsKey('businessHours'), isFalse);
      expect(body.containsKey('businessDays'), isFalse);
    },
  );

  test(
    'uploadOfflineCollectQr posts multipart to offline-collect upload endpoint',
    () async {
      final transport = FakeHttpTransport({
        'POST /admin/shop/offline-collect/upload': '{"code":0}',
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      await repository.uploadOfflineCollectQr(
        isWechat: true,
        bytes: [1, 2, 3, 4],
        filename: 'my_collect_qr.png',
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/admin/shop/offline-collect/upload');
      expect(request.headers['X-Shop-Id'], '8');
      expect(
        request.headers['Content-Type'],
        startsWith('multipart/form-data; boundary='),
      );
      final body = String.fromCharCodes(request.bodyBytes!);
      expect(body, contains('name="wechatQr"'));
      expect(body, contains('filename="my_collect_qr.png"'));
      expect(body, contains('Content-Type: image/png'));
      expect(request.bodyBytes!, containsAll([1, 2, 3, 4]));

      // 支付宝字段走 alipayQr，jpeg 使用 image/jpeg
      final transport2 = FakeHttpTransport({
        'POST /admin/shop/offline-collect/upload': '{"code":0}',
      });
      final repository2 = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'https://www.laofei.com.cn',
          transport: transport2,
          token: 'token',
          shopId: 8,
        ),
      );
      await repository2.uploadOfflineCollectQr(
        isWechat: false,
        bytes: [9, 8],
        filename: 'alipay.jpg',
      );
      final body2 = String.fromCharCodes(transport2.requests.single.bodyBytes!);
      expect(body2, contains('name="alipayQr"'));
      expect(body2, contains('Content-Type: image/jpeg'));
    },
  );

  group('CashierSettingsPage', () {
    testWidgets('uses production overview permissions and live section rows', (
      tester,
    ) async {
      _usePosViewport(tester);
      final repository = _FakeCashierSettingsRepository(
        overview: const CashierSettingsOverview(
          shopId: 8,
          modules: [
            CashierSettingsModule(
              module: 'printing',
              permission: 'printing:view',
              permitted: true,
              source: 'SHOP',
              summary: '2 台打印设备',
              alerts: 1,
            ),
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
        sections: const {
          'printer:devices': CashierSettingsSectionData(
            raw: {'page': 1, 'pageSize': 20, 'total': 21},
            items: [
              {
                'id': 9,
                'name': '后厨打印机',
                'transport': 'LAN',
                'status': 'ONLINE',
              },
            ],
            total: 21,
            page: 1,
            pageSize: 20,
            source: 'SHOP',
            version: null,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: repository,
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              kdsAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-tile-打印设置')), findsOneWidget);
      expect(find.textContaining('2 台打印设备'), findsOneWidget);
      expect(find.byKey(const Key('settings-tile-支付渠道')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
      await tester.pumpAndSettle();
      expect(find.text('后厨打印机'), findsOneWidget);
      expect(find.text('前台小票机'), findsNothing);
      await tester.tap(find.byKey(const Key('settings-page-next')));
      await tester.pumpAndSettle();
      expect(repository.sectionLoads, ['printer:devices', 'printer:devices']);
      expect(repository.sectionPages, [1, 2]);
    });

    testWidgets('marketing tile stays visible even when overview denies it', (
      tester,
    ) async {
      _usePosViewport(tester);
      final repository = _FakeCashierSettingsRepository(
        overview: const CashierSettingsOverview(
          shopId: 8,
          modules: [
            CashierSettingsModule(
              module: 'marketing',
              permission: 'marketing:view',
              permitted: false,
              source: 'SHOP',
              summary: '首单活动与核销',
              alerts: 0,
            ),
            CashierSettingsModule(
              module: 'payment',
              permission: 'payment:view',
              permitted: false,
              source: 'SHOP',
              summary: '支付渠道',
              alerts: 0,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: repository,
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              kdsAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 营销磁贴与 KDS/外卖一样恒显示，入口不被 overview 权限过滤。
      expect(find.byKey(const Key('settings-tile-营销活动')), findsOneWidget);
      expect(find.byKey(const Key('settings-tile-支付渠道')), findsNothing);
    });

    testWidgets('opens every Figma settings destination from the hub', (
      tester,
    ) async {
      _usePosViewport(tester);
      final repository = _FakeCashierSettingsRepository(
        payments: const [
          CashierPaymentMethod(
            id: 2,
            code: 'cash',
            name: '现金',
            sortOrder: 1,
            enabled: true,
          ),
          CashierPaymentMethod(
            id: 3,
            code: 'custom_pay',
            name: '自定义支付',
            sortOrder: 9,
            enabled: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: repository,
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              kdsAvailable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const pages = [
        '店铺信息',
        '打印设置',
        '支付渠道',
        '通知消息',
        '营销活动',
        '员工权限',
        '库存原料',
        '外卖管理',
        '数据报表',
        '日志',
      ];
      for (final page in pages) {
        expect(find.byKey(Key('settings-tile-$page')), findsOneWidget);
      }

      for (final page in pages) {
        await tester.tap(find.byKey(Key('settings-tile-$page')));
        await tester.pumpAndSettle();
        expect(find.text(page), findsWidgets);
        await tester.tap(find.byKey(const Key('settings-back')));
        await tester.pumpAndSettle();
      }
      expect(find.text('系统设置'), findsOneWidget);
      expect(repository.paymentLoads, 0);
    });

    testWidgets('loads inventory rows from the production section endpoint', (
      tester,
    ) async {
      _usePosViewport(tester);
      final repository = _FakeCashierSettingsRepository(
        sections: const {
          'inventory:materials': CashierSettingsSectionData(
            raw: {'total': 1},
            items: [
              {'id': 18, 'name': '生菜', 'status': 'ENABLED', 'stock': 12},
            ],
            total: 1,
            page: 1,
            pageSize: 20,
            source: 'SHOP',
            version: null,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: repository,
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              kdsAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-tile-库存原料')));
      await tester.pumpAndSettle();
      expect(find.text('生菜'), findsOneWidget);
      expect(find.textContaining('状态：ENABLED'), findsOneWidget);
      expect(repository.sectionLoads, contains('inventory:materials'));
    });

    testWidgets(
      'saves store hours with the server version and restores inheritance',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          storeSettings: const CashierStoreSettings(
            module: 'store',
            source: 'SHOP',
            version: 4,
            basic: {'name': '西湖店', 'code': 'XH-01'},
            businessHours: [
              {
                'days': [1, 2, 3, 4, 5],
                'open': '09:00',
                'close': '22:00',
                'enabled': true,
              },
            ],
            businessDays: [1, 2, 3, 4, 5],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CashierSettingsPage(
                repository: repository,
                paymentRepository: _FakeCashierPaymentRepository(),
                storeName: '西湖店',
                kdsAvailable: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();

        expect(find.text('西湖店'), findsWidgets);
        await tester.enterText(find.widgetWithText(TextField, '西湖店'), '西湖旗舰店');
        await tester.ensureVisible(
          find.byKey(const Key('settings-store-save-info')),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-store-save-info')));
        await tester.pumpAndSettle();

        expect(repository.savedStoreVersion, 4);
        expect(repository.savedBasic!['name'], '西湖旗舰店');
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('settings-store-restore')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-store-restore')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认恢复'));
        await tester.pumpAndSettle();
        expect(repository.restoredStoreVersion, 5);
      },
    );

    testWidgets('opens the migrated kitchen KDS page from the settings hub', (
      tester,
    ) async {
      _usePosViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: _FakeCashierSettingsRepository(),
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              kdsAvailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-tile-厨房KDS')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-tile-厨房KDS')));
      await tester.pumpAndSettle();

      expect(find.text('KDS 连接'), findsOneWidget);
      expect(find.text('代理请求'), findsOneWidget);
      expect(find.text('当前平台未启动 KDS 局域网代理'), findsOneWidget);
    });

    testWidgets('marketing prototype exposes first-order lifecycle pages', (
      tester,
    ) async {
      _usePosViewport(tester);
      await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-tile-营销活动')));
      await tester.pumpAndSettle();

      expect(find.text('首单活动'), findsWidgets);
      expect(find.text('资格与互斥'), findsOneWidget);
      expect(find.text('核销记录'), findsOneWidget);
      await tester.tap(find.text('资格与互斥'));
      await tester.pumpAndSettle();
      expect(find.text('按当前门店计算首单资格'), findsOneWidget);
      expect(find.text('取消或全额退款后恢复资格'), findsOneWidget);
      expect(find.text('会员折扣与普通优惠券不可叠加'), findsOneWidget);
    });

    testWidgets(
      'inventory without API client uses real read-only section data', (
      tester) async {
      _usePosViewport(tester);
      await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-tile-库存原料')));
      await tester.pumpAndSettle();

      for (final label in [
        '原料',
        'BOM配方',
        '采购',
        '供应商',
        '仓库',
        '调拨',
        '批次',
          '库存预警',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('BOM配方'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-refresh')), findsOneWidget);
      expect(find.text('多版本定时生效'), findsNothing);
      await tester.tap(find.text('调拨'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-refresh')), findsOneWidget);
      await tester.tap(find.text('批次'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-refresh')), findsOneWidget);
    },
    );

    testWidgets(
      'settings payment destination renders the real payment config page',
      (tester) async {
        _usePosViewport(tester);
        await _pumpSettings(tester);

        await tester.tap(find.byKey(const Key('settings-tile-支付渠道')));
        await tester.pumpAndSettle();

        expect(find.byType(CashierPaymentConfigPage), findsOneWidget);
        expect(find.text('分别管理收银端、小程序端支付能力与本店商户凭证'), findsOneWidget);
        expect(find.text('线下收款码'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('printing and log prototypes expose confirmed operations', (
      tester,
    ) async {
      _usePosViewport(tester);
      await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-section-devices')));
      await tester.pumpAndSettle();
      expect(find.text('已配置打印设备'), findsOneWidget);
      expect(find.text('添加打印机'), findsOneWidget);
      expect(find.text('添加新打印设备'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-section-rules')));
      await tester.pumpAndSettle();
      expect(find.text('出票打印分流规则'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-tile-日志')));
      await tester.pumpAndSettle();
      // 日志页已从原型占位切换为真实页面；测试环境无后端 client，
      // 页面应显示「需要登录」错误态而非原型占位文案。
      expect(find.byType(CashierSettingsLogPage), findsOneWidget);
      expect(find.text('日志查询需要登录后使用'), findsOneWidget);
    });

    testWidgets('printing rules can add the packing scenario directly', (
      tester,
    ) async {
      _usePosViewport(tester);
      await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-section-rules')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-print-rule-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-print-rule-add-packing')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('settings-print-rule-add-packing')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-print-rule-packing')),
        findsOneWidget,
      );
      expect(find.textContaining('仅打包/自提订单生效'), findsOneWidget);
    });

    testWidgets('detail prototype adapts to an Android-width viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDetailPage(
              repository: _FakeCashierSettingsRepository(),
              destination: SettingsDestination.inventory,
              paymentRepository: _FakeCashierPaymentRepository(),
              storeName: '西湖店',
              onBack: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('settings-section-bom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-refresh')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('access evaluate page', () {
    testWidgets('submits userId and renders server verdict', (tester) async {
      final repository = _FakeCashierSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsAccessEvaluatePage(
              repository: repository,
              section: const SettingsSectionSpec(
                'matrix',
                '权限矩阵',
                Icons.grid_on_outlined,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 权限矩阵页内打开「权限解释」弹窗（POST /admin/access/evaluate）
      await tester.tap(find.byKey(const Key('access-matrix-evaluate')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('access-evaluate-user-id')),
        '12',
      );
      await tester.tap(find.byKey(const Key('access-evaluate-submit')));
      await tester.pumpAndSettle();

      expect(repository.evaluatedPermission, 'settings:view');
      expect(find.text('允许'), findsOneWidget);
      expect(find.text('店长'), findsOneWidget);
      expect(find.text('deny-wins-on-same-priority'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('evaluate dialog submits business context and shows approval verdict', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeCashierSettingsRepository();
      repository.evaluationOverride = const CashierAccessEvaluation(
        allow: true,
        permissionGranted: true,
        shopInScope: true,
        matchedRoles: ['店长'],
        policyPassed: false,
        approvalRequired: true,
        reasonCode: 'POLICY_MAX_AMOUNT',
        matchedPolicies: '[{"policy_code":"MAX_AMOUNT_REFUND_50","policy_name":"退款金额上限 50 元"}]',
        rule: 'deny-wins-on-same-priority',
        explanation: '金额 60 超出 50 元上限，需店长授权',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsAccessEvaluatePage(
              repository: repository,
              section: const SettingsSectionSpec(
                'matrix',
                '权限矩阵',
                Icons.grid_on_outlined,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('access-matrix-evaluate')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('access-evaluate-user-id')),
        '12',
      );
      await tester.enterText(
        find.byKey(const Key('access-evaluate-context')),
        '{"amount": 60, "discountRate": 0.75, "resourceType": "ORDER", "resourceId": "20261006001"}',
      );
      await tester.tap(find.byKey(const Key('access-evaluate-submit')));
      await tester.pumpAndSettle();

      // 业务上下文原样传给仓库 → 服务端
      expect(repository.evaluatedContext?['amount'], 60);
      expect(repository.evaluatedContext?['resourceId'], '20261006001');

      // ABAC 决策结果：需审批 → 「放行，需审批」+ 原因码 + 命中策略 + 审批信息
      expect(find.text('放行，需审批'), findsOneWidget);
      expect(find.text('未通过'), findsOneWidget);
      expect(find.textContaining('需店长现场授权'), findsOneWidget);
      expect(find.text('POLICY_MAX_AMOUNT'), findsOneWidget);
      expect(find.textContaining('MAX_AMOUNT_REFUND_50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    );

    testWidgets('evaluate dialog rejects malformed context JSON', (tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsAccessEvaluatePage(
              repository: repository,
              section: const SettingsSectionSpec(
                'matrix',
                '权限矩阵',
                Icons.grid_on_outlined,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('access-matrix-evaluate')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('access-evaluate-user-id')),
        '12',
      );
      await tester.enterText(
        find.byKey(const Key('access-evaluate-context')),
        '{amount: 60,',
      );
      await tester.tap(find.byKey(const Key('access-evaluate-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('JSON 格式不合法'), findsOneWidget);
      expect(repository.evaluatedContext, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders SettingsStatusBadge with all types', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SettingsStatusBadge(
                  label: '已启用',
                  type: StatusBadgeType.success,
                ),
                SettingsStatusBadge(
                  label: '库存不足',
                  type: StatusBadgeType.warning,
                ),
                SettingsStatusBadge(
                  label: '连接失败',
                  type: StatusBadgeType.danger,
                ),
                SettingsStatusBadge(label: '提示信息', type: StatusBadgeType.info),
              ],
            ),
          ),
        ),
      );
      expect(find.text('已启用'), findsOneWidget);
      expect(find.text('库存不足'), findsOneWidget);
      expect(find.text('连接失败'), findsOneWidget);
      expect(find.text('提示信息'), findsOneWidget);
    });

    testWidgets(
      'renders SettingsConfigSourceBadge and handles override action',
      (tester) async {
        var switched = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsConfigSourceBadge(
                source: SettingsConfigSource.headquarters,
                onSwitchToOverride: () => switched = true,
              ),
            ),
          ),
        );
        expect(find.text('继承总店'), findsOneWidget);
        expect(find.text('改为门店配置'), findsOneWidget);
        await tester.tap(find.text('改为门店配置'));
        await tester.pump();
        expect(switched, isTrue);
      },
    );

    testWidgets('renders SettingsEmptyState and handles action callback', (
      tester,
    ) async {
      var actionTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsEmptyState(
              title: '暂无打印规则',
              description: '请点击下方按钮新增第一条打印规则',
              primaryActionLabel: '新增规则',
              onPrimaryAction: () => actionTriggered = true,
            ),
          ),
        ),
      );
      expect(find.text('暂无打印规则'), findsOneWidget);
      expect(find.text('请点击下方按钮新增第一条打印规则'), findsOneWidget);
      await tester.tap(find.text('新增规则'));
      await tester.pump();
      expect(actionTriggered, isTrue);
    });

    testWidgets(
      'showSettingsConfirmDialog shows impact list and returns decision',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    result = await showSettingsConfirmDialog(
                      context: context,
                      title: '停用微信支付渠道',
                      message: '停用后所有扫码盒子将无法使用微信收款。',
                      impacts: const ['前台收银台扫码收款', '扫码点餐小程序'],
                      destructive: true,
                    );
                  },
                  child: const Text('触发弹窗'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('触发弹窗'));
        await tester.pumpAndSettle();

        expect(find.text('停用微信支付渠道'), findsOneWidget);
        expect(find.text('前台收银台扫码收款'), findsOneWidget);
        expect(find.text('扫码点餐小程序'), findsOneWidget);

        await tester.tap(find.text('确认'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
      },
    );

    testWidgets(
      'CashierSettingsStorePage supports business day cut-off and verifies business section removed',
      (tester) async {
        _usePosViewport(tester);
        await _pumpSettings(tester);

        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();

        expect(find.text('营业设置'), findsNothing);

        await tester.tap(find.text('营业日'));
        await tester.pumpAndSettle();
        expect(find.text('营业日切日时间设置'), findsOneWidget);
        expect(find.text('保存切日时间'), findsOneWidget);
        expect(find.text('关门强制流程'), findsOneWidget);
        expect(
          find.byKey(const Key('store-shift-required-switch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('store-settle-required-switch')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CashierSettingsStorePage saves shift/settle required force flags',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('营业日'));
        await tester.pumpAndSettle();

        // 初始默认关闭
        final shiftSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('store-shift-required-switch')),
        );
        expect(shiftSwitch.value, isFalse);
        final settleSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('store-settle-required-switch')),
        );
        expect(settleSwitch.value, isFalse);

        await tester.tap(find.byKey(const Key('store-shift-required-switch')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('store-settle-required-switch')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('store-force-settings-save')));
        await tester.pumpAndSettle();

        expect(repository.savedBasic?['shiftRequired'], 1);
        expect(repository.savedBasic?['settleRequired'], 1);
      },
    );

    testWidgets(
      'CashierSettingsKdsPage exposes proxy connection requests and device management',
      (tester) async {
        _usePosViewport(tester);
        final runtime = _FakeAuthorityKdsRuntime(initialStatus: 'active');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CashierSettingsPage(
                repository: _FakeCashierSettingsRepository(),
                paymentRepository: _FakeCashierPaymentRepository(),
                storeName: '西湖店',
                kdsAvailable: true,
                kdsRuntime: runtime,
                permissions: const {'kds:config'},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('settings-tile-厨房KDS')));
        await tester.pumpAndSettle();

        expect(find.text('KDS 连接'), findsWidgets);
        expect(find.text('代理请求'), findsOneWidget);
        expect(find.text('设备管理'), findsOneWidget);
        expect(find.text('模式配置'), findsNothing);
        expect(find.text('档口分屏'), findsNothing);
        expect(find.text('菜品绑屏'), findsNothing);
        expect(find.text('设备绑定'), findsNothing);
        expect(find.textContaining('主收银'), findsNothing);

        await tester.tap(find.text('代理请求'));
        await tester.pumpAndSettle();
        expect(find.text('代理转发接口请求'), findsOneWidget);

        await tester.tap(find.text('设备管理'));
        await tester.pumpAndSettle();
        expect(find.text('当前收银会话未配置云端客户端'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsStorePage renders Figma store info and store notice cards',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();

        // Verify Store Info Figma card
        expect(find.text('店铺信息'), findsWidgets);
        expect(find.text('门店 ID'), findsOneWidget);
        expect(find.text('* 名称'), findsOneWidget);
        expect(find.text('编码'), findsOneWidget);
        expect(find.text('联系电话'), findsOneWidget);
        expect(find.text('线下收款码'), findsOneWidget);
        expect(find.text('微信  [已配置]'), findsOneWidget);
        expect(find.text('支付宝  [已配置]'), findsOneWidget);
        expect(find.text('保存店铺信息'), findsOneWidget);

        await tester.ensureVisible(find.text('保存店铺信息'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存店铺信息'));
        await tester.pumpAndSettle();
        expect(find.text('店铺信息已成功保存'), findsOneWidget);
        expect(repository.savedBasic, isNotNull);
        expect(repository.savedBasic!['name'], '老肥油边王(松源海鲜街)');
        expect(repository.savedBasic!['phone'], '15975017545');
        // 收款码提交契约字段（预设路径模式）
        expect(
          repository.savedBasic!['offlineCollectWechatImagePath'],
          '/image/offline-collect/shop_1_wechat.png',
        );
        expect(
          repository.savedBasic!['offlineCollectAlipayImagePath'],
          '/image/offline-collect/shop_1_alipay.png',
        );
        expect(repository.savedBasic!.containsKey('wechatQr'), isFalse);
        expect(repository.savedBasic!.containsKey('alipayQr'), isFalse);

        // Verify Store Notice Figma card
        await tester.tap(find.text('店铺公告'));
        await tester.pumpAndSettle();

        expect(repository.sectionLoads, contains('store:notice'));
        expect(find.text('店铺公告'), findsWidgets);
        expect(find.text('* 标题'), findsOneWidget);
        expect(find.text('可视化'), findsOneWidget);
        expect(find.text('源码模式'), findsOneWidget);
        expect(find.text('阅读预览'), findsOneWidget);
        expect(find.text('+ 门店信息'), findsOneWidget);
        expect(find.text('+ 配送规则'), findsOneWidget);
        expect(find.text('+ 优惠福利'), findsOneWidget);
        expect(find.text('+ 温馨提示'), findsOneWidget);
        expect(find.text('【标题】'), findsOneWidget);
        expect(find.text('B 加粗'), findsOneWidget);
        expect(find.text('🔴 标红'), findsOneWidget);

        // Switch to Code Mode
        await tester.tap(find.text('源码模式'));
        await tester.pumpAndSettle();
        expect(find.text('HTML 源码模式（可直接编写/粘贴 HTML 代码）'), findsOneWidget);

        // Switch to Reading Preview Mode
        await tester.tap(find.text('阅读预览'));
        await tester.pumpAndSettle();
        expect(find.text('老肥家鲜煲烧烤 · 门店公告'), findsOneWidget);
        expect(find.text('1:1 真机效果'), findsOneWidget);
        expect(find.text('我知道了 · 进入点餐'), findsOneWidget);
        expect(find.textContaining('门店信息'), findsOneWidget);

        // Switch back to Visual Mode
        await tester.tap(find.text('可视化'));
        await tester.pumpAndSettle();
        expect(find.text('启用'), findsOneWidget);
        expect(find.text('发布公告'), findsOneWidget);

        await tester.ensureVisible(find.text('发布公告'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('发布公告'));
        await tester.pumpAndSettle();
        expect(find.text('店铺公告已成功发布并同步至微信小程序端'), findsOneWidget);
        expect(repository.publishedAnnouncement, isNotNull);
        expect(repository.publishedAnnouncement!['title'], '门店公告');
        expect(repository.publishedAnnouncement!['status'], 1);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage renders clean square card devices grid and printer tabs',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 2},
              items: [
                {
                  'id': 1,
                  'name': '后厨打印机',
                  'vendor': '飞鹅云',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                  'ticketTypes': ['KITCHEN', 'EXPEDITE'],
                },
                {
                  'id': 2,
                  'name': '前台收银小票机',
                  'vendor': '易联云',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                  'ticketTypes': ['FULL_ORDER', 'CHECKOUT'],
                },
              ],
              total: 2,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
            'printer:rules': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'scenario': '结账单 / 客户收银小票',
                  'templateCode': 'STANDARD_RECEIPT',
                  'copies': 1,
                  'deviceId': 2,
                  'enabled': true,
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
            'printer:test': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 1,
                  'name': '后厨打印机',
                  'vendor': '飞鹅云',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Verify clean modern Devices square cards layout
        expect(find.text('已配置打印设备'), findsOneWidget);
        expect(find.text('后厨打印机'), findsOneWidget);
        expect(find.text('前台收银小票机'), findsOneWidget);
        expect(find.text('添加新打印设备'), findsOneWidget);

        // Verify legacy bottom card elements are removed
        expect(find.text('飞鹅云账号 user'), findsNothing);
        expect(find.text('飞鹅云 ukey'), findsNothing);

        // Switch to Rules tab
        await tester.tap(find.byKey(const Key('settings-section-rules')));
        await tester.pumpAndSettle();
        expect(find.text('出票打印分流规则'), findsOneWidget);
        expect(find.text('结账单 / 客户收银小票'), findsOneWidget);

        // Switch to Test tab
        await tester.tap(find.byKey(const Key('settings-section-test')));
        await tester.pumpAndSettle();
        expect(find.text('打印机通讯与出票测试'), findsOneWidget);
        expect(find.text('发送出票'), findsOneWidget);

        await tester.tap(find.text('发送出票'));
        await tester.pumpAndSettle();
        expect(find.text('出票测试指令已发送至「后厨打印机」'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage test tab supports scenario test types and custom content',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:test': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 8,
                  'name': '海鲜档口出单机',
                  'vendor': '飞鹅云',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-section-test')));
        await tester.pumpAndSettle();

        // Verify scenario chips
        expect(find.text('标准收银明细小票'), findsOneWidget);
        expect(find.text('后厨菜品分单小票'), findsOneWidget);
        expect(find.text('切刀裁切与走纸测试'), findsOneWidget);
        expect(find.text('自定义测试打印内容'), findsOneWidget);

        // Select CUTTER_TEST and test print
        await tester.tap(find.text('切刀裁切与走纸测试'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送出票'));
        await tester.pumpAndSettle();

        expect(repository.testedPrinterId, 8);
        expect(repository.testedPrinterType, 'CUTTER_TEST');

        // Select CUSTOM, type custom text, and test print
        await tester.tap(find.text('自定义测试打印内容'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '【测试单】1号桌 炭烤大油边 2份 辣');
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送出票'));
        await tester.pumpAndSettle();

        expect(repository.testedPrinterType, 'CUSTOM');
        expect(repository.testedPrinterContent, '【测试单】1号桌 炭烤大油边 2份 辣');
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage card supports probe and cloud clear queue actions',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 15,
                  'name': '后厨飞鹅云打印机',
                  'vendor': '飞鹅云',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                  'sn': '924698188',
                  'shopName': '西湖旗舰店',
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Verify probe button on square card
        expect(find.text('探活'), findsOneWidget);
        await tester.tap(find.text('探活'));
        await tester.pumpAndSettle();

        expect(find.text('「后厨飞鹅云打印机」硬件探活结果'), findsOneWidget);
        expect(find.text('正常在线'), findsOneWidget);
        expect(find.text('纸仓充足'), findsOneWidget);
        expect(find.text('仓盖已闭合'), findsOneWidget);

        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
        expect(find.text('「后厨飞鹅云打印机」硬件探活结果'), findsNothing);

        // Verify clear queue button on cloud square card
        expect(find.text('清空'), findsOneWidget);
        await tester.tap(find.text('清空'));
        await tester.pumpAndSettle();

        expect(find.text('清空待打印队列'), findsOneWidget);
        await tester.tap(find.text('清空队列'));
        await tester.pumpAndSettle();

        expect(repository.clearedPrinterQueueId, 15);
        expect(find.text('「后厨飞鹅云打印机」待打印队列已清空'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage jobs tab supports status filtering and one-click reprint',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:jobs': CashierSettingsSectionData(
              raw: {'total': 2},
              items: [
                {
                  'id': 101,
                  'status': 'SUCCESS',
                  'retryCount': 0,
                  'deviceId': 15,
                  'createdAt': '2026-08-30 18:30:00',
                  'jobType': 'packing',
                  'scenarioName': '打包单',
                  'bizType': 'kds_serve',
                  'bizId': 8877,
                },
                {
                  'id': 102,
                  'status': 'FAILED',
                  'error': '云打印机缺纸脱机',
                  'payloadText':
                      '<CB>失败补打小票</CB><BR>测试菜品                  1<BR><CUT>',
                  'retryCount': 3,
                  'deviceId': 15,
                  'createdAt': '2026-08-30 18:32:00',
                },
              ],
              total: 2,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-section-jobs')));
        await tester.pumpAndSettle();

        expect(find.text('打印任务流水与重试记录'), findsOneWidget);
        expect(find.text('全部 (2)'), findsOneWidget);
        expect(find.text('成功 (1)'), findsOneWidget);
        expect(find.text('失败 (1)'), findsOneWidget);

        // v1.2.218 业务溯源 chip：KDS 划菜 + 明细 id
        expect(find.text('KDS 划菜 #8877'), findsOneWidget);
        expect(find.text('打包单'), findsOneWidget);

        // Filter failed jobs
        await tester.tap(find.text('失败 (1)'));
        await tester.pumpAndSettle();

        expect(find.text('任务 #102'), findsOneWidget);
        expect(find.text('失败原因: 云打印机缺纸脱机'), findsOneWidget);
        expect(find.text('查看打印内容'), findsOneWidget);
        expect(find.text('任务 #101'), findsNothing);

        await tester.tap(find.text('查看打印内容'));
        await tester.pumpAndSettle();
        expect(find.text('打印内容预览'), findsOneWidget);
        expect(find.byKey(const Key('printing-job-paper')), findsOneWidget);
        expect(find.text('失败补打小票'), findsOneWidget);
        expect(find.text('- - - - - 切刀裁切线 - - - - -'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();

        // Tap reprint button
        await tester.tap(find.text('一键补打'));
        await tester.pumpAndSettle();

        expect(repository.reprintedJobId, 102);
        expect(find.text('任务 #102 补打指令已下发'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage renders clean empty state without mock devices when backend returns 0 items',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 0},
              items: [],
              total: 0,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Verify no mock devices exist
        expect(find.text('后厨打印机'), findsNothing);
        expect(find.text('前台收银小票机'), findsNothing);
        expect(find.text('出餐划单打印机'), findsNothing);

        // Verify Add button and empty state
        expect(find.text('已配置打印设备'), findsOneWidget);
        expect(find.text('添加新打印设备'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage renders device square cards with color-coded status, vendor, and shop info',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 3},
              items: [
                {
                  'id': 10,
                  'name': '海鲜生烤出单机',
                  'vendor': '飞鹅云',
                  'shopName': '老肥油边王(松源海鲜街)',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                  'sn': '924698188',
                  'paperSize': '80mm',
                  'copies': 1,
                  'isDefault': true,
                },
                {
                  'id': 11,
                  'name': '凉菜间网口小票机',
                  'vendor': '佳博',
                  'shopName': '老肥油边王(松源海鲜街)',
                  'transport': 'LAN',
                  'status': 'OFFLINE',
                  'ip': '192.168.1.188',
                  'port': 9100,
                  'paperSize': '58mm',
                  'copies': 1,
                  'isDefault': false,
                },
                {
                  'id': 12,
                  'name': '外卖出餐机',
                  'vendor': '易联云',
                  'shopName': '老肥油边王(松源海鲜街)',
                  'transport': 'CLOUD',
                  'status': 'ERROR',
                  'sn': 'k4-888999',
                  'paperSize': '80mm',
                  'copies': 2,
                  'isDefault': false,
                },
              ],
              total: 3,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );

        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Verify header and device cards
        expect(find.text('已配置打印设备'), findsOneWidget);
        expect(find.text('海鲜生烤出单机'), findsOneWidget);
        expect(find.text('凉菜间网口小票机'), findsOneWidget);
        expect(find.text('外卖出餐机'), findsOneWidget);

        // Verify online / offline / error badges
        expect(find.text('在线'), findsWidgets);
        expect(find.text('离线'), findsOneWidget);
        expect(find.text('异常'), findsOneWidget);

        // Verify basic info
        expect(find.text('商家品牌: '), findsWidgets);
        expect(find.text('所属门店: '), findsWidgets);
        expect(find.text('连接方式: '), findsWidgets);
        expect(find.text('云打印 · SN: 924698188'), findsOneWidget);
        expect(find.text('网口 · IP: 192.168.1.188'), findsOneWidget);
        expect(find.text('添加新打印设备'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage accurately displays out-of-paper, cover-open, and offline hardware statuses',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 3},
              items: [
                {
                  'id': 31,
                  'name': '1号档口缺纸机',
                  'vendor': '飞鹅云',
                  'status': 'ONLINE',
                  'paperStatus': 'OUT_OF_PAPER',
                  'coverStatus': 'CLOSED',
                },
                {
                  'id': 32,
                  'name': '2号档口开盖机',
                  'vendor': '飞鹅云',
                  'status': 'ONLINE',
                  'paperStatus': 'NORMAL',
                  'coverStatus': 'OPEN',
                },
                {
                  'id': 33,
                  'name': '3号未知状态机',
                  'vendor': '佳博',
                  'status': 'UNKNOWN',
                },
              ],
              total: 3,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        expect(find.text('缺纸'), findsOneWidget);
        expect(find.text('开盖'), findsOneWidget);
        expect(find.text('未知'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage enters device edit configuration page on card tap and prevents exiting when dirty without confirmation',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 20,
                  'name': '后厨生烤打印机',
                  'vendor': '飞鹅云',
                  'shopName': '老肥油边王(松源海鲜街)',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                  'sn': '924698188',
                  'user': '870992729@qq.com',
                  'ukey': 'pc7KMwRFBEZtkm3f',
                  'paperSize': '80mm',
                  'copies': 1,
                  'isDefault': true,
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );

        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Tap on device square card to enter edit view
        await tester.tap(find.text('后厨生烤打印机'));
        await tester.pumpAndSettle();

        // Verify edit view
        expect(find.text('配置打印机 - 后厨生烤打印机'), findsOneWidget);
        expect(find.text('返回设备列表'), findsOneWidget);
        expect(find.text('已同步最新'), findsOneWidget);
        expect(find.text('出票测试'), findsOneWidget);

        // Verify Ticket Types Selector & Presets
        expect(find.text('支持打印票据类型 (勾选此打印机负责打印的单据)'), findsOneWidget);
        expect(find.text('厨房小票'), findsOneWidget);
        expect(find.text('前台整单'), findsOneWidget);
        expect(find.text('预结单'), findsOneWidget);
        expect(find.text('结账单'), findsOneWidget);
        expect(find.text('传菜单'), findsOneWidget);
        expect(find.text('外卖单'), findsOneWidget);

        // Switch ticket types with kitchen preset
        await tester.ensureVisible(
          find.byKey(const Key('settings-preset-kitchen')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-preset-kitchen')));
        await tester.pumpAndSettle();

        // Also toggle takeout ticket
        await tester.ensureVisible(
          find.byKey(const Key('settings-ticket-type-takeout')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-ticket-type-takeout')));
        await tester.pumpAndSettle();

        // Modify device name to make form dirty
        await tester.enterText(
          find.widgetWithText(TextField, '后厨生烤打印机'),
          '后厨生烤打印机(升级版)',
        );
        await tester.pumpAndSettle();

        // Scroll back to top to check dirty badge and back button
        await tester.drag(find.byType(ListView).first, const Offset(0, 800));
        await tester.pumpAndSettle();

        expect(find.text('已编辑 (未保存)'), findsOneWidget);

        // Tap Back button while dirty -> expects confirmation dialog
        await tester.tap(find.text('返回设备列表'));
        await tester.pumpAndSettle();

        expect(find.text('未保存的修改'), findsOneWidget);
        expect(find.text('继续编辑'), findsOneWidget);
        expect(find.text('放弃修改'), findsOneWidget);

        // Click "继续编辑" -> stays on page
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.text('配置打印机 - 后厨生烤打印机'), findsOneWidget);

        // Tap Save button -> saves and shows message
        await tester.tap(
          find.byKey(const Key('settings-printer-save-btn')).first,
        );
        await tester.pumpAndSettle();

        expect(repository.savedPrinterDevice, isNotNull);
        expect(repository.savedPrinterDevice!.name, '后厨生烤打印机(升级版)');
        expect(repository.savedPrinterDevice!.version, 1);
        expect(
          repository.savedPrinterDevice!.ticketTypes,
          containsAll(['KITCHEN', 'EXPEDITE', 'TAKEOUT']),
        );
        expect(find.text('飞鹅云打印机配置已保存并同步至打印调度中心'), findsOneWidget);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage handles 409 version conflict and prompts refresh',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {'id': 20, 'name': '后厨生烤打印机', 'vendor': '飞鹅云', 'version': 1},
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        repository.throwConflictOnSave = true;

        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('后厨生烤打印机'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('settings-printer-save-btn')).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('配置版本冲突 (409)'), findsOneWidget);
        expect(find.text('拉取最新配置'), findsOneWidget);

        await tester.tap(find.text('拉取最新配置'));
        await tester.pumpAndSettle();
        expect(find.text('配置版本冲突 (409)'), findsNothing);
      },
    );

    test(
      'ReceiptTemplateScenario codes align with OpenAPI and fromCode maps correctly',
      () {
        expect(ReceiptTemplateScenario.standardReceipt.code, 'CHECKOUT');
        expect(ReceiptTemplateScenario.kitchenTicket.code, 'KITCHEN');
        expect(ReceiptTemplateScenario.fullOrder.code, 'FULL_ORDER');
        expect(ReceiptTemplateScenario.preCheckout.code, 'PRE_CHECKOUT');
        expect(ReceiptTemplateScenario.expedite.code, 'EXPEDITE');
        expect(ReceiptTemplateScenario.takeout.code, 'TAKEOUT');
        expect(ReceiptTemplateScenario.cutterTest.code, 'TEST');

        for (final s in ReceiptTemplateScenario.values) {
          expect(ReceiptTemplateScenario.fromCode(s.code), equals(s));
        }
        expect(
          ReceiptTemplateScenario.fromCode('CHECKOUT'),
          ReceiptTemplateScenario.standardReceipt,
        );
        expect(
          ReceiptTemplateScenario.fromCode('KITCHEN'),
          ReceiptTemplateScenario.kitchenTicket,
        );
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage opens receipt preview simulator from test tab and templates gallery',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 10,
                  'name': '前台80mm收银小票机',
                  'vendor': '佳博',
                  'transport': 'USB',
                  'status': 'ONLINE',
                  'isDefault': true,
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );
        repository.templates.add(
          PrintingTemplate(
            id: 601,
            shopId: 8,
            templateCode: 'tpl_kitchen_system',
            templateName: '后厨制作模板',
            scenario: 'KITCHEN',
            paperSize: '80mm',
            isSystem: true,
            isDefault: true,
            version: 1,
          ),
        );

        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // 1. Switch to "票据模板" tab
        await tester.tap(find.byKey(const Key('settings-section-templates')));
        await tester.pumpAndSettle();

        expect(find.text('票据排版模板管理'), findsOneWidget);
        expect(find.text('热敏纸模拟器'), findsOneWidget);

        // Open from template card
        await tester.tap(
          find.byKey(const Key('settings-template-preview-601')),
        );
        await tester.pumpAndSettle();

        // Verify simulator dialog is visible
        expect(find.textContaining('票据打印效果实时预览'), findsOneWidget);
        expect(find.text('80mm 标准宽纸'), findsOneWidget);
        expect(find.text('58mm 窄票卷纸'), findsOneWidget);
        expect(find.text('复制文本排版'), findsOneWidget);

        // Toggle to 58mm
        await tester.tap(find.text('58mm 窄票卷纸'));
        await tester.pumpAndSettle();
        expect(find.textContaining('58mm 窄幅 (32列)'), findsOneWidget);

        // Switch scenario chip to full order
        await tester.tap(find.byKey(const Key('preview-chip-FULL_ORDER')));
        await tester.pumpAndSettle();
        expect(find.textContaining('开台就餐全单汇总'), findsWidgets);

        // Close dialog
        await tester.tap(find.byTooltip('关闭预览'));
        await tester.pumpAndSettle();
        expect(find.textContaining('票据打印效果实时预览'), findsNothing);

        // 2. Switch to "出票测试" tab
        await tester.tap(find.byKey(const Key('settings-section-test')));
        await tester.pumpAndSettle();

        expect(find.text('预览小票排版效果'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('settings-printer-open-preview-btn')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('票据打印效果实时预览'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭预览'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage opens receipt preview from device edit toolbar',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: const {
            'printer:devices': CashierSettingsSectionData(
              raw: {'total': 1},
              items: [
                {
                  'id': 10,
                  'name': '前台80mm收银小票机',
                  'vendor': '佳博',
                  'transport': 'USB',
                  'status': 'ONLINE',
                  'isDefault': true,
                },
              ],
              total: 1,
              page: 1,
              pageSize: 20,
              source: 'SHOP',
              version: 1,
            ),
          },
        );

        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Enter edit device page
        await tester.tap(find.text('前台80mm收银小票机'));
        await tester.pumpAndSettle();

        // Verify "效果预览" in toolbar
        expect(
          find.byKey(const Key('settings-printer-edit-preview-btn')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('settings-printer-edit-preview-btn')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('票据打印效果实时预览'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭预览'));
        await tester.pumpAndSettle();
        expect(find.textContaining('票据打印效果实时预览'), findsNothing);
      },
    );

    testWidgets(
      'CashierSettingsStorePage pops image picker and zoom lightbox dialogs',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();

        // Tap change image button for WeChat QR code
        await tester.ensureVisible(find.text('更换图片').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('更换图片').first);
        await tester.pumpAndSettle();

        // Verify Image Picker Dialog
        expect(find.text('选择微信线下收款码图片'), findsOneWidget);
        expect(find.text('预设标准收款码模板：'), findsOneWidget);
        expect(find.text('确认选择'), findsOneWidget);

        // Select preset and confirm
        await tester.tap(find.text('确认选择'));
        await tester.pumpAndSettle();
        expect(find.textContaining('已选取「微信收款码」图片'), findsOneWidget);

        // Tap zoom on QR code preview icon
        await tester.ensureVisible(find.byIcon(Icons.zoom_in).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.zoom_in).first);
        await tester.pumpAndSettle();

        // Verify Lightbox Dialog
        expect(find.text('微信线下收款码预览'), findsOneWidget);
        expect(find.textContaining('已解码跳转串：wxp://'), findsOneWidget);
        expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
        expect(find.text('关闭预览'), findsOneWidget);

        // Click copy payload icon
        await tester.tap(find.byIcon(Icons.copy_rounded));
        await tester.pumpAndSettle();
        expect(find.text('已复制收款码跳转串至剪贴板'), findsOneWidget);

        await tester.tap(find.text('关闭预览'));
        await tester.pumpAndSettle();
        expect(find.text('微信线下收款码预览'), findsNothing);
      },
    );

    testWidgets(
      'CashierSettingsStorePage prompts unsaved changes dialog when modified and returning',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();
        await _pumpSettings(tester, repository: repository);

        await tester.tap(find.byKey(const Key('settings-tile-店铺信息')));
        await tester.pumpAndSettle();

        // Edit store name to make page dirty
        await tester.enterText(
          find.widgetWithText(TextField, '老肥油边王(松源海鲜街)'),
          '老肥油边王(新店名)',
        );
        await tester.pumpAndSettle();

        // Tap back button
        await tester.tap(find.byKey(const Key('settings-back')));
        await tester.pumpAndSettle();

        // Expect unsaved changes dialog
        expect(find.text('未保存的修改'), findsOneWidget);
        expect(find.text('当前页面有尚未保存的配置，离开后修改将会丢失。是否确认放弃修改？'), findsOneWidget);
        expect(find.text('继续编辑'), findsOneWidget);
        expect(find.text('放弃修改'), findsOneWidget);

        // Click "继续编辑" -> dialog dismisses and stays on page
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.text('未保存的修改'), findsNothing);
        expect(find.text('店铺信息'), findsWidgets);

        // Tap back button again and confirm discard
        await tester.tap(find.byKey(const Key('settings-back')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();

        // Verify returned to hub
        expect(find.byKey(const Key('settings-tile-店铺信息')), findsOneWidget);
      },
    );

    test(
      'PrintPreviewResult.fromJson safely parses AST nodes, paper sizes and tickets',
      () {
        final json = {
          'scenario': 'CHECKOUT',
          'scenarioName': '结账小票',
          'paperSize': '80mm',
          'paperWidthMm': 80,
          'paperWidthChars': 48,
          'shopName': '老肥油边王',
          'totalTickets': 2,
          'tickets': [
            {
              'ticketIndex': 1,
              'title': '客户联',
              'rawContent': 'RAW_1',
              'plainText': '客户联排版',
              'ruleId': 10,
              'deviceId': 20,
              'deviceName': '前台热敏机',
              'templateId': 30,
              'templateCode': 'checkout_customer',
              'elements': [
                {
                  'type': 'HEADER',
                  'text': '老肥油边王(松源店)',
                  'align': 'CENTER',
                  'bold': true,
                  'size': 'LARGE',
                },
                {'type': 'DIVIDER'},
                {
                  'type': 'TABLE_ROW',
                  'columns': ['招牌烤大油边', 'x2', '76.00'],
                  'bold': true,
                },
                {
                  'type': 'KEY_VALUE',
                  'key': '实付金额',
                  'value': '¥76.00',
                  'bold': true,
                },
                {
                  'type': 'QRCODE',
                  'text': 'https://pay.example.com/receipt/123',
                },
                {'type': 'CUT'},
              ],
            },
            {
              'ticketIndex': 2,
              'title': '后厨联',
              'rawContent': 'RAW_2',
              'plainText': '后厨分单',
              'elements': [
                {
                  'type': 'HEADER',
                  'text': '后厨制作分单 [08号桌]',
                  'align': 'LEFT',
                  'size': 'DOUBLE',
                },
              ],
            },
          ],
          'bindingWarnings': ['会员昵称未绑定', '会员昵称未绑定'],
          'capabilityWarnings': ['设备不支持钱箱指令'],
        };

        final result = PrintPreviewResult.fromJson(json);
        expect(result.scenario, 'CHECKOUT');
        expect(result.scenarioName, '结账小票');
        expect(result.is80mm, isTrue);
        expect(result.totalTickets, 2);
        expect(result.tickets.length, 2);
        expect(result.tickets[0].title, '客户联');
        expect(result.tickets[0].elements.length, 6);
        expect(result.tickets[0].elements[0].type, PrintElementType.header);
        expect(result.tickets[0].elements[0].size, PrintElementSize.large);
        expect(result.tickets[0].elements[2].type, PrintElementType.tableRow);
        expect(result.tickets[0].elements[2].columns, [
          '招牌烤大油边',
          'x2',
          '76.00',
        ]);
        expect(result.tickets[0].elements[3].type, PrintElementType.keyValue);
        expect(result.tickets[0].elements[3].key, '实付金额');
        expect(result.tickets[0].elements[3].value, '¥76.00');
        expect(result.tickets[0].elements[4].type, PrintElementType.qrcode);
        expect(result.tickets[0].elements[5].type, PrintElementType.cut);
        expect(result.tickets[1].title, '后厨联');
        expect(result.tickets[0].ruleId, 10);
        expect(result.tickets[0].deviceName, '前台热敏机');
        expect(result.tickets[0].templateCode, 'checkout_customer');
        expect(result.bindingWarnings, ['会员昵称未绑定']);
        expect(result.capabilityWarnings, ['设备不支持钱箱指令']);
      },
    );

    testWidgets(
      'CashierReceiptPreviewDialog fetches backend preview and allows direct print',
      (tester) async {
        _usePosViewport(tester);
        var printExecuted = false;

        final previewData = PrintPreviewResult(
          scenario: 'ORDER',
          scenarioName: '前台整单',
          paperSize: '80mm',
          paperWidthMm: 80,
          paperWidthChars: 48,
          shopName: '老肥油边王',
          totalTickets: 1,
          tickets: [
            PrintTicket(
              ticketIndex: 1,
              title: '前台整单小票',
              rawContent: 'ORDER_RAW',
              plainText: '前台整单文本',
              elements: const [
                PrintElement(
                  type: PrintElementType.header,
                  text: '老肥油边王前台整单',
                  align: PrintElementAlign.center,
                  size: PrintElementSize.large,
                ),
                PrintElement(
                  type: PrintElementType.keyValue,
                  key: '桌号',
                  value: '08号桌',
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => FilledButton(
                  onPressed: () {
                    showCashierReceiptPreviewDialog(
                      context: ctx,
                      orderId: 88,
                      orderNo: 'NO.202608310088',
                      initialScenario: ReceiptTemplateScenario.fullOrder,
                      onFetchPreview: (sc, size, custom) async => previewData,
                      onExecutePrint: () async {
                        printExecuted = true;
                      },
                    );
                  },
                  child: const Text('打开预览'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('打开预览'));
        await tester.pumpAndSettle();

        // 验证弹窗渲染了后端返回的 AST 节点与订单标识
        expect(find.textContaining('票据打印效果实时预览'), findsOneWidget);
        expect(find.text('后端真实解析'), findsOneWidget);
        expect(find.textContaining('NO.202608310088'), findsOneWidget);
        expect(find.text('老肥油边王前台整单'), findsOneWidget);
        expect(find.text('08号桌'), findsOneWidget);

        // 验证可以直接点击「确认无误，立即打印」
        expect(
          find.byKey(const Key('preview-dialog-direct-print-btn')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('preview-dialog-direct-print-btn')),
        );
        await tester.pumpAndSettle();

        expect(printExecuted, isTrue);
      },
    );

    test(
      'PrintingTemplate and PrintTemplateDsl serialize and deserialize faithfully',
      () {
        final dsl = PrintTemplateDsl.defaultForScenario(
          'ORDER',
          paperSize: '80mm',
        );
        expect(dsl.paperSize, '80mm');
        expect(dsl.scenario, 'ORDER');
        expect(dsl.blocks.length, greaterThanOrEqualTo(5));

        final dslMap = dsl.toJson();
        final reDecodedDsl = PrintTemplateDsl.fromJson(dslMap);
        expect(reDecodedDsl.paperSize, '80mm');
        expect(reDecodedDsl.blocks.length, dsl.blocks.length);
        expect(reDecodedDsl.blocks.first.type, 'HEADER');

        final template = PrintingTemplate(
          id: 12,
          shopId: 8,
          templateCode: 'tpl_order_custom',
          templateName: '老肥招牌结账小票',
          scenario: 'ORDER',
          paperSize: '80mm',
          isSystem: false,
          isDefault: true,
          templateDsl: dsl,
          version: 3,
        );

        final json = template.toJson();
        expect(json['id'], 12);
        expect(json['templateName'], '老肥招牌结账小票');
        expect(json['isDefault'], true);

        final parsed = PrintingTemplate.fromJson(json);
        expect(parsed.id, 12);
        expect(parsed.templateName, '老肥招牌结账小票');
        expect(parsed.templateDsl?.paperSize, '80mm');
        expect(parsed.version, 3);
      },
    );

    testWidgets(
      'CashierPrintingTemplateDesignerDialog allows block customization and saving',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();

        PrintingTemplate? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    savedResult =
                        await showCashierPrintingTemplateDesignerDialog(
                          context: ctx,
                          repository: repository,
                          storeName: '老肥油边王',
                          initialScenario: 'ORDER',
                        );
                  },
                  child: const Text('打开设计器'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('打开设计器'));
        await tester.pumpAndSettle();

        // 验证设计器组件渲染
        expect(find.text('新建自定义小票模板'), findsOneWidget);
        expect(find.text('小票区块构成'), findsOneWidget);
        expect(find.textContaining('真实热敏小票预览'), findsOneWidget);

        // 修改模板名称
        final nameFinder = find.widgetWithText(TextField, '模板名称');
        expect(nameFinder, findsOneWidget);
        await tester.enterText(nameFinder, '我的特色结账小票');
        await tester.pumpAndSettle();

        // 验证保存模板
        expect(
          find.byKey(const Key('settings-template-save-btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('settings-template-save-btn')));
        await tester.pumpAndSettle();

        expect(savedResult, isNotNull);
        expect(savedResult!.templateName, '我的特色结账小票');
        expect(repository.templates.length, 1);
        expect(repository.templates.first.templateName, '我的特色结账小票');
      },
    );

    testWidgets(
      'CashierPrintingTemplateDesignerDialog supports pure text template mode with variable binding',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();

        PrintingTemplate? savedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    savedResult =
                        await showCashierPrintingTemplateDesignerDialog(
                          context: context,
                          repository: repository,
                          storeName: '老肥烧烤总店',
                          initialScenario: 'ORDER',
                        );
                  },
                  child: const Text('打开设计器'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('打开设计器'));
        await tester.pumpAndSettle();

        // 切换到纯文本模式
        expect(find.text('纯文本参数绑定'), findsOneWidget);
        await tester.tap(find.text('纯文本参数绑定'));
        await tester.pumpAndSettle();

        // 验证参数插入工具栏与文本框
        expect(find.text('点击直接插入动态绑定参数：'), findsOneWidget);
        expect(find.text('菜品名'), findsOneWidget);
        expect(find.text('单价'), findsOneWidget);
        expect(find.text('数量'), findsOneWidget);
        expect(find.text('金额小计'), findsOneWidget);
        expect(find.text('加菜'), findsOneWidget);
        expect(find.text('订单ID'), findsOneWidget);

        // 点击插入参数
        await tester.tap(find.text('订单ID'));
        await tester.pumpAndSettle();

        // 保存模板
        await tester.tap(find.byKey(const Key('settings-template-save-btn')));
        await tester.pumpAndSettle();

        expect(savedResult, isNotNull);
        expect(savedResult!.templateDsl?.mode, 'TEXT');
        expect(savedResult!.templateDsl?.rawTemplate, contains('{订单ID}'));
      },
    );

    testWidgets(
      'CashierPrintingTemplateDesignerDialog handles Ctrl+V through the guarded paste path',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const crashGuardChannel = MethodChannel(
          'laofei_cashier/native_crash_guard',
        );
        final guardStates = <bool>[];
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': '粘贴诊断标记'};
          }
          return null;
        });
        messenger.setMockMethodCallHandler(crashGuardChannel, (call) async {
          if (call.method == 'setReceiptTemplateTextGuard') {
            guardStates.add(call.arguments as bool);
          }
          return null;
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(crashGuardChannel, null);
          await CrashLog.instance.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showCashierPrintingTemplateDesignerDialog(
                    context: context,
                    repository: repository,
                    storeName: '老肥烧烤总店',
                    initialScenario: 'ORDER',
                  ),
                  child: const Text('打开设计器'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开设计器'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('纯文本参数绑定'));
        await tester.pumpAndSettle();
        expect(guardStates, [isTrue]);

        final editor = find.byKey(
          const Key('settings-template-raw-text-editor'),
        );
        expect(editor, findsOneWidget);
        await tester.tap(editor);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        final field = tester.widget<TextField>(editor);
        expect(field.controller!.text, contains('粘贴诊断标记'));
        expect('粘贴诊断标记'.allMatches(field.controller!.text), hasLength(1));
        final breadcrumb = CrashLog.instance.breadcrumbsSnapshot.last;
        expect(breadcrumb.category, 'printing_template');
        expect(breadcrumb.message, startsWith('paste_completed '));
        expect(breadcrumb.data?['character_count'], 6);
        expect(breadcrumb.data.toString(), isNot(contains('粘贴诊断标记')));

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(guardStates, [isTrue, isFalse]);
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage does not render built-in fallback templates when repository is empty',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: {
            'printer:devices': CashierSettingsSectionData.fromResponse({
              'total': 0,
              'items': [],
            }),
            'printer:templates': CashierSettingsSectionData.fromResponse({
              'total': 0,
              'items': [],
            }),
          },
        );
        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-section-templates')));
        await tester.pumpAndSettle();

        expect(find.text('暂无可用票据模板'), findsOneWidget);
        expect(
          find.byKey(const Key('settings-printer-preview-template-CHECKOUT')),
          findsNothing,
        );
        for (final label in const [
          '点餐小票 (ORDER)',
          '厨房小票 (KITCHEN)',
          '前台整单小票 (FULL_ORDER)',
          '预结单 (PRE_CHECKOUT)',
          '结账单 (CHECKOUT)',
          '催菜单 (EXPEDITE)',
          '外卖小票 (TAKEOUT)',
          '打包单 (PACKING)',
          '交接班报表 (SHIFT)',
          '退款单据 (REFUND)',
          '商品标签杯贴 (LABEL)',
          '自检测试单 (TEST)',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
      },
    );

    testWidgets(
      'CashierSettingsPrinterPage renders templates from repository and allows managing them',
      (tester) async {
        _usePosViewport(tester);
        final repository = _FakeCashierSettingsRepository(
          sections: {
            'printer:devices': CashierSettingsSectionData.fromResponse({
              'total': 1,
              'items': [
                {
                  'id': 1,
                  'name': '前台打印机',
                  'vendor': '飞鹅云',
                  'shopName': '总店',
                  'transport': 'CLOUD',
                  'status': 'ONLINE',
                },
              ],
            }),
            'printer:templates': CashierSettingsSectionData.fromResponse({
              'total': 0,
              'items': [],
            }),
          },
        );

        // Pre-populate a template in fake repository
        repository.templates.add(
          PrintingTemplate(
            id: 501,
            shopId: 8,
            templateCode: 'tpl_custom_order',
            templateName: '特色堂食小票',
            scenario: 'ORDER',
            paperSize: '58mm',
            isSystem: false,
            isDefault: true,
            version: 1,
          ),
        );

        await _pumpSettings(tester, repository: repository);
        await tester.tap(find.byKey(const Key('settings-tile-打印设置')));
        await tester.pumpAndSettle();

        // Switch to "票据模板" tab
        await tester.tap(find.byKey(const Key('settings-section-templates')));
        await tester.pumpAndSettle();

        expect(find.text('票据排版模板管理'), findsOneWidget);
        expect(find.text('特色堂食小票'), findsOneWidget);
        expect(find.text('默认模板'), findsOneWidget);
        expect(find.text('门店自定义'), findsOneWidget);

        // Open designer from template card
        expect(
          find.byKey(const Key('settings-template-edit-501')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('settings-template-edit-501')));
        await tester.pumpAndSettle();

        expect(find.text('编辑小票模板'), findsOneWidget);
        expect(find.text('取消'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        expect(find.text('编辑小票模板'), findsNothing);
      },
    );
  });

  group('cashier settings delivery manager', () {
    Future<void> pumpDelivery(
      WidgetTester tester,
      _FakeCashierSettingsRepository repository,
      String sectionId, {
      String label = '配送规则',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsDeliveryPage(
              repository: repository,
              section: SettingsSectionSpec(
                sectionId,
                label,
                Icons.storefront_outlined,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('platforms renders enable switch and channel overview', (
      tester,
    ) async {
      final repository = _FakeCashierSettingsRepository();
      tester.view.physicalSize = const Size(1920, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDelivery(tester, repository, 'platforms', label: '外卖平台');
      await tester.pumpAndSettle();

      expect(find.text('外卖平台'), findsOneWidget);
      expect(find.text('门店外卖开通'), findsOneWidget);
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('自动发单已开启'), findsOneWidget);
      expect(find.text('定时同步已开启'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delivery-platforms-enabled')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repository.savedTakeoutConfig, isNotNull);
      expect(repository.savedTakeoutConfig!.enabled, 0);
      expect(find.text('已关闭'), findsNWidgets(2));
    });

    testWidgets('rules renders form fields, tier rows and saves', (
      tester,
    ) async {
      final repository = _FakeCashierSettingsRepository();
      tester.view.physicalSize = const Size(1920, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDelivery(tester, repository, 'rules');
      await tester.pumpAndSettle();

      expect(find.text('配送规则'), findsWidgets);
      expect(find.text('起送价（元）'), findsOneWidget);
      expect(find.text('满额免配送费（元）'), findsOneWidget);
      expect(find.byKey(const Key('delivery-tier-0')), findsOneWidget);
      expect(find.byKey(const Key('delivery-tier-2')), findsOneWidget);
      expect(find.byKey(const Key('delivery-tier-add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delivery-tier-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delivery-tier-3')), findsOneWidget);

      await tester.tap(find.text('保存规则'));
      await tester.pumpAndSettle();

      expect(repository.savedTakeoutConfig, isNotNull);
      expect(repository.savedTakeoutConfig!.minOrderAmount, 68);
      expect(repository.savedTakeoutConfig!.tiers.length, 4);
    });

    testWidgets('zsq renders switches and saves', (tester) async {
      final repository = _FakeCashierSettingsRepository();
      tester.view.physicalSize = const Size(1920, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDelivery(tester, repository, 'zsq', label: '真省钱配送');
      await tester.pumpAndSettle();

      expect(find.text('真省钱聚合配送'), findsOneWidget);
      expect(find.text('接单后自动发配送'), findsOneWidget);
      expect(find.text('外卖状态定时同步'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delivery-zsq-auto')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存开关'));
      await tester.pumpAndSettle();

      expect(repository.savedZsqAutoApi, isNotNull);
      expect(repository.savedZsqAutoApi!.autoDispatchEnabled, false);
      expect(repository.savedZsqAutoApi!.takeoutSyncEnabled, true);
    });

    testWidgets('records renders stats, filters and redispatch action', (
      tester,
    ) async {
      final repository = _FakeCashierSettingsRepository();
      tester.view.physicalSize = const Size(1920, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDelivery(tester, repository, 'records', label: '配送记录');
      await tester.pumpAndSettle();
      expect(find.textContaining('不支持的外卖管理页面'), findsNothing);

      expect(find.text('配送中（本页）'), findsOneWidget);
      expect(find.text('已完成（本页）'), findsOneWidget);
      expect(find.text('配送中'), findsOneWidget);
      expect(find.text('已完成'), findsWidgets);
      expect(find.text('配送失败'), findsOneWidget);
      expect(find.text('ORD20260909018'), findsOneWidget);

      // 详情弹窗
      await tester.tap(find.text('详情').first);
      await tester.pumpAndSettle();
      expect(find.text('配送单详情'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      // 配送失败行 -> 重发
      await tester.tap(find.text('重发').first);
      await tester.pumpAndSettle();
      expect(find.text('重发配送'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(repository.deliveryOperations, contains('redispatch:9003'));

      // 状态筛选
      await tester.tap(find.byKey(const Key('delivery-records-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已完成').last);
      await tester.pumpAndSettle();

      expect(find.text('ORD20260909012'), findsOneWidget);
      expect(find.text('ORD20260909018'), findsNothing);
    });

    testWidgets('records rapid page clicks do not crash', (tester) async {
      final repository = _FakeCashierSettingsRepository();
      tester.view.physicalSize = const Size(1920, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDelivery(tester, repository, 'records', label: '配送记录');
      await tester.pumpAndSettle();

      expect(find.text('共 45 条 · 第 1/3 页（统计为当前页）'), findsOneWidget);
      // 快速连点下一页（不等待中间结果），验证不崩溃且分页状态稳定
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('下一页'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 5));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('共 45 条 · 第 '), findsOneWidget);
    });
  });
}

void _noop() {}

Future<void> _pumpSettings(
  WidgetTester tester, {
  _FakeCashierSettingsRepository? repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CashierSettingsPage(
          repository: repository ?? _FakeCashierSettingsRepository(),
          paymentRepository: _FakeCashierPaymentRepository(),
          storeName: '西湖店',
          kdsAvailable: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _usePosViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeCashierPaymentRepository implements CashierPaymentRepository {
  int saveCount = 0;

  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async =>
      const CashierPaymentCapabilities();

  @override
  Future<CashierPaymentCapabilities> saveCapabilities(
    CashierPaymentCapabilities capabilities,
  ) async {
    saveCount++;
    return capabilities;
  }

  @override
  Future<PaymentMerchantCollection> loadMerchants(
    PaymentChannel channel,
  ) async => const PaymentMerchantCollection();

  @override
  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  }) async => PaymentMerchantForm(channel: channel, merchantKey: merchantKey);

  @override
  Future<PaymentMerchantForm> loadMerchant(int id) async => PaymentMerchantForm(
    channel: PaymentChannel.wechat,
    merchantKey: 'default',
  );

  @override
  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form) async =>
      form;

  @override
  Future<PaymentMerchantDeleteResult> deleteMerchant(int id) async =>
      PaymentMerchantDeleteResult(deletedId: id, softDeleted: true);

  @override
  Future<PaymentNotifyUrls> loadNotifyUrls() async =>
      const PaymentNotifyUrls(
        wechatPayNotify: 'https://api.test/notify/wechat/pay',
        wechatRefundNotify: 'https://api.test/notify/wechat/refund',
        alipayPayNotify: 'https://api.test/notify/alipay/pay',
      );

  @override
  Future<PaymentPrivateKeyUploadResult> uploadWechatPrivateKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async => const PaymentPrivateKeyUploadResult(
    privateKeyRef: 'payment-keys/wechat-default.pem',
  );

  @override
  Future<PaymentPlatformPublicKeyUploadResult> uploadWechatPlatformPublicKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async => const PaymentPlatformPublicKeyUploadResult(
    platformPubKeyRef: 'payment-keys/shop-0/wechat-default-platform-public.pem',
    materialType: 'PUBLIC_KEY',
  );

  @override
  Future<PaymentMerchantForm> uploadMerchantPrivateKey({
    required int merchantId,
    required List<int> pemBytes,
    required String filename,
  }) async => PaymentMerchantForm(
    id: merchantId,
    channel: PaymentChannel.wechat,
    merchantKey: 'default',
  );

  @override
  Future<PaymentCertificateUploadResult> uploadCertificate({
    required List<int> bytes,
    required String filename,
    String? merchantKey,
    String type = 'AUTO',
  }) async => PaymentCertificateUploadResult(
    certificateType: type,
    fileRef: 'payment-keys/test-$filename',
    filename: filename,
    fileSize: bytes.length,
  );

  @override
  Future<PaymentMerchantForm> uploadMerchantCertificate({
    required int merchantId,
    required List<int> bytes,
    required String filename,
    String type = 'AUTO',
  }) async => PaymentMerchantForm(
    id: merchantId,
    channel: PaymentChannel.wechat,
    merchantKey: 'default',
  );

  @override
  Future<PaymentRoutingRuleCollection> loadRoutingRules(
    PaymentChannel channel,
  ) async =>
      PaymentRoutingRuleCollection(channel: channel, rules: const []);

  @override
  Future<PaymentRoutingRule> saveRoutingRule({
    int? id,
    required Map<String, Object?> data,
  }) async =>
      PaymentRoutingRule(
        id: id ?? 0,
        ruleName: data['ruleName']?.toString() ?? '',
        priority: 0,
        targetMerchantKey: 'default',
      );

  @override
  Future<bool> deleteRoutingRule(int id) async => true;

  @override
  Future<bool> sortRoutingRules(
    PaymentChannel channel,
    List<int> ruleIds,
  ) async =>
      true;

  @override
  Future<PaymentRoutingSimulationResult> simulateRouting(
    Map<String, Object?> context,
  ) async =>
      const PaymentRoutingSimulationResult();

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}
}

class _FakeCashierSettingsRepository implements CashierSettingsRepository {
  _FakeCashierSettingsRepository({
    this.payments = const [],
    this.overview = const CashierSettingsOverview(shopId: 8, modules: []),
    this.sections = const {},
    this.storeSettings = const CashierStoreSettings(
      module: 'store',
      source: 'SHOP',
      version: 1,
      basic: {
        'shopId': 1,
        'name': '老肥油边王(松源海鲜街)',
        'code': '1001',
        'address': '广东省江门市鹤山市沙坪街道大鹏路',
        'phone': '15975017545',
        'openTime': '18:30:00',
        'closeTime': '01:30:00',
        'status': 1,
        'sort': 0,
        'latitude': 22.760231,
        'longitude': 112.973179,
        'remark': '',
        'wechatQrConfigured': true,
        'alipayQrConfigured': true,
        'hasWechatQr': true,
        'hasAlipayQr': true,
        'wechatQrImageUrl': '/image/offline-collect/shop_1_wechat.png',
        'alipayQrImageUrl': '/image/offline-collect/shop_1_alipay.png',
        'offlineCollectWechatPayload': 'wxp://f2f0101928374650029384756',
        'offlineCollectAlipayPayload':
            'https://qr.alipay.com/fkx19283746592837465',
      },
      businessHours: [
        {
          'days': [0, 1, 2, 3, 4, 5, 6],
          'open': '18:30',
          'close': '01:30',
          'enabled': true,
        },
      ],
      businessDays: [0, 1, 2, 3, 4, 5, 6],
    ),
  });

  int businessLoads = 0;
  int paymentLoads = 0;
  final List<String> sectionLoads = [];
  final List<int> sectionPages = [];
  final List<CashierPaymentMethod> payments;
  final CashierSettingsOverview overview;
  final Map<String, CashierSettingsSectionData> sections;
  final CashierStoreSettings storeSettings;
  int? savedStoreVersion;
  List<Map<String, Object?>>? savedBusinessHours;
  List<int>? savedBusinessDays;
  int? restoredStoreVersion;
  String? evaluatedPermission;

  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async => overview;

  @override
  Future<CashierSettingsSectionData> loadSettingsSection({
    required String module,
    required String section,
    int page = 1,
    int pageSize = 20,
  }) async {
    final key = '$module:$section';
    sectionLoads.add(key);
    sectionPages.add(page);
    return sections[key] ??
        const CashierSettingsSectionData(
          raw: {},
          items: [],
          total: 0,
          page: 1,
          pageSize: 20,
          source: 'SHOP',
          version: 1,
        );
  }

  Map<String, Object?>? savedBasic;
  Map<String, Object?>? publishedAnnouncement;

  @override
  Future<CashierStoreSettings> loadStoreSettings() async => storeSettings;

  final List<({bool isWechat, List<int> bytes, String filename})> uploadedQrs =
      [];

  @override
  Future<void> uploadOfflineCollectQr({
    required bool isWechat,
    required List<int> bytes,
    required String filename,
  }) async {
    uploadedQrs.add((isWechat: isWechat, bytes: bytes, filename: filename));
  }

  @override
  Future<CashierStoreSettings> saveStoreSettings({
    required int version,
    Map<String, Object?>? basic,
    List<Map<String, Object?>>? businessHours,
    List<int>? businessDays,
  }) async {
    savedStoreVersion = version;
    savedBasic = basic;
    savedBusinessHours = businessHours;
    savedBusinessDays = businessDays;
    return CashierStoreSettings(
      module: 'store',
      source: 'SHOP',
      version: version + 1,
      basic: basic ?? storeSettings.basic,
      businessHours: businessHours ?? storeSettings.businessHours,
      businessDays: businessDays ?? storeSettings.businessDays,
    );
  }

  @override
  Future<int> publishAnnouncement({
    int? id,
    required String title,
    required String content,
    required int status,
    int sort = 0,
    String? startTime,
    String? endTime,
  }) async {
    publishedAnnouncement = {
      'id': id,
      'title': title,
      'content': content,
      'status': status,
      'sort': sort,
      'startTime': startTime,
      'endTime': endTime,
    };
    return id ?? 101;
  }

  @override
  Future<CashierStoreSettings> restoreStoreSettings({
    required int version,
  }) async {
    restoredStoreVersion = version;
    return const CashierStoreSettings(
      module: 'store',
      source: 'HEADQUARTERS',
      version: 6,
      basic: {},
      businessHours: [],
      businessDays: [],
    );
  }

  @override
  Future<CashierBusinessSettings> changeBusinessStatus(
    bool isOpen, {
    bool force = false,
  }) async =>
      CashierBusinessSettings(isOpen: isOpen, isReviewed: true, shopId: 8);

  @override
  Future<CashierAccessEvaluation> evaluateAccess({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async {
    evaluatedPermission = permission;
    evaluatedContext = context;
    final override = evaluationOverride;
    if (override != null) return override;
    return CashierAccessEvaluation(
      allow: true,
      permissionGranted: true,
      shopInScope: true,
      matchedRoles: const ['店长'],
      priority: 80,
      rule: 'deny-wins-on-same-priority',
      explanation: '命中角色「店长」，允许访问',
    );
  }

  Map<String, Object?>? evaluatedContext;
  CashierAccessEvaluation? evaluationOverride;

  List<CashierAccessEmployee> accessEmployees = const [
    CashierAccessEmployee(
      adminId: 1,
      userName: '张店长',
      roles: [
        CashierAccessRoleRef(
          id: 1,
          roleCode: 'ROLE_STORE_MANAGER',
          roleName: '店长',
        ),
      ],
      shops: [1, 2],
    ),
    CashierAccessEmployee(
      adminId: 2,
      userName: '李收银',
      roles: [
        CashierAccessRoleRef(id: 2, roleCode: 'ROLE_CASHIER', roleName: '收银员'),
      ],
      shops: [1],
    ),
  ];
  List<CashierAccessRole> accessRoles = const [
    CashierAccessRole(
      id: 1,
      roleCode: 'ROLE_STORE_MANAGER',
      roleName: '店长',
      remark: '管理本店全部门店事务与员工授权',
      sortOrder: 80,
      version: 3,
      adminCount: 12,
      permissions: [
        CashierPermissionCodeRef(
          id: 1,
          permissionCode: 'settings:view',
          permissionName: '设置查看',
        ),
      ],
    ),
    CashierAccessRole(
      id: 2,
      roleCode: 'ROLE_CASHIER',
      roleName: '收银员',
      remark: '收银、结账、会员查询',
      sortOrder: 40,
      version: 2,
      adminCount: 5,
      permissions: [
        CashierPermissionCodeRef(
          id: 1,
          permissionCode: 'settings:view',
          permissionName: '设置查看',
        ),
      ],
    ),
    CashierAccessRole(
      id: 3,
      roleCode: 'ROLE_TEMPORARY',
      roleName: '临时帮工',
      remark: '只读权限',
      sortOrder: 20,
      version: 1,
      adminCount: 0,
    ),
  ];
  List<CashierPermissionCode> permissionCodes = const [
    CashierPermissionCode(
      id: 1,
      permissionCode: 'settings:view',
      permissionName: '设置查看',
      module: 'settings',
      remark: '查看设置',
      sortOrder: 10,
    ),
    CashierPermissionCode(
      id: 2,
      permissionCode: 'order:view',
      permissionName: '订单查看',
      module: 'order',
      remark: '查看订单与明细',
      sortOrder: 20,
    ),
    CashierPermissionCode(
      id: 3,
      permissionCode: 'access:manage',
      permissionName: '权限管理',
      module: 'access',
      remark: '员工授权与角色管理',
      sortOrder: 30,
    ),
  ];
  List<CashierShopRef> shopList = const [
    CashierShopRef(id: 1, name: '西湖店', code: '1001'),
    CashierShopRef(id: 2, name: '滨江店', code: '1002'),
  ];
  List<CashierApiPermission> apiPermissions = const [
    CashierApiPermission(
      id: 1,
      method: 'GET',
      pathPattern: '/admin/access/employees',
      permissionCode: 'access:manage',
      remark: '员工列表',
    ),
  ];
  List<CashierAccessAuditEntry> accessAudit = [
    CashierAccessAuditEntry(
      id: 1,
      title: '张店长 调整了员工 李收银 的授权',
      time: DateTime(2026, 9, 9, 10, 24),
      module: 'security',
      action: '调整授权',
      detail: '移除角色「收银员」，新增角色「值班经理」',
    ),
  ];
  int? assignedAdminId;
  List<int>? assignedRoleIds;
  List<int>? assignedShopIds;
  bool? assignedConfirm;
  int? deletedRoleId;
  int? deletedApiPermissionId;
  int? deletedPermissionCodeId;
  bool reloadCalled = false;
  ({
    String? roleCode,
    String? roleName,
    List<int>? permissionIds,
    String? forceReason,
  })? createdRole;
  ({
    int? id,
    int? version,
    String? roleName,
    List<int>? permissionIds,
    String? forceReason,
  })? updatedRole;
  ({String? code, String? name})? savedPermissionCode;
  ({String? method, String? path, String? code})? savedApiPermission;

  @override
  Future<PagedCashierAccessEmployees> loadAccessEmployees({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    final filtered = accessEmployees
        .where((e) => keyword.isEmpty || e.userName.contains(keyword))
        .toList();
    final start = (page - 1) * pageSize;
    final items = start >= filtered.length
        ? <CashierAccessEmployee>[]
        : filtered.sublist(start, (start + pageSize).clamp(0, filtered.length));
    return PagedCashierAccessEmployees(
      page: page,
      pageSize: pageSize,
      total: filtered.length,
      items: items,
    );
  }

  @override
  Future<void> assignAccessEmployee({
    required int adminId,
    required List<int> roleIds,
    required List<int> shopIds,
    required bool confirm,
  }) async {
    assignedAdminId = adminId;
    assignedRoleIds = roleIds;
    assignedShopIds = shopIds;
    assignedConfirm = confirm;
  }

  int? createdEmployeeCount;
  int? deletedEmployeeId;
  bool? deletedEmployeeConfirm;

  @override
  Future<void> createEmployee({
    required String userName,
    required String password,
    String? workNo,
    String? realName,
    String? jobTitle,
    List<int>? roleIds,
    List<int>? shopIds,
  }) async {
    createdEmployeeCount = (createdEmployeeCount ?? 0) + 1;
    final newEmployee = CashierAccessEmployee(
      adminId: 100 + (createdEmployeeCount ?? 0),
      userName: userName,
      workNo: workNo ?? '',
      realName: realName ?? '',
      jobTitle: jobTitle ?? '',
      displayName: realName?.isNotEmpty == true ? realName! : userName,
      roles: (roleIds ?? const [])
          .map((id) => CashierAccessRoleRef(id: id, roleName: '角色#$id'))
          .toList(),
      shops: shopIds ?? const [],
    );
    accessEmployees = [...accessEmployees, newEmployee];
  }

  @override
  Future<void> updateEmployee({
    required int adminId,
    String? workNo,
    String? realName,
    String? jobTitle,
    String? password,
    List<int>? roleIds,
    List<int>? shopIds,
  }) async {
    accessEmployees = accessEmployees.map((e) {
      if (e.adminId == adminId) {
        return CashierAccessEmployee(
          adminId: adminId,
          userName: e.userName,
          workNo: workNo ?? e.workNo,
          realName: realName ?? e.realName,
          jobTitle: jobTitle ?? e.jobTitle,
          displayName: realName?.isNotEmpty == true ? realName! : e.displayName,
          phone: e.phone,
          roles: roleIds != null
              ? roleIds
                    .map(
                      (id) => CashierAccessRoleRef(id: id, roleName: '角色#$id'),
                    )
                    .toList()
              : e.roles,
          shops: shopIds ?? e.shops,
        );
      }
      return e;
    }).toList();
  }

  @override
  Future<void> deleteEmployee({
    required int adminId,
    required bool confirm,
  }) async {
    deletedEmployeeId = adminId;
    deletedEmployeeConfirm = confirm;
    accessEmployees = accessEmployees
        .where((e) => e.adminId != adminId)
        .toList();
  }

  int? statusUpdatedAdminId;
  String? statusUpdatedValue;
  int? forceLogoutAdminId;
  int? effectivePermissionAdminId;
  List<String>? conflictCheckedCodes;
  CashierAccessPolicy? createdPolicy;
  CashierAccessPolicy? updatedPolicy;
  int? deletedPolicyId;
  ({int roleId, int policyId, int? shopId})? assignedPolicy;
  int? approvalDetailId;

  @override
  Future<CashierEmployeeStatusResult> updateEmployeeStatus({
    required int adminId,
    required String status,
  }) async {
    statusUpdatedAdminId = adminId;
    statusUpdatedValue = status;
    return CashierEmployeeStatusResult(
      adminId: adminId,
      accountStatus: status,
      permissionVersion: 2,
    );
  }

  @override
  Future<void> forceLogoutEmployee({required int adminId}) async {
    forceLogoutAdminId = adminId;
  }

  @override
  Future<CashierEffectivePermissions> loadEffectivePermissions({
    required int adminId,
    int? shopId,
  }) async {
    effectivePermissionAdminId = adminId;
    return CashierEffectivePermissions(
      adminId: adminId,
      userName: 'zhang_manager',
      realName: '张店长',
      permissions: const ['cashier:operate', 'order:operate:refund'],
    );
  }

  @override
  Future<List<CashierAccessConflict>> checkAccessConflicts({
    required List<String> permissionCodes,
  }) async {
    conflictCheckedCodes = permissionCodes;
    return const [];
  }

  @override
  Future<List<CashierAccessPolicy>> loadAccessPolicies({
    String? permissionCode,
  }) async =>
      const [];

  @override
  Future<CashierAccessPolicy> createAccessPolicy(
    CashierAccessPolicy policy,
  ) async {
    createdPolicy = policy;
    return policy;
  }

  @override
  Future<CashierAccessPolicy> updateAccessPolicy({
    required int id,
    required CashierAccessPolicy policy,
  }) async {
    updatedPolicy = policy;
    return policy;
  }

  @override
  Future<void> deleteAccessPolicy(int id) async {
    deletedPolicyId = id;
  }

  @override
  Future<void> assignAccessPolicy({
    required int roleId,
    required int policyId,
    int? shopId,
  }) async {
    assignedPolicy = (roleId: roleId, policyId: policyId, shopId: shopId);
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async {
    approvalDetailId = id;
    return null;
  }

  @override
  Future<List<CashierAccessRole>> loadAccessRoles() async => accessRoles;

  @override
  Future<void> createAccessRole({
    required String roleCode,
    required String roleName,
    String remark = '',
    int sortOrder = 100,
    List<int>? permissionIds,
    String? forceReason,
  }) async {
    createdRole = (
      roleCode: roleCode,
      roleName: roleName,
      permissionIds: permissionIds,
      forceReason: forceReason,
    );
  }

  @override
  Future<void> updateAccessRole({
    required int id,
    required int version,
    String? roleName,
    String? remark,
    int? sortOrder,
    List<int>? permissionIds,
    String? forceReason,
  }) async {
    updatedRole = (
      id: id,
      version: version,
      roleName: roleName,
      permissionIds: permissionIds,
      forceReason: forceReason,
    );
  }

  @override
  Future<void> deleteAccessRole({
    required int id,
    required bool confirm,
  }) async {
    deletedRoleId = id;
  }

  @override
  Future<List<CashierPermissionCode>> loadPermissionCodes() async =>
      permissionCodes;

  @override
  Future<void> savePermissionCode({
    int? id,
    String? permissionCode,
    String? permissionName,
    String? module,
    String? remark,
    int? sortOrder,
  }) async {
    savedPermissionCode = (code: permissionCode, name: permissionName);
  }

  @override
  Future<void> deletePermissionCode(int id) async {
    deletedPermissionCodeId = id;
  }

  @override
  Future<List<CashierApiPermission>> loadApiPermissions() async =>
      apiPermissions;

  @override
  Future<void> saveApiPermission({
    int? id,
    required String method,
    required String pathPattern,
    required String permissionCode,
    String remark = '',
  }) async {
    savedApiPermission = (
      method: method,
      path: pathPattern,
      code: permissionCode,
    );
  }

  @override
  Future<void> deleteApiPermission(int id) async {
    deletedApiPermissionId = id;
  }

  @override
  Future<void> reloadApiPermissions() async {
    reloadCalled = true;
  }

  @override
  Future<List<CashierAccessAuditEntry>> loadAccessAudit({
    int page = 1,
    int pageSize = 20,
  }) async {
    final start = (page - 1) * pageSize;
    return start >= accessAudit.length
        ? <CashierAccessAuditEntry>[]
        : accessAudit.sublist(
            start,
            (start + pageSize).clamp(0, accessAudit.length),
          );
  }

  @override
  Future<List<CashierShopRef>> loadShopList({String keyword = ''}) async =>
      shopList;

  @override
  Future<PagedCashierAdministrators> loadAdministrators() async =>
      const PagedCashierAdministrators(items: [], total: 0, allRoles: []);

  @override
  Future<CashierBusinessSettings> loadBusinessSettings() async {
    businessLoads++;
    return const CashierBusinessSettings(
      isOpen: true,
      isReviewed: true,
      shopId: 8,
    );
  }

  @override
  Future<CashierSettingsShift?> loadCurrentShift() async => null;

  CashierPrinterDevice? savedPrinterDevice;
  int? deletedPrinterId;
  int? testedPrinterId;

  String? testedPrinterType;
  String? testedPrinterContent;
  bool throwConflictOnSave = false;

  @override
  Future<CashierPrinterDevice> savePrinterDevice(
    CashierPrinterDevice device,
  ) async {
    if (throwConflictOnSave) {
      throw Exception('409 PRINTING_VERSION_CONFLICT');
    }
    savedPrinterDevice = device;
    return device.copyWith(id: device.id ?? 101, version: device.version + 1);
  }

  @override
  Future<bool> deletePrinterDevice(int id) async {
    deletedPrinterId = id;
    return true;
  }

  @override
  Future<bool> testPrinterDevice(
    int id, {
    String? testType,
    String? customContent,
  }) async {
    testedPrinterId = id;
    testedPrinterType = testType;
    testedPrinterContent = customContent;
    return true;
  }

  @override
  Future<CashierPrinterStatusProbe> probePrinterDeviceStatus(int id) async {
    return CashierPrinterStatusProbe(
      deviceId: id,
      online: true,
      status: 'ONLINE',
      paperStatus: 'NORMAL',
      coverStatus: 'CLOSED',
      lastPingTime: DateTime.now(),
    );
  }

  int? clearedPrinterQueueId;
  int? reprintedJobId;
  int? savedRulesVersion;
  List<Map<String, Object?>>? savedRulesList;

  @override
  Future<bool> clearPrinterQueue(int id) async {
    clearedPrinterQueueId = id;
    return true;
  }

  @override
  Future<bool> reprintPrintJob(int id) async {
    reprintedJobId = id;
    return true;
  }

  @override
  Future<bool> savePrintingRules({
    required int version,
    required List<Map<String, Object?>> rules,
  }) async {
    savedRulesVersion = version;
    savedRulesList = rules;
    return true;
  }

  List<PrintingTemplate> templates = [];

  @override
  Future<List<PrintingTemplate>> loadPrintingTemplates({
    String? scenario,
    String? paperSize,
  }) async {
    return templates.where((t) {
      if (scenario != null && scenario != 'ALL' && t.scenario != scenario)
        return false;
      if (paperSize != null && paperSize != 'ALL' && t.paperSize != paperSize)
        return false;
      return true;
    }).toList();
  }

  @override
  Future<PrintingTemplate> getPrintingTemplate(int id) async {
    return templates.firstWhere(
      (t) => t.id == id,
      orElse: () => throw Exception('Template not found'),
    );
  }

  @override
  Future<PrintingTemplate> createPrintingTemplate({
    required String templateName,
    String? templateCode,
    required String scenario,
    String paperSize = '58mm',
    bool isDefault = false,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  }) async {
    final newId = (templates.isEmpty
        ? 1
        : templates.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1);
    final created = PrintingTemplate(
      id: newId,
      shopId: 8,
      templateCode: templateCode ?? 'tpl_${scenario.toLowerCase()}_$newId',
      templateName: templateName,
      scenario: scenario,
      paperSize: paperSize,
      isSystem: false,
      isDefault: isDefault,
      templateJson: templateJson,
      templateDsl: templateDsl != null
          ? PrintTemplateDsl.fromJson(templateDsl)
          : null,
      version: 1,
      createdAt: DateTime.now(),
    );
    templates.add(created);
    return created;
  }

  @override
  Future<PrintingTemplate> updatePrintingTemplate({
    required int id,
    required int version,
    String? templateName,
    String? scenario,
    String? paperSize,
    bool? isDefault,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  }) async {
    final idx = templates.indexWhere((t) => t.id == id);
    if (idx < 0) throw Exception('Template not found');
    final cur = templates[idx];
    final updated = cur.copyWith(
      templateName: templateName ?? cur.templateName,
      scenario: scenario ?? cur.scenario,
      paperSize: paperSize ?? cur.paperSize,
      isDefault: isDefault ?? cur.isDefault,
      templateJson: templateJson ?? cur.templateJson,
      templateDsl: templateDsl != null
          ? PrintTemplateDsl.fromJson(templateDsl)
          : cur.templateDsl,
      version: cur.version + 1,
      updatedAt: DateTime.now(),
    );
    templates[idx] = updated;
    return updated;
  }

  @override
  Future<bool> deletePrintingTemplate(int id) async {
    templates.removeWhere((t) => t.id == id);
    return true;
  }

  @override
  Future<PrintingTemplate> setDefaultPrintingTemplate(int id) async {
    final idx = templates.indexWhere((t) => t.id == id);
    if (idx < 0) throw Exception('Template not found');
    final cur = templates[idx];
    for (int i = 0; i < templates.length; i++) {
      if (templates[i].scenario == cur.scenario) {
        templates[i] = templates[i].copyWith(isDefault: templates[i].id == id);
      }
    }
    return templates[idx];
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    int? deviceId,
    String paperSize = '58mm',
    bool isAddDishes = false,
    List<String>? cidFilter,
    int? detailId,
    int? serveQty,
    int? shiftId,
    String? testType,
    String? customContent,
    int? templateId,
    String? templateJson,
    Map<String, Object?>? templateDsl,
    Map<String, Object?>? refundInfo,
    Map<String, Object?>? statistics,
  }) async {
    return PrintPreviewResult(
      scenario: scenario,
      scenarioName: '打印预览',
      paperSize: paperSize,
      paperWidthMm: paperSize == '80mm' ? 80 : 58,
      paperWidthChars: paperSize == '80mm' ? 48 : 32,
      shopName: '老肥油边王(松源海鲜街)',
      totalTickets: 1,
      tickets: [
        PrintTicket(
          ticketIndex: 1,
          title: '小票',
          rawContent: 'RAW_PREVIEW',
          plainText: '老肥油边王(松源海鲜街)\n----------------\n招牌大油边 x2  76.00',
          elements: [
            const PrintElement(
              type: PrintElementType.header,
              text: '老肥油边王(松源海鲜街)',
              align: PrintElementAlign.center,
              size: PrintElementSize.large,
            ),
            const PrintElement(type: PrintElementType.divider),
            const PrintElement(
              type: PrintElementType.tableRow,
              columns: ['招牌大油边', 'x2', '76.00'],
              bold: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<PrintingTemplateMeta> getPrintingTemplateMeta() async {
    return PrintingTemplateMeta.fromJson({
      'scenarios': [
        {'code': 'ORDER', 'name': '点餐小票'},
        {'code': 'KITCHEN', 'name': '厨房小票'},
        {'code': 'FULL_ORDER', 'name': '前台整单小票'},
        {'code': 'PRE_CHECKOUT', 'name': '预结单'},
        {'code': 'CHECKOUT', 'name': '结账单'},
        {'code': 'EXPEDITE', 'name': '催菜单'},
        {'code': 'TAKEOUT', 'name': '外卖小票'},
        {'code': 'PACKING', 'name': '打包单'},
        {'code': 'SHIFT', 'name': '交接班报表'},
        {'code': 'REFUND', 'name': '退款单据'},
        {'code': 'LABEL', 'name': '商品标签杯贴'},
        {'code': 'TEST', 'name': '自检测试单'},
      ],
      'parametersByScenario': {
        'SHIFT': [
          {'name': 'shiftId', 'tag': '{班次ID}'},
        ],
        'REFUND': [
          {'name': 'refundAmount', 'tag': '{退款金额}'},
        ],
        'LABEL': [
          {'name': 'goodsName', 'tag': '{商品名称}'},
        ],
      },
    });
  }

  @override
  Future<PrintPreviewResult> fetchExactPrintPreview({
    required String scenario,
    int? orderId,
    String? orderNo,
    int? shiftId,
    int? ruleId,
    int? deviceId,
    int? detailId,
    int? serveQty,
    List<String>? cidFilter,
  }) {
    return fetchPrintPreview(
      scenario: scenario,
      orderId: orderId,
      orderNo: orderNo,
      shiftId: shiftId,
      deviceId: deviceId,
      detailId: detailId,
      serveQty: serveQty,
      cidFilter: cidFilter,
    );
  }

  // ============ 外卖管理（UI009） ============
  ShopTakeoutConfig? savedTakeoutConfig;
  ZsqAutoApiConfig? savedZsqAutoApi;
  final List<String> deliveryOperations = [];
  final List<TakeoutDeliveryRecord> deliveryRecords = [
    TakeoutDeliveryRecord(
      orderId: 9001,
      orderNo: 'ORD20260909018',
      receiverName: '陈小姐',
      receiverPhone: '138****2210',
      addressFull: '江门市蓬江区建设路 88 号',
      deliveryFee: 8,
      dispatchStatus: 'delivering',
      zsqDispatchStatus: 'dispatched',
      zsqPhase: 'TO_USER',
      zsqRiderName: '张师傅',
      createdAt: DateTime(2026, 9, 9, 12, 31),
    ),
    TakeoutDeliveryRecord(
      orderId: 9002,
      orderNo: 'ORD20260909012',
      receiverName: '李先生',
      receiverPhone: '136****7755',
      addressFull: '江门市蓬江区发展大道 5 号',
      deliveryFee: 5,
      dispatchStatus: 'completed',
      zsqDispatchStatus: 'completed',
      zsqPhase: 'DELIVERED',
      createdAt: DateTime(2026, 9, 9, 11, 58),
    ),
    TakeoutDeliveryRecord(
      orderId: 9003,
      orderNo: 'ORD20260909007',
      receiverName: '王女士',
      receiverPhone: '189****3321',
      addressFull: '江门市蓬江区丰乐路 12 号',
      deliveryFee: 10,
      dispatchStatus: 'dispatch_failed',
      zsqDispatchStatus: 'failed',
      zsqPhase: 'WAITING_RIDER',
      createdAt: DateTime(2026, 9, 9, 11, 20),
    ),
    TakeoutDeliveryRecord(
      orderId: 9004,
      orderNo: 'ORD20260908096',
      receiverName: '赵先生',
      receiverPhone: '137****9088',
      addressFull: '江门市江海区江南路 21 号',
      deliveryFee: 5,
      dispatchStatus: 'cancelled',
      zsqDispatchStatus: 'cancelled',
      zsqPhase: 'CANCELLED',
      createdAt: DateTime(2026, 9, 8, 18, 42),
    ),
    ...List.generate(
      41,
      (i) => TakeoutDeliveryRecord(
        orderId: 9100 + i,
        orderNo: 'ORD20260909R${(i + 1).toString().padLeft(3, '0')}',
        receiverName: '顾客${i + 1}',
        receiverPhone: '139****00${i % 90 + 10}',
        addressFull: '江门市新会区测试路 ${i + 1} 号',
        deliveryFee: (i % 5) * 2 + 2,
        dispatchStatus: i % 3 == 0
            ? 'accepted'
            : (i % 3 == 1 ? 'completed' : 'cancelled'),
        zsqDispatchStatus: i % 3 == 0
            ? 'pending'
            : (i % 3 == 1 ? 'completed' : 'cancelled'),
        zsqPhase: i % 3 == 0
            ? 'WAITING_RIDER'
            : (i % 3 == 1 ? 'DELIVERED' : 'CANCELLED'),
        createdAt: DateTime(2026, 9, 8, 8 + i % 8, i % 60),
      ),
    ),
  ];

  @override
  Future<ShopTakeoutConfig> loadTakeoutConfig() async =>
      const ShopTakeoutConfig(
        shopId: 1,
        enabled: 1,
        deliveryFee: 0,
        minOrderAmount: 68,
        freeDeliveryThreshold: 168,
        maxDeliveryDistanceKm: 5,
        freeDeliveryMaxDistanceKm: 5,
        leadTimeMinutes: 30,
        remark: '起送68元；1-3km 5元、3-4km 8元、4-5km 10元；满168元5公里内免配送费',
        tiers: [
          DeliveryFeeTier(toKm: 3, fee: 5),
          DeliveryFeeTier(toKm: 4, fee: 8),
          DeliveryFeeTier(toKm: 5, fee: 10),
        ],
      );

  @override
  Future<ShopTakeoutConfig> saveTakeoutConfig(ShopTakeoutConfig config) async {
    savedTakeoutConfig = config;
    return config;
  }

  @override
  Future<ZsqAutoApiConfig> loadZsqAutoApi() async => const ZsqAutoApiConfig(
    shopId: 1,
    autoDispatchEnabled: true,
    takeoutSyncEnabled: true,
  );

  @override
  Future<ZsqAutoApiConfig> saveZsqAutoApi(ZsqAutoApiConfig config) async {
    savedZsqAutoApi = config;
    return config;
  }

  @override
  @override
  Future<PagedTakeoutDeliveries> loadTakeoutDeliveries({
    int page = 1,
    int pageSize = 20,
    String? dispatchStatus,
    DateTime? start,
    DateTime? end,
  }) async {
    final filtered = dispatchStatus == null || dispatchStatus.isEmpty
        ? deliveryRecords
        : deliveryRecords
              .where((r) => r.dispatchStatus == dispatchStatus)
              .toList(growable: false);
    final start = (page - 1) * pageSize;
    final slice = start >= filtered.length
        ? const <TakeoutDeliveryRecord>[]
        : filtered.sublist(
            start,
            start + pageSize > filtered.length
                ? filtered.length
                : start + pageSize,
          );
    return PagedTakeoutDeliveries(items: slice, total: filtered.length);
  }

  @override
  Future<TakeoutDeliveryDetail> loadTakeoutDeliveryDetail(int orderId) async {
    final record = deliveryRecords
        .where((r) => r.orderId == orderId)
        .firstOrNull;
    return TakeoutDeliveryDetail(
      orderId: orderId,
      orderNo: record?.orderNo ?? '#$orderId',
      delivery: record,
    );
  }

  @override
  Future<ZsqRiderTracking> loadTakeoutTracking(int orderId) async =>
      const ZsqRiderTracking(
        riderName: '张师傅',
        riderPhone: '137****1122',
        phase: 'TO_USER',
        statusDesc: '配送中',
        platformDistanceText: '0.8 公里',
        platformDurationText: '12 分钟',
        toUserMinutes: 12,
        logs: [
          ZsqTrackingLog(time: null, text: '骑手已接单（张师傅）'),
          ZsqTrackingLog(time: null, text: '骑手到店取货'),
          ZsqTrackingLog(time: null, text: '配送中 · 距店铺 0.8km'),
        ],
      );

  @override
  Future<TakeoutDeliveryDetail> updateTakeoutDeliveryStatus(
    int orderId,
    String dispatchStatus,
  ) async {
    deliveryOperations.add('status:$orderId:$dispatchStatus');
    final record = deliveryRecords
        .where((r) => r.orderId == orderId)
        .firstOrNull;
    return TakeoutDeliveryDetail(
      orderId: orderId,
      orderNo: record?.orderNo ?? '#$orderId',
      delivery: record,
    );
  }

  @override
  Future<TakeoutDeliveryDetail> zsqDispatch(
    int orderId, {
    bool redispatch = false,
  }) async {
    deliveryOperations.add(
      redispatch ? 'redispatch:$orderId' : 'dispatch:$orderId',
    );
    final record = deliveryRecords
        .where((r) => r.orderId == orderId)
        .firstOrNull;
    return TakeoutDeliveryDetail(
      orderId: orderId,
      orderNo: record?.orderNo ?? '#$orderId',
      delivery: record,
    );
  }

  @override
  Future<TakeoutDeliveryDetail> zsqSync(int orderId) async {
    deliveryOperations.add('sync:$orderId');
    final record = deliveryRecords
        .where((r) => r.orderId == orderId)
        .firstOrNull;
    return TakeoutDeliveryDetail(
      orderId: orderId,
      orderNo: record?.orderNo ?? '#$orderId',
      delivery: record,
    );
  }

  @override
  Future<List<SubscribeSceneTemplate>> listSubscribeSceneTemplates() async => [];

  @override
  Future<bool> createSubscribeSceneTemplate(
    Map<String, dynamic> data,
  ) async => true;

  @override
  Future<bool> updateSubscribeSceneTemplate(
    String sceneCode,
    Map<String, dynamic> data,
  ) async => true;

  @override
  Future<bool> deleteSubscribeSceneTemplate(
    String sceneCode,
  ) async => true;

  @override
  Future<List<SubscribeSendLog>> listSubscribeSendLogs({
    String? bizNo,
    String? openid,
    String? scene,
    String? status,
    int limit = 50,
  }) async => [];
}

class _FakeAuthorityKdsRuntime implements CashierKdsRuntime {
  _FakeAuthorityKdsRuntime({required this.initialStatus})
    : status = initialStatus;

  final String initialStatus;
  String status;
  int refreshCount = 0;
  int port = 17026;
  int restartCount = 0;

  @override
  String get lanStatus => status;

  @override
  String? get lanError => null;

  @override
  int get lanPort => port;

  @override
  int get configuredPort => port;

  @override
  String get cashierDeviceCode => 'CASHIER-TEST-01';

  @override
  int get connectedDeviceCount => 0;

  @override
  bool get isAvailable => true;

  @override
  List<CashierKdsInteractionLog> get interactionLogs => const [];

  @override
  int get droppedInteractionLogCount => 0;

  @override
  Future<List<String>> lanAddresses() async => ['192.168.1.10:$port'];

  @override
  Future<void> restartLanServer() async {
    restartCount += 1;
    status = 'active';
  }

  @override
  Future<void> refreshProxyListener() async {
    refreshCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
