import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/real_cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/domain/cashier_payment_config.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_payment_config_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('cashier payment config parsing', () {
    test('parses terminal capabilities and inherited merchant templates', () {
      final capabilities = CashierPaymentCapabilities.fromJson({
        'targetShopId': '8',
        'scope': 'shop',
        'hasOwnConfig': 1,
        'inheritsGlobal': false,
        'clients': {
          'cashier': {
            'enabled': true,
            'channels': {
              'wechat': true,
              'alipay': 1,
              'balance': 'true',
              'combined': false,
            },
          },
          'miniProgram': {
            'enabled': true,
            'channels': {'wechat': false, 'balance': true},
          },
        },
        'offlineCollectEnabled': true,
        'offlineCollectChannels': ['wechat'],
        'disabledMessage': '请联系服务员结账',
      });
      final merchants = PaymentMerchantCollection.fromJson({
        'target_shop_id': 8,
        'owned': [
          {
            'id': '21',
            'channel': 'wechat',
            'merchant_key': 'default',
            'mch_id': '1900000109',
            'enabled': 1,
            'has_api_v3_key': true,
          },
        ],
        'inheritedTemplates': [
          {
            'id': 2,
            'channel': 'alipay',
            'merchantKey': 'default',
            'readOnly': true,
            'enabled': true,
          },
        ],
      });

      expect(capabilities.targetShopId, 8);
      expect(capabilities.cashier.alipay, isTrue);
      expect(capabilities.cashier.combined, isFalse);
      expect(capabilities.miniProgram.wechat, isFalse);
      expect(capabilities.offlineChannels, {PaymentChannel.wechat});
      expect(merchants.owned.single.merchantKey, 'default');
      expect(merchants.owned.single.hasApiV3Key, isTrue);
      expect(merchants.inheritedTemplates.single.readOnly, isTrue);
    });

    test('merchant form preserves masked secrets and validates APIv3 and APIv2 keys', () {
      final form = PaymentMerchantForm.fromJson({
        'id': 21,
        'exists': true,
        'editable': true,
        'channel': 'wechat',
        'merchantKey': 'default',
        'apiV3Key': '******',
        'hasApiV3Key': true,
        'apiV2Key': '******',
        'hasApiV2Key': true,
        'clientCertP12Ref': '/path/to/wechat-default.p12',
        'hasClientCertP12': true,
        'alipayAppCertRef': '/path/to/appCert.crt',
        'hasAlipayAppCert': true,
        'alipayPublicCertRef': '/path/to/alipayCert.crt',
        'hasAlipayPublicCert': true,
        'alipayRootCertRef': '/path/to/alipayRoot.crt',
        'hasAlipayRootCert': true,
        'notifyUrlSuggestions': {
          'payment': 'https://example.test/order/notify',
        },
        'missingFields': ['serialNo'],
      });

      expect(form.apiV3Key, PaymentMerchantForm.maskedSecret);
      expect(form.apiV2Key, PaymentMerchantForm.maskedSecret);
      expect(form.hasApiV2Key, isTrue);
      expect(form.clientCertP12Ref, '/path/to/wechat-default.p12');
      expect(form.hasClientCertP12, isTrue);
      expect(form.alipayAppCertRef, '/path/to/appCert.crt');
      expect(form.hasAlipayAppCert, isTrue);
      expect(form.notifyUrlSuggestions['payment'], contains('/order/notify'));

      // Validate APIv3
      expect(validateApiV3Key('', hasExistingKey: true), isNull);
      expect(
        validateApiV3Key('short', hasExistingKey: false),
        'APIv3 密钥必须为 32 位',
      );
      expect(validateApiV3Key('12345678901234567890123456789012'), isNull);

      // Validate APIv2
      expect(validateApiV2Key('', hasExistingKey: true), isNull);
      expect(validateApiV2Key('', hasExistingKey: false), isNull);
      expect(validateApiV2Key('******', hasExistingKey: true), isNull);
      expect(
        validateApiV2Key('short', hasExistingKey: false),
        'APIv2 密钥必须为 32 位',
      );
      expect(validateApiV2Key('12345678901234567890123456789012'), isNull);

      // Validate P12 bytes
      expect(validateClientCertP12Bytes(null), contains('过短或损坏'));
      expect(validateClientCertP12Bytes([1, 2, 3]), contains('过短或损坏'));
      expect(
        validateClientCertP12Bytes(utf8.encode('-----BEGIN CERTIFICATE----- 123456789012345678901234567890')),
        contains('上传的是 PEM 文本文件'),
      );
      final validP12Header = List<int>.filled(32, 0x30);
      expect(validateClientCertP12Bytes(validP12Header), isNull);

      // toSaveJson verification
      final saveJson = form.copyWith(
        apiV2Key: 'abcdefabcdefabcdefabcdefabcdef12',
      ).toSaveJson();
      expect(saveJson['apiV2Key'], 'abcdefabcdefabcdefabcdefabcdef12');
      expect(saveJson['clientCertP12Ref'], '/path/to/wechat-default.p12');
      expect(saveJson['alipayAppCertRef'], '/path/to/appCert.crt');
      expect(saveJson['alipayPublicCertRef'], '/path/to/alipayCert.crt');
      expect(saveJson['alipayRootCertRef'], '/path/to/alipayRoot.crt');
    });

    test('PaymentCertificateUploadResult parses unified upload response', () {
      final res = PaymentCertificateUploadResult.fromJson({
        'certificateType': 'CLIENT_CERT_P12',
        'fileRef': 'payment-keys/shop-1/wechat-default.p12',
        'filename': 'apiclient_cert.p12',
        'fileSize': 2048,
        'clientCertP12Ref': 'payment-keys/shop-1/wechat-default.p12',
      });
      expect(res.certificateType, 'CLIENT_CERT_P12');
      expect(res.fileRef, 'payment-keys/shop-1/wechat-default.p12');
      expect(res.clientCertP12Ref, 'payment-keys/shop-1/wechat-default.p12');
      expect(res.fileSize, 2048);
    });
  });

  group('RealCashierPaymentRepository contract', () {
    test('loads and saves capabilities with shop header', () async {
      final response = {
        'code': 0,
        'data': {
          'onlinePayEnabled': true,
          'clients': {
            'cashier': {
              'enabled': true,
              'channels': {
                'wechat': true,
                'alipay': false,
                'balance': true,
                'combined': false,
              },
            },
            'miniProgram': {
              'enabled': true,
              'channels': {'wechat': false, 'balance': true},
            },
          },
        },
      };
      final transport = FakeHttpTransport({
        'GET /admin/payment/capabilities': jsonEncode(response),
        'PUT /admin/payment/capabilities': jsonEncode(response),
      });
      final repository = RealCashierPaymentRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );

      final capabilities = await repository.loadCapabilities();
      await repository.saveCapabilities(
        capabilities.copyWith(
          cashier: capabilities.cashier.copyWith(alipay: true),
        ),
      );

      expect(transport.requests, hasLength(2));
      expect(
        transport.requests.every(
          (request) => request.headers['X-Shop-Id'] == '8',
        ),
        isTrue,
      );
      expect(transport.requests.last.method, 'PUT');
      expect(jsonDecode(transport.requests.last.body!), {
        'clients': {
          'cashier': {
            'enabled': true,
            'channelStates': {
              'wechat': {'enabled': true},
              'alipay': {'enabled': true},
              'balance': {'enabled': true},
              'combined': {'enabled': false},
              'wechat_qr': {'enabled': false},
              'alipay_qr': {'enabled': false},
            },
          },
          'miniProgram': {
            'enabled': true,
            'channelStates': {
              'wechat': {'enabled': false},
              'balance': {'enabled': true},
              'alipay': {'enabled': false},
            },
          },
        },
        'disabledMessage': '请联系服务员结账',
      });
    });

    test(
      'uses documented list, edit-form, save, detail and delete routes',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/payment/merchants': jsonEncode({
            'code': 0,
            'data': {'owned': <Object?>[], 'inheritedTemplates': <Object?>[]},
          }),
          'GET /admin/payment/merchants/edit-form': jsonEncode({
            'code': 0,
            'data': {
              'exists': false,
              'editable': true,
              'channel': 'wechat',
              'merchantKey': 'default',
            },
          }),
          'PUT /admin/payment/merchants/save': jsonEncode({
            'code': 0,
            'data': {
              'id': 31,
              'exists': true,
              'editable': true,
              'channel': 'wechat',
              'merchantKey': 'default',
            },
          }),
          'GET /admin/payment/merchants/31': jsonEncode({
            'code': 0,
            'data': {
              'id': 31,
              'exists': true,
              'editable': true,
              'channel': 'wechat',
              'merchantKey': 'default',
            },
          }),
          'DELETE /admin/payment/merchants/31': jsonEncode({
            'code': 0,
            'data': {'deletedId': 31, 'physicallyDeleted': true},
          }),
        });
        final repository = RealCashierPaymentRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 8,
          ),
        );

        await repository.loadMerchants(PaymentChannel.wechat);
        final blank = await repository.loadEditForm(
          PaymentChannel.wechat,
          merchantKey: 'default',
        );
        final saved = await repository.saveMerchant(
          blank.copyWith(
            appId: 'wx-app',
            mchId: '1900000109',
            apiV3Key: '12345678901234567890123456789012',
          ),
        );
        await repository.loadMerchant(saved.id!);
        final deleted = await repository.deleteMerchant(saved.id!);

        expect(deleted.physicallyDeleted, isTrue);
        expect(deleted.deleted, isTrue);
        expect(transport.requests.map((request) => request.method), [
          'GET',
          'GET',
          'PUT',
          'GET',
          'DELETE',
        ]);
        expect(transport.requests.first.uri.queryParameters, {
          'channel': 'wechat',
        });
        expect(transport.requests[1].uri.queryParameters, {
          'channel': 'wechat',
          'merchantKey': 'default',
        });
        expect(
          jsonDecode(transport.requests[2].body!),
          containsPair('mchId', '1900000109'),
        );
        expect(
          jsonDecode(transport.requests[2].body!),
          containsPair('notifyUrl', ''),
        );
        expect(
          transport.requests.every(
            (request) => request.headers['X-Shop-Id'] == '8',
          ),
          isTrue,
        );
      },
    );
  });

  group('D013/D014/D015 capability parsing', () {
    test('parses qr switches, ready hints and channelStates', () {
      final capabilities = CashierPaymentCapabilities.fromJson({
        'clients': {
          'cashier': {
            'enabled': true,
            'channels': {
              'wechat': true,
              'alipay': true,
              'balance': true,
              'combined': false,
              'wechat_qr': true,
              'alipay_qr': false,
            },
            'wechatMerchantReady': false,
            'wechatReadyHint': '线上微信支付需先配置默认微信商户',
            'channelStates': {
              'wechat': {
                'enabled': true,
                'available': true,
                'hint': '',
              },
              'combined': {
                'enabled': false,
                'available': false,
                'hint': '组合支付需至少两个基础渠道生效',
              },
            },
          },
          'miniProgram': {
            'enabled': true,
            'channels': {'wechat': false, 'balance': true, 'alipay': true},
            'channelStates': {
              'wechat': {
                'enabled': false,
                'available': false,
                'hint': '请先配置微信商户',
              },
            },
          },
        },
        'canEnableCashierWechatPay': false,
      });

      expect(capabilities.canEnableCashierWechatPay, isFalse);
      expect(capabilities.cashier.wechatQr, isTrue);
      expect(capabilities.cashier.alipayQr, isFalse);
      expect(capabilities.cashier.wechatMerchantReady, isFalse);
      expect(
        capabilities.cashier.wechatReadyHint,
        '线上微信支付需先配置默认微信商户',
      );
      expect(
        capabilities.cashier.stateOf('combined')?.available,
        isFalse,
      );
      expect(
        capabilities.cashier.stateOf('combined')?.hint,
        '组合支付需至少两个基础渠道生效',
      );
      expect(capabilities.miniProgram.alipay, isTrue);
      expect(
        capabilities.miniProgram.stateOf('wechat')?.hint,
        '请先配置微信商户',
      );
      // D014 兼容派生：收款码开关来自 wechat_qr/alipay_qr。
      expect(capabilities.offlineCollectEnabled, isTrue);
      expect(capabilities.offlineChannels, {PaymentChannel.wechat});
    });

    test('falls back to legacy offline collect fields when qr keys absent', () {
      final capabilities = CashierPaymentCapabilities.fromJson({
        'clients': {
          'cashier': {
            'enabled': true,
            'channels': {'wechat': true, 'alipay': false},
          },
        },
        'offlineCollectEnabled': true,
        'offlineCollectChannels': ['alipay'],
      });

      expect(capabilities.cashier.wechatQr, isFalse);
      expect(capabilities.cashier.alipayQr, isTrue);
      expect(capabilities.offlineChannels, {PaymentChannel.alipay});
    });

    test('switch values resolve from channelStates when channels absent (D021 single source)', () {
      // PUT/GET 响应仅含 channelStates（无 channels 键）时，保存后按钮
      // 识别（回显）必须仍正确：channelStates.<渠道>.enabled 为权威。
      final capabilities = CashierPaymentCapabilities.fromJson({
        'clients': {
          'cashier': {
            'enabled': true,
            'channelStates': {
              'wechat': {'enabled': true, 'available': true, 'hint': ''},
              'alipay': {'enabled': false, 'available': true, 'hint': ''},
              'balance': {'enabled': true, 'available': true, 'hint': ''},
              'combined': {'enabled': false, 'available': false, 'hint': '需至少两个基础渠道生效'},
              'wechat_qr': {'enabled': true, 'available': true, 'hint': ''},
              'alipay_qr': {'enabled': false, 'available': true, 'hint': ''},
            },
          },
          'miniProgram': {
            'enabled': true,
            'channelStates': {
              'wechat': {'enabled': true, 'available': true, 'hint': ''},
              'balance': {'enabled': false, 'available': true, 'hint': ''},
              'alipay': {'enabled': false, 'available': true, 'hint': ''},
            },
          },
        },
      });

      expect(capabilities.cashier.wechat, isTrue);
      expect(capabilities.cashier.alipay, isFalse);
      expect(capabilities.cashier.balance, isTrue);
      expect(capabilities.cashier.combined, isFalse);
      expect(capabilities.cashier.wechatQr, isTrue);
      expect(capabilities.cashier.alipayQr, isFalse);
      expect(capabilities.miniProgram.wechat, isTrue);
      expect(capabilities.miniProgram.balance, isFalse);
      expect(capabilities.miniProgram.alipay, isFalse);
    });

    test('channelStates wins over channels when they diverge (D021)', () {
      // channels 为历史保存值、channelStates 为权威：按钮识别跟随 channelStates。
      final capabilities = CashierPaymentCapabilities.fromJson({
        'clients': {
          'cashier': {
            'enabled': true,
            'channels': {
              'wechat': true,
              'wechat_qr': true,
              'alipay_qr': true,
            },
            'channelStates': {
              'wechat': {'enabled': false, 'available': false, 'hint': '商户未配置'},
              'wechat_qr': {'enabled': true, 'available': true, 'hint': ''},
              'alipay_qr': {'enabled': false, 'available': true, 'hint': ''},
            },
          },
        },
      });

      expect(capabilities.cashier.wechat, isFalse);
      expect(capabilities.cashier.wechatQr, isTrue);
      expect(capabilities.cashier.alipayQr, isFalse);
    });

    test('save json mirrors qr switches and channelStates', () {
      final capabilities = const CashierPaymentCapabilities(
        cashier: const PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          wechatQr: true,
          channelStates: {
            'wechat': PaymentChannelCapabilityState(
              enabled: true,
              available: true,
            ),
          },
        ),
        miniProgram: const PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          alipay: true,
        ),
      );

      final saved = capabilities.toSaveJson();
      final cashier = (saved['clients']! as Map)['cashier']! as Map;
      final miniProgram = (saved['clients']! as Map)['miniProgram']! as Map;
      // D017：写入不携带 channels 与旧平铺键，仅 channelStates + disabledMessage
      expect(cashier.containsKey('channels'), isFalse);
      expect(miniProgram.containsKey('channels'), isFalse);
      expect(saved.containsKey('offlineCollectEnabled'), isFalse);
      expect(saved.containsKey('offlineCollectChannels'), isFalse);
      // 真实意图派生：channels 布尔 → channelStates.<渠道>.enabled
      final cashierStates = cashier['channelStates']! as Map;
      expect((cashierStates['wechat']! as Map)['enabled'], isTrue);
      expect((cashierStates['wechat_qr']! as Map)['enabled'], isTrue);
      expect((cashierStates['alipay_qr']! as Map)['enabled'], isFalse);
      final miniStates = miniProgram['channelStates']! as Map;
      expect((miniStates['wechat']! as Map)['enabled'], isTrue);
      expect((miniStates['alipay']! as Map)['enabled'], isTrue);
      expect((miniStates['balance']! as Map)['enabled'], isFalse);
    });

    test('save derives channelStates intent from channels, not stale GET values', () {
      // GET 返回该门店 cashier 各渠道全 false 的 channelStates（旧值），
      // 用户仅改动 channels（开微信）——保存时 channelStates 必须发真实意图，
      // 不能回传旧值导致后端按全 false 覆盖。
      const capabilities = CashierPaymentCapabilities(
        cashier: PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          channelStates: {
            'wechat': PaymentChannelCapabilityState(
              enabled: false,
              available: true,
            ),
            'alipay': PaymentChannelCapabilityState(enabled: false),
            'balance': PaymentChannelCapabilityState(enabled: false),
            'combined': PaymentChannelCapabilityState(enabled: false),
            'wechat_qr': PaymentChannelCapabilityState(enabled: false),
            'alipay_qr': PaymentChannelCapabilityState(enabled: false),
          },
        ),
      );

      final saved = capabilities.toSaveJson();
      final cashier = (saved['clients']! as Map)['cashier']! as Map;
      final states = cashier['channelStates']! as Map;
      expect((states['wechat']! as Map)['enabled'], isTrue);
      expect((states['alipay']! as Map)['enabled'], isFalse);
      expect(cashier.containsKey('channels'), isFalse);
    });
  });

  testWidgets('owned merchant can be soft-deleted from payment config', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CashierPaymentConfigPage(
          repository: repository,
          canEdit: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.byKey(
      const Key('cashier-payment-merchant-delete-31'),
    );
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('删除商户配置'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('cashier-payment-merchant-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.deletedIds, [31]);
    expect(find.text('商户配置已删除并停用'), findsNothing);
  });

  testWidgets(
    'disables unavailable channels and shows hints from channelStates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeCashierPaymentRepository(
        initial: const CashierPaymentCapabilities(
          cashier: const PaymentTerminalCapabilities(
            enabled: true,
            wechat: true,
            combined: true,
            channelStates: {
              'wechat': PaymentChannelCapabilityState(
                enabled: true,
                available: true,
              ),
              'combined': PaymentChannelCapabilityState(
                enabled: true,
                available: false,
                hint: '组合支付需至少两个基础渠道生效',
              ),
            },
          ),
          miniProgram: const PaymentTerminalCapabilities(
            enabled: true,
            wechat: false,
            channelStates: {
              'wechat': PaymentChannelCapabilityState(
                enabled: false,
                available: false,
                hint: '请先配置微信商户',
              ),
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: CashierPaymentConfigPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      // 小程序端开放支付宝开关：收银端 + 小程序端各一个。
      expect(find.widgetWithText(SwitchListTile, '支付宝'), findsNWidgets(2));
      // available=false 的渠道开关禁用。
      final combined = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '组合支付'),
      );
      expect(combined.onChanged, isNull);
      // 不可用原因文案展示。
      expect(find.text('组合支付需至少两个基础渠道生效'), findsOneWidget);
      expect(find.text('请先配置微信商户'), findsOneWidget);
    },
  );

  testWidgets('收款码归入收银端卡「线下收款码」分组', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository(
      initial: const CashierPaymentCapabilities(
        cashier: PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          wechatQr: true,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CashierPaymentConfigPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    // 分组标签仅收银端卡展示；两个收款码独立行。
    expect(find.text('线下收款码'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, '微信收款码'), findsOneWidget);
    expect(
      find.widgetWithText(SwitchListTile, '支付宝收款码'),
      findsOneWidget,
    );
    // 旧底部独立区已移除。
    expect(find.text('线下个人收款码'), findsNothing);
  });

  testWidgets('小程序端卡内带 C 端关闭提示输入框', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository(
      initial: const CashierPaymentCapabilities(
        disabledMessage: '请联系服务员结账',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CashierPaymentConfigPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('线上支付关闭提示（C 端展示）'), findsOneWidget);
  });

  testWidgets('商户卡头展示就绪摘要', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository(
      initial: const CashierPaymentCapabilities(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CashierPaymentConfigPage(
          repository: repository,
          canEdit: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本店 1 条'), findsOneWidget);
    expect(find.text('default 支付就绪'), findsOneWidget);
    expect(find.text('本店 0 条'), findsOneWidget);
  });

  testWidgets('保存前拦截已开启但不可用的渠道', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository(
      initial: const CashierPaymentCapabilities(
        cashier: PaymentTerminalCapabilities(
          enabled: true,
          wechat: true,
          combined: true,
          channelStates: {
            'combined': PaymentChannelCapabilityState(
              enabled: true,
              available: false,
              hint: '组合支付需至少两个基础渠道生效',
            ),
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CashierPaymentConfigPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存开关'));
    await tester.pumpAndSettle();

    expect(repository.saveCount, 0);
    expect(find.textContaining('暂不可开启'), findsOneWidget);
    // 弹窗文案 + 组合支付行 hint 各出现一次。
    expect(find.textContaining('组合支付需至少两个基础渠道生效'), findsNWidgets(2));
  });

  testWidgets('M-F 回调地址模板与私钥工具面板渲染', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCashierPaymentRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CashierPaymentConfigPage(
          repository: repository,
          canEdit: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('支付回调地址模板'));
    await tester.pumpAndSettle();
    expect(find.text('支付回调地址模板'), findsOneWidget);
    expect(find.text('微信支付通知'), findsOneWidget);
    expect(find.text('https://api.test/notify/wechat/pay'), findsOneWidget);
    expect(find.text('https://api.test/notify/alipay/pay'), findsOneWidget);

    await tester.ensureVisible(find.text('微信商户私钥'));
    await tester.pumpAndSettle();
    expect(find.text('微信商户私钥'), findsOneWidget);
    expect(
      find.byKey(const Key('cashier-payment-upload-private-key')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cashier-payment-bind-merchant-key')),
      findsOneWidget,
    );
  });

  group('CashierPaymentConfigPage permission-based visibility tests', () {
    testWidgets(
      'without payment edit permission, switches are displayed normally, other edit groups are hidden silently without notice',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _FakeCashierPaymentRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: CashierPaymentConfigPage(
              repository: repository,
              permissions: const {'cashier:operate', 'table:operate'},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. 开关卡片正常显示
        expect(find.text('支付能力'), findsOneWidget);
        expect(find.text('保存开关'), findsOneWidget);
        expect(find.text('终端总开关'), findsWidgets);
        expect(find.widgetWithText(SwitchListTile, '微信'), findsWidgets);
        expect(find.widgetWithText(SwitchListTile, '支付宝'), findsWidgets);
        expect(find.widgetWithText(SwitchListTile, '余额'), findsWidgets);

        // 2. 5 个高危财务编辑组受限隐藏
        expect(find.text('微信支付商户'), findsNothing);
        expect(find.text('支付宝商户'), findsNothing);
        expect(find.byKey(const Key('cashier-routing-rules-card')), findsNothing);
        expect(find.text('支付回调地址模板'), findsNothing);
        expect(find.text('微信商户私钥'), findsNothing);

        // 3. 隐藏了就隐藏了，不需要提示隐藏了（无任何提示卡片或解锁按钮）
        expect(
          find.byKey(const Key('cashier-payment-restricted-card')),
          findsNothing,
        );
        expect(find.text('商户凭证与高级分流编辑已受限隐藏'), findsNothing);
        expect(
          find.byKey(const Key('cashier-payment-auth-unlock-btn')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'with payment:config:write permission, all edit groups are directly visible',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _FakeCashierPaymentRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: CashierPaymentConfigPage(
              repository: repository,
              permissions: const {'payment:config:write'},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 开关正常显示
        expect(find.text('支付能力'), findsOneWidget);
        expect(find.text('保存开关'), findsOneWidget);

        // 5 个编辑组直接展示
        expect(find.text('微信支付商户'), findsOneWidget);
        expect(find.text('支付宝商户'), findsOneWidget);
        expect(find.byKey(const Key('cashier-routing-rules-card')), findsOneWidget);
        expect(find.text('支付回调地址模板'), findsOneWidget);
        expect(find.text('微信商户私钥'), findsOneWidget);

        // 无受限提示卡片
        expect(
          find.byKey(const Key('cashier-payment-restricted-card')),
          findsNothing,
        );
      },
    );
  });
}

class _FakeCashierPaymentRepository implements CashierPaymentRepository {
  _FakeCashierPaymentRepository({
    this.initial = const CashierPaymentCapabilities(),
  });

  final CashierPaymentCapabilities initial;
  final List<int> deletedIds = [];
  int saveCount = 0;

  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async => initial;

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
  ) async => PaymentMerchantCollection(
    owned: channel == PaymentChannel.wechat
        ? [
            PaymentMerchant(
              id: 31,
              channel: channel,
              merchantKey: 'default',
              enabled: deletedIds.isEmpty,
              payReady: true,
              mchId: '1900000109',
            ),
          ]
        : const [],
  );

  @override
  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  }) async => PaymentMerchantForm(channel: channel, merchantKey: merchantKey);

  @override
  Future<PaymentMerchantForm> loadMerchant(int id) async =>
      const PaymentMerchantForm(
        id: 31,
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
      );

  @override
  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form) async =>
      form;

  @override
  Future<PaymentMerchantDeleteResult> deleteMerchant(int id) async {
    deletedIds.add(id);
    return PaymentMerchantDeleteResult(deletedId: id, softDeleted: true);
  }

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
