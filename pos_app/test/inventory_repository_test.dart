import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/real_inventory_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/inventory_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('inventory models', () {
    test('parses purchase list rows with camel and snake fields', () {
      final purchase = InventoryPurchase.fromJson({
        'id': 12,
        'status': 'PENDING_REVIEW',
        'supplier_id': 3,
        'supplier_name': '江门鲜达供应商',
        'warehouseId': 5,
        'warehouse_name': '主仓',
        'items': [
          {'materialId': 101, 'qty': 2, 'price': 12.5},
          {'materialId': 102, 'qty': 1, 'price': 8},
        ],
        'created_at': '2026-10-07T10:00:00',
      });

      expect(purchase.id, 12);
      expect(purchase.status, 'PENDING_REVIEW');
      expect(purchase.supplierId, 3);
      expect(purchase.supplierName, '江门鲜达供应商');
      expect(purchase.warehouseId, 5);
      expect(purchase.warehouseName, '主仓');
      expect(purchase.itemCount, 2);
      expect(purchase.totalAmount, 33.0);
    });

    test('parses itemsJson string into bom item count', () {
      final bom = InventoryBom.fromJson({
        'id': 7,
        'dishId': 88,
        'versionNo': 'v2',
        'status': 'HISTORY',
        'dishName': '招牌烧鸡',
        'itemsJson': '[{"materialId":1,"qty":1}]',
        'effectiveFrom': '2026-09-01',      });

      expect(bom.dishId, 88);
      expect(bom.versionNo, 'v2');
      expect(bom.status, 'HISTORY');
      expect(bom.itemCount, 1);
      expect(bom.dishName, '招牌烧鸡');
    });

    test('extractInventoryList handles bare list, items map and data map', () {
      final fromBare = extractInventoryList([
        {'id': 1},
        {'id': 2},
      ]);
      final fromItems = extractInventoryList({
        'items': [
          {'id': 3},
        ],
      });
      final fromData = extractInventoryList({
        'data': [
          {'id': 4},
        ],
      });
      final fromEmpty = extractInventoryList({'total': 0});

      expect(fromBare.length, 2);
      expect(fromItems.single['id'], 3);
      expect(fromData.single['id'], 4);
      expect(fromEmpty, isEmpty);
    });
  });

  group('inventory repository', () {
    RealInventoryRepository build(FakeHttpTransport transport) {
      return RealInventoryRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('listPurchases sends status/page query and parses rows', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/purchases': jsonEncode({
          'items': [
            {'id': 1, 'status': 'APPROVED', 'supplierId': 2, 'warehouseId': 3},
          ],
        }),
      });
      final repository = build(transport);

      final result =
          await repository.listPurchases(status: 'APPROVED', page: 2, pageSize: 50);

      expect(result.single.id, 1);
      expect(result.single.status, 'APPROVED');
      expect(transport.requests.single.uri.queryParameters['status'], 'APPROVED');
      expect(transport.requests.single.uri.queryParameters['page'], '2');
      expect(transport.requests.single.uri.queryParameters['pageSize'], '50');
      expect(transport.requests.single.headers['X-Shop-Id'], '8');
    });

    test('createPurchase posts supplier/warehouse/items and rejects empty items',
        () async {
      final transport = FakeHttpTransport({
        'POST /admin/inventory/purchases': jsonEncode({
          'id': 21,
          'status': 'PENDING_REVIEW',
          'supplierId': 2,
          'warehouseId': 3,
        }),
      });
      final repository = build(transport);

      await expectLater(
        repository.createPurchase(supplierId: 2, warehouseId: 3, items: const []),
        throwsArgumentError,
      );

      final result = await repository.createPurchase(
        supplierId: 2,
        warehouseId: 3,
        items: const [
          {'materialId': 11, 'qty': 2.0, 'price': 15.0},
        ],
      );

      expect(result.id, 21);
      expect(result.status, 'PENDING_REVIEW');
      expect(jsonDecode(transport.requests.last.body!), {
        'supplierId': 2,
        'warehouseId': 3,
        'items': [
          {'materialId': 11, 'qty': 2.0, 'price': 15.0},
        ],
      });
    });

    test('updatePurchaseStatus sends id/action/reason', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/inventory/purchases': jsonEncode({'code': 0}),
      });
      final repository = build(transport);

      await repository.updatePurchaseStatus(
        id: 21,
        action: 'reject',
        reason: '单价有误',
      );

      expect(jsonDecode(transport.requests.single.body!), {
        'id': 21,
        'action': 'reject',
        'reason': '单价有误',
      });
    });

    test('receiveTransfer calls path-scoped PUT endpoint', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/inventory/transfers/7/receive': jsonEncode({
          'id': 7,
          'status': 'RECEIVED',
          'fromWarehouseId': 1,
          'toWarehouseId': 2,
          'materialId': 55,
          'qty': 3,
          'batchNo': 'B20261007',
        }),
      });
      final repository = build(transport);

      final result = await repository.receiveTransfer(id: 7);

      expect(result.status, 'RECEIVED');
      expect(result.batchNo, 'B20261007');
      expect(transport.requests.single.method, 'PUT');
      expect(transport.requests.single.uri.path, '/admin/inventory/transfers/7/receive');
    });

    test('listTransfers filters by status', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/transfers': jsonEncode({
          'items': [
            {'id': 7, 'status': 'IN_TRANSIT', 'fromWarehouseId': 1, 'toWarehouseId': 2},
          ],
        }),
      });
      final repository = build(transport);

      final result = await repository.listTransfers(status: 'IN_TRANSIT');

      expect(result.single.id, 7);
      expect(result.single.status, 'IN_TRANSIT');
      expect(transport.requests.single.uri.queryParameters['status'], 'IN_TRANSIT');
    });

    test('listBoms and activateBom round trip', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/boms': jsonEncode({
          'items': [
            {'id': 9, 'dishId': 88, 'versionNo': 'v1', 'status': 'DRAFT'},
          ],
        }),
        'PUT /admin/inventory/boms/9/activate': jsonEncode({
          'id': 9,
          'dishId': 88,
          'versionNo': 'v1',
          'status': 'ACTIVE',
        }),
      });
      final repository = build(transport);

      final list = await repository.listBoms();
      expect(list.single.status, 'DRAFT');

      final activated = await repository.activateBom(id: 9);
      expect(activated.status, 'ACTIVE');
      expect(transport.requests.last.method, 'PUT');
      expect(transport.requests.last.uri.path, '/admin/inventory/boms/9/activate');
    });

    test('createPurchase response as direct body map is tolerated', () async {
      final transport = FakeHttpTransport({
        'POST /admin/inventory/purchases':
            jsonEncode({'id': 30, 'status': 'PENDING_REVIEW'}),
      });
      final repository = build(transport);

      final result = await repository.createPurchase(
        supplierId: 1,
        warehouseId: 2,
        items: const [
          {'materialId': 1, 'qty': 1.0, 'price': 1.0},
        ],
      );

      expect(result.id, 30);
    });

    test('listSuppliers and add/update/delete round trip', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/suppliers': jsonEncode({
          'items': [
            {'id': 1, 'name': '江门鲜达', 'contactName': '陈生'},
          ],
        }),
        'POST /admin/inventory/suppliers': jsonEncode({'id': 2}),
        'PUT /admin/inventory/suppliers': jsonEncode({'ok': true}),
        'DELETE /admin/inventory/suppliers': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      final list = await repository.listSuppliers();
      expect(list.single.name, '江门鲜达');

      final added = await repository.addSupplier(
        const InventorySupplier(id: 0, name: '新供应商'),
      );
      expect(added.id, 2);
      expect(
        jsonDecode(transport.requests[1].body!),
        {'name': '新供应商'},
      );

      await repository.updateSupplier(
        const InventorySupplier(
          id: 2,
          name: '新供应商',
          contactPhone: '13800138000',
        ),
      );
      final updateBody = jsonDecode(transport.requests[2].body!) as Map;
      expect(updateBody['id'], 2);
      expect(updateBody['contactPhone'], '13800138000');

      await repository.deleteSupplier(id: 2);
      expect(transport.requests.last.method, 'DELETE');
      expect(
        transport.requests.last.uri.queryParameters['id'],
        '2',
      );
    });

    test('addSupplier rejects empty name', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.addSupplier(const InventorySupplier(id: 0, name: ' ')),
        throwsArgumentError,
      );
    });

    test('listWarehouses and add/update round trip', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/warehouses': jsonEncode({
          'items': [
            {'id': 1, 'name': '主仓', 'legalEntity': '江门老飞餐饮'},
          ],
        }),
        'POST /admin/inventory/warehouses': jsonEncode({'id': 3}),
        'PUT /admin/inventory/warehouses': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      final list = await repository.listWarehouses();
      expect(list.single.legalEntity, '江门老飞餐饮');

      final added = await repository.addWarehouse(
        const InventoryWarehouse(
          id: 0,
          name: '冷库',
          legalEntity: '江门老飞餐饮',
        ),
      );
      expect(added.id, 3);
      expect(jsonDecode(transport.requests[1].body!), {
        'name': '冷库',
        'legalEntity': '江门老飞餐饮',
      });

      await repository.updateWarehouse(
        const InventoryWarehouse(
          id: 3,
          name: '冷库2',
          legalEntity: '江门老飞餐饮',
        ),
      );
      expect(jsonDecode(transport.requests[2].body!), {
        'id': 3,
        'name': '冷库2',
        'legalEntity': '江门老飞餐饮',
      });
    });

    test('addWarehouse rejects missing legalEntity', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.addWarehouse(
          const InventoryWarehouse(id: 0, name: 'x', legalEntity: ''),
        ),
        throwsArgumentError,
      );
    });

    test('createBom posts dishId/items/effectiveFrom', () async {
      final transport = FakeHttpTransport({
        'POST /admin/inventory/boms': jsonEncode({
          'id': 11,
          'dishId': 88,
          'versionNo': 'v3',
          'status': 'DRAFT',
        }),
      });
      final repository = build(transport);

      final created = await repository.createBom(
        dishId: 88,
        items: const [
          {'materialId': 1, 'qty': 2.0, 'unit': 'kg'},
        ],
        effectiveFrom: '2026-10-08 00:00:00',
      );

      expect(created.versionNo, 'v3');
      expect(jsonDecode(transport.requests.single.body!), {
        'dishId': 88,
        'items': [
          {'materialId': 1, 'qty': 2.0, 'unit': 'kg'},
        ],
        'effectiveFrom': '2026-10-08 00:00:00',
      });
    });

    test('createBom rejects empty items', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.createBom(dishId: 88, items: const []),
        throwsArgumentError,
      );
    });

    test('updateBom posts body with id', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/inventory/boms': jsonEncode({'id': 11, 'status': 'DRAFT'}),
      });
      final repository = build(transport);

      await repository.updateBom(
        id: 11,
        dishId: 88,
        items: const [
          {'materialId': 2, 'qty': 1.0},
        ],
      );

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['id'], 11);
      expect(body['dishId'], 88);
    });

    test('createTransfer posts from/to/items and validates', () async {
      final transport = FakeHttpTransport({
        'POST /admin/inventory/transfers': jsonEncode({
          'id': 5,
          'status': 'IN_TRANSIT',
          'fromWarehouseId': 1,
          'toWarehouseId': 2,
        }),
      });
      final repository = build(transport);

      final created = await repository.createTransfer(
        fromWarehouseId: 1,
        toWarehouseId: 2,
        items: const [
          {'batchId': 10, 'materialId': 3, 'qty': 5.0},
        ],
      );

      expect(created.status, 'IN_TRANSIT');
      expect(jsonDecode(transport.requests.single.body!), {
        'fromWarehouseId': 1,
        'toWarehouseId': 2,
        'items': [
          {'batchId': 10, 'materialId': 3, 'qty': 5.0},
        ],
      });
    });

    test('createTransfer rejects same warehouse or empty items', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.createTransfer(
          fromWarehouseId: 1,
          toWarehouseId: 1,
          items: const [
            {'batchId': 1, 'materialId': 1, 'qty': 1.0},
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createTransfer(
          fromWarehouseId: 1,
          toWarehouseId: 2,
          items: const [],
        ),
        throwsArgumentError,
      );
    });

    test('listBatches parses rows with FEFO fields', () async {
      final transport = FakeHttpTransport({
        'GET /admin/inventory/batches': jsonEncode({
          'items': [
            {
              'id': 20,
              'batchNo': 'B001',
              'materialId': 3,
              'warehouseId': 1,
              'qty': 10,
              'expiryDate': '2026-12-01',
              'available': 8,
            },
          ],
        }),
      });
      final repository = build(transport);

      final batches = await repository.listBatches(warehouseId: 1);

      expect(batches.single.batchNo, 'B001');
      expect(batches.single.available, 8);
      expect(
        transport.requests.single.uri.queryParameters['warehouse_id'],
        '1',
      );
    });
  });
}
