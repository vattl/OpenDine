import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_device_capability.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_camera_scanner_view.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/wechat_micropay_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('Cashier WeChat Micropay Models & Normalization', () {
    test('normalizes micropay channel codes correctly', () {
      expect(
        PosPaymentChannelKind.normalize('online_wechat_micropay'),
        PosPaymentChannelKind.wechatMicropay,
      );
      expect(
        PosPaymentChannelKind.normalize('wechat_micropay'),
        PosPaymentChannelKind.wechatMicropay,
      );
      expect(
        PosPaymentChannelKind.normalize('micropay'),
        PosPaymentChannelKind.wechatMicropay,
      );
      expect(
        PosPaymentChannelKind.normalize('微信付款码'),
        PosPaymentChannelKind.wechatMicropay,
      );
      expect(
        PosPaymentChannelKind.normalize('微信付款码支付'),
        PosPaymentChannelKind.wechatMicropay,
      );
      expect(
        PosPaymentChannelKind.normalize('付款码支付'),
        PosPaymentChannelKind.wechatMicropay,
      );
    });

    test('parses PosWechatMicropayOrder correctly from JSON', () {
      final json = {
        'code': 0,
        'msg': 'success',
        'data': {
          'orderNo': 'ORD202610160001',
          'outTradeNo': 'MP202610160001',
          'amountFen': 3800,
          'tradeState': 'SUCCESS',
          'status': 'SUCCESS',
          'transactionId': 'WX42000012345678',
        },
      };

      final order = PosWechatMicropayOrder.fromJson(json);
      expect(order.orderNo, 'ORD202610160001');
      expect(order.outTradeNo, 'MP202610160001');
      expect(order.amountFen, 3800);
      expect(order.amountYuan, 38.0);
      expect(order.tradeState, 'SUCCESS');
      expect(order.status, 'SUCCESS');
      expect(order.isSuccess, isTrue);
      expect(order.isUserPaying, isFalse);
      expect(order.transactionId, 'WX42000012345678');
    });

    test('parses PosWechatMicropayStatus correctly from JSON', () {
      final json = {
        'orderNo': 'ORD202610160001',
        'outTradeNo': 'MP202610160001',
        'amountFen': 3800,
        'tradeState': 'USERPAYING',
        'status': 'USERPAYING',
      };

      final status = PosWechatMicropayStatus.fromJson(json);
      expect(status.orderNo, 'ORD202610160001');
      expect(status.tradeState, 'USERPAYING');
      expect(status.isUserPaying, isTrue);
      expect(status.isSuccess, isFalse);
      expect(status.isClosed, isFalse);
    });

    test('parses PosWechatMicropayReverseResult correctly from JSON', () {
      final json = {
        'reversed': true,
        'alreadyPaid': false,
        'outTradeNo': 'MP202610160001',
      };

      final result = PosWechatMicropayReverseResult.fromJson(json);
      expect(result.reversed, isTrue);
      expect(result.alreadyPaid, isFalse);
      expect(result.outTradeNo, 'MP202610160001');
    });

    test('CashierWechatMicropayException identifies business error codes', () {
      const e40031 = CashierWechatMicropayException(code: 40031, message: 'invalid code');
      expect(e40031.isCodeFormatInvalid, isTrue);

      const e40941 = CashierWechatMicropayException(code: 40941, message: 'pending order');
      expect(e40941.isConflictOrPending, isTrue);

      const e40241 = CashierWechatMicropayException(code: 40241, message: 'denied');
      expect(e40241.isWechatPayDenied, isTrue);

      const e50341 = CashierWechatMicropayException(code: 50341, message: 'uncertain');
      expect(e50341.isUncertainNeedQuery, isTrue);

      const e40944 = CashierWechatMicropayException(code: 40944, message: 'not 15s');
      expect(e40944.isNotMatured15s, isTrue);

      const e50343 = CashierWechatMicropayException(code: 50343, message: 'reverse uncertain');
      expect(e50343.isReverseUncertain, isTrue);
    });
  });

  group('RealPosRepository WeChat Micropay API Integration', () {
    test('payWechatMicropay posts to /cashier/payment/wechat/micropay/orders', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/micropay/orders': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'orderNo': 'ORD202610160001',
            'outTradeNo': 'MP202610160001',
            'amountFen': 3800,
            'tradeState': 'SUCCESS',
            'status': 'SUCCESS',
          },
        }),
      });

      final client = AdminApiClient(
        baseUrl: 'http://example.com',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      final order = await repo.payWechatMicropay(
        orderNo: 'ORD202610160001',
        authCode: '134800001111222233',
        terminalId: 'POS-01',
      );

      expect(order.orderNo, 'ORD202610160001');
      expect(order.isSuccess, isTrue);

      final req = transport.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/cashier/payment/wechat/micropay/orders');
      final body = jsonDecode(req.body!) as Map<String, dynamic>;
      expect(body['orderNo'], 'ORD202610160001');
      expect(body['authCode'], '134800001111222233');
      expect(body['terminalId'], 'POS-01');
      expect(body.containsKey('amount'), isFalse);
      expect(body.containsKey('amountFen'), isFalse);
    });

    test('queryWechatMicropayOrder gets status', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/payment/wechat/micropay/orders/ORD202610160001': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'orderNo': 'ORD202610160001',
            'outTradeNo': 'MP202610160001',
            'amountFen': 3800,
            'tradeState': 'USERPAYING',
            'status': 'USERPAYING',
          },
        }),
      });

      final client = AdminApiClient(
        baseUrl: 'http://example.com',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      final status = await repo.queryWechatMicropayOrder(orderNo: 'ORD202610160001');
      expect(status.isUserPaying, isTrue);

      final req = transport.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/cashier/payment/wechat/micropay/orders/ORD202610160001');
    });

    test('reverseWechatMicropayOrder posts reverse', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/micropay/orders/ORD202610160001/reverse': jsonEncode({
          'code': 0,
          'msg': 'success',
          'data': {
            'reversed': true,
            'alreadyPaid': false,
            'outTradeNo': 'MP202610160001',
          },
        }),
      });

      final client = AdminApiClient(
        baseUrl: 'http://example.com',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      final result = await repo.reverseWechatMicropayOrder(orderNo: 'ORD202610160001');
      expect(result.reversed, isTrue);
      expect(result.alreadyPaid, isFalse);

      final req = transport.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/cashier/payment/wechat/micropay/orders/ORD202610160001/reverse');
    });

    test('throws CashierWechatMicropayException with business code on failure', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/payment/wechat/micropay/orders': jsonEncode({
          'code': 40031,
          'msg': '付款码格式错误或已过期',
        }),
      });

      final client = AdminApiClient(
        baseUrl: 'http://example.com',
        transport: transport,
      );
      final repo = RealPosRepository(client);

      expect(
        () => repo.payWechatMicropay(
          orderNo: 'ORD202610160001',
          authCode: '123',
        ),
        throwsA(isA<CashierWechatMicropayException>().having(
          (e) => e.code,
          'code',
          40031,
        )),
      );
    });
  });

  group('WechatMicropayCheckoutDialog Widget Test', () {
    final testOrder = PosOrder(
      id: 1,
      orderNo: 'ORD202610160001',
      tableNumber: 'A08',
      diners: 2,
      total: 38.0,
      createdAt: DateTime.now(),
      lines: const [],
    );

    testWidgets('renders waiting scan view, validates 18-digit auth code', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WechatMicropayCheckoutDialog(
              order: testOrder,
              payMicropay: (code) async => const PosWechatMicropayOrder(
                orderNo: 'ORD202610160001',
                outTradeNo: 'MP001',
                amountFen: 3800,
                tradeState: 'SUCCESS',
              ),
              queryOrder: () async => const PosWechatMicropayStatus(
                orderNo: 'ORD202610160001',
                outTradeNo: 'MP001',
                amountFen: 3800,
                tradeState: 'SUCCESS',
                status: 'SUCCESS',
              ),
              reverseOrder: () async => const PosWechatMicropayReverseResult(reversed: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('微信付款码支付 (商家扫顾客)'), findsOneWidget);
      expect(find.text('🪑 桌台：A08'), findsOneWidget);
      expect(find.text('¥ 38.00'), findsOneWidget);
      expect(find.text('请使用扫码枪扫描顾客手机微信付款码'), findsOneWidget);
      expect(find.byKey(const Key('wechat-micropay-authcode-input')), findsOneWidget);

      // Submit invalid format (< 18 digits)
      await tester.enterText(find.byKey(const Key('wechat-micropay-authcode-input')), '12345');
      await tester.tap(find.byKey(const Key('wechat-micropay-submit-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('付款码格式错误'), findsOneWidget);

      // Submit valid 18 digits starting with 13
      await tester.enterText(find.byKey(const Key('wechat-micropay-authcode-input')), '134800001111222233');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('微信付款码支付成功！'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets('handles USERPAYING state with polling, channel locking and reverse guard', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      var queryCalled = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WechatMicropayCheckoutDialog(
              order: testOrder,
              initialAuthCode: '134800001111222233',
              payMicropay: (code) async => const PosWechatMicropayOrder(
                orderNo: 'ORD202610160001',
                outTradeNo: 'MP001',
                amountFen: 3800,
                tradeState: 'USERPAYING',
                status: 'USERPAYING',
              ),
              queryOrder: () async {
                queryCalled++;
                return const PosWechatMicropayStatus(
                  orderNo: 'ORD202610160001',
                  outTradeNo: 'MP001',
                  amountFen: 3800,
                  tradeState: 'USERPAYING',
                  status: 'USERPAYING',
                );
              },
              reverseOrder: () async => const PosWechatMicropayReverseResult(reversed: true),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In USERPAYING view
      expect(find.text('顾客正在手机上输入支付密码...'), findsOneWidget);
      expect(find.textContaining('已锁定订单，禁止重新扫码或切换其他渠道'), findsOneWidget);
      expect(find.textContaining('撤销 (15s)'), findsOneWidget);

      // Reversal button is disabled initially
      final reverseBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('wechat-micropay-reverse-button')),
      );
      expect(reverseBtn.onPressed, isNull);

      // Fast forward 2 seconds to trigger silent poll
      await tester.pump(const Duration(seconds: 2));
      expect(queryCalled, greaterThanOrEqualTo(1));

      // Fast forward 14 more seconds to expire 15s reverse guard
      await tester.pump(const Duration(seconds: 14));
      expect(find.text('撤销支付'), findsOneWidget);

      final reverseBtnAfter = tester.widget<OutlinedButton>(
        find.byKey(const Key('wechat-micropay-reverse-button')),
      );
      expect(reverseBtnAfter.onPressed, isNotNull);

      // Tap query button manually
      await tester.tap(find.byKey(const Key('wechat-micropay-query-button')));
      await tester.pump();
      expect(queryCalled, greaterThanOrEqualTo(2));
    });
  });

  group('PosDeviceEnvironment Capability Detection', () {
    testWidgets('identifies android and non-android environments correctly', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            // Android desktop/large tablet (overrideIsAndroid = true, width = 1024)
            expect(
              PosDeviceEnvironment.isAndroidTablet(
                context,
                overrideIsAndroid: true,
                overrideWidth: 1024,
              ),
              isTrue,
            );

            // Android phone (overrideIsAndroid = true, width = 390, shortestSide = 390)
            expect(
              PosDeviceEnvironment.isAndroidTablet(
                context,
                overrideIsAndroid: true,
                overrideWidth: 390,
                overrideShortestSide: 390,
              ),
              isFalse,
            );

            // Non-Android PC (overrideIsAndroid = false, width = 1280)
            expect(
              PosDeviceEnvironment.isAndroidTablet(
                context,
                overrideIsAndroid: false,
                overrideWidth: 1280,
              ),
              isFalse,
            );

            // Android tablet with camera
            expect(
              PosDeviceEnvironment.isAndroidTabletWithCamera(
                context,
                overrideIsAndroid: true,
                overrideHasCamera: true,
                overrideWidth: 800,
              ),
              isTrue,
            );

            // Android tablet without camera
            expect(
              PosDeviceEnvironment.isAndroidTabletWithCamera(
                context,
                overrideIsAndroid: true,
                overrideHasCamera: false,
                overrideWidth: 800,
              ),
              isFalse,
            );

            return const SizedBox();
          },
        ),
      );
    });
  });

  group('Android Tablet Camera Scanner View Interaction', () {
    final testOrder = PosOrder(
      id: 2,
      orderNo: 'ORD202610160002',
      tableNumber: 'B02',
      diners: 4,
      total: 88.0,
      createdAt: DateTime.now(),
      lines: const [],
    );

    testWidgets('shows camera button on Android tablet, opens camera viewfinder and scans', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      String? submittedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WechatMicropayCheckoutDialog(
              order: testOrder,
              isAndroidTabletWithCameraOverride: true,
              payMicropay: (code) async {
                submittedCode = code;
                return const PosWechatMicropayOrder(
                  orderNo: 'ORD202610160002',
                  outTradeNo: 'MP002',
                  amountFen: 8800,
                  tradeState: 'SUCCESS',
                  status: 'SUCCESS',
                  transactionId: 'WX_CAM_42000000',
                );
              },
              queryOrder: () async => const PosWechatMicropayStatus(
                orderNo: 'ORD202610160002',
                outTradeNo: 'MP002',
                amountFen: 8800,
                tradeState: 'SUCCESS',
                status: 'SUCCESS',
              ),
              reverseOrder: () async => const PosWechatMicropayReverseResult(reversed: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tablet detection pill & camera button are visible
      expect(find.byKey(const Key('wechat-micropay-tablet-detect-pill')), findsOneWidget);
      expect(find.text('检测到安卓平板设备，支持免扫码枪直接扫码'), findsOneWidget);
      expect(find.byKey(const Key('wechat-micropay-open-camera-button')), findsOneWidget);
      expect(find.text('打开平板摄像头扫码'), findsOneWidget);

      // Tap open camera button
      await tester.tap(find.byKey(const Key('wechat-micropay-open-camera-button')));
      await tester.pump(const Duration(milliseconds: 100));

      // Viewfinder is displayed
      expect(find.byKey(const Key('wechat-micropay-camera-viewfinder')), findsOneWidget);
      expect(find.text('请将顾客微信付款码（条形码/二维码）对准扫描框'), findsOneWidget);
      expect(find.byKey(const Key('camera-switch-lens-button')), findsOneWidget);
      expect(find.byKey(const Key('camera-toggle-torch-button')), findsOneWidget);
      expect(find.byKey(const Key('camera-switch-to-scanner-gun-button')), findsOneWidget);

      // Toggle lens (rear -> front -> rear)
      await tester.tap(find.byKey(const Key('camera-switch-lens-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('前置镜头'), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera-switch-lens-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('后置镜头'), findsOneWidget);

      // Toggle torch
      await tester.tap(find.byKey(const Key('camera-toggle-torch-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('补光已开'), findsOneWidget);

      // Switch to scanner gun and back
      await tester.tap(find.byKey(const Key('camera-switch-to-scanner-gun-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('wechat-micropay-authcode-input')), findsOneWidget);

      // Re-open camera and simulate barcode detection
      await tester.tap(find.byKey(const Key('wechat-micropay-open-camera-button')));
      await tester.pump(const Duration(milliseconds: 100));

      // Simulate camera recognition of 18-digit auth code
      final scannerFinder = find.byKey(const Key('wechat-micropay-camera-viewfinder'));
      final PosCameraScannerView scannerWidget = tester.widget(scannerFinder);
      scannerWidget.onBarcodeScanned('134812345678901234');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(submittedCode, '134812345678901234');
      expect(find.text('微信付款码支付成功！'), findsOneWidget);
      expect(find.text('¥ 88.00'), findsNWidgets(2));

      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets('does not show camera button on non-tablet PC desktop by default', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WechatMicropayCheckoutDialog(
              order: testOrder,
              isAndroidTabletWithCameraOverride: false,
              payMicropay: (code) async => const PosWechatMicropayOrder(
                orderNo: 'ORD202610160002',
                outTradeNo: 'MP002',
                amountFen: 8800,
                tradeState: 'SUCCESS',
              ),
              queryOrder: () async => const PosWechatMicropayStatus(
                orderNo: 'ORD202610160002',
                outTradeNo: 'MP002',
                amountFen: 8800,
                tradeState: 'SUCCESS',
                status: 'SUCCESS',
              ),
              reverseOrder: () async => const PosWechatMicropayReverseResult(reversed: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wechat-micropay-tablet-detect-pill')), findsNothing);
      expect(find.byKey(const Key('wechat-micropay-open-camera-button')), findsNothing);
      expect(find.byKey(const Key('wechat-micropay-authcode-input')), findsOneWidget);
    });
  });
}
