import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/real_cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_printing/data/unified_print_service.dart';
import 'package:admin_panel_flutter/src/features/cashier_printing/domain/unified_print_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/data/real_cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('UnifiedPrintRequest serialization', () {
    test('Scenario 1: minimal kitchen order reprint with only orderNo', () {
      const req = UnifiedPrintRequest(orderNo: '2026100512300001');
      final json = req.toJson();
      expect(json['order_no'], '2026100512300001');
      expect(json['is_reprint'], isTrue);
      expect(json.containsKey('cid_list'), isFalse);
      expect(json.containsKey('scenario'), isFalse);
    });

    test('Scenario 2: partial dish kitchen reprint with cidList and reason', () {
      const req = UnifiedPrintRequest(
        orderNo: '2026100512300001',
        cidList: [1024, 1025],
        reason: '顾客催单重印',
      );
      final json = req.toJson();
      expect(json['order_no'], '2026100512300001');
      expect(json['cid_list'], [1024, 1025]);
      expect(json['reason'], '顾客催单重印');
      expect(json['is_reprint'], isTrue);
    });

    test('Scenario 3: checkout receipt reprint', () {
      const req = UnifiedPrintRequest(
        orderNo: '2026100512300001',
        scenario: UnifiedPrintScenario.checkout,
        isReprint: true,
      );
      final json = req.toJson();
      expect(json['order_no'], '2026100512300001');
      expect(json['scenario'], 'checkout');
      expect(json['is_reprint'], isTrue);
    });

    test('Scenario 4: directed print to specific device', () {
      const req = UnifiedPrintRequest(
        orderNo: '2026100512300001',
        deviceId: 8,
        copies: 1,
      );
      final json = req.toJson();
      expect(json['device_id'], 8);
      expect(json['copies'], 1);
    });

    test('Scenario 5: shift handover report reprint', () {
      const req = UnifiedPrintRequest(
        scenario: UnifiedPrintScenario.shift,
        shiftId: 66,
      );
      final json = req.toJson();
      expect(json['scenario'], 'shift');
      expect(json['shift_id'], 66);
    });
  });

  group('UnifiedPrintResult deserialization and state', () {
    test('successfully parses multi-job success response', () {
      final json = {
        'total_jobs': 2,
        'dispatched_count': 2,
        'failed_count': 0,
        'summary': '成功分发 2 个打印任务到 2 台设备',
        'jobs': [
          {
            'job_id': 10581,
            'device_id': 3,
            'device_name': '后厨热菜档口打印机',
            'status': 'SUCCESS',
            'copies': 1,
          },
          {
            'job_id': 10582,
            'device_id': 4,
            'device_name': '后厨凉菜/烧烤打印机',
            'status': 'SUCCESS',
            'copies': 1,
          }
        ],
      };

      final result = UnifiedPrintResult.fromJson(json);
      expect(result.totalJobs, 2);
      expect(result.dispatchedCount, 2);
      expect(result.failedCount, 0);
      expect(result.isSuccess, isTrue);
      expect(result.hasFailures, isFalse);
      expect(result.jobs.length, 2);
      expect(result.jobs.first.deviceName, '后厨热菜档口打印机');
      expect(result.jobs.first.isSuccess, isTrue);
    });

    test('correctly identifies partial failures and extracts error messages', () {
      final json = {
        'total_jobs': 2,
        'dispatched_count': 1,
        'failed_count': 1,
        'summary': '部分打印任务派发失败',
        'jobs': [
          {
            'job_id': 10581,
            'device_id': 3,
            'device_name': '后厨热菜档口打印机',
            'status': 'SUCCESS',
            'copies': 1,
          },
          {
            'job_id': 10582,
            'device_id': 4,
            'device_name': '后厨凉菜/烧烤打印机',
            'status': 'FAILED',
            'copies': 1,
            'error_message': '设备离线',
          }
        ],
      };

      final result = UnifiedPrintResult.fromJson(json);
      expect(result.isSuccess, isFalse);
      expect(result.hasFailures, isTrue);
      expect(result.firstErrorMessage, '后厨凉菜/烧烤打印机: 设备离线');
    });
  });

  group('PosPrintResult backward compatibility and dispatch parsing', () {
    test('parses from UnifiedPrintResponse structure', () {
      final dispatchData = {
        'total_jobs': 1,
        'dispatched_count': 1,
        'failed_count': 0,
        'summary': '成功分发 1 个打印任务',
        'order_no': '2026100512300001',
      };
      final posResult = PosPrintResult.fromJson(dispatchData);
      expect(posResult.printSuccess, isTrue);
      expect(posResult.content, '成功分发 1 个打印任务');
      expect(posResult.orderNo, '2026100512300001');
    });

    test('parses from legacy structure', () {
      final legacyData = {
        'content': 'ESC/POS RAW TICKET CONTENT',
        'printSuccess': true,
        'orderNo': '2026100512300001',
      };
      final posResult = PosPrintResult.fromJson(legacyData);
      expect(posResult.printSuccess, isTrue);
      expect(posResult.content, 'ESC/POS RAW TICKET CONTENT');
      expect(posResult.orderNo, '2026100512300001');
    });
  });

  final successDispatchResponse = jsonEncode({
    'code': 200,
    'msg': 'success',
    'data': {
      'total_jobs': 1,
      'dispatched_count': 1,
      'failed_count': 0,
      'summary': '成功分发 1 个打印任务',
      'jobs': [
        {
          'job_id': 10581,
          'device_id': 3,
          'device_name': '后厨打印机',
          'status': 'SUCCESS',
          'copies': 1,
        }
      ],
    },
  });

  group('UnifiedPrintService', () {
    test('dispatch routes to cashier endpoint by default', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final service = UnifiedPrintService(client);
      final result = await service.reprintKitchenOrder(orderNo: 'ORD001');

      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'ORD001');
      expect(body['scenario'], 'kitchen');
      expect(result.isSuccess, isTrue);
    });

    test('dispatch routes to admin endpoint when isAdmin is true', () async {
      final transport = FakeHttpTransport({
        'POST /admin/printing/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final service = UnifiedPrintService(client);
      await service.reprintReceipt(orderNo: 'ORD002', isAdmin: true);

      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/admin/printing/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'ORD002');
      expect(body['scenario'], 'checkout');
    });
  });

  group('RealCashierBillRepository print migration', () {
    test('printKitchen targets cashierPrintDispatchEndpoint', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealCashierBillRepository(client);

      await repo.printKitchen(orderNo: 'B001', categoryIds: ['10', '20']);
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'B001');
      expect(body['scenario'], 'kitchen');
      expect(body['cid_list'], [10, 20]);
    });

    test('printReceipt targets cashierPrintDispatchEndpoint directly', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealCashierBillRepository(client);

      await repo.printReceipt(orderNo: 'B002', orderId: 99);
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'B002');
      expect(body['order_id'], 99);
      expect(body['scenario'], 'checkout');
    });

    test('printReceipt dispatches pre_checkout scenario when specified', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealCashierBillRepository(client);

      await repo.printReceipt(
        orderNo: 'B003',
        scenario: 'pre_checkout',
      );
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'B003');
      expect(body['scenario'], 'pre_checkout');
      expect(body['is_reprint'], isTrue);
    });
  });

  group('RealPosRepository print migration', () {
    test('reprintKitchenTicket targets cashierPrintDispatchEndpoint', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      await repo.reprintKitchenTicket(orderNo: 'POS001');
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_no'], 'POS001');
      expect(body['scenario'], 'kitchen');
    });

    test('printFrontTicket dispatches full_order (前台小票)', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      final result = await repo.printFrontTicket(orderId: 88, orderNo: 'POS002');
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['order_id'], 88);
      expect(body['order_no'], 'POS002');
      expect(body['scenario'], 'full_order');
      expect(result.printSuccess, isTrue);
    });

    for (final entry in <PosReceiptPrintType, String>{
      PosReceiptPrintType.kitchen: 'kitchen',
      PosReceiptPrintType.front: 'full_order',
      PosReceiptPrintType.preCheckout: 'pre_checkout',
      PosReceiptPrintType.checkout: 'checkout',
    }.entries) {
      test('printReceiptTicket dispatches ${entry.value}', () async {
        final transport = FakeHttpTransport({
          'POST /cashier/print/dispatch': successDispatchResponse,
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
        );
        final repo = RealPosRepository(client);

        await repo.printReceiptTicket(
          type: entry.key,
          orderId: 88,
          orderNo: 'POS002',
        );
        final body = jsonDecode(transport.requests.single.body!) as Map;
        expect(body['order_id'], 88);
        expect(body['order_no'], 'POS002');
        expect(body['scenario'], entry.value);
        expect(body['is_reprint'], isTrue);
      });
    }
  });

  group('RealCashierShiftRepository print migration', () {
    test('reprintShiftTicket targets cashierPrintDispatchEndpoint with scenario=shift', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': successDispatchResponse,
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
      );
      final repo = RealCashierShiftRepository(client);

      await repo.reprintShiftTicket(55);
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['scenario'], 'shift');
      expect(body['shift_id'], 55);
      expect(body['is_reprint'], isTrue);
    });
  });
}
