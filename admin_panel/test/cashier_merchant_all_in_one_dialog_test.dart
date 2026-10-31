import 'dart:convert';
import 'dart:typed_data';

import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/domain/cashier_payment_config.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_payment_config_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _validPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC7VNT...
-----END PRIVATE KEY-----''';

const _validRsaPrivateKeyPem = '''
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA0Y3...
-----END RSA PRIVATE KEY-----''';

const _certificatePem = '''
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIU...
-----END CERTIFICATE-----''';

class _MockPaymentRepository implements CashierPaymentRepository {
  _MockPaymentRepository();

  final CashierPaymentCapabilities initialCapabilities =
      const CashierPaymentCapabilities();
  PaymentMerchantForm? lastSavedForm;
  List<int>? lastUploadedBytes;
  String? lastUploadedFilename;
  String? lastUploadedMerchantKey;
  int uploadCallCount = 0;
  List<int>? lastUploadedCertBytes;
  String? lastUploadedCertFilename;
  String? lastUploadedCertMerchantKey;
  int uploadCertCallCount = 0;
  int uploadCertificateCallCount = 0;
  String? lastCertificateType;
  List<int>? lastCertificateBytes;
  String? lastCertificateFilename;
  int saveCallCount = 0;

  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async =>
      initialCapabilities;

  @override
  Future<CashierPaymentCapabilities> saveCapabilities(
    CashierPaymentCapabilities capabilities,
  ) async => capabilities;

  @override
  Future<PaymentMerchantCollection> loadMerchants(
    PaymentChannel channel,
  ) async => const PaymentMerchantCollection();

  @override
  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  }) async => PaymentMerchantForm(
    channel: channel,
    merchantKey: merchantKey,
    notifyUrlSuggestions: const {
      'payment': 'https://api.test/order/notify',
      'refund': 'https://api.test/refund/notify',
    },
  );

  @override
  Future<PaymentMerchantForm> loadMerchant(int id) async =>
      const PaymentMerchantForm(
        id: 1,
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
      );

  @override
  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form) async {
    saveCallCount++;
    lastSavedForm = form;
    return form;
  }

  @override
  Future<PaymentMerchantDeleteResult> deleteMerchant(int id) async =>
      PaymentMerchantDeleteResult(deletedId: id, softDeleted: true);

  @override
  Future<PaymentNotifyUrls> loadNotifyUrls() async => const PaymentNotifyUrls(
    wechatPayNotify: 'https://api.test/notify/wechat/pay',
    wechatRefundNotify: 'https://api.test/notify/wechat/refund',
    alipayPayNotify: 'https://api.test/notify/alipay/pay',
  );

  @override
  Future<PaymentPrivateKeyUploadResult> uploadWechatPrivateKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async {
    uploadCallCount++;
    lastUploadedBytes = pemBytes;
    lastUploadedFilename = filename;
    lastUploadedMerchantKey = merchantKey;
    return PaymentPrivateKeyUploadResult(
      privateKeyRef: 'payment-keys/wechat-$merchantKey-uploaded.pem',
    );
  }

  @override
  Future<PaymentPlatformPublicKeyUploadResult> uploadWechatPlatformPublicKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async {
    uploadCertCallCount++;
    lastUploadedCertBytes = pemBytes;
    lastUploadedCertFilename = filename;
    lastUploadedCertMerchantKey = merchantKey;
    return PaymentPlatformPublicKeyUploadResult(
      platformPubKeyRef:
          'payment-keys/shop-1/wechat-$merchantKey-platform-public.pem',
      materialType: 'PUBLIC_KEY',
    );
  }

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
  }) async {
    uploadCertificateCallCount++;
    lastCertificateType = type;
    lastCertificateBytes = bytes;
    lastCertificateFilename = filename;
    return PaymentCertificateUploadResult(
      certificateType: type,
      fileRef: 'payment-keys/shop-1/wechat-$merchantKey-$filename',
      filename: filename,
      fileSize: bytes.length,
    );
  }

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

void main() {
  group('validatePemContent format verification', () {
    test('rejects empty input', () {
      expect(validatePemContent(''), '私钥内容不能为空');
      expect(validatePemContent('   \n  '), '私钥内容不能为空');
    });

    test('rejects certificate and public key files with actionable warning', () {
      expect(
        validatePemContent(_certificatePem),
        contains('检测到证书或公钥内容，请上传包含 BEGIN PRIVATE KEY 的商户私钥文件'),
      );
      expect(
        validatePemContent('-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3...'),
        contains('检测到证书或公钥内容'),
      );
    });

    test('rejects arbitrary text without PRIVATE KEY marker', () {
      expect(
        validatePemContent('Hello World this is some random string'),
        contains('私钥格式无效'),
      );
    });

    test('accepts PKCS#8 and PKCS#1 private key PEMs', () {
      expect(validatePemContent(_validPrivateKeyPem), isNull);
      expect(validatePemContent(_validRsaPrivateKeyPem), isNull);
    });
  });

  group('validatePublicCertificateContent format verification', () {
    test('rejects empty input', () {
      final res = validatePublicCertificateContent('');
      expect(res.isValid, isFalse);
      expect(res.error, '公钥证书内容不能为空');
    });

    test('rejects private key files with actionable warning', () {
      final res = validatePublicCertificateContent(_validPrivateKeyPem);
      expect(res.isValid, isFalse);
      expect(res.error, contains('检测到私钥内容，此处仅允许上传微信支付平台公钥或 X.509 平台证书'));
    });

    test('accepts PUBLIC KEY PEM', () {
      const pubKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Y3...
-----END PUBLIC KEY-----''';
      final res = validatePublicCertificateContent(pubKeyPem);
      expect(res.isValid, isTrue);
      expect(res.materialType, 'PUBLIC_KEY');
      expect(res.error, isNull);
    });

    test('accepts X.509 CERTIFICATE PEM', () {
      final res = validatePublicCertificateContent(_certificatePem);
      expect(res.isValid, isTrue);
      expect(res.materialType, 'CERTIFICATE');
      expect(res.error, isNull);
    });

    test('rejects arbitrary text without PUBLIC KEY or CERTIFICATE markers', () {
      final res = validatePublicCertificateContent('Hello World invalid cert content');
      expect(res.isValid, isFalse);
      expect(res.error, contains('文件不是有效的微信支付平台公钥或 X.509 平台证书'));
    });
  });

  group('MerchantFormDialog All-In-One Widget Tests', () {
    testWidgets('renders key selector chips, inline private key card and fields', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(repository: repo, initialValue: initialForm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title & Key Selector
      expect(find.text('新增微信支付商户'), findsOneWidget);
      expect(find.text('商户实例键 (merchantKey)'), findsOneWidget);
      expect(find.byKey(const Key('cashier-merchant-chip-default')), findsOneWidget);
      expect(
        find.byKey(const Key('cashier-merchant-chip-small_amount')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cashier-merchant-chip-custom')), findsOneWidget);

      // Inline Private Key Card
      expect(find.text('商户私钥 (apiclient_key.pem) 直传'), findsOneWidget);
      expect(find.text('未配置私钥'), findsOneWidget);
      expect(
        find.byKey(const Key('cashier-merchant-pick-pk-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-merchant-paste-pk-btn')),
        findsOneWidget,
      );

      // Save button
      expect(find.text('保存商户并立即生效'), findsOneWidget);
    });

    testWidgets('switches to custom merchant key input when custom chip tapped', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(repository: repo, initialValue: initialForm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cashier-merchant-custom-key-input')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('cashier-merchant-chip-custom')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cashier-merchant-custom-key-input')),
        findsOneWidget,
      );
    });

    testWidgets('file picking updates status pill to ready and shows file name', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      final mockFile = PlatformFile(
        name: 'apiclient_key.pem',
        size: _validPrivateKeyPem.length,
        bytes: Uint8List.fromList(utf8.encode(_validPrivateKeyPem)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(
              repository: repo,
              initialValue: initialForm,
              pickFileOverride: () async => mockFile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未配置私钥'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-pick-pk-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-pick-pk-btn')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('apiclient_key.pem (已通过本地 BEGIN PRIVATE KEY 校验)'),
        findsOneWidget,
      );
    });

    testWidgets('pasting invalid cert PEM is rejected with error in paste dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(repository: repo, initialValue: initialForm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open paste dialog
      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-paste-pk-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-paste-pk-btn')));
      await tester.pumpAndSettle();

      expect(find.text('粘贴微信 PEM 私钥内容'), findsOneWidget);

      // Enter certificate pem
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-paste-pk-input')),
        _certificatePem,
      );
      await tester.tap(
        find.byKey(const Key('cashier-merchant-paste-pk-confirm-btn')),
      );
      await tester.pumpAndSettle();

      // Error shown, dialog remains open
      expect(find.textContaining('检测到证书或公钥内容'), findsOneWidget);

      // Now enter valid private key
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-paste-pk-input')),
        _validPrivateKeyPem,
      );
      await tester.tap(
        find.byKey(const Key('cashier-merchant-paste-pk-confirm-btn')),
      );
      await tester.pumpAndSettle();

      // Paste dialog closed, private key ready
      expect(find.text('粘贴微信 PEM 私钥内容'), findsNothing);
      expect(find.text('私钥已就绪'), findsOneWidget);
    });

    testWidgets('submitting form auto-uploads private key and saves merchant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      final mockFile = PlatformFile(
        name: 'apiclient_key.pem',
        size: _validPrivateKeyPem.length,
        bytes: Uint8List.fromList(utf8.encode(_validPrivateKeyPem)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(
              repository: repo,
              initialValue: initialForm,
              pickFileOverride: () async => mockFile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill in required fields
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-appId')),
        'wx1234567890abcdef',
      );
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-mchId')),
        '1900000109',
      );
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-apiV3Key')),
        '12345678901234567890123456789012',
      );
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-serialNo')),
        '7C8D9E0F1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D',
      );

      // Pick private key file
      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-pick-pk-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-pick-pk-btn')));
      await tester.pumpAndSettle();
      expect(find.text('私钥已就绪'), findsOneWidget);

      // Tap Save
      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-form-save-btn')),
      );
      await tester.tap(
        find.byKey(const Key('cashier-merchant-form-save-btn')),
      );
      await tester.pumpAndSettle();

      // Verify that uploadWechatPrivateKey was invoked before saveMerchant
      expect(repo.uploadCallCount, 1);
      expect(repo.lastUploadedFilename, 'apiclient_key.pem');
      expect(repo.lastUploadedMerchantKey, 'default');
      expect(
        utf8.decode(repo.lastUploadedBytes!),
        contains('BEGIN PRIVATE KEY'),
      );

      // Verify saveMerchant was invoked with the uploaded privateKeyRef
      expect(repo.saveCallCount, 1);
      expect(repo.lastSavedForm!.merchantKey, 'default');
      expect(repo.lastSavedForm!.appId, 'wx1234567890abcdef');
      expect(repo.lastSavedForm!.mchId, '1900000109');
      expect(
        repo.lastSavedForm!.privateKeyRef,
        'payment-keys/wechat-default-uploaded.pem',
      );
    });

    testWidgets(
      'renders inline public certificate card with initial status and controls',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _MockPaymentRepository();
        const initialForm = PaymentMerchantForm(
          channel: PaymentChannel.wechat,
          merchantKey: 'default',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MerchantFormDialog(
                initialValue: initialForm,
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('微信支付平台公钥证书'), findsOneWidget);
        expect(
          find.byKey(const Key('cashier-merchant-cert-status-badge')),
          findsOneWidget,
        );
        expect(find.text('待选择文件'), findsOneWidget);
        expect(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
          findsOneWidget,
        );
        expect(
          find.text('支持 .pem / .cer / .crt；PUBLIC KEY 或 CERTIFICATE'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashier-merchant-field-platformPubKeyId')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashier-merchant-pubkey-ref-preview')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'picking public certificate updates status badge and file description',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const pubKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Y3...
-----END PUBLIC KEY-----''';

        final repo = _MockPaymentRepository();
        const initialForm = PaymentMerchantForm(
          channel: PaymentChannel.wechat,
          merchantKey: 'default',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MerchantFormDialog(
                initialValue: initialForm,
                repository: repo,
                pickCertFileOverride: () async => PlatformFile(
                  name: 'wechatpay_platform_pub.pem',
                  size: pubKeyPem.length,
                  bytes: Uint8List.fromList(utf8.encode(pubKeyPem)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.tap(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('公钥证书已就绪'), findsOneWidget);
        expect(
          find.textContaining('wechatpay_platform_pub.pem · PUBLIC KEY 校验通过 · 保存时上传'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'picking private key in public certificate picker shows error and blocks',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _MockPaymentRepository();
        const initialForm = PaymentMerchantForm(
          channel: PaymentChannel.wechat,
          merchantKey: 'default',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MerchantFormDialog(
                initialValue: initialForm,
                repository: repo,
                pickCertFileOverride: () async => PlatformFile(
                  name: 'apiclient_key.pem',
                  size: _validPrivateKeyPem.length,
                  bytes: Uint8List.fromList(utf8.encode(_validPrivateKeyPem)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.tap(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cashier-merchant-form-error')),
          findsOneWidget,
        );
        expect(find.textContaining('检测到私钥内容'), findsOneWidget);
        expect(find.text('待选择文件'), findsOneWidget);
      },
    );

    testWidgets(
      'submitting form auto-uploads both private key and public certificate',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const pubKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Y3...
-----END PUBLIC KEY-----''';

        final repo = _MockPaymentRepository();
        const initialForm = PaymentMerchantForm(
          channel: PaymentChannel.wechat,
          merchantKey: 'default',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MerchantFormDialog(
                initialValue: initialForm,
                repository: repo,
                pickFileOverride: () async => PlatformFile(
                  name: 'apiclient_key.pem',
                  size: _validPrivateKeyPem.length,
                  bytes: Uint8List.fromList(utf8.encode(_validPrivateKeyPem)),
                ),
                pickCertFileOverride: () async => PlatformFile(
                  name: 'wechatpay_pub.pem',
                  size: pubKeyPem.length,
                  bytes: Uint8List.fromList(utf8.encode(pubKeyPem)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('cashier-merchant-field-appId')),
          'wx1234567890abcdef',
        );
        await tester.enterText(
          find.byKey(const Key('cashier-merchant-field-mchId')),
          '1900000109',
        );
        await tester.enterText(
          find.byKey(const Key('cashier-merchant-field-apiV3Key')),
          '12345678901234567890123456789012',
        );
        await tester.enterText(
          find.byKey(const Key('cashier-merchant-field-serialNo')),
          '7C8D9E0F1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D',
        );
        await tester.enterText(
          find.byKey(const Key('cashier-merchant-field-platformPubKeyId')),
          'PUB_KEY_ID_0000000001',
        );

        // Pick private key file
        await tester.ensureVisible(
          find.byKey(const Key('cashier-merchant-pick-pk-btn')),
        );
        await tester.tap(find.byKey(const Key('cashier-merchant-pick-pk-btn')));
        await tester.pumpAndSettle();

        // Pick public certificate file
        await tester.ensureVisible(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.tap(
          find.byKey(const Key('cashier-merchant-pick-cert-btn')),
        );
        await tester.pumpAndSettle();

        // Tap Save
        await tester.ensureVisible(
          find.byKey(const Key('cashier-merchant-form-save-btn')),
        );
        await tester.tap(
          find.byKey(const Key('cashier-merchant-form-save-btn')),
        );
        await tester.pumpAndSettle();

        // Verify that both uploads were invoked before saveMerchant
        expect(repo.uploadCallCount, 1);
        expect(repo.lastUploadedFilename, 'apiclient_key.pem');

        expect(repo.uploadCertCallCount, 1);
        expect(repo.lastUploadedCertFilename, 'wechatpay_pub.pem');
        expect(repo.lastUploadedCertMerchantKey, 'default');
        expect(
          utf8.decode(repo.lastUploadedCertBytes!),
          contains('BEGIN PUBLIC KEY'),
        );

        // Verify saveMerchant was invoked with both uploaded refs
        expect(repo.saveCallCount, 1);
        expect(repo.lastSavedForm!.merchantKey, 'default');
        expect(
          repo.lastSavedForm!.privateKeyRef,
          'payment-keys/wechat-default-uploaded.pem',
        );
        expect(
          repo.lastSavedForm!.platformPubKeyRef,
          'payment-keys/shop-1/wechat-default-platform-public.pem',
        );
        expect(
          repo.lastSavedForm!.platformPubKeyId,
          'PUB_KEY_ID_0000000001',
        );
      },
    );

    testWidgets('renders inline P12 client certificate card and APIv2 key field', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(repository: repo, initialValue: initialForm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cashier-merchant-field-apiV2Key')),
        findsOneWidget,
      );
      expect(find.text('客户端双向认证证书 (apiclient_cert.p12) 直传'), findsOneWidget);
      expect(
        find.byKey(const Key('cashier-merchant-pick-p12-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-merchant-p12-status')),
        findsOneWidget,
      );
      expect(find.text('未配置客户端证书'), findsOneWidget);
    });

    testWidgets('picking valid P12 client certificate updates status badge', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      final dummyP12Bytes = Uint8List.fromList(List<int>.filled(64, 0x30));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(
              repository: repo,
              initialValue: initialForm,
              pickP12FileOverride: () async => PlatformFile(
                name: 'apiclient_cert.p12',
                size: dummyP12Bytes.length,
                bytes: dummyP12Bytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-pick-p12-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-pick-p12-btn')));
      await tester.pumpAndSettle();

      expect(find.text('客户端证书已就绪'), findsOneWidget);
      expect(
        find.textContaining('apiclient_cert.p12 (PKCS12 校验通过'),
        findsOneWidget,
      );
    });

    testWidgets('picking PEM in P12 client certificate picker rejects with error', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      final pemBytes =
          Uint8List.fromList(utf8.encode('-----BEGIN CERTIFICATE-----\nMIID...'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(
              repository: repo,
              initialValue: initialForm,
              pickP12FileOverride: () async => PlatformFile(
                name: 'cert.pem',
                size: pemBytes.length,
                bytes: pemBytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-pick-p12-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-pick-p12-btn')));
      await tester.pumpAndSettle();

      expect(find.text('未配置客户端证书'), findsOneWidget);
      expect(
        find.textContaining('上传的是 PEM 文本文件，客户端证书必须为 PKCS12 二进制（.p12/.pfx）文件'),
        findsOneWidget,
      );
    });

    testWidgets('renders Alipay application private key and certificate triple card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.alipay,
        merchantKey: 'default',
        exists: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(repository: repo, initialValue: initialForm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('应用私钥 (app_private_key.pem) 直传'), findsOneWidget);
      expect(find.text('支付宝公钥证书三件套'), findsOneWidget);
      expect(
        find.byKey(const Key('cashier-merchant-pick-alipay-app-cert-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-merchant-pick-alipay-public-cert-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-merchant-pick-alipay-root-cert-btn')),
        findsOneWidget,
      );
    });

    testWidgets('submitting form with pending P12 certificate auto-uploads and saves apiV2Key', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();
      const initialForm = PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
        exists: false,
      );

      final dummyP12Bytes = Uint8List.fromList(List<int>.filled(64, 0x30));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantFormDialog(
              repository: repo,
              initialValue: initialForm,
              pickP12FileOverride: () async => PlatformFile(
                name: 'apiclient_cert.p12',
                size: dummyP12Bytes.length,
                bytes: dummyP12Bytes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter required fields
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-apiV3Key')),
        '12345678901234567890123456789012',
      );
      await tester.enterText(
        find.byKey(const Key('cashier-merchant-field-apiV2Key')),
        '12345678901234567890123456789012',
      );

      // Pick P12
      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-pick-p12-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-pick-p12-btn')));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.ensureVisible(
        find.byKey(const Key('cashier-merchant-form-save-btn')),
      );
      await tester.tap(find.byKey(const Key('cashier-merchant-form-save-btn')));
      await tester.pumpAndSettle();

      expect(repo.uploadCertificateCallCount, 1);
      expect(repo.lastCertificateType, 'CLIENT_CERT_P12');
      expect(repo.lastCertificateFilename, 'apiclient_cert.p12');

      expect(repo.saveCallCount, 1);
      expect(
        repo.lastSavedForm!.apiV2Key,
        '12345678901234567890123456789012',
      );
      expect(
        repo.lastSavedForm!.clientCertP12Ref,
        'payment-keys/shop-1/wechat-default-apiclient_cert.p12',
      );
    });
  });

  group('CashierPaymentConfigPage Add Merchant Direct Flow', () {
    testWidgets('tapping 新增商户 directly launches all-in-one MerchantFormDialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockPaymentRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: CashierPaymentConfigPage(
            repository: repo,
            canEdit: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find "新增商户" button on WeChat section
      final addMerchantBtn = find.byKey(const Key('cashier-merchant-add-wechat'));
      await tester.ensureVisible(addMerchantBtn);
      await tester.tap(addMerchantBtn);
      await tester.pumpAndSettle();

      // Verifies MerchantFormDialog is opened immediately without intermediate dialog
      expect(find.byType(MerchantFormDialog), findsOneWidget);
      expect(find.text('新增微信支付商户'), findsOneWidget);
      expect(find.text('商户实例键 (merchantKey)'), findsOneWidget);
      expect(find.text('商户私钥 (apiclient_key.pem) 直传'), findsOneWidget);
    });
  });
}
