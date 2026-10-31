import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/wechat_native_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('Cashier WeChat Native Pay Models & Normalization', () {
    test('normalizes native and offline payment channels correctly', () {
      expect(
        PosPaymentChannelKind.normalize('online_wechat'),
        PosPaymentChannelKind.wechatNative,
      );
      expect(
        PosPaymentChannelKind.normalize('wechat_native'),
        PosPaymentChannelKind.wechatNative,
      );
      expect(
        PosPaymentChannelKind.normalize('native_wechat'),
        PosPaymentChannelKind.wechatNative,
      );
      expect(
        PosPaymentChannelKind.normalize('cashier_wechat_native'),
        PosPaymentChannelKind.wechatNative,
      );

      // Offline collection channel backwards compatibility
      expect(
        PosPaymentChannelKind.normalize('offline_wechat_qr'),
        PosPaymentChannelKind.wechat,
      );
      expect(
        PosPaymentChannelKind.normalize('wechat_qr'),
        PosPaymentChannelKind.wechat,
      );
      expect(
        PosPaymentChannelKind.normalize('wechat'),
        PosPaymentChannelKind.wechat,
      );
      expect(
        PosPaymentChannelKind.normalize('微信收款码'),
        PosPaymentChannelKind.wechat,
      );
    });

    test('parses PosWechatNativeOrder correctly from JSON', () {
      final json = {
        'code': 0,
        'msg': 'success',
        'data': {
          'paymentId': 101,
          'orderNo': 'ORD20261015001',
          'outTradeNo': 'WN20261015001',
          'codeUrl': 'weixin://wxpay/bizpayurl?pr=abcdef',
          'amountFen': 8800,
          'expiresAt': '2026-10-15T12:00:00Z',
          'tradeState': 'NOTPAY',
          'reused': true,
        },
      };

      final order = PosWechatNativeOrder.fromJson(json);
      expect(order.paymentId, 101);
      expect(order.orderNo, 'ORD20261015001');
      expect(order.outTradeNo, 'WN20261015001');
      expect(order.codeUrl, 'weixin://wxpay/bizpayurl?pr=abcdef');
      expect(order.amountFen, 8800);
      expect(order.amountYuan, 88.0);
      expect(order.tradeState, 'NOTPAY');
      expect(order.reused, isTrue);
      expect(order.expiresAt, isNotNull);
    });

    test('parses PosWechatNativeStatus correctly from JSON', () {
      final json = {
        'paymentId': 101,
        'orderNo': 'ORD20261015001',
        'outTradeNo': 'WN20261015001',
        'amountFen': 8800,
        'tradeState': 'SUCCESS',
        'status': 'PAID',
        'transactionId': 'WX4200000001',
      };

      final status = PosWechatNativeStatus.fromJson(json);
      expect(status.paymentId, 101);
      expect(status.orderNo, 'ORD20261015001');
      expect(status.tradeState, 'SUCCESS');
      expect(status.status, 'PAID');
      expect(status.isSuccess, isTrue);
      expect(status.isClosed, isFalse);
      expect(status.transactionId, 'WX4200000001');
    });

    test('parses PosWechatNativeCloseResult correctly from JSON', () {
      final json = {
        'closed': true,
        'idempotent': true,
        'outTradeNo': 'WN20261015001',
      };

      final closeResult = PosWechatNativeCloseResult.fromJson(json);
      expect(closeResult.closed, isTrue);
      expect(closeResult.idempotent, isTrue);
      expect(closeResult.outTradeNo, 'WN20261015001');
    });
  });

  group('RealPosRepository WeChat Native Pay API integration', () {
    test('createWechatNativeOrder sends POST and parses response', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/native/orders': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'paymentId': 102,
            'orderNo': 'ORD002',
            'outTradeNo': 'OUT002',
            'codeUrl': 'weixin://wxpay/bizpayurl?pr=xyz123',
            'amountFen': 5000,
            'tradeState': 'NOTPAY',
            'reused': false,
          },
        }),
      });

      final repo = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test-token',
          shopId: 1,
        ),
      );

      final result = await repo.createWechatNativeOrder(
        orderNo: 'ORD002',
        terminalId: 'POS-01',
      );

      expect(result.paymentId, 102);
      expect(result.orderNo, 'ORD002');
      expect(result.amountFen, 5000);
      expect(result.codeUrl, 'weixin://wxpay/bizpayurl?pr=xyz123');

      final req = transport.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/cashier/payment/wechat/native/orders');
      final body = jsonDecode(req.body!) as Map<String, dynamic>;
      expect(body['orderNo'], 'ORD002');
      expect(body['terminalId'], 'POS-01');
      expect(body.containsKey('amount'), isFalse);
      expect(body.containsKey('amountFen'), isFalse);
    });

    test('queryWechatNativeOrder sends GET with encoded orderNo', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/payment/wechat/native/orders/ORD003': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'paymentId': 103,
            'orderNo': 'ORD003',
            'outTradeNo': 'OUT003',
            'amountFen': 6600,
            'tradeState': 'SUCCESS',
            'status': 'PAID',
            'transactionId': 'TX999',
          },
        }),
      });

      final repo = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test-token',
          shopId: 1,
        ),
      );

      final status = await repo.queryWechatNativeOrder(orderNo: 'ORD003');
      expect(status.paymentId, 103);
      expect(status.tradeState, 'SUCCESS');
      expect(status.isSuccess, isTrue);
      expect(status.transactionId, 'TX999');

      final req = transport.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/cashier/payment/wechat/native/orders/ORD003');
    });

    test('closeWechatNativeOrder sends POST with encoded orderNo', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/native/orders/ORD004/close': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'closed': true,
            'idempotent': false,
            'outTradeNo': 'OUT004',
          },
        }),
      });

      final repo = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test-token',
          shopId: 1,
        ),
      );

      final closeResult = await repo.closeWechatNativeOrder(orderNo: 'ORD004');
      expect(closeResult.closed, isTrue);

      final req = transport.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/cashier/payment/wechat/native/orders/ORD004/close');
    });

    test('throws CashierWechatNativeException with business code on failure', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/native/orders': jsonEncode({
          'code': 40931,
          'msg': '当前订单存在处理中的出码记录，请稍后刷新',
        }),
      });

      final repo = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test-token',
          shopId: 1,
        ),
      );

      expect(
        () => repo.createWechatNativeOrder(orderNo: 'ORD005'),
        throwsA(
          isA<CashierWechatNativeException>()
              .having((e) => e.code, 'code', 40931)
              .having((e) => e.message, 'message', contains('处理中的出码记录')),
        ),
      );
    });
  });

  group('WechatNativeCheckoutDialog Widget Tests', () {
    const dummyOrder = PosOrder(
      id: 1,
      orderNo: 'ORD-TEST-001',
      tableNumber: 'A08',
      diners: 2,
      total: 88.5,
      grossAmount: 88.5,
      createdAt: null,
      lines: [],
    );

    testWidgets('renders QR code, amount, and order number properly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final createdOrder = PosWechatNativeOrder(
        paymentId: 1,
        orderNo: 'ORD-TEST-001',
        outTradeNo: 'OUT-TEST-001',
        codeUrl: 'weixin://wxpay/bizpayurl?pr=TEST1234',
        amountFen: 8850,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        tradeState: 'NOTPAY',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WechatNativeCheckoutDialog(
              order: dummyOrder,
              createOrder: () async => createdOrder,
              queryOrder: () async => const PosWechatNativeStatus(
                paymentId: 1,
                orderNo: 'ORD-TEST-001',
                outTradeNo: 'OUT-TEST-001',
                amountFen: 8850,
                tradeState: 'NOTPAY',
                status: 'UNPAID',
              ),
              closeOrder: () async => const PosWechatNativeCloseResult(
                closed: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('微信支付'), findsWidgets);
      expect(find.textContaining('A08'), findsOneWidget);
      expect(find.textContaining('ORD-TEST-001'), findsOneWidget);
      expect(find.text('¥88.50'), findsOneWidget);
      expect(find.text('关闭支付'), findsOneWidget);
      expect(find.text('立即主动查单'), findsOneWidget);
    });

    testWidgets('automatically pops with success when query reports isSuccess', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final createdOrder = PosWechatNativeOrder(
        paymentId: 2,
        orderNo: 'ORD-TEST-001',
        outTradeNo: 'OUT-TEST-002',
        codeUrl: 'weixin://wxpay/bizpayurl?pr=TEST9999',
        amountFen: 8850,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        tradeState: 'NOTPAY',
      );

      var queryCount = 0;
      WechatNativeDialogResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<WechatNativeDialogResult>(
                      context: context,
                      builder: (_) => WechatNativeCheckoutDialog(
                        order: dummyOrder,
                        createOrder: () async => createdOrder,
                        queryOrder: () async {
                          queryCount++;
                          if (queryCount >= 2) {
                            return const PosWechatNativeStatus(
                              paymentId: 2,
                              orderNo: 'ORD-TEST-001',
                              outTradeNo: 'OUT-TEST-002',
                              amountFen: 8850,
                              tradeState: 'SUCCESS',
                              status: 'PAID',
                              transactionId: 'WX123456',
                            );
                          }
                          return const PosWechatNativeStatus(
                            paymentId: 2,
                            orderNo: 'ORD-TEST-001',
                            outTradeNo: 'OUT-TEST-002',
                            amountFen: 8850,
                            tradeState: 'USERPAYING',
                            status: 'PAYING',
                          );
                        },
                        closeOrder: () async => const PosWechatNativeCloseResult(
                          closed: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dialogResult, isNull);

      // Advance 2s for poll 1
      await tester.pump(const Duration(seconds: 2));
      expect(dialogResult, isNull);

      // Advance 2s for poll 2 (isSuccess -> true)
      await tester.pump(const Duration(seconds: 2));
      // Dialog shows success view for 1200ms before popping
      await tester.pump(const Duration(milliseconds: 1300));

      expect(dialogResult, WechatNativeDialogResult.success);
    });

    testWidgets('cancels and closes order when user clicks cancel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var closeCalled = false;
      final createdOrder = PosWechatNativeOrder(
        paymentId: 3,
        orderNo: 'ORD-TEST-001',
        outTradeNo: 'OUT-TEST-003',
        codeUrl: 'weixin://wxpay/bizpayurl?pr=TEST_CANCEL',
        amountFen: 8850,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        tradeState: 'NOTPAY',
      );

      WechatNativeDialogResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<WechatNativeDialogResult>(
                      context: context,
                      builder: (_) => WechatNativeCheckoutDialog(
                        order: dummyOrder,
                        createOrder: () async => createdOrder,
                        queryOrder: () async => const PosWechatNativeStatus(
                          paymentId: 3,
                          orderNo: 'ORD-TEST-001',
                          outTradeNo: 'OUT-TEST-003',
                          amountFen: 8850,
                          tradeState: 'NOTPAY',
                          status: 'UNPAID',
                        ),
                        closeOrder: () async {
                          closeCalled = true;
                          return const PosWechatNativeCloseResult(
                            closed: true,
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('关闭支付'), findsOneWidget);
      await tester.tap(find.text('关闭支付'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(closeCalled, isTrue);
      expect(dialogResult, WechatNativeDialogResult.cancelled);
    });

    testWidgets('top-right close icon dismisses dialog with cancelled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var closeCalled = false;
      final createdOrder = PosWechatNativeOrder(
        paymentId: 3,
        orderNo: 'ORD-TEST-001',
        outTradeNo: 'OUT-TEST-003',
        codeUrl: 'weixin://wxpay/bizpayurl?pr=TEST_CANCEL',
        amountFen: 8850,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        tradeState: 'NOTPAY',
      );

      WechatNativeDialogResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<WechatNativeDialogResult>(
                      context: context,
                      builder: (_) => WechatNativeCheckoutDialog(
                        order: dummyOrder,
                        createOrder: () async => createdOrder,
                        queryOrder: () async => const PosWechatNativeStatus(
                          paymentId: 3,
                          orderNo: 'ORD-TEST-001',
                          outTradeNo: 'OUT-TEST-003',
                          amountFen: 8850,
                          tradeState: 'NOTPAY',
                          status: 'UNPAID',
                        ),
                        closeOrder: () async {
                          closeCalled = true;
                          return const PosWechatNativeCloseResult(closed: true);
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('wechat-native-header-close-btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wechat-native-header-close-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(closeCalled, isTrue);
      expect(dialogResult, WechatNativeDialogResult.cancelled);
    });

    testWidgets('shows force exit confirmation when closeOrder fails and allows force exit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final createdOrder = PosWechatNativeOrder(
        paymentId: 3,
        orderNo: 'ORD-TEST-001',
        outTradeNo: 'OUT-TEST-003',
        codeUrl: 'weixin://wxpay/bizpayurl?pr=TEST_FAIL_CLOSE',
        amountFen: 8850,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        tradeState: 'NOTPAY',
      );

      WechatNativeDialogResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<WechatNativeDialogResult>(
                      context: context,
                      builder: (_) => WechatNativeCheckoutDialog(
                        order: dummyOrder,
                        createOrder: () async => createdOrder,
                        queryOrder: () async => const PosWechatNativeStatus(
                          paymentId: 3,
                          orderNo: 'ORD-TEST-001',
                          outTradeNo: 'OUT-TEST-003',
                          amountFen: 8850,
                          tradeState: 'NOTPAY',
                          status: 'UNPAID',
                        ),
                        closeOrder: () async {
                          throw const CashierWechatNativeException(
                            code: 50333,
                            message: '微信关单失败，请先查单确认支付状态',
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Click "关闭支付" which fails closeOrder
      await tester.tap(find.text('关闭支付'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Force exit confirmation dialog should appear
      expect(find.byKey(const Key('wechat-native-force-exit-dialog')), findsOneWidget);
      expect(find.text('强制退出微信支付确认'), findsOneWidget);

      // Tap confirm force exit
      await tester.tap(find.byKey(const Key('wechat-native-confirm-force-exit-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dialogResult, WechatNativeDialogResult.cancelled);
    });

    testWidgets('allows direct force exit on anomaly view (code: 50331/40931)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      WechatNativeDialogResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showDialog<WechatNativeDialogResult>(
                      context: context,
                      builder: (_) => WechatNativeCheckoutDialog(
                        order: dummyOrder,
                        createOrder: () async {
                          throw const CashierWechatNativeException(
                            code: 50331,
                            message: '微信下单结果暂不确定，请先查询支付状态，勿重复收款',
                          );
                        },
                        queryOrder: () async => const PosWechatNativeStatus(
                          paymentId: 3,
                          orderNo: 'ORD-TEST-001',
                          outTradeNo: 'OUT-TEST-003',
                          amountFen: 8850,
                          tradeState: 'NOTPAY',
                          status: 'UNPAID',
                        ),
                        closeOrder: () async {
                          throw const CashierWechatNativeException(
                            code: 50333,
                            message: '微信关单失败，请先查单确认支付状态',
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Anomaly view shown with fallback force exit button
      expect(find.text('下单状态待确认 (防重收款拦截)'), findsOneWidget);
      expect(find.byKey(const Key('wechat-native-force-exit-btn')), findsOneWidget);

      // Tap force exit button
      await tester.tap(find.byKey(const Key('wechat-native-force-exit-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Confirmation dialog appears
      expect(find.byKey(const Key('wechat-native-force-exit-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wechat-native-confirm-force-exit-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dialogResult, WechatNativeDialogResult.cancelled);
    });
  });
}
