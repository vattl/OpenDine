import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_approval_dialog.dart';
import 'package:admin_panel_flutter/src/features/orders/domain/admin_order.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('WI-064 乐观并发控制 · 异常与冲突判定', () {
    test('HTTP 409 + ORDER_VERSION_CONFLICT 识别为版本冲突并解析 conflictRevision', () {
      const ex = ApiException(
        '订单已被其他终端修改，请刷新后重试',
        statusCode: 409,
        reasonCode: 'ORDER_VERSION_CONFLICT',
        data: {'error_code': 'ORDER_VERSION_CONFLICT', 'revision': 5},
      );
      expect(ex.isOrderVersionConflict, isTrue);
      expect(ex.conflictRevision, 5);
    });

    test('HTTP 409 + 提示文字包含"订单已被其他终端修改"识别为版本冲突', () {
      const ex = ApiException(
        '订单已被其他终端修改',
        statusCode: 409,
      );
      expect(ex.isOrderVersionConflict, isTrue);
    });

    test('普通 400 或 500 不误判为版本冲突', () {
      const ex1 = ApiException(
        '库存不足',
        statusCode: 400,
        reasonCode: 'INSUFFICIENT_STOCK',
      );
      expect(ex1.isOrderVersionConflict, isFalse);
      expect(ex1.conflictRevision, isNull);

      const ex2 = ApiException(
        '服务器异常',
        statusCode: 500,
      );
      expect(ex2.isOrderVersionConflict, isFalse);
    });
  });

  group('WI-064 订单模型 · revision 解析与 copyWith', () {
    test('PosOrder 解析 revision 字段 (camel / snake)', () {
      final order1 = PosOrder.fromJson({
        'id': 1,
        'orderNo': 'ORD-001',
        'tableNumber': 'A01',
        'diners': 2,
        'total': 100.0,
        'grossAmount': 100.0,
        'createdAt': '2026-10-24 10:00:00',
        'revision': 3,
        'lines': [],
      });
      expect(order1.revision, 3);

      final order2 = PosOrder.fromJson({
        'id': 2,
        'order_no': 'ORD-002',
        'table_number': 'A02',
        'diners': 1,
        'total': 50.0,
        'gross_amount': 50.0,
        'order_revision': 7,
        'lines': [],
      });
      expect(order2.revision, 7);

      final order3 = order1.copyWith(revision: 4);
      expect(order3.revision, 4);
      expect(order3.orderNo, 'ORD-001');
    });

    test('CashierBill 解析 revision 字段', () {
      final bill1 = CashierBill.fromJson({
        'id': 1,
        'order_no': 'ORD-001',
        'revision': 6,
        'lines': [],
      });
      expect(bill1.revision, 6);

      final bill2 = CashierBill.fromJson({
        'id': 2,
        'orderNo': 'ORD-002',
        'order_revision': 8,
        'lines': [],
      });
      expect(bill2.revision, 8);

      final billCopied = bill1.copyWith(revision: 9);
      expect(billCopied.revision, 9);
    });

    test('AdminOrder 解析 revision 字段', () {
      final adminOrder = AdminOrder.fromJson({
        'id': 10,
        'order_no': 'ORD-010',
        'table_number': 'B01',
        'revision': 12,
        'lines': [],
      });
      expect(adminOrder.revision, 12);

      final copied = adminOrder.copyWith(revision: 13);
      expect(copied.revision, 13);
    });
  });

  group('WI-064 RealPosRepository · expectedVersion 提交与 revision 响应提取', () {
    test('addDishes 发送 camelCase expectedVersion，禁止发送 snake_case，并提取 revision', () async {
      final transport = _CapturingTransport(
        responseJson: {'code': 0, 'revision': 5, 'data': {}},
      );
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token-test',
        shopId: 1,
      );
      final repo = RealPosRepository(client);

      final dish = PosDish.fromJson({
        'id': 1,
        'name': '羊肉串',
        'typeId': 1,
        'unitprice': 5.0,
        'unit': '串',
      });

      final nextRev = await repo.addDishes(
        orderNo: 'ORD-100',
        tableNumber: 'A01',
        lines: const PosCart().add(dish).lines,
        expectedVersion: 4,
      );

      expect(nextRev, 5);
      final sentBody = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
      expect(sentBody['expectedVersion'], 4);
      expect(sentBody.containsKey('expected_version'), isFalse);
    });

    test('refundDish 发送 expectedVersion 并提取 revision', () async {
      final transport = _CapturingTransport(
        responseJson: {'code': 0, 'revision': 6},
      );
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token-test',
        shopId: 1,
      );
      final repo = RealPosRepository(client);

      final nextRev = await repo.refundDish(
        orderNo: 'ORD-100',
        detailId: 10,
        quantity: 1,
        approvalToken: 'test-approval-token',
        expectedVersion: 5,
      );

      expect(nextRev, 6);
      final sentBody = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
      expect(sentBody['expectedVersion'], 5);
      expect(sentBody['approvalToken'], 'test-approval-token');
      expect(sentBody.containsKey('expected_version'), isFalse);
    });

    test('giftDish 发送 expectedVersion 并提取 revision', () async {
      final transport = _CapturingTransport(
        responseJson: {'code': 0, 'revision': 7},
      );
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token-test',
        shopId: 1,
      );
      final repo = RealPosRepository(client);

      final nextRev = await repo.giftDish(
        orderNo: 'ORD-100',
        detailId: 10,
        approvalToken: 'test-approval-token',
        expectedVersion: 6,
      );

      expect(nextRev, 7);
      final sentBody = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
      expect(sentBody['expectedVersion'], 6);
      expect(sentBody['approvalToken'], 'test-approval-token');
      expect(sentBody.containsKey('expected_version'), isFalse);
    });

    test('discountOrder 发送 expectedVersion 并提取 revision', () async {
      final transport = _CapturingTransport(
        responseJson: {'code': 0, 'revision': 8},
      );
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token-test',
        shopId: 1,
      );
      final repo = RealPosRepository(client);

      final nextRev = await repo.discountOrder(
        orderNo: 'ORD-100',
        discountAmount: 10.0,
        reason: '整单优惠',
        approvalToken: 'test-approval-token',
        expectedVersion: 7,
      );

      expect(nextRev, 8);
      final sentBody = jsonDecode(transport.lastBody!) as Map<String, dynamic>;
      expect(sentBody['expectedVersion'], 7);
      expect(sentBody['approvalToken'], 'test-approval-token');
      expect(sentBody.containsKey('expected_version'), isFalse);
    });
  });

  group('WI-064 敏感操作流 · 冲突时终止重试且不弹审批窗', () {
    testWidgets('遇到 ORDER_VERSION_CONFLICT: 不弹授权窗，不重试，弹出提示，返回 false', (tester) async {
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: FakeHttpTransport(const {}),
        token: 'fake-token',
        shopId: 1,
        terminalId: 'POS-01',
      );
      final repo = AccessApprovalRepository(client);
      var executeCalls = 0;
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await runSensitiveWithApproval(
                    context: context,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '退菜审批',
                      permission: refundPermission,
                      permissionLabel: '退菜',
                      bizType: 'ORDER',
                      bizId: 'ORD-CONFLICT',
                    ),
                    execute: (token) async {
                      executeCalls++;
                      throw const ApiException(
                        '订单已被其他终端修改，请刷新后重试',
                        statusCode: 409,
                        reasonCode: 'ORDER_VERSION_CONFLICT',
                        data: {'error_code': 'ORDER_VERSION_CONFLICT', 'revision': 9},
                      );
                    },
                  );
                },
                child: const Text('执行退菜'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('执行退菜'));
      await tester.pumpAndSettle();

      // 验证未弹出店长授权弹窗
      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
      // 验证只执行了 1 次（没有重试或用最新 revision 重放旧动作）
      expect(executeCalls, 1);
      // 验证展示了警告弹窗
      expect(find.text('订单版本冲突'), findsOneWidget);
      expect(find.text('订单已被其他终端修改，请确认后重试'), findsOneWidget);

      // 点击确认关闭提示弹窗
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // 返回结果为 false
      expect(result, isFalse);
    });
  });
}

class _CapturingTransport implements HttpTransport {
  _CapturingTransport({required this.responseJson});

  final Map<String, dynamic> responseJson;
  String? lastBody;
  Map<String, String> lastHeaders = const {};

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    lastHeaders = headers;
    lastBody = body;
    return HttpResponseData(
      statusCode: 200,
      body: jsonEncode(responseJson),
    );
  }
}
