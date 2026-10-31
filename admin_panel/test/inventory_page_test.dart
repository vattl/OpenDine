import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_inventory_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeSettingsRepository implements CashierSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('inventory settings page (M-E)', () {
    Widget build({
      required FakeHttpTransport transport,
      required String sectionId,
      Set<String> permissions = const {},
    }) {
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 8,
      );
      return MaterialApp(
        home: Scaffold(
          body: CashierSettingsInventoryPage(
            repository: _FakeSettingsRepository(),
            client: client,
            section: SettingsSectionSpec(
              sectionId,
              'section',
              Icons.inventory_2_outlined,
            ),
            permissions: permissions,
          ),
        ),
      );
    }

    testWidgets('purchase section lists purchases and shows manage actions',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/purchases': jsonEncode({
          'items': [
            {
              'id': 1,
              'status': 'PENDING_REVIEW',
              'supplierName': '鲜达',
              'warehouseName': '主仓',
              'items': [
                {'materialId': 1, 'qty': 2, 'price': 10},
              ],
            },
          ],
        }),
        'GET /admin/inventory/suppliers': jsonEncode({'items': []}),
        'GET /admin/inventory/warehouses': jsonEncode({'items': []}),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'purchase',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('采购单'), findsOneWidget);
      expect(find.text('采购单 #1'), findsOneWidget);
      expect(find.text('待审核'), findsOneWidget);
      expect(find.text('审核通过'), findsOneWidget);
      expect(find.text('驳回'), findsOneWidget);
    });

    testWidgets('purchase section hides manage actions without permission',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/purchases': jsonEncode({
          'items': [
            {'id': 2, 'status': 'RECEIVED', 'supplierId': 1, 'warehouseId': 1},
          ],
        }),
        'GET /admin/inventory/suppliers': jsonEncode({'items': []}),
        'GET /admin/inventory/warehouses': jsonEncode({'items': []}),
      });

      await tester.pumpWidget(build(transport: transport, sectionId: 'purchase'));
      await tester.pumpAndSettle();

      expect(find.text('采购单 #2'), findsOneWidget);
      expect(find.text('新建采购单'), findsNothing);
      expect(find.text('审核通过'), findsNothing);
    });

    testWidgets('transfers section shows receive for in-transit orders',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/transfers': jsonEncode({
          'items': [
            {
              'id': 7,
              'status': 'IN_TRANSIT',
              'fromWarehouseId': 1,
              'toWarehouseId': 2,
              'materialId': 55,
              'qty': 3,
            },
          ],
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'transfers',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('调拨单 #7'), findsOneWidget);
      expect(find.text('在途'), findsOneWidget);
      expect(find.text('确认收货'), findsOneWidget);
    });

    testWidgets('bom section shows activate action for non-active versions',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/boms': jsonEncode({
          'items': [
            {
              'id': 9,
              'dishId': 88,
              'versionNo': 'v1',
              'status': 'DRAFT',
              'dishName': '招牌烧鸡',
            },
          ],
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'bom',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('招牌烧鸡 · v1'), findsOneWidget);
      expect(find.text('草稿'), findsOneWidget);
      expect(find.text('激活'), findsOneWidget);
    });

    testWidgets('suppliers section lists rows and opens add dialog',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/suppliers': jsonEncode({
          'items': [
            {'id': 1, 'name': '江门鲜达', 'contactName': '陈生'},
          ],
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'suppliers',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('江门鲜达'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory-supplier-edit-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('inventory-supplier-delete-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('inventory-supplier-add')));
      await tester.pumpAndSettle();
      expect(find.text('新增供应商'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('inventory-supplier-form-name')),
        findsOneWidget,
      );
    });

    testWidgets('warehouses section lists rows and hides add without permission',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/warehouses': jsonEncode({
          'items': [
            {'id': 1, 'name': '主仓', 'legalEntity': '江门老飞餐饮'},
          ],
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'warehouses'),
      );
      await tester.pumpAndSettle();

      expect(find.text('主仓'), findsOneWidget);
      expect(find.text('新增仓库'), findsNothing);
    });

    testWidgets('batches section lists rows with FEFO fields',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/batches': jsonEncode({
          'items': [
            {
              'id': 20,
              'batchNo': 'B001',
              'materialName': '牛肉',
              'qty': 10,
              'expiryDate': '2026-12-01',
              'available': 8,
            },
          ],
        }),
      });

      await tester.pumpWidget(build(transport: transport, sectionId: 'batches'));
      await tester.pumpAndSettle();

      expect(find.textContaining('B001'), findsOneWidget);
      expect(find.textContaining('到期 2026-12-01'), findsOneWidget);
    });

    testWidgets('transfers section opens create dialog with warehouse options',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/transfers': jsonEncode({'items': []}),
        'GET /admin/inventory/warehouses': jsonEncode({
          'items': [
            {'id': 1, 'name': '主仓', 'legalEntity': '江门老飞餐饮'},
            {'id': 2, 'name': '冷库', 'legalEntity': '江门老飞餐饮'},
          ],
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'transfers',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inventory-transfer-create')));
      await tester.pumpAndSettle();

      expect(find.text('创建调拨单'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory-transfer-form-from')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('inventory-transfer-form-items')),
        findsOneWidget,
      );
    });

    testWidgets('bom section opens create dialog', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/boms': jsonEncode({'items': []}),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'bom',
          permissions: const {'inventory:manage'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inventory-bom-create')));
      await tester.pumpAndSettle();

      expect(find.text('新建 BOM 配方'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory-bom-form-dish')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('inventory-bom-form-items')),
        findsOneWidget,
      );
    });
  });
}