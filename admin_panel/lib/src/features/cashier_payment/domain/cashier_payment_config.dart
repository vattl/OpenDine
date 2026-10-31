import 'dart:convert';

enum PaymentChannel {
  wechat('wechat', '微信支付'),
  alipay('alipay', '支付宝');

  const PaymentChannel(this.code, this.label);

  final String code;
  final String label;

  static PaymentChannel from(Object? value) =>
      value == 'alipay' ? PaymentChannel.alipay : PaymentChannel.wechat;
}

/// D015 渠道状态：enabled（可写）/ available（只读）/ hint（只读）。
class PaymentChannelCapabilityState {
  const PaymentChannelCapabilityState({
    this.enabled = false,
    this.available = true,
    this.hint = '',
  });

  factory PaymentChannelCapabilityState.fromJson(Object? value) {
    final json = _map(value);
    return PaymentChannelCapabilityState(
      enabled: _bool(json['enabled']),
      available: _bool(json['available']),
      hint: _string(json['hint']),
    );
  }

  final bool enabled;
  final bool available;
  final String hint;

  Map<String, Object?> toSaveJson() => {'enabled': enabled};
}

class PaymentTerminalCapabilities {
  const PaymentTerminalCapabilities({
    this.enabled = false,
    this.wechat = false,
    this.alipay = false,
    this.balance = false,
    this.combined = false,
    this.wechatQr = false,
    this.alipayQr = false,
    this.wechatMerchantReady = false,
    this.wechatReadyHint = '',
    this.channelStates = const {},
  });

  /// [legacyCollectEnabled]/[legacyChannels] 用于 D014 旧数据回退：
  /// 响应仅有 offlineCollect* 时据此推导 wechat_qr/alipay_qr。
  /// 开关值统一以 `channelStates.<渠道>.enabled` 为权威（D021 单一来源：
  /// 保存/回显按钮识别以此为准，`channels`/平铺键/legacy 仅作兼容回退）。
  factory PaymentTerminalCapabilities.fromJson(
    Object? value, {
    bool legacyCollectEnabled = false,
    Set<PaymentChannel> legacyChannels = const {},
  }) {
    final json = _map(value);
    final channels = _map(json['channels']);
    final states = _channelStates(json['channelStates']);
    bool switchOf(String channel, Object? legacy) =>
        states[channel]?.enabled ?? _bool(legacy);
    return PaymentTerminalCapabilities(
      enabled: _bool(json['enabled']),
      wechat: switchOf('wechat', channels['wechat'] ?? json['wechat']),
      alipay: switchOf('alipay', channels['alipay'] ?? json['alipay']),
      balance: switchOf('balance', channels['balance'] ?? json['balance']),
      combined: switchOf('combined', channels['combined'] ?? json['combined']),
      wechatQr: switchOf(
        'wechat_qr',
        channels['wechat_qr'] ??
            json['wechatQr'] ??
            (legacyCollectEnabled &&
                legacyChannels.contains(PaymentChannel.wechat)),
      ),
      alipayQr: switchOf(
        'alipay_qr',
        channels['alipay_qr'] ??
            json['alipayQr'] ??
            (legacyCollectEnabled &&
                legacyChannels.contains(PaymentChannel.alipay)),
      ),
      wechatMerchantReady: _bool(json['wechatMerchantReady']),
      wechatReadyHint: _string(json['wechatReadyHint']),
      channelStates: states,
    );
  }

  final bool enabled;
  final bool wechat;
  final bool alipay;
  final bool balance;
  final bool combined;
  final bool wechatQr;
  final bool alipayQr;
  final bool wechatMerchantReady;
  final String wechatReadyHint;
  final Map<String, PaymentChannelCapabilityState> channelStates;

  PaymentChannelCapabilityState? stateOf(String channel) =>
      channelStates[channel];

  PaymentTerminalCapabilities copyWith({
    bool? enabled,
    bool? wechat,
    bool? alipay,
    bool? balance,
    bool? combined,
    bool? wechatQr,
    bool? alipayQr,
    bool? wechatMerchantReady,
    String? wechatReadyHint,
    Map<String, PaymentChannelCapabilityState>? channelStates,
  }) => PaymentTerminalCapabilities(
    enabled: enabled ?? this.enabled,
    wechat: wechat ?? this.wechat,
    alipay: alipay ?? this.alipay,
    balance: balance ?? this.balance,
    combined: combined ?? this.combined,
    wechatQr: wechatQr ?? this.wechatQr,
    alipayQr: alipayQr ?? this.alipayQr,
    wechatMerchantReady: wechatMerchantReady ?? this.wechatMerchantReady,
    wechatReadyHint: wechatReadyHint ?? this.wechatReadyHint,
    channelStates: channelStates ?? this.channelStates,
  );

  /// D017：保存意图以 channels 当前布尔为唯一来源，逐渠道派生
  /// `channelStates.<渠道>.enabled`（不回传 GET 旧值）；写入不再携带
  /// `channels`（后端忽略）与旧平铺键。
  Map<String, Object?> toCashierJson() => {
    'enabled': enabled,
    'channelStates': {
      for (final entry in _cashierChannelStates().entries)
        entry.key: {'enabled': entry.value},
    },
  };

  Map<String, Object?> toMiniProgramJson() => {
    'enabled': enabled,
    'channelStates': {
      for (final entry in _miniProgramChannelStates().entries)
        entry.key: {'enabled': entry.value},
    },
  };

  Map<String, bool> _cashierChannelStates() => {
    'wechat': wechat,
    'alipay': alipay,
    'balance': balance,
    'combined': combined,
    'wechat_qr': wechatQr,
    'alipay_qr': alipayQr,
  };

  Map<String, bool> _miniProgramChannelStates() => {
    'wechat': wechat,
    'balance': balance,
    'alipay': alipay,
  };
}

class CashierPaymentCapabilities {
  const CashierPaymentCapabilities({
    this.targetShopId = 0,
    this.scope = '',
    this.hasOwnConfig = false,
    this.inheritsGlobal = false,
    this.onlinePayEnabled = false,
    this.canEnableCashierWechatPay = false,
    this.cashier = const PaymentTerminalCapabilities(),
    this.miniProgram = const PaymentTerminalCapabilities(),
    this.disabledMessage = '请联系服务员结账',
  });

  factory CashierPaymentCapabilities.fromJson(Map<String, Object?> json) {
    final clients = _map(json['clients']);
    final legacyCollectEnabled = _bool(
      _first(json, const ['offlineCollectEnabled', 'offline_collect_enabled']),
    );
    final legacyChannels = _strings(
      _first(json, const ['offlineCollectChannels', 'offline_collect_channels']),
    ).map(PaymentChannel.from).toSet();
    return CashierPaymentCapabilities(
      targetShopId: _int(
        _first(json, const ['targetShopId', 'target_shop_id']),
      ),
      scope: _string(json['scope']),
      hasOwnConfig: _bool(
        _first(json, const ['hasOwnConfig', 'has_own_config']),
      ),
      inheritsGlobal: _bool(
        _first(json, const ['inheritsGlobal', 'inherits_global']),
      ),
      onlinePayEnabled: _bool(
        _first(json, const ['onlinePayEnabled', 'online_pay_enabled']),
      ),
      canEnableCashierWechatPay: _bool(
        _first(json, const [
          'canEnableCashierWechatPay',
          'can_enable_cashier_wechat_pay',
        ]),
      ),
      cashier: PaymentTerminalCapabilities.fromJson(
        clients['cashier'],
        legacyCollectEnabled: legacyCollectEnabled,
        legacyChannels: legacyChannels,
      ),
      miniProgram: PaymentTerminalCapabilities.fromJson(
        clients['miniProgram'] ?? clients['mini_program'],
      ),
      disabledMessage:
          _string(
              _first(json, const ['disabledMessage', 'disabled_message']),
            ).trim().isEmpty
          ? '请联系服务员结账'
          : _string(
              _first(json, const ['disabledMessage', 'disabled_message']),
            ),
    );
  }

  final int targetShopId;
  final String scope;
  final bool hasOwnConfig;
  final bool inheritsGlobal;
  final bool onlinePayEnabled;
  final bool canEnableCashierWechatPay;
  final PaymentTerminalCapabilities cashier;
  final PaymentTerminalCapabilities miniProgram;
  final String disabledMessage;

  /// 兼容派生（D014 后以 clients.cashier.channels.wechat_qr/alipay_qr 为权威）。
  bool get offlineCollectEnabled => cashier.wechatQr || cashier.alipayQr;

  Set<PaymentChannel> get offlineChannels => {
    if (cashier.wechatQr) PaymentChannel.wechat,
    if (cashier.alipayQr) PaymentChannel.alipay,
  };

  CashierPaymentCapabilities copyWith({
    bool? onlinePayEnabled,
    bool? canEnableCashierWechatPay,
    PaymentTerminalCapabilities? cashier,
    PaymentTerminalCapabilities? miniProgram,
    String? disabledMessage,
  }) => CashierPaymentCapabilities(
    targetShopId: targetShopId,
    scope: scope,
    hasOwnConfig: hasOwnConfig,
    inheritsGlobal: inheritsGlobal,
    onlinePayEnabled: onlinePayEnabled ?? this.onlinePayEnabled,
    canEnableCashierWechatPay:
        canEnableCashierWechatPay ?? this.canEnableCashierWechatPay,
    cashier: cashier ?? this.cashier,
    miniProgram: miniProgram ?? this.miniProgram,
    disabledMessage: disabledMessage ?? this.disabledMessage,
  );

  /// D017 写入无兼容：仅 `clients.*.enabled` + `channelStates.<渠道>.enabled`
  /// + `disabledMessage`；`offlineCollect*` 与 `clients.*.channels.*` 请求
  /// 携带即忽略，不再发送。
  Map<String, Object?> toSaveJson() => {
    'clients': {
      'cashier': cashier.toCashierJson(),
      'miniProgram': miniProgram.toMiniProgramJson(),
    },
    'disabledMessage': disabledMessage.trim(),
  };
}

class PaymentMerchant {
  const PaymentMerchant({
    this.id,
    required this.channel,
    required this.merchantKey,
    this.shopId = 0,
    this.enabled = false,
    this.readOnly = false,
    this.appId = '',
    this.mchId = '',
    this.notifyUrl = '',
    this.hasApiV3Key = false,
    this.hasApiV2Key = false,
    this.hasPrivateKey = false,
    this.hasClientCertP12 = false,
    this.hasAlipayAppCert = false,
    this.hasAlipayPublicCert = false,
    this.hasAlipayRootCert = false,
    this.credentialVersion = 1,
    this.payReady = false,
    this.remark = '',
  });

  factory PaymentMerchant.fromJson(
    Map<String, Object?> json,
  ) => PaymentMerchant(
    id: _nullableInt(json['id']),
    channel: PaymentChannel.from(json['channel']),
    merchantKey: _string(_first(json, const ['merchantKey', 'merchant_key'])),
    shopId: _int(_first(json, const ['shopId', 'shop_id'])),
    enabled: _bool(json['enabled']),
    readOnly: _bool(_first(json, const ['readOnly', 'read_only'])),
    appId: _string(_first(json, const ['appId', 'app_id'])),
    mchId: _string(_first(json, const ['mchId', 'mch_id'])),
    notifyUrl: _string(_first(json, const ['notifyUrl', 'notify_url'])),
    hasApiV3Key: _bool(_first(json, const ['hasApiV3Key', 'has_api_v3_key'])) ||
        _string(json['apiV3KeyMasked']).isNotEmpty,
    hasApiV2Key: _bool(_first(json, const ['hasApiV2Key', 'has_api_v2_key'])) ||
        _string(json['apiV2KeyMasked']).isNotEmpty,
    hasPrivateKey: _bool(
      _first(json, const ['hasPrivateKey', 'has_private_key']),
    ) || _string(json['privateKeyRefMasked']).isNotEmpty,
    hasClientCertP12: _bool(
      _first(json, const ['hasClientCertP12', 'has_client_cert_p12']),
    ) || _string(json['clientCertP12RefMasked']).isNotEmpty,
    hasAlipayAppCert: _bool(
      _first(json, const ['hasAlipayAppCert', 'has_alipay_app_cert']),
    ) || _string(json['alipayAppCertRefMasked']).isNotEmpty,
    hasAlipayPublicCert: _bool(
      _first(json, const ['hasAlipayPublicCert', 'has_alipay_public_cert']),
    ) || _string(json['alipayPublicCertRefMasked']).isNotEmpty,
    hasAlipayRootCert: _bool(
      _first(json, const ['hasAlipayRootCert', 'has_alipay_root_cert']),
    ) || _string(json['alipayRootCertRefMasked']).isNotEmpty,
    credentialVersion: _int(
      _first(json, const ['credentialVersion', 'credential_version']) ?? 1,
    ),
    payReady: _bool(_first(json, const ['payReady', 'pay_ready'])),
    remark: _string(json['remark']),
  );

  final int? id;
  final PaymentChannel channel;
  final String merchantKey;
  final int shopId;
  final bool enabled;
  final bool readOnly;
  final String appId;
  final String mchId;
  final String notifyUrl;
  final bool hasApiV3Key;
  final bool hasApiV2Key;
  final bool hasPrivateKey;
  final bool hasClientCertP12;
  final bool hasAlipayAppCert;
  final bool hasAlipayPublicCert;
  final bool hasAlipayRootCert;
  final int credentialVersion;
  final bool payReady;
  final String remark;
}

class PaymentMerchantCollection {
  const PaymentMerchantCollection({
    this.targetShopId = 0,
    this.scope = '',
    this.owned = const [],
    this.inheritedTemplates = const [],
  });

  factory PaymentMerchantCollection.fromJson(Map<String, Object?> json) =>
      PaymentMerchantCollection(
        targetShopId: _int(
          _first(json, const ['targetShopId', 'target_shop_id']),
        ),
        scope: _string(json['scope']),
        owned: _maps(json['owned']).map(PaymentMerchant.fromJson).toList(),
        inheritedTemplates:
            _maps(json['inheritedTemplates'] ?? json['inherited_templates'])
                .map(
                  (item) =>
                      PaymentMerchant.fromJson({...item, 'readOnly': true}),
                )
                .toList(),
      );

  final int targetShopId;
  final String scope;
  final List<PaymentMerchant> owned;
  final List<PaymentMerchant> inheritedTemplates;
}

class PaymentMerchantForm {
  const PaymentMerchantForm({
    this.id,
    this.exists = false,
    this.editable = true,
    this.shopId = 0,
    required this.channel,
    required this.merchantKey,
    this.enabled = true,
    this.appId = '',
    this.mchId = '',
    this.notifyUrl = '',
    this.refundNotifyUrl = '',
    this.hasApiV3Key = false,
    this.apiV3Key = '',
    this.hasApiV2Key = false,
    this.apiV2Key = '',
    this.hasPrivateKey = false,
    this.privateKeyRef = '',
    this.hasClientCertP12 = false,
    this.clientCertP12Ref = '',
    this.platformPubKeyId = '',
    this.platformPubKeyRef = '',
    this.serialNo = '',
    this.hasAlipayAppCert = false,
    this.alipayAppCertRef = '',
    this.hasAlipayPublicCert = false,
    this.alipayPublicCertRef = '',
    this.hasAlipayRootCert = false,
    this.alipayRootCertRef = '',
    this.credentialVersion = 1,
    this.payReady = false,
    this.missingFields = const [],
    this.notifyUrlSuggestions = const {},
    this.routingRuleJson = '',
    this.sortOrder = 0,
    this.remark = '',
  });

  static const maskedSecret = '******';

  factory PaymentMerchantForm.fromJson(
    Map<String, Object?> json,
  ) => PaymentMerchantForm(
    id: _nullableInt(json['id']),
    exists: _bool(json['exists']),
    editable: json.containsKey('editable') ? _bool(json['editable']) : true,
    shopId: _int(_first(json, const ['shopId', 'shop_id'])),
    channel: PaymentChannel.from(json['channel']),
    merchantKey: _string(_first(json, const ['merchantKey', 'merchant_key'])),
    enabled: json.containsKey('enabled') ? _bool(json['enabled']) : true,
    appId: _string(_first(json, const ['appId', 'app_id'])),
    mchId: _string(_first(json, const ['mchId', 'mch_id'])),
    notifyUrl: _string(_first(json, const ['notifyUrl', 'notify_url'])),
    refundNotifyUrl: _string(
      _first(json, const ['refundNotifyUrl', 'refund_notify_url']),
    ),
    hasApiV3Key: _bool(_first(json, const ['hasApiV3Key', 'has_api_v3_key'])),
    apiV3Key: _string(_first(json, const ['apiV3Key', 'api_v3_key'])),
    hasApiV2Key: _bool(_first(json, const ['hasApiV2Key', 'has_api_v2_key'])),
    apiV2Key: _string(_first(json, const ['apiV2Key', 'api_v2_key'])),
    hasPrivateKey: _bool(
      _first(json, const ['hasPrivateKey', 'has_private_key']),
    ),
    privateKeyRef: _string(
      _first(json, const ['privateKeyRef', 'private_key_ref']),
    ),
    hasClientCertP12: _bool(
      _first(json, const ['hasClientCertP12', 'has_client_cert_p12']),
    ),
    clientCertP12Ref: _string(
      _first(json, const ['clientCertP12Ref', 'client_cert_p12_ref']),
    ),
    platformPubKeyId: _string(
      _first(json, const ['platformPubKeyId', 'platform_pub_key_id']),
    ),
    platformPubKeyRef: _string(
      _first(json, const ['platformPubKeyRef', 'platform_pub_key_ref']),
    ),
    serialNo: _string(_first(json, const ['serialNo', 'serial_no'])),
    hasAlipayAppCert: _bool(
      _first(json, const ['hasAlipayAppCert', 'has_alipay_app_cert']),
    ),
    alipayAppCertRef: _string(
      _first(json, const ['alipayAppCertRef', 'alipay_app_cert_ref']),
    ),
    hasAlipayPublicCert: _bool(
      _first(json, const ['hasAlipayPublicCert', 'has_alipay_public_cert']),
    ),
    alipayPublicCertRef: _string(
      _first(json, const ['alipayPublicCertRef', 'alipay_public_cert_ref']),
    ),
    hasAlipayRootCert: _bool(
      _first(json, const ['hasAlipayRootCert', 'has_alipay_root_cert']),
    ),
    alipayRootCertRef: _string(
      _first(json, const ['alipayRootCertRef', 'alipay_root_cert_ref']),
    ),
    credentialVersion: _int(
      _first(json, const ['credentialVersion', 'credential_version']) ?? 1,
    ),
    payReady: _bool(_first(json, const ['payReady', 'pay_ready'])),
    missingFields: _strings(
      _first(json, const ['missingFields', 'missing_fields']),
    ),
    notifyUrlSuggestions: _stringMap(
      _first(json, const ['notifyUrlSuggestions', 'notify_url_suggestions']),
    ),
    routingRuleJson: _string(
      _first(json, const ['routingRuleJson', 'routing_rule_json']),
    ),
    sortOrder: _int(_first(json, const ['sortOrder', 'sort_order'])),
    remark: _string(json['remark']),
  );

  final int? id;
  final bool exists;
  final bool editable;
  final int shopId;
  final PaymentChannel channel;
  final String merchantKey;
  final bool enabled;
  final String appId;
  final String mchId;
  final String notifyUrl;
  final String refundNotifyUrl;
  final bool hasApiV3Key;
  final String apiV3Key;
  final bool hasApiV2Key;
  final String apiV2Key;
  final bool hasPrivateKey;
  final String privateKeyRef;
  final bool hasClientCertP12;
  final String clientCertP12Ref;
  final String platformPubKeyId;
  final String platformPubKeyRef;
  final String serialNo;
  final bool hasAlipayAppCert;
  final String alipayAppCertRef;
  final bool hasAlipayPublicCert;
  final String alipayPublicCertRef;
  final bool hasAlipayRootCert;
  final String alipayRootCertRef;
  final int credentialVersion;
  final bool payReady;
  final List<String> missingFields;
  final Map<String, String> notifyUrlSuggestions;
  final String routingRuleJson;
  final int sortOrder;
  final String remark;

