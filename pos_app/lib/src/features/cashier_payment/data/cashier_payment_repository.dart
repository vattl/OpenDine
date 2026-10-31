import '../domain/cashier_payment_config.dart';

abstract interface class CashierPaymentRepository {
  Future<CashierPaymentCapabilities> loadCapabilities();

  Future<CashierPaymentCapabilities> saveCapabilities(
    CashierPaymentCapabilities capabilities,
  );

  Future<PaymentMerchantCollection> loadMerchants(PaymentChannel channel);

  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  });

  Future<PaymentMerchantForm> loadMerchant(int id);

  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form);

  Future<PaymentMerchantDeleteResult> deleteMerchant(int id);

  /// 支付回调 URL 模板（只读）。
  Future<PaymentNotifyUrls> loadNotifyUrls();

  /// 上传微信商户 PEM 私钥（先传文件，返回 privateKeyRef 供新增商户配置引用）。
  Future<PaymentPrivateKeyUploadResult> uploadWechatPrivateKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  });

  /// 上传微信支付平台公钥或平台证书（返回 platformPubKeyRef 供新增/编辑商户配置引用）。
  Future<PaymentPlatformPublicKeyUploadResult> uploadWechatPlatformPublicKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  });

  /// 上传并绑定指定商户的微信 PEM 私钥（立即更新该商户配置）。
  Future<PaymentMerchantForm> uploadMerchantPrivateKey({
    required int merchantId,
    required List<int> pemBytes,
    required String filename,
  });

  /// 全类型统一证书/私钥/公钥上传（支持 CLIENT_CERT_P12, PRIVATE_KEY, PLATFORM_PUBLIC_KEY, ALIPAY_*）。
  Future<PaymentCertificateUploadResult> uploadCertificate({
    required List<int> bytes,
    required String filename,
    String? merchantKey,
    String type = 'AUTO',
  });

  /// 指定商户直绑统一证书上传。
  Future<PaymentMerchantForm> uploadMerchantCertificate({
    required int merchantId,
    required List<int> bytes,
    required String filename,
    String type = 'AUTO',
  });

  /// 查询当前渠道的商户分流路由规则列表。
  Future<PaymentRoutingRuleCollection> loadRoutingRules(PaymentChannel channel);

  /// 新增或修改商户分流路由规则。
  Future<PaymentRoutingRule> saveRoutingRule({
    int? id,
    required Map<String, Object?> data,
  });

  /// 删除指定路由规则。
  Future<bool> deleteRoutingRule(int id);

  /// 批量更新路由规则优先级排序。
  Future<bool> sortRoutingRules(PaymentChannel channel, List<int> ruleIds);

  /// 现场试算模拟器。
  Future<PaymentRoutingSimulationResult> simulateRouting(
    Map<String, Object?> context,
  );

  /// 现场店长/管理员账号密码二次授权校验。
  Future<void> verifyPassword({
    required String username,
    required String password,
  });
}
