import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/cashier_payment_config.dart';
import 'cashier_payment_repository.dart';

class RealCashierPaymentRepository implements CashierPaymentRepository {
  const RealCashierPaymentRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async {
    final response = await client.get(paymentCapabilitiesEndpoint);
    return CashierPaymentCapabilities.fromJson(_object(response));
  }

  @override
  Future<CashierPaymentCapabilities> saveCapabilities(
    CashierPaymentCapabilities capabilities,
  ) async {
    final response = await client.request(
      paymentCapabilitiesSaveEndpoint,
      body: capabilities.toSaveJson(),
    );
    return CashierPaymentCapabilities.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantCollection> loadMerchants(
    PaymentChannel channel,
  ) async {
    final response = await client.get(
      paymentMerchantsEndpoint,
      query: {'channel': channel.code},
    );
    return PaymentMerchantCollection.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  }) async {
    final response = await client.get(
      paymentMerchantEditFormEndpoint,
      query: {'channel': channel.code, 'merchantKey': merchantKey.trim()},
    );
    return PaymentMerchantForm.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantForm> loadMerchant(int id) async {
    final response = await client.get(paymentMerchantDetailEndpoint(id));
    return PaymentMerchantForm.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form) async {
    final validation = validateApiV3Key(
      form.apiV3Key,
      hasExistingKey: form.hasApiV3Key,
    );
    if (form.channel == PaymentChannel.wechat && validation != null) {
      throw FormatException(validation);
    }
    final response = await client.request(
      paymentMerchantSaveEndpoint,
      body: form.toSaveJson(),
    );
    return PaymentMerchantForm.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantDeleteResult> deleteMerchant(int id) async {
    final response = await client.request(paymentMerchantDeleteEndpoint(id));
    return PaymentMerchantDeleteResult.fromJson(_object(response));
  }

  @override
  Future<PaymentNotifyUrls> loadNotifyUrls() async {
    final response = await client.get(paymentNotifyUrlsEndpoint);
    return PaymentNotifyUrls.fromJson(_object(response));
  }

  @override
  Future<PaymentPrivateKeyUploadResult> uploadWechatPrivateKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async {
    if (pemBytes.isEmpty) {
      throw ArgumentError('pemBytes must not be empty');
    }
    final response = await client.postMultipart(
      paymentPrivateKeyUploadEndpoint,
      files: {
        'file': (
          bytes: pemBytes,
          filename: filename,
          contentType: 'application/x-pem-file',
        ),
      },
      query: {
        if (merchantKey != null && merchantKey.trim().isNotEmpty)
          'merchantKey': merchantKey.trim(),
      },
    );
    return PaymentPrivateKeyUploadResult.fromJson(_object(response));
  }

  @override
  Future<PaymentPlatformPublicKeyUploadResult> uploadWechatPlatformPublicKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async {
    if (pemBytes.isEmpty) {
      throw ArgumentError('pemBytes must not be empty');
    }
    final response = await client.postMultipart(
      paymentPlatformPublicKeyUploadEndpoint,
      files: {
        'file': (
          bytes: pemBytes,
          filename: filename,
          contentType: 'application/x-pem-file',
        ),
      },
      query: {
        if (merchantKey != null && merchantKey.trim().isNotEmpty)
          'merchantKey': merchantKey.trim(),
      },
    );
    return PaymentPlatformPublicKeyUploadResult.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantForm> uploadMerchantPrivateKey({
    required int merchantId,
    required List<int> pemBytes,
    required String filename,
  }) async {
    if (pemBytes.isEmpty) {
      throw ArgumentError('pemBytes must not be empty');
    }
    final response = await client.postMultipart(
      paymentMerchantPrivateKeyUploadEndpoint(merchantId),
      files: {
        'file': (
          bytes: pemBytes,
          filename: filename,
          contentType: 'application/x-pem-file',
        ),
      },
    );
    return PaymentMerchantForm.fromJson(_object(response));
  }

  @override
  Future<PaymentCertificateUploadResult> uploadCertificate({
    required List<int> bytes,
    required String filename,
    String? merchantKey,
    String type = 'AUTO',
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes must not be empty');
    }
    final response = await client.postMultipart(
      paymentCertificateUploadEndpoint,
      files: {
        'file': (
          bytes: bytes,
          filename: filename,
          contentType: 'application/octet-stream',
        ),
      },
      query: {
        if (merchantKey != null && merchantKey.trim().isNotEmpty)
          'merchantKey': merchantKey.trim(),
        if (type.trim().isNotEmpty) 'type': type.trim(),
      },
    );
    return PaymentCertificateUploadResult.fromJson(_object(response));
  }

  @override
  Future<PaymentMerchantForm> uploadMerchantCertificate({
    required int merchantId,
    required List<int> bytes,
    required String filename,
    String type = 'AUTO',
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes must not be empty');
    }
    final response = await client.postMultipart(
      paymentMerchantCertificateUploadEndpoint(merchantId),
      files: {
        'file': (
          bytes: bytes,
          filename: filename,
          contentType: 'application/octet-stream',
        ),
      },
      query: {
        if (type.trim().isNotEmpty) 'type': type.trim(),
      },
    );
    return PaymentMerchantForm.fromJson(_object(response));
  }

  @override
  Future<PaymentRoutingRuleCollection> loadRoutingRules(
    PaymentChannel channel,
  ) async {
    final response = await client.get(
      paymentRoutingRulesEndpoint,
      query: {'channel': channel.code},
    );
    return PaymentRoutingRuleCollection.fromJson(_object(response));
  }

  @override
  Future<PaymentRoutingRule> saveRoutingRule({
    int? id,
    required Map<String, Object?> data,
  }) async {
    final endpoint = id != null
        ? paymentRoutingRuleUpdateEndpoint(id)
        : paymentRoutingRuleCreateEndpoint;
    final response = await client.request(endpoint, body: data);
    return PaymentRoutingRule.fromJson(_object(response));
  }

  @override
  Future<bool> deleteRoutingRule(int id) async {
    final response = await client.request(paymentRoutingRuleDeleteEndpoint(id));
    final map = _object(response);
    return map['deleted'] == true;
  }

  @override
  Future<bool> sortRoutingRules(
    PaymentChannel channel,
    List<int> ruleIds,
  ) async {
    final response = await client.request(
      paymentRoutingRulesSortEndpoint,
      query: {'channel': channel.code},
      body: {'ruleIds': ruleIds},
    );
    final map = _object(response);
    return map['sorted'] == true;
  }

  @override
  Future<PaymentRoutingSimulationResult> simulateRouting(
    Map<String, Object?> context,
  ) async {
    final response = await client.post(
      paymentRoutingRulesSimulateEndpoint,
      body: context,
    );
    return PaymentRoutingSimulationResult.fromJson(_object(response));
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    final account = username.trim();
    await client.post(
      adminLoginEndpoint,
      body: {
        'workNo': account,
        'userName': account,
        'password': password,
      },
    );
  }
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};