  PaymentMerchantForm copyWith({
    int? id,
    bool? exists,
    bool? editable,
    PaymentChannel? channel,
    String? merchantKey,
    bool? enabled,
    String? appId,
    String? mchId,
    String? notifyUrl,
    String? refundNotifyUrl,
    bool? hasApiV3Key,
    String? apiV3Key,
    bool? hasApiV2Key,
    String? apiV2Key,
    bool? hasPrivateKey,
    String? privateKeyRef,
    bool? hasClientCertP12,
    String? clientCertP12Ref,
    String? platformPubKeyId,
    String? platformPubKeyRef,
    String? serialNo,
    bool? hasAlipayAppCert,
    String? alipayAppCertRef,
    bool? hasAlipayPublicCert,
    String? alipayPublicCertRef,
    bool? hasAlipayRootCert,
    String? alipayRootCertRef,
    int? credentialVersion,
    String? routingRuleJson,
    int? sortOrder,
    String? remark,
  }) => PaymentMerchantForm(
    id: id ?? this.id,
    exists: exists ?? this.exists,
    editable: editable ?? this.editable,
    shopId: shopId,
    channel: channel ?? this.channel,
    merchantKey: merchantKey ?? this.merchantKey,
    enabled: enabled ?? this.enabled,
    appId: appId ?? this.appId,
    mchId: mchId ?? this.mchId,
    notifyUrl: notifyUrl ?? this.notifyUrl,
    refundNotifyUrl: refundNotifyUrl ?? this.refundNotifyUrl,
    hasApiV3Key: hasApiV3Key ?? this.hasApiV3Key,
    apiV3Key: apiV3Key ?? this.apiV3Key,
    hasApiV2Key: hasApiV2Key ?? this.hasApiV2Key,
    apiV2Key: apiV2Key ?? this.apiV2Key,
    hasPrivateKey: hasPrivateKey ?? this.hasPrivateKey,
    privateKeyRef: privateKeyRef ?? this.privateKeyRef,
    hasClientCertP12: hasClientCertP12 ?? this.hasClientCertP12,
    clientCertP12Ref: clientCertP12Ref ?? this.clientCertP12Ref,
    platformPubKeyId: platformPubKeyId ?? this.platformPubKeyId,
    platformPubKeyRef: platformPubKeyRef ?? this.platformPubKeyRef,
    serialNo: serialNo ?? this.serialNo,
    hasAlipayAppCert: hasAlipayAppCert ?? this.hasAlipayAppCert,
    alipayAppCertRef: alipayAppCertRef ?? this.alipayAppCertRef,
    hasAlipayPublicCert: hasAlipayPublicCert ?? this.hasAlipayPublicCert,
    alipayPublicCertRef: alipayPublicCertRef ?? this.alipayPublicCertRef,
    hasAlipayRootCert: hasAlipayRootCert ?? this.hasAlipayRootCert,
    alipayRootCertRef: alipayRootCertRef ?? this.alipayRootCertRef,
    credentialVersion: credentialVersion ?? this.credentialVersion,
    payReady: payReady,
    missingFields: missingFields,
    notifyUrlSuggestions: notifyUrlSuggestions,
    routingRuleJson: routingRuleJson ?? this.routingRuleJson,
    sortOrder: sortOrder ?? this.sortOrder,
    remark: remark ?? this.remark,
  );

  Map<String, Object?> toSaveJson() => {
    if (id != null) 'id': id,
    'channel': channel.code,
    'merchantKey': merchantKey.trim(),
    'enabled': enabled,
    'appId': appId.trim(),
    'mchId': mchId.trim(),
    'notifyUrl': notifyUrl.trim(),
    'refundNotifyUrl': refundNotifyUrl.trim(),
    if (apiV3Key.trim().isNotEmpty) 'apiV3Key': apiV3Key.trim(),
    if (apiV2Key.trim().isNotEmpty) 'apiV2Key': apiV2Key.trim(),
    'privateKeyRef': privateKeyRef.trim(),
    'clientCertP12Ref': clientCertP12Ref.trim(),
    'platformPubKeyId': platformPubKeyId.trim(),
    'platformPubKeyRef': platformPubKeyRef.trim(),
    'serialNo': serialNo.trim(),
    'alipayAppCertRef': alipayAppCertRef.trim(),
    'alipayPublicCertRef': alipayPublicCertRef.trim(),
    'alipayRootCertRef': alipayRootCertRef.trim(),
    'routingRuleJson': routingRuleJson.trim(),
    'sortOrder': sortOrder,
    'remark': remark.trim(),
  };
}

class PaymentMerchantDeleteResult {
  const PaymentMerchantDeleteResult({
    required this.deletedId,
    this.physicallyDeleted = false,
    this.softDeleted = false,
  });

  factory PaymentMerchantDeleteResult.fromJson(Map<String, Object?> json) =>
      PaymentMerchantDeleteResult(
        deletedId: _int(_first(json, const ['deletedId', 'deleted_id'])),
        physicallyDeleted: _bool(
          _first(json, const ['physicallyDeleted', 'physically_deleted']),
        ),
        softDeleted: _bool(_first(json, const ['softDeleted', 'soft_deleted'])),
      );

  final int deletedId;
  final bool physicallyDeleted;
  final bool softDeleted;
  bool get deleted => physicallyDeleted || softDeleted;
}

String? validateApiV3Key(String value, {bool hasExistingKey = false}) {
  final key = value.trim();
  if (key.isEmpty && hasExistingKey) return null;
  if (key == PaymentMerchantForm.maskedSecret && hasExistingKey) return null;
  if (key.length != 32) return 'APIv3 密钥必须为 32 位';
  return null;
}

String? validateApiV2Key(String value, {bool hasExistingKey = false}) {
  final key = value.trim();
  if (key.isEmpty) return null;
  if (key == PaymentMerchantForm.maskedSecret && hasExistingKey) return null;
  if (key.length != 32) return 'APIv2 密钥必须为 32 位';
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Map<String, Object?>> _maps(Object? value) => value is Iterable
    ? value
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : const [];

/// 支付回调 URL 模板（openapi /admin/payment/notify-urls，只读）。
class PaymentNotifyUrls {
  const PaymentNotifyUrls({
    required this.wechatPayNotify,
    required this.wechatRefundNotify,
    required this.alipayPayNotify,
  });

  final String wechatPayNotify;
  final String wechatRefundNotify;
  final String alipayPayNotify;

  static PaymentNotifyUrls fromJson(Map<String, Object?> json) =>
      PaymentNotifyUrls(
        wechatPayNotify: _string(_first(
          json,
          const ['wechatPayNotify', 'wechat_pay_notify'],
        )),
        wechatRefundNotify: _string(_first(
          json,
          const ['wechatRefundNotify', 'wechat_refund_notify'],
        )),
        alipayPayNotify: _string(_first(
          json,
          const ['alipayPayNotify', 'alipay_pay_notify'],
        )),
      );

  bool get isEmpty =>
      wechatPayNotify.isEmpty &&
      wechatRefundNotify.isEmpty &&
      alipayPayNotify.isEmpty;
}

/// 微信 PEM 私钥上传结果（返回服务器文件路径，数据库只存该路径不存 PEM 内容）。
class PaymentPrivateKeyUploadResult {
  const PaymentPrivateKeyUploadResult({required this.privateKeyRef});

  final String privateKeyRef;

  static PaymentPrivateKeyUploadResult fromJson(Map<String, Object?> json) =>
      PaymentPrivateKeyUploadResult(
        privateKeyRef: _string(_first(
          json,
          const ['privateKeyRef', 'private_key_ref'],
        )),
      );
}

/// 微信支付平台公钥/证书上传结果（返回服务器文件路径与材料类型）。
class PaymentPlatformPublicKeyUploadResult {
  const PaymentPlatformPublicKeyUploadResult({
    required this.platformPubKeyRef,
    required this.materialType,
  });

  final String platformPubKeyRef;
  final String materialType;

  static PaymentPlatformPublicKeyUploadResult fromJson(Map<String, Object?> json) =>
      PaymentPlatformPublicKeyUploadResult(
        platformPubKeyRef: _string(_first(
          json,
          const ['platformPubKeyRef', 'platform_pub_key_ref'],
        )),
        materialType: _string(_first(
          json,
          const ['materialType', 'material_type'],
        )),
      );
}

/// 统一证书上传结果（支持 CLIENT_CERT_P12, PRIVATE_KEY, PLATFORM_PUBLIC_KEY, ALIPAY_*）。
class PaymentCertificateUploadResult {
  const PaymentCertificateUploadResult({
    required this.certificateType,
    required this.fileRef,
    required this.filename,
    required this.fileSize,
    this.materialType = '',
    this.clientCertP12Ref = '',
    this.privateKeyRef = '',
    this.platformPubKeyRef = '',
    this.alipayAppCertRef = '',
    this.alipayPublicCertRef = '',
    this.alipayRootCertRef = '',
  });

  final String certificateType;
  final String fileRef;
  final String filename;
  final int fileSize;
  final String materialType;
  final String clientCertP12Ref;
  final String privateKeyRef;
  final String platformPubKeyRef;
  final String alipayAppCertRef;
  final String alipayPublicCertRef;
  final String alipayRootCertRef;

  static PaymentCertificateUploadResult fromJson(Map<String, Object?> json) {
    final certType = _string(
      _first(json, const ['certificateType', 'certificate_type']),
    );
    final ref = _string(_first(json, const ['fileRef', 'file_ref']));
    final p12 = _string(
      _first(json, const ['clientCertP12Ref', 'client_cert_p12_ref']),
    );
    final pk = _string(
      _first(json, const ['privateKeyRef', 'private_key_ref']),
    );
    final pub = _string(
      _first(json, const ['platformPubKeyRef', 'platform_pub_key_ref']),
    );
    final appCert = _string(
      _first(json, const ['alipayAppCertRef', 'alipay_app_cert_ref']),
    );
    final pubCert = _string(
      _first(json, const ['alipayPublicCertRef', 'alipay_public_cert_ref']),
    );
    final rootCert = _string(
      _first(json, const ['alipayRootCertRef', 'alipay_root_cert_ref']),
    );

    return PaymentCertificateUploadResult(
      certificateType: certType,
      fileRef: ref,
      filename: _string(json['filename']),
      fileSize: _int(_first(json, const ['fileSize', 'file_size'])),
      materialType: _string(
        _first(json, const ['materialType', 'material_type']),
      ),
      clientCertP12Ref: p12.isNotEmpty ? p12 : (certType == 'CLIENT_CERT_P12' ? ref : ''),
      privateKeyRef: pk.isNotEmpty ? pk : (certType == 'PRIVATE_KEY' ? ref : ''),
      platformPubKeyRef: pub.isNotEmpty ? pub : (certType == 'PLATFORM_PUBLIC_KEY' ? ref : ''),
      alipayAppCertRef: appCert.isNotEmpty ? appCert : (certType == 'ALIPAY_APP_CERT' ? ref : ''),
      alipayPublicCertRef: pubCert.isNotEmpty ? pubCert : (certType == 'ALIPAY_PUBLIC_CERT' ? ref : ''),
      alipayRootCertRef: rootCert.isNotEmpty ? rootCert : (certType == 'ALIPAY_ROOT_CERT' ? ref : ''),
    );
  }
}

/// 客户端证书字节校验（PKCS12 / .p12 / .pfx，排斥 PEM 文本，大小限制 512KB）。
String? validateClientCertP12Bytes(List<int>? bytes) {
  if (bytes == null || bytes.length < 24) {
    return '客户端证书文件过短或损坏';
  }
  if (bytes.length > 512 * 1024) {
    return '客户端证书文件过大（最多 512KB）';
  }
  final sampleLength = bytes.length < 64 ? bytes.length : 64;
  final head = String.fromCharCodes(bytes.sublist(0, sampleLength));
  if (head.startsWith('-') || head.contains('-----BEGIN')) {
    return '上传的是 PEM 文本文件，客户端证书必须为 PKCS12 二进制（.p12/.pfx）文件';
  }
  return null;
}

Object? _first(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return json[key];
  }
  return null;
}

String _string(Object? value) => value == null ? '' : '$value';

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {
    'true',
    '1',
    'yes',
    'enabled',
  }.contains('$value'.trim().toLowerCase());
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

List<String> _strings(Object? value) => value is Iterable
    ? value.map(_string).where((item) => item.isNotEmpty).toList()
    : const [];

Map<String, PaymentChannelCapabilityState> _channelStates(Object? value) =>
    _map(value).map(
      (key, value) =>
          MapEntry(key, PaymentChannelCapabilityState.fromJson(value)),
    );

Map<String, String> _stringMap(Object? value) =>
    _map(value).map((key, value) => MapEntry(key, _string(value)));

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0.0;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

List<int> _intList(Object? value) => value is Iterable
    ? value.map(_int).toList()
    : const [];

class GoodsMatchCondition {
  const GoodsMatchCondition({
    this.goodsNameKeywords = const [],
    this.categoryIds = const [],
    this.goodsIds = const [],
    this.mode = 'CONTAINS_ANY',
  });

  factory GoodsMatchCondition.fromJson(Map<String, Object?> json) =>
      GoodsMatchCondition(
        goodsNameKeywords: _strings(
          _first(json, const ['goodsNameKeywords', 'goods_name_keywords']),
        ),
        categoryIds: _intList(
          _first(json, const ['categoryIds', 'category_ids']),
        ),
        goodsIds: _intList(_first(json, const ['goodsIds', 'goods_ids'])),
        mode: _string(json['mode']).isEmpty ? 'CONTAINS_ANY' : _string(json['mode']),
      );

  final List<String> goodsNameKeywords;
  final List<int> categoryIds;
  final List<int> goodsIds;
  final String mode; // CONTAINS_ANY, CONTAINS_ALL, ONLY

  Map<String, Object?> toJson() => {
        'goodsNameKeywords': goodsNameKeywords,
        'categoryIds': categoryIds,
        'goodsIds': goodsIds,
        'mode': mode,
      };
}

class TimeRangeCondition {
  const TimeRangeCondition({
    this.startTime = '',
    this.endTime = '',
  });

  factory TimeRangeCondition.fromJson(Map<String, Object?> json) =>
      TimeRangeCondition(
        startTime: _string(
          _first(json, const ['startTime', 'start_time']),
        ),
        endTime: _string(
          _first(json, const ['endTime', 'end_time']),
        ),
      );

  final String startTime;
  final String endTime;

  Map<String, Object?> toJson() => {
        'startTime': startTime,
        'endTime': endTime,
      };
}

class PaymentRoutingConditions {
  const PaymentRoutingConditions({
    this.diningTypes = const [],
    this.minPaidYuan,
    this.maxPaidYuan,
    this.goodsMatch,
    this.timeRange,
  });

  factory PaymentRoutingConditions.fromJson(Map<String, Object?> json) {
    final goodsObj = _first(json, const ['goodsMatch', 'goods_match']);
    final timeObj = _first(json, const ['timeRange', 'time_range']);
    return PaymentRoutingConditions(
      diningTypes: _strings(
        _first(json, const ['diningTypes', 'dining_types']),
      ),
      minPaidYuan: _nullableDouble(
        _first(json, const ['minPaidYuan', 'min_paid_yuan']),
      ),
      maxPaidYuan: _nullableDouble(
        _first(json, const ['maxPaidYuan', 'max_paid_yuan']),
      ),
      goodsMatch: goodsObj is Map<String, Object?>
          ? GoodsMatchCondition.fromJson(goodsObj)
          : null,
      timeRange: timeObj is Map<String, Object?>
          ? TimeRangeCondition.fromJson(timeObj)
          : null,
    );
  }

  final List<String> diningTypes;
  final double? minPaidYuan;
  final double? maxPaidYuan;
  final GoodsMatchCondition? goodsMatch;
  final TimeRangeCondition? timeRange;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{};
    if (diningTypes.isNotEmpty) map['diningTypes'] = diningTypes;
    if (minPaidYuan != null) map['minPaidYuan'] = minPaidYuan;
    if (maxPaidYuan != null) map['maxPaidYuan'] = maxPaidYuan;
    if (goodsMatch != null) map['goodsMatch'] = goodsMatch!.toJson();
    if (timeRange != null) map['timeRange'] = timeRange!.toJson();
    return map;
  }
}

class PaymentRoutingRule {
  const PaymentRoutingRule({
    this.id,
    this.shopId = 0,
    this.channel = PaymentChannel.wechat,
    this.ruleName = '',
    this.priority = 100,
    this.enabled = true,
    this.targetMerchantKey = 'default',
    this.matchMode = 'ALL',
    this.conditionsJson = '',
    this.conditions,
    this.remark = '',
    this.targetMerchantPayReady = true,
    this.inherited = false,
    this.readOnly = false,
  });

  factory PaymentRoutingRule.fromJson(Map<String, Object?> json) {
    final channelCode = _string(json['channel']).toLowerCase();
    final channel = channelCode == 'alipay'
        ? PaymentChannel.alipay
        : PaymentChannel.wechat;
    final condStr = _string(
      _first(json, const ['conditionsJson', 'conditions_json']),
    );
    PaymentRoutingConditions? parsedConditions;
    if (condStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(condStr);
        if (decoded is Map<String, Object?>) {
          parsedConditions = PaymentRoutingConditions.fromJson(decoded);
        }
      } catch (_) {}
    } else if (json['conditions'] is Map<String, Object?>) {
      parsedConditions = PaymentRoutingConditions.fromJson(
        json['conditions'] as Map<String, Object?>,
      );
    }

    return PaymentRoutingRule(
      id: _nullableInt(json['id']),
      shopId: _int(_first(json, const ['shopId', 'shop_id'])),
      channel: channel,
      ruleName: _string(_first(json, const ['ruleName', 'rule_name'])),
      priority: _int(json['priority']),
      enabled: _bool(json['enabled']),
      targetMerchantKey: _string(
        _first(json, const ['targetMerchantKey', 'target_merchant_key']),
      ),
      matchMode: _string(
        _first(json, const ['matchMode', 'match_mode']),
      ).toUpperCase() == 'ANY'
          ? 'ANY'
          : 'ALL',
      conditionsJson: condStr,
      conditions: parsedConditions,
      remark: _string(json['remark']),
      targetMerchantPayReady: _bool(
        _first(json, const ['targetMerchantPayReady', 'target_merchant_pay_ready']),
      ),
      inherited: _bool(json['inherited']),
      readOnly: _bool(json['readOnly'] ?? json['read_only']),
    );
  }

  final int? id;
  final int shopId;
  final PaymentChannel channel;
  final String ruleName;
  final int priority;
  final bool enabled;
  final String targetMerchantKey;
  final String matchMode; // ALL or ANY
  final String conditionsJson;
  final PaymentRoutingConditions? conditions;
  final String remark;
  final bool targetMerchantPayReady;
  final bool inherited;
  final bool readOnly;

  Map<String, Object?> toSaveJson() => {
        'channel': channel.code,
        'ruleName': ruleName,
        'priority': priority,
        'enabled': enabled,
        'targetMerchantKey': targetMerchantKey,
        'matchMode': matchMode,
        'conditions': conditions?.toJson() ?? {},
        'remark': remark,
      };
}

class PaymentRoutingRuleCollection {
  const PaymentRoutingRuleCollection({
    this.targetShopId = 0,
    this.scope = '',
    this.channel = PaymentChannel.wechat,
    this.rules = const [],
    this.inheritedTemplates = const [],
  });

  factory PaymentRoutingRuleCollection.fromJson(Map<String, Object?> json) {
    final channelCode = _string(json['channel']).toLowerCase();
    final channel = channelCode == 'alipay'
        ? PaymentChannel.alipay
        : PaymentChannel.wechat;
    return PaymentRoutingRuleCollection(
      targetShopId: _int(
        _first(json, const ['targetShopId', 'target_shop_id']),
      ),
      scope: _string(json['scope']),
      channel: channel,
      rules: _maps(json['rules']).map(PaymentRoutingRule.fromJson).toList(),
      inheritedTemplates: _maps(
        json['inheritedTemplates'] ?? json['inherited_templates'],
      ).map((item) => PaymentRoutingRule.fromJson({...item, 'inherited': true, 'readOnly': true})).toList(),
    );
  }

  final int targetShopId;
  final String scope;
  final PaymentChannel channel;
  final List<PaymentRoutingRule> rules;
  final List<PaymentRoutingRule> inheritedTemplates;
}

class PaymentRoutingSimulationResult {
  const PaymentRoutingSimulationResult({
    this.shopId = 0,
    this.channel = 'wechat',
    this.inputPaidYuan = 0.0,
    this.inputDiningType = '',
    this.inputGoodsCount = 0,
    this.matched = false,
    this.matchedRuleId,
    this.matchedRuleName = '',
    this.targetMerchantKey = '',
    this.targetMerchantPayReady = true,
    this.effectiveMerchantKey = 'default',
    this.fallbackOccurred = false,
    this.reason = '',
  });

  factory PaymentRoutingSimulationResult.fromJson(Map<String, Object?> json) =>
      PaymentRoutingSimulationResult(
        shopId: _int(_first(json, const ['shopId', 'shop_id'])),
        channel: _string(json['channel']),
        inputPaidYuan: _double(_first(json, const ['inputPaidYuan', 'input_paid_yuan'])),
        inputDiningType: _string(
          _first(json, const ['inputDiningType', 'input_dining_type']),
        ),
        inputGoodsCount: _int(
          _first(json, const ['inputGoodsCount', 'input_goods_count']),
        ),
        matched: _bool(json['matched']),
        matchedRuleId: _nullableInt(
          _first(json, const ['matchedRuleId', 'matched_rule_id']),
        ),
        matchedRuleName: _string(
          _first(json, const ['matchedRuleName', 'matched_rule_name']),
        ),
        targetMerchantKey: _string(
          _first(json, const ['targetMerchantKey', 'target_merchant_key']),
        ),
        targetMerchantPayReady: _bool(
          _first(
            json,
            const ['targetMerchantPayReady', 'target_merchant_pay_ready'],
          ),
        ),
        effectiveMerchantKey: _string(
          _first(json, const ['effectiveMerchantKey', 'effective_merchant_key']),
        ),
        fallbackOccurred: _bool(
          _first(json, const ['fallbackOccurred', 'fallback_occurred']),
        ),
        reason: _string(json['reason']),
      );

  final int shopId;
  final String channel;
  final double inputPaidYuan;
  final String inputDiningType;
  final int inputGoodsCount;
  final bool matched;
  final int? matchedRuleId;
  final String matchedRuleName;
  final String targetMerchantKey;
  final bool targetMerchantPayReady;
  final String effectiveMerchantKey;
  final bool fallbackOccurred;
  final String reason;
}

