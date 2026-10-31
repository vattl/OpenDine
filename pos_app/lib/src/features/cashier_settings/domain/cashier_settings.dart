import 'dart:convert';

import '../../auth/domain/access_approval_models.dart';

class CashierBusinessSettings {
  const CashierBusinessSettings({
    required this.isOpen,
    required this.isReviewed,
    required this.shopId,
  });

  factory CashierBusinessSettings.fromJson(Map<String, Object?> rawJson) {
    final json = rawJson['data'] is Map
        ? (rawJson['data'] as Map).cast<String, Object?>()
        : rawJson;
    return CashierBusinessSettings(
      isOpen: _asBool(
        json['business'] ??
            json['bus'] ??
            json['isOpen'] ??
            json['is_open'] ??
            json['status'],
      ),
      isReviewed: _asBool(
        json['isReview'] ??
            json['is_review'] ??
            json['reviewed'] ??
            json['review'],
      ),
      shopId: _asInt(
        json['shopId'] ??
            json['shop_id'] ??
            json['merchantId'] ??
            json['merchant_id'],
      ),
    );
  }

  final bool isOpen;
  final bool isReviewed;
  final int? shopId;
}

class CashierPaymentMethod {
  const CashierPaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.enabled,
  });

  factory CashierPaymentMethod.fromJson(Map<String, Object?> json) {
    return CashierPaymentMethod(
      id: _asInt(json['id']) ?? 0,
      code: '${json['code'] ?? ''}',
      name: '${json['name'] ?? ''}',
      sortOrder: _asInt(json['sort_order'] ?? json['sortOrder']) ?? 0,
      enabled: _asBool(json['enabled']),
    );
  }

  final int id;
  final String code;
  final String name;
  final int sortOrder;
  final bool enabled;
}

class CashierSettingsShift {
  const CashierSettingsShift({
    required this.id,
    required this.adminId,
    required this.shopId,
    required this.startTime,
    required this.endTime,
    required this.startCash,
    required this.endCash,
    required this.orderCount,
    required this.totalAmount,
    this.cashierName,
  });

  factory CashierSettingsShift.fromJson(Map<String, Object?> json) {
    return CashierSettingsShift(
      id: _asInt(json['id']) ?? 0,
      adminId: _asInt(json['admin_id'] ?? json['adminId']),
      shopId: _asInt(json['shop_id'] ?? json['shopId']),
      startTime: _asDateTime(json['start_time'] ?? json['startTime']),
      endTime: _asDateTime(json['end_time'] ?? json['endTime']),
      startCash: _asDouble(json['start_cash'] ?? json['startCash']),
      endCash: _asDouble(json['end_cash'] ?? json['endCash']),
      orderCount: _asInt(json['order_count'] ?? json['orderCount']) ?? 0,
      totalAmount: _asDouble(json['total_amount'] ?? json['totalAmount']),
      cashierName: _asNullableString(
        json['admin_name'] ?? json['cashier_name'] ?? json['cashierName'],
      ),
    );
  }

  final int id;
  final int? adminId;
  final int? shopId;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? startCash;
  final double? endCash;
  final int orderCount;
  final double? totalAmount;
  final String? cashierName;
}

class EmployeeAssignmentException implements Exception {
  const EmployeeAssignmentException(this.adminId, this.cause);
  final int adminId;
  final Object cause;
  @override
  String toString() => '账号已创建（ID $adminId），但角色/门店授权失败。请重试授权，不要重复创建账号。原因：$cause';
}

class CashierSettingsOverview {
  const CashierSettingsOverview({required this.shopId, required this.modules});

  factory CashierSettingsOverview.fromJson(Map<String, Object?> json) {
    return CashierSettingsOverview(
      shopId: _asInt(json['shopId'] ?? json['shop_id']),
      modules: _asObjectList(
        json['modules'],
      ).map(CashierSettingsModule.fromJson).toList(growable: false),
    );
  }

  final int? shopId;
  final List<CashierSettingsModule> modules;

  CashierSettingsModule? module(String code) {
    final normalized = code.trim().toLowerCase();
    for (final module in modules) {
      if (module.module.toLowerCase() == normalized) return module;
    }
    return null;
  }
}

class CashierSettingsModule {
  const CashierSettingsModule({
    required this.module,
    required this.permission,
    required this.permitted,
    required this.source,
    required this.summary,
    required this.alerts,
  });

  factory CashierSettingsModule.fromJson(Map<String, Object?> json) {
    return CashierSettingsModule(
      module: '${json['module'] ?? ''}'.trim(),
      permission: '${json['permission'] ?? ''}'.trim(),
      permitted: _asBool(json['permitted']),
      source: '${json['source'] ?? 'SYSTEM'}'.trim().toUpperCase(),
      summary: '${json['summary'] ?? ''}'.trim(),
      alerts: _asInt(json['alerts']) ?? 0,
    );
  }

  final String module;
  final String permission;
  final bool permitted;
  final String source;
  final String summary;
  final int alerts;
}

class CashierStoreSettings {
  const CashierStoreSettings({
    required this.module,
    required this.source,
    required this.version,
    required this.basic,
    required this.businessHours,
    required this.businessDays,
    this.updatedAt,
    this.updatedBy,
  });

  factory CashierStoreSettings.fromJson(Map<String, Object?> json) {
    return CashierStoreSettings(
      module: '${json['module'] ?? 'store'}'.trim(),
      source: '${json['source'] ?? 'SYSTEM'}'.trim().toUpperCase(),
      version: _asInt(json['version']) ?? 0,
      updatedAt: _asDateTime(json['updatedAt'] ?? json['updated_at']),
      updatedBy: _asNullableString(json['updatedBy'] ?? json['updated_by']),
      basic: _asObjectMap(json['basic']),
      businessHours: _asObjectList(
        json['businessHours'] ?? json['business_hours'],
      ),
      businessDays: _asIntList(json['businessDays'] ?? json['business_days']),
    );
  }

  final String module;
  final String source;
  final int version;
  final DateTime? updatedAt;
  final String? updatedBy;
  final Map<String, Object?> basic;
  final List<Map<String, Object?>> businessHours;
  final List<int> businessDays;
}

class CashierAccessEvaluation {
  const CashierAccessEvaluation({
    AuthorizationOutcome? outcome,
    this.allow = false,
    this.permissionGranted = false,
    this.shopInScope = true,
    this.matchedRoles = const [],
    this.priority,
    this.rule,
    this.explanation,
    this.policyPassed,
    this.approvalRequired,
    this.reasonCode,
    this.matchedPolicies,
    this.approval,
  }) : outcome = outcome ??
            (approvalRequired == true
                ? AuthorizationOutcome.requireApproval
                : (allow ? AuthorizationOutcome.allow : AuthorizationOutcome.deny));

  factory CashierAccessEvaluation.fromJson(Map<String, Object?> json) {
    return CashierAccessEvaluation(
      outcome: parseOutcome(json),
      allow: _asBool(json['allow']),
      permissionGranted: _asBool(
        json['permissionGranted'] ?? json['permission_granted'],
      ),
      shopInScope: _asBool(json['shopInScope'] ?? json['shop_in_scope']),
      matchedRoles: _matchedRoles(
        json['matchedRoles'] ?? json['matched_roles'],
      ),
      priority: _asInt(json['priority']),
      rule: _asNullableString(json['rule']),
      explanation: _asNullableString(json['explanation']),
      // ABAC 决策引擎专属字段（legacy 通道不返回时为 null）。
      policyPassed: json['policyPassed'] == null
          ? null
          : _asBool(json['policyPassed']),
      approvalRequired: json['approvalRequired'] == null
          ? null
          : _asBool(json['approvalRequired']),
      reasonCode: _asNullableString(json['reasonCode']),
      matchedPolicies: _jsonSummary(
        json['matchedPolicies'] ?? json['matched_policies'],
      ),
      approval: _jsonSummary(json['approval']),
    );
  }

  /// 决策结果三态语义（ALLOW / REQUIRE_APPROVAL / DENY，WI-062）。
  final AuthorizationOutcome outcome;

  final bool allow;
  final bool permissionGranted;
  final bool shopInScope;
  final List<String> matchedRoles;
  final int? priority;
  final String? rule;
  final String? explanation;

  /// 策略是否通过（ABAC 决策引擎）。
  final bool? policyPassed;

  /// 是否触发审批（超出阈值/需店长授权时 true）。
  final bool? approvalRequired;

  /// 决策原因码（如 POLICY_MAX_AMOUNT / POLICY_MIN_DISCOUNT_RATE）。
  final String? reasonCode;

  /// 命中的策略列表摘要（JSON 文本，含 policy_code / policy_name）。
  final String? matchedPolicies;

  /// 审批信息摘要（approvalToken / maxAmount / expiresAt 等，JSON 文本）。
  final String? approval;

  /// 是否允许直接执行。
  bool get isAllowed => outcome == AuthorizationOutcome.allow;

  /// 是否需要发起审批授权。
  bool get requiresApproval => outcome == AuthorizationOutcome.requireApproval;

  /// 是否硬拒绝（禁止提交，禁止轮询重试）。
  bool get isDenied => outcome == AuthorizationOutcome.deny;
}

/// 将列表/对象摘要成可展示的 JSON 文本（null 返回 null）。
String? _jsonSummary(Object? value) {
  if (value == null) return null;
  if (value is String) {
    return value.trim().isEmpty ? null : value.trim();
  }
  try {
    final encoded = jsonEncode(value);
    return encoded.isEmpty ? null : encoded;
  } catch (_) {
    return null;
  }
}

class CashierSettingsSectionData {
  const CashierSettingsSectionData({
    required this.raw,
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.source,
    required this.version,
  });

  factory CashierSettingsSectionData.fromResponse(Object? response) {
    final raw = _asObjectMap(response);
    final directItems = _asObjectList(
      raw['items'] ?? raw['list'] ?? raw['records'] ?? raw['rows'],
    );
    final items = directItems.isNotEmpty
        ? directItems
        : response is List
        ? _asObjectList(response)
        : const <Map<String, Object?>>[];
    return CashierSettingsSectionData(
      raw: raw,
      items: items,
      total: _asInt(raw['total']) ?? items.length,
      page: _asInt(raw['page']) ?? 1,
      pageSize: _asInt(raw['pageSize'] ?? raw['page_size']) ?? 20,
      source: '${raw['source'] ?? ''}'.trim().toUpperCase(),
      version: _asInt(raw['version']),
    );
  }

  final Map<String, Object?> raw;
  final List<Map<String, Object?>> items;
  final int total;
  final int page;
  final int pageSize;
  final String source;
  final int? version;
}

class CashierPrinterDevice {
  const CashierPrinterDevice({
    this.id,
    required this.name,
    this.vendor = '通用ESC/POS',
    this.shopId,
    this.shopName = '',
    this.transport = 'CLOUD',
    this.status = 'ONLINE',
    this.ip,
    this.port = 9100,
    this.sn,
    this.ukey,
    this.user,
    this.apiKey,
    this.apiUrl,
    this.paperSize = '80mm',
    this.copies = 1,
    this.autoCut = true,
    this.beeper = true,
    this.enabled = true,
    this.isDefault = false,
    this.ticketTypes = const ['FULL_ORDER', 'CHECKOUT'],
    this.version = 1,
    this.paperStatus = 'NORMAL',
    this.coverStatus = 'CLOSED',
    this.lastPingTime,
    this.updatedAt,
    this.updatedBy,
  });

  factory CashierPrinterDevice.fromJson(Map<String, Object?> json) {
    final conn = json['connection'] is Map
        ? (json['connection'] as Map).cast<String, Object?>()
        : null;
    final name =
        '${json['name'] ?? json['deviceName'] ?? json['title'] ?? '未命名打印机'}'
            .trim();
    final parsedTicketTypes = _asStringList(
      json['ticketTypes'] ??
          json['ticket_types'] ??
          json['receiptTypes'] ??
          json['receipt_types'] ??
          json['docTypes'],
    );
    final ticketTypes = parsedTicketTypes.isNotEmpty
        ? parsedTicketTypes
        : _inferDefaultTicketTypes(name);

    return CashierPrinterDevice(
      id: _asInt(json['id']),
      name: name,
      vendor:
          '${json['vendor'] ?? json['brand'] ?? json['vendorName'] ?? '通用ESC/POS'}'
              .trim(),
      shopId: _asInt(json['shopId'] ?? json['shop_id']),
      shopName: '${json['shopName'] ?? json['shop_name'] ?? ''}'.trim(),
      transport:
          '${json['transport'] ?? json['connectionType'] ?? json['type'] ?? 'CLOUD'}'
              .trim()
              .toUpperCase(),
      status: '${json['status'] ?? 'ONLINE'}'.trim().toUpperCase(),
      paperStatus: '${json['paperStatus'] ?? json['paper_status'] ?? 'NORMAL'}'
          .trim()
          .toUpperCase(),
      coverStatus: '${json['coverStatus'] ?? json['cover_status'] ?? 'CLOSED'}'
          .trim()
          .toUpperCase(),
      lastPingTime: _asDateTime(json['lastPingTime'] ?? json['last_ping_time']),
      ip: _asNullableString(
        json['ip'] ?? conn?['ip'] ?? json['ipAddress'] ?? json['host'],
      ),
      port: _asInt(json['port'] ?? conn?['port']) ?? 9100,
      sn: _asNullableString(
        json['sn'] ??
            conn?['sn'] ??
            json['deviceSn'] ??
            json['code'] ??
            json['serialNumber'],
      ),
      ukey: _asNullableString(
        json['ukey'] ??
            conn?['ukey'] ??
            conn?['key'] ??
            json['uKey'] ??
            json['appSecret'],
      ),
      user: _asNullableString(
        json['user'] ?? conn?['user'] ?? json['account'] ?? json['appId'],
      ),
      apiKey: _asNullableString(
        json['apiKey'] ?? conn?['apiKey'] ?? json['api_key'],
      ),
      apiUrl: _asNullableString(
        json['apiUrl'] ?? conn?['apiUrl'] ?? conn?['url'] ?? json['api_url'],
      ),
      paperSize: '${json['paperSize'] ?? json['paper_size'] ?? '80mm'}'.trim(),
      copies: _asInt(json['copies']) ?? 1,
      autoCut: _asBool(json['autoCut'] ?? json['auto_cut'] ?? true),
      beeper: _asBool(json['beeper'] ?? json['beep'] ?? true),
      enabled: json.containsKey('enabled') ? _asBool(json['enabled']) : true,
      isDefault: _asBool(json['isDefault'] ?? json['is_default']),
      ticketTypes: ticketTypes,
      version: _asInt(json['version']) ?? 1,
      updatedAt: _asDateTime(json['updatedAt'] ?? json['updated_at']),
      updatedBy: _asNullableString(json['updatedBy'] ?? json['updated_by']),
    );
  }

  Map<String, Object?> toJson() {
    final connectionMap = <String, Object?>{
      if (ip != null && ip!.isNotEmpty) 'ip': ip,
      'port': port,
      if (sn != null && sn!.isNotEmpty) 'sn': sn,
      if (ukey != null && ukey!.isNotEmpty) 'ukey': ukey,
      if (user != null && user!.isNotEmpty) 'user': user,
      if (apiKey != null && apiKey!.isNotEmpty) 'apiKey': apiKey,
      if (apiUrl != null && apiUrl!.isNotEmpty) 'apiUrl': apiUrl,
    };

    return {
      if (id != null) 'id': id,
      'name': name,
      'vendor': vendor,
      'brand': vendor,
      if (shopId != null) 'shopId': shopId,
      'shopName': shopName,
      'transport': transport,
      'status': status,
      'paperStatus': paperStatus,
      'paper_status': paperStatus,
      'coverStatus': coverStatus,
      'cover_status': coverStatus,
      if (lastPingTime != null) 'lastPingTime': lastPingTime!.toIso8601String(),
      if (ip != null) 'ip': ip,
      'port': port,
      if (sn != null) 'sn': sn,
      if (ukey != null) 'ukey': ukey,
      if (user != null) 'user': user,
      if (apiKey != null) 'apiKey': apiKey,
      if (apiUrl != null) 'apiUrl': apiUrl,
      'connection': connectionMap,
      'paperSize': paperSize,
      'copies': copies,
      'autoCut': autoCut,
      'beeper': beeper,
      'enabled': enabled,
      'isDefault': isDefault,
      'ticketTypes': ticketTypes,
      'ticket_types': ticketTypes,
      'version': version,
    };
  }

  CashierPrinterDevice copyWith({
    int? id,
    String? name,
    String? vendor,
    int? shopId,
    String? shopName,
    String? transport,
    String? status,
    String? paperStatus,
    String? coverStatus,
    DateTime? lastPingTime,
    String? ip,
    int? port,
    String? sn,
    String? ukey,
    String? user,
    String? apiKey,
    String? apiUrl,
    String? paperSize,
    int? copies,
    bool? autoCut,
    bool? beeper,
    bool? enabled,
    bool? isDefault,
    List<String>? ticketTypes,
    int? version,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return CashierPrinterDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      vendor: vendor ?? this.vendor,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      transport: transport ?? this.transport,
      status: status ?? this.status,
      paperStatus: paperStatus ?? this.paperStatus,
      coverStatus: coverStatus ?? this.coverStatus,
      lastPingTime: lastPingTime ?? this.lastPingTime,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      sn: sn ?? this.sn,
      ukey: ukey ?? this.ukey,
      user: user ?? this.user,
      apiKey: apiKey ?? this.apiKey,
      apiUrl: apiUrl ?? this.apiUrl,
      paperSize: paperSize ?? this.paperSize,
      copies: copies ?? this.copies,
      autoCut: autoCut ?? this.autoCut,
      beeper: beeper ?? this.beeper,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
      ticketTypes: ticketTypes ?? this.ticketTypes,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  final int? id;
  final String name;
  final String vendor;
  final int? shopId;
  final String shopName;
  final String transport;
  final String status;
  final String paperStatus;
  final String coverStatus;
  final DateTime? lastPingTime;
  final String? ip;
  final int port;
  final String? sn;
  final String? ukey;
  final String? user;
  final String? apiKey;
  final String? apiUrl;
  final String paperSize;
  final int copies;
  final bool autoCut;
  final bool beeper;
  final bool enabled;
  final bool isDefault;
  final List<String> ticketTypes;
  final int version;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get isOnline =>
      (status == 'ONLINE' ||
          status == '1' ||
          status == 'NORMAL' ||
          status == 'READY') &&
      !isOutOfPaper &&
      !isCoverOpen;
  bool get isOffline =>
      status == 'OFFLINE' || status == '0' || status == 'DISCONNECTED';
  bool get isError =>
      status == 'ERROR' ||
      status == '2' ||
      status == 'NO_PAPER' ||
      status == 'COVER_OPEN' ||
      isOutOfPaper ||
      isCoverOpen ||
      paperStatus == 'ERROR' ||
      coverStatus == 'ERROR';
  bool get isUnknown =>
      status == 'UNKNOWN' || (!isOnline && !isOffline && !isError);

  bool get isOutOfPaper => paperStatus == 'OUT_OF_PAPER';
  bool get isCoverOpen => coverStatus == 'OPEN';
  bool get isPaperNormal => paperStatus == 'NORMAL';
  bool get isCoverClosed => coverStatus == 'CLOSED';

  String get statusDisplayName => switch (status.toUpperCase()) {
    'ONLINE' ||
    '1' ||
    'NORMAL' ||
    'READY' => isOutOfPaper ? '缺纸' : (isCoverOpen ? '开盖' : '在线'),
    'OFFLINE' || '0' || 'DISCONNECTED' => '离线',
    'ERROR' ||
    '2' ||
    'NO_PAPER' ||
    'COVER_OPEN' => isOutOfPaper ? '缺纸' : (isCoverOpen ? '开盖' : '异常/缺纸'),
    'UNKNOWN' => '未知',
    _ => status,
  };

  String get paperStatusDisplayName => switch (paperStatus.toUpperCase()) {
    'NORMAL' => '纸仓充足',
    'OUT_OF_PAPER' => '缺纸',
    'ERROR' => '纸仓故障',
    _ => '状态未知',
  };

  String get coverStatusDisplayName => switch (coverStatus.toUpperCase()) {
    'CLOSED' => '仓盖闭合',
    'OPEN' => '仓盖开启',
    'ERROR' => '传感器异常',
    _ => '状态未知',
  };

  String get transportDisplayName => switch (transport.toUpperCase()) {
    'CLOUD' || 'FEIE' || 'YILIAN' => '云打印',
    'LAN' || 'NETWORK' || 'ETHERNET' => '局域网 (LAN)',
    'USB' => 'USB 直连',
    'BLUETOOTH' || 'BLE' => '蓝牙连接',
    _ => transport,
  };

  List<String> get ticketTypeLabels =>
      ticketTypes.map(CashierPrinterTicketType.getLabel).toList();

  String get ticketTypesSummary =>
      ticketTypeLabels.isEmpty ? '未配置票据' : ticketTypeLabels.join(' · ');
}

/// 打印机支持的票据类型
class CashierPrinterTicketType {
  const CashierPrinterTicketType({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;

  static const kitchen = CashierPrinterTicketType(
    code: 'KITCHEN',
    label: '厨房小票',
    description: '后厨制作分单与档口出菜凭据',
  );

  static const fullOrder = CashierPrinterTicketType(
    code: 'FULL_ORDER',
    label: '前台整单',
    description: '收银前台全单点菜单',
  );

  static const preCheckout = CashierPrinterTicketType(
    code: 'PRE_CHECKOUT',
    label: '预结单',
    description: '顾客核对消费预结明细',
  );

  static const checkout = CashierPrinterTicketType(
    code: 'CHECKOUT',
    label: '结账单',
    description: '结账完成打印正式小票凭证',
  );

  static const expedite = CashierPrinterTicketType(
    code: 'EXPEDITE',
    label: '传菜单',
    description: '催菜/划单/传菜出餐凭单',
  );

  static const takeout = CashierPrinterTicketType(
    code: 'TAKEOUT',
    label: '外卖单',
    description: '外卖平台接单配送凭条',
  );

  static const packing = CashierPrinterTicketType(
    code: 'PACKING',
    label: '打包单',
    description: '打包/到店自提订单的独立核餐凭条',
  );

  static const List<CashierPrinterTicketType> all = [
    kitchen,
    fullOrder,
    preCheckout,
    checkout,
    expedite,
    takeout,
    packing,
  ];

  static const List<String> frontDeskPreset = [
    'FULL_ORDER',
    'PRE_CHECKOUT',
    'CHECKOUT',
  ];

  static const List<String> kitchenPreset = ['KITCHEN', 'EXPEDITE'];

  static String getLabel(String code) {
    for (final item in all) {
      if (item.code.toUpperCase() == code.toUpperCase()) return item.label;
    }
    return code;
  }
}

List<String> _inferDefaultTicketTypes(String name) {
  if (name.contains('后厨') || name.contains('厨房') || name.contains('档口')) {
    return const ['KITCHEN', 'EXPEDITE'];
  }
  if (name.contains('出餐') || name.contains('划单') || name.contains('传菜')) {
    return const ['EXPEDITE'];
  }
  if (name.contains('外卖')) {
    return const ['TAKEOUT'];
  }
  return const ['FULL_ORDER', 'PRE_CHECKOUT', 'CHECKOUT'];
}

class CashierPrinterStatusProbe {
  const CashierPrinterStatusProbe({
    required this.deviceId,
    required this.online,
    required this.status,
    this.paperStatus = 'NORMAL',
    this.coverStatus = 'CLOSED',
    this.lastPingTime,
  });

  factory CashierPrinterStatusProbe.fromJson(Map<String, Object?> json) {
    final statusStr =
        '${json['status'] ?? (json['online'] == true ? 'ONLINE' : 'OFFLINE')}'
            .trim()
            .toUpperCase();
    final isOnlineVal = _asBool(json['online'] ?? (statusStr == 'ONLINE'));
    return CashierPrinterStatusProbe(
      deviceId: _asInt(json['deviceId'] ?? json['id']) ?? 0,
      online: isOnlineVal,
      status: statusStr,
      paperStatus: '${json['paperStatus'] ?? json['paper_status'] ?? 'NORMAL'}'
          .trim()
          .toUpperCase(),
      coverStatus: '${json['coverStatus'] ?? json['cover_status'] ?? 'CLOSED'}'
          .trim()
          .toUpperCase(),
      lastPingTime: _asDateTime(json['lastPingTime'] ?? json['last_ping_time']),
    );
  }

  final int deviceId;
  final bool online;
  final String status;
  final String paperStatus;
  final String coverStatus;
  final DateTime? lastPingTime;

  bool get isOnline =>
      (online || status == 'ONLINE' || status == '1' || status == 'NORMAL') &&
      status != 'OFFLINE' &&
      status != 'ERROR';
  bool get isError =>
      status == 'ERROR' ||
      status == '2' ||
      paperStatus == 'OUT_OF_PAPER' ||
      coverStatus == 'OPEN' ||
      paperStatus == 'ERROR' ||
      coverStatus == 'ERROR';
  bool get isOffline =>
      status == 'OFFLINE' || status == '0' || (!online && status != 'ERROR');
  bool get isUnknown =>
      status == 'UNKNOWN' || (!isOnline && !isOffline && !isError);

  bool get isPaperNormal => paperStatus == 'NORMAL';
  bool get isOutOfPaper => paperStatus == 'OUT_OF_PAPER';
  bool get isCoverClosed => coverStatus == 'CLOSED';
  bool get isCoverOpen => coverStatus == 'OPEN';

  String get statusLabel => switch (status.toUpperCase()) {
    'ONLINE' ||
    '1' => (isOutOfPaper ? '在线 (缺纸告警)' : (isCoverOpen ? '在线 (仓盖开启)' : '正常在线')),
    'OFFLINE' || '0' => '离线 / 未连接',
    'ERROR' || '2' =>
      (isOutOfPaper ? '设备异常 (缺纸)' : (isCoverOpen ? '设备异常 (开盖)' : '设备异常 / 故障')),
    _ => '状态未知',
  };

  String get paperStatusLabel => switch (paperStatus.toUpperCase()) {
    'NORMAL' => '纸仓充足',
    'OUT_OF_PAPER' => '缺纸告警 (需装纸)',
    'ERROR' => '纸仓检测异常',
    _ => '未知 / 未检测',
  };

  String get coverStatusLabel => switch (coverStatus.toUpperCase()) {
    'CLOSED' => '仓盖已闭合',
    'OPEN' => '仓盖开启 (需盖紧)',
    'ERROR' => '传感器检测异常',
    _ => '未知 / 未检测',
  };
}

List<String> _matchedRoles(Object? value) {
  if (value is! List) return const [];
  final roles = <String>[];
  for (final item in value) {
    final name = switch (item) {
      String s => s.trim(),
      Map m => '${m['roleName'] ?? m['name'] ?? m['role'] ?? ''}'.trim(),
      _ => '',
    };
    if (name.isNotEmpty) roles.add(name);
  }
  return roles;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch ('$value'.trim().toLowerCase()) {
    'true' || '1' || 'yes' || 'enabled' => true,
    _ => false,
  };
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

DateTime? _asDateTime(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return null;
  return DateTime.tryParse('$value');
}

String? _asNullableString(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? null : text;
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) return Map.of(value);
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Map<String, Object?>> _asObjectList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}

List<int> _asIntList(Object? value) {
  if (value is! List) return const [];
  return value.map(_asInt).whereType<int>().toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((item) => '$item'.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    return value
        .split(RegExp('[,;|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

/// 员工（access 体系，GET /admin/access/employees）
class CashierAccessEmployee {
  const CashierAccessEmployee({
    required this.adminId,
    required this.userName,
    this.workNo = '',
    this.realName = '',
    this.jobTitle = '',
    this.displayName = '',
    this.phone = '',
    this.roles = const [],
    this.shops = const [],
    this.accountStatus = CashierAccessEmployeeStatus.active,
    this.permissionVersion = 1,
    this.lastLoginAt,
    this.lastLoginIp = '',
  });

  factory CashierAccessEmployee.fromJson(Map<String, Object?> json) {
    final workNo = '${json['workNo'] ?? json['work_no'] ?? ''}'.trim();
    final realName = '${json['realName'] ?? json['real_name'] ?? ''}'.trim();
    final jobTitle = '${json['jobTitle'] ?? json['job_title'] ?? ''}'.trim();
    final userName = '${json['userName'] ?? json['username'] ?? ''}'.trim();
    final displayName =
        '${json['displayName'] ?? json['name'] ?? (realName.isNotEmpty ? realName : userName)}'
            .trim();
    return CashierAccessEmployee(
      adminId: _asInt(json['adminId'] ?? json['admin_id']) ?? 0,
      userName: userName,
      workNo: workNo,
      realName: realName,
      jobTitle: jobTitle,
      displayName: displayName,
      phone: '${json['phone'] ?? ''}'.trim(),
      roles: _asObjectList(
        json['roles'],
      ).map(CashierAccessRoleRef.fromJson).toList(growable: false),
      shops: _asIntList(json['shops'] ?? json['shopIds'] ?? json['shop_ids']),
      accountStatus:
          '${json['accountStatus'] ?? json['account_status'] ?? CashierAccessEmployeeStatus.active}'
              .trim()
              .toUpperCase(),
      permissionVersion:
          _asInt(json['permissionVersion'] ?? json['permission_version']) ?? 1,
      lastLoginAt: _asDateTime(json['lastLoginAt'] ?? json['last_login_at']),
      lastLoginIp: '${json['lastLoginIp'] ?? json['last_login_ip'] ?? ''}'.trim(),
    );
  }

  final int adminId;
  final String userName;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String displayName;
  final String phone;
  final List<CashierAccessRoleRef> roles;
  final List<int> shops;

  /// 账号状态：ACTIVE / DISABLED / RESIGNED / LOCKED（对齐服务端 Admin.account_status）。
  final String accountStatus;

  /// 权限版本号：角色绑定或权限变更时服务端自动累加，落后即要求重新鉴权。
  final int permissionVersion;

  /// 最近登录时间。
  final DateTime? lastLoginAt;

  /// 最近登录 IP。
  final String lastLoginIp;
}

/// 员工账号状态四态（对齐服务端 Admin.STATUS_*）。
class CashierAccessEmployeeStatus {
  static const active = 'ACTIVE';
  static const disabled = 'DISABLED';
  static const resigned = 'RESIGNED';
  static const locked = 'LOCKED';

  static String label(String? status) {
    switch (status) {
      case active:
        return '在职';
      case disabled:
        return '已停用';
      case resigned:
        return '已离职';
      case locked:
        return '已锁定';
      default:
        return status == null || status.isEmpty ? '-' : status;
    }
  }
}

/// 员工状态变更结果（PUT /admin/access/employees/{id}/status 返回）。
class CashierEmployeeStatusResult {
  const CashierEmployeeStatusResult({
    this.adminId = 0,
    this.accountStatus = CashierAccessEmployeeStatus.active,
    this.permissionVersion = 1,
  });

  factory CashierEmployeeStatusResult.fromJson(Map<String, Object?> json) {
    return CashierEmployeeStatusResult(
      adminId: _asInt(json['adminId'] ?? json['admin_id']) ?? 0,
      accountStatus:
          '${json['accountStatus'] ?? json['account_status'] ?? CashierAccessEmployeeStatus.active}'
              .trim()
              .toUpperCase(),
      permissionVersion:
          _asInt(json['permissionVersion'] ?? json['permission_version']) ?? 1,
    );
  }

  final int adminId;
  final String accountStatus;
  final int permissionVersion;
}

class CashierAccessRoleRef {
  const CashierAccessRoleRef({
    required this.id,
    this.roleCode = '',
    this.roleName = '',
  });

  factory CashierAccessRoleRef.fromJson(Map<String, Object?> json) {
    return CashierAccessRoleRef(
      id: _asInt(json['id']) ?? 0,
      roleCode: '${json['roleCode'] ?? json['role_code'] ?? ''}'.trim(),
      roleName: '${json['roleName'] ?? json['role_name'] ?? ''}'.trim(),
    );
  }

  final int id;
  final String roleCode;
  final String roleName;
}

class PagedCashierAccessEmployees {
  const PagedCashierAccessEmployees({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  factory PagedCashierAccessEmployees.fromJson(Map<String, Object?> json) {
    return PagedCashierAccessEmployees(
      page: _asInt(json['page']) ?? 1,
      pageSize: _asInt(json['pageSize'] ?? json['page_size']) ?? 20,
      total: _asInt(json['total']) ?? 0,
      items: _asObjectList(
        json['items'],
      ).map(CashierAccessEmployee.fromJson).toList(growable: false),
    );
  }

  final int page;
  final int pageSize;
  final int total;
  final List<CashierAccessEmployee> items;
}

class CashierAccessRole {
  const CashierAccessRole({
    required this.id,
    required this.roleCode,
    required this.roleName,
    this.remark = '',
    this.sortOrder = 100,
    this.version = 1,
    this.adminCount = 0,
    this.permissions = const [],
  });

  factory CashierAccessRole.fromJson(Map<String, Object?> json) {
    return CashierAccessRole(
      id: _asInt(json['id']) ?? 0,
      roleCode: '${json['roleCode'] ?? json['role_code'] ?? ''}'.trim(),
      roleName: '${json['roleName'] ?? json['role_name'] ?? ''}'.trim(),
      remark: '${json['remark'] ?? ''}'.trim(),
      sortOrder: _asInt(json['sortOrder'] ?? json['sort_order']) ?? 100,
      version: _asInt(json['version']) ?? 1,
      adminCount: _asInt(json['adminCount'] ?? json['admin_count']) ?? 0,
      permissions: _asObjectList(
        json['permissions'],
      ).map(CashierPermissionCodeRef.fromJson).toList(growable: false),
    );
  }

  final int id;
  final String roleCode;
  final String roleName;
  final String remark;
  final int sortOrder;
  final int version;
  final int adminCount;
  final List<CashierPermissionCodeRef> permissions;
}

class CashierPermissionCodeRef {
  const CashierPermissionCodeRef({
    required this.id,
    this.permissionCode = '',
    this.permissionName = '',
  });

  factory CashierPermissionCodeRef.fromJson(Map<String, Object?> json) {
    return CashierPermissionCodeRef(
      id: _asInt(json['id']) ?? 0,
      permissionCode:
          '${json['permissionCode'] ?? json['permission_code'] ?? ''}'.trim(),
      permissionName:
          '${json['permissionName'] ?? json['permission_name'] ?? ''}'.trim(),
    );
  }

  final int id;
  final String permissionCode;
  final String permissionName;
}

class CashierPermissionCode {
  const CashierPermissionCode({
    this.id,
    required this.permissionCode,
    required this.permissionName,
    this.module = '',
    this.remark = '',
    this.sortOrder = 0,
  });

  factory CashierPermissionCode.fromJson(Map<String, Object?> json) {
    return CashierPermissionCode(
      id: _asInt(json['id']),
      permissionCode:
          '${json['permission_code'] ?? json['permissionCode'] ?? ''}'.trim(),
      permissionName:
          '${json['permission_name'] ?? json['permissionName'] ?? ''}'.trim(),
      module: '${json['module'] ?? ''}'.trim(),
      remark: '${json['remark'] ?? ''}'.trim(),
      sortOrder: _asInt(json['sort_order'] ?? json['sortOrder']) ?? 0,
    );
  }

  final int? id;
  final String permissionCode;
  final String permissionName;
  final String module;
  final String remark;
  final int sortOrder;
}

class CashierApiPermission {
  const CashierApiPermission({
    this.id,
    required this.method,
    required this.pathPattern,
    required this.permissionCode,
    this.remark = '',
  });

  factory CashierApiPermission.fromJson(Map<String, Object?> json) {
    return CashierApiPermission(
      id: _asInt(json['id']),
      method: '${json['method'] ?? ''}'.trim().toUpperCase(),
      pathPattern: '${json['path_pattern'] ?? json['pathPattern'] ?? ''}'
          .trim(),
      permissionCode:
          '${json['permission_code'] ?? json['permissionCode'] ?? ''}'.trim(),
      remark: '${json['remark'] ?? ''}'.trim(),
    );
  }

  final int? id;
  final String method;
  final String pathPattern;
  final String permissionCode;
  final String remark;
}

class CashierAccessAuditEntry {
  const CashierAccessAuditEntry({
    this.id,
    required this.title,
    this.time,
    this.module = '',
    this.action = '',
    this.detail = '',
  });

  factory CashierAccessAuditEntry.fromJson(Map<String, Object?> json) {
    return CashierAccessAuditEntry(
      id: _asInt(json['id']),
      title: _auditTitle(json),
      time: _asDateTime(
        json['createTime'] ?? json['create_time'] ?? json['time'],
      ),
      module: '${json['module'] ?? ''}'.trim(),
      action: '${json['action'] ?? ''}'.trim(),
      detail: _auditDetail(json),
    );
  }

  final int? id;
  final String title;
  final DateTime? time;
  final String module;
  final String action;
  final String detail;
}

String _auditTitle(Map<String, Object?> json) {
  final action = '${json['action'] ?? ''}'.trim();
  final operator =
      '${json['operatorName'] ?? json['operator_name'] ?? json['operator'] ?? '管理员'}'
          .trim();
  return operator.isEmpty ? action : '$operator $action';
}

String _auditDetail(Map<String, Object?> json) {
  final summary =
      json['summary'] ?? json['detail'] ?? json['description'] ?? '';
  return '$summary'.trim();
}

class CashierShopRef {
  const CashierShopRef({
    required this.id,
    this.name = '',
    this.code = '',
    this.status = 1,
  });

  factory CashierShopRef.fromJson(Map<String, Object?> json) {
    return CashierShopRef(
      id: _asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
      code: '${json['code'] ?? ''}'.trim(),
      status: _asInt(json['status']) ?? 1,
    );
  }

  final int id;
  final String name;
  final String code;
  final int status;
}

class CashierShopSummary {
  const CashierShopSummary({required this.id, this.name = '', this.code = ''});

  factory CashierShopSummary.fromJson(Map<String, Object?> json) {
    return CashierShopSummary(
      id: _asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
      code: '${json['code'] ?? ''}'.trim(),
    );
  }

  final int id;
  final String name;
  final String code;
}

class CashierAdministrator {
  const CashierAdministrator({
    required this.id,
    required this.userName,
    this.workNo = '',
    this.realName = '',
    this.jobTitle = '',
    this.displayName = '',
    this.phone = '',
    this.email = '',
    this.roleIds = const [],
    this.roles = const [],
    this.scope = '',
    this.shopIds = const [],
    this.shops = const [],
    this.createTime = '',
  });

  factory CashierAdministrator.fromJson(Map<String, Object?> json) {
    final workNo = '${json['workNo'] ?? json['work_no'] ?? ''}'.trim();
    final realName = '${json['realName'] ?? json['real_name'] ?? ''}'.trim();
    final jobTitle = '${json['jobTitle'] ?? json['job_title'] ?? ''}'.trim();
    final userName = '${json['userName'] ?? json['username'] ?? ''}'.trim();
    final displayName =
        '${json['displayName'] ?? json['name'] ?? (realName.isNotEmpty ? realName : userName)}'
            .trim();
    return CashierAdministrator(
      id: _asInt(json['id']) ?? 0,
      userName: userName,
      workNo: workNo,
      realName: realName,
      jobTitle: jobTitle,
      displayName: displayName,
      phone: '${json['phone'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      roleIds: _asIntList(json['roleIds']),
      roles: _asObjectList(
        json['roles'],
      ).map(CashierAccessRoleRef.fromJson).toList(growable: false),
      scope: '${json['scope'] ?? ''}'.trim(),
      shopIds: _asIntList(json['shopIds']),
      shops: _asObjectList(
        json['shops'],
      ).map(CashierShopSummary.fromJson).toList(growable: false),
      createTime: '${json['createTime'] ?? json['create_time'] ?? ''}'.trim(),
    );
  }

  final int id;
  final String userName;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String displayName;
  final String phone;
  final String email;
  final List<int> roleIds;
  final List<CashierAccessRoleRef> roles;
  final String scope;
  final List<int> shopIds;
  final List<CashierShopSummary> shops;
  final String createTime;

  String get effectiveName => displayName.isNotEmpty
      ? displayName
      : (realName.isNotEmpty ? realName : userName);
}

class PagedCashierAdministrators {
  const PagedCashierAdministrators({
    required this.items,
    this.total = 0,
    this.allRoles = const [],
  });

  factory PagedCashierAdministrators.fromJson(Map<String, Object?> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, Object?>()
        : json;
    return PagedCashierAdministrators(
      items: _asObjectList(
        data['list'] ?? json['list'],
      ).map(CashierAdministrator.fromJson).toList(growable: false),
      total: _asInt(data['total'] ?? json['total']) ?? 0,
      allRoles: _asObjectList(
        data['allRoles'] ?? json['allRoles'],
      ).map(CashierAccessRoleRef.fromJson).toList(growable: false),
    );
  }

  final List<CashierAdministrator> items;
  final int total;
  final List<CashierAccessRoleRef> allRoles;
}

// ============ 外卖管理（UI009） ============

class DeliveryFeeTier {
  const DeliveryFeeTier({required this.toKm, required this.fee});

  factory DeliveryFeeTier.fromJson(Map<String, Object?> json) {
    return DeliveryFeeTier(
      toKm: _asDouble(json['toKm'] ?? json['to_km']) ?? 0,
      fee: _asDouble(json['fee']) ?? 0,
    );
  }

  final double toKm;
  final double fee;

  Map<String, Object?> toJson() => {'toKm': toKm, 'fee': fee};
}

class ShopTakeoutConfig {
  const ShopTakeoutConfig({
    this.shopId,
    this.enabled = 0,
    this.deliveryFee,
    this.minOrderAmount,
    this.freeDeliveryThreshold,
    this.maxDeliveryDistanceKm,
    this.freeDeliveryMaxDistanceKm,
    this.tiers = const [],
    this.leadTimeMinutes,
    this.remark = '',
    this.updatedAt,
  });

  factory ShopTakeoutConfig.fromJson(Map<String, Object?> json) {
    return ShopTakeoutConfig(
      shopId: _asInt(json['shop_id'] ?? json['shopId']),
      enabled: _asInt(json['enabled']) ?? 0,
      deliveryFee: _asDouble(json['delivery_fee'] ?? json['deliveryFee']),
      minOrderAmount: _asDouble(
        json['min_order_amount'] ?? json['minOrderAmount'],
      ),
      freeDeliveryThreshold: _asDouble(
        json['free_delivery_threshold'] ?? json['freeDeliveryThreshold'],
      ),
      maxDeliveryDistanceKm: _asDouble(
        json['max_delivery_distance_km'] ?? json['maxDeliveryDistanceKm'],
      ),
      freeDeliveryMaxDistanceKm: _asDouble(
        json['free_delivery_max_distance_km'] ??
            json['freeDeliveryMaxDistanceKm'],
      ),
      tiers: _parseDeliveryTiers(
        json['delivery_fee_tiers_json'] ?? json['deliveryFeeTiersJson'],
      ),
      leadTimeMinutes: _asInt(
        json['lead_time_minutes'] ?? json['leadTimeMinutes'],
      ),
      remark: '${json['remark'] ?? ''}'.trim(),
      updatedAt: _asDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }

  final int? shopId;
  final int enabled;
  final double? deliveryFee;
  final double? minOrderAmount;
  final double? freeDeliveryThreshold;
  final double? maxDeliveryDistanceKm;
  final double? freeDeliveryMaxDistanceKm;
  final List<DeliveryFeeTier> tiers;
  final int? leadTimeMinutes;
  final String remark;
  final DateTime? updatedAt;

  ShopTakeoutConfig copyWith({
    int? enabled,
    double? deliveryFee,
    double? minOrderAmount,
    double? freeDeliveryThreshold,
    double? maxDeliveryDistanceKm,
    double? freeDeliveryMaxDistanceKm,
    List<DeliveryFeeTier>? tiers,
    int? leadTimeMinutes,
    String? remark,
  }) {
    return ShopTakeoutConfig(
      shopId: shopId,
      enabled: enabled ?? this.enabled,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      freeDeliveryThreshold:
          freeDeliveryThreshold ?? this.freeDeliveryThreshold,
      maxDeliveryDistanceKm:
          maxDeliveryDistanceKm ?? this.maxDeliveryDistanceKm,
      freeDeliveryMaxDistanceKm:
          freeDeliveryMaxDistanceKm ?? this.freeDeliveryMaxDistanceKm,
      tiers: tiers ?? this.tiers,
      leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
      remark: remark ?? this.remark,
      updatedAt: updatedAt,
    );
  }
}

class ZsqAutoApiConfig {
  const ZsqAutoApiConfig({
    this.shopId = 0,
    this.autoDispatchEnabled = false,
    this.takeoutSyncEnabled = false,
  });

  factory ZsqAutoApiConfig.fromJson(Map<String, Object?> json) {
    final auto = json['autoDispatchEnabled'] ?? json['autoApiEnabled'];
    return ZsqAutoApiConfig(
      shopId: _asInt(json['shopId'] ?? json['shop_id']) ?? 0,
      autoDispatchEnabled: _asBool(auto),
      takeoutSyncEnabled: _asBool(json['takeoutSyncEnabled']),
    );
  }

  final int shopId;
  final bool autoDispatchEnabled;
  final bool takeoutSyncEnabled;

  ZsqAutoApiConfig copyWith({
    bool? autoDispatchEnabled,
    bool? takeoutSyncEnabled,
  }) {
    return ZsqAutoApiConfig(
      shopId: shopId,
      autoDispatchEnabled: autoDispatchEnabled ?? this.autoDispatchEnabled,
      takeoutSyncEnabled: takeoutSyncEnabled ?? this.takeoutSyncEnabled,
    );
  }
}

class TakeoutDeliveryRecord {
  const TakeoutDeliveryRecord({
    this.orderId = 0,
    this.orderNo = '',
    this.receiverName = '',
    this.receiverPhone = '',
    this.addressFull = '',
    this.deliveryFee,
    this.actualDeliveryFee,
    this.dispatchStatus = '',
    this.zsqDispatchStatus = '',
    this.zsqPhase = '',
    this.zsqOrderId = '',
    this.zsqRiderName = '',
    this.createdAt,
    this.updatedAt,
  });

  factory TakeoutDeliveryRecord.fromJson(Map<String, Object?> json) {
    return TakeoutDeliveryRecord(
      orderId: _asInt(json['order_id'] ?? json['orderId']) ?? 0,
      orderNo: '${json['order_no'] ?? json['orderNo'] ?? ''}'.trim(),
      receiverName: '${json['receiver_name'] ?? json['receiverName'] ?? ''}'
          .trim(),
      receiverPhone: '${json['receiver_phone'] ?? json['receiverPhone'] ?? ''}'
          .trim(),
      addressFull: '${json['address_full'] ?? json['addressFull'] ?? ''}'
          .trim(),
      deliveryFee: _asDouble(json['delivery_fee'] ?? json['deliveryFee']),
      // v1.2.279：实际配送费（语义别名，取自 zsq_actual_fee）。
      actualDeliveryFee: _asDouble(
        json['actual_delivery_fee'] ??
            json['actualDeliveryFee'] ??
            json['zsq_actual_fee'],
      ),
      dispatchStatus:
          '${json['dispatch_status'] ?? json['dispatchStatus'] ?? ''}'.trim(),
      zsqDispatchStatus:
          '${json['zsq_dispatch_status'] ?? json['zsqDispatchStatus'] ?? ''}'
              .trim(),
      zsqPhase: '${json['zsq_phase'] ?? json['zsqPhase'] ?? ''}'.trim(),
      zsqOrderId: '${json['zsq_order_id'] ?? json['zsqOrderId'] ?? ''}'.trim(),
      zsqRiderName: '${json['zsq_rider_name'] ?? json['zsqRiderName'] ?? ''}'
          .trim(),
      createdAt: _asDateTime(
        json['created_at'] ?? json['createdAt'] ?? json['time'],
      ),
      updatedAt: _asDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }

  final int orderId;
  final String orderNo;
  final String receiverName;
  final String receiverPhone;
  final String addressFull;
  final double? deliveryFee;

  /// 实际配送费（元）：真省钱平台实际跑腿费用（zsq_actual_fee）。
  final double? actualDeliveryFee;
  final String dispatchStatus;
  final String zsqDispatchStatus;
  final String zsqPhase;
  final String zsqOrderId;
  final String zsqRiderName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class TakeoutDeliveryDetail {
  const TakeoutDeliveryDetail({
    this.orderId = 0,
    this.orderNo = '',
    this.settAmount,
    this.createdAt,
    this.delivery,
  });

  factory TakeoutDeliveryDetail.fromJson(Map<String, Object?> json) {
    final order = json['order'] is Map
        ? (json['order'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final delivery = json['delivery'] is Map
        ? (json['delivery'] as Map).cast<String, Object?>()
        : null;
    return TakeoutDeliveryDetail(
      orderId: _asInt(order['id'] ?? json['orderId']) ?? 0,
      orderNo:
          '${order['order_no'] ?? order['orderNo'] ?? json['orderNo'] ?? ''}'
              .trim(),
      settAmount: _asDouble(order['sett_amount'] ?? order['settAmount']),
      createdAt: _asDateTime(order['create_time'] ?? order['createTime']),
      delivery: delivery == null
          ? null
          : TakeoutDeliveryRecord.fromJson(delivery),
    );
  }

  final int orderId;
  final String orderNo;
  final double? settAmount;
  final DateTime? createdAt;
  final TakeoutDeliveryRecord? delivery;
}

class ZsqTrackingLog {
  const ZsqTrackingLog({this.time, this.text = ''});

  factory ZsqTrackingLog.fromJson(Map<String, Object?> json) {
    final rawTime =
        json['ts'] ??
        json['time'] ??
        json['createTime'] ??
        json['create_time'] ??
        json['updatedAt'];
    final rawText =
        json['statusDesc'] ??
        json['desc'] ??
        json['description'] ??
        json['message'] ??
        json['action'] ??
        json['remark'] ??
        json['event'];
    return ZsqTrackingLog(time: _asDateTime(rawTime), text: '$rawText'.trim());
  }

  final DateTime? time;
  final String text;
}

class ZsqRiderTracking {
  const ZsqRiderTracking({
    this.riderName,
    this.riderPhone,
    this.phase,
    this.statusDesc,
    this.platformDistanceText,
    this.platformDurationText,
    this.toShopMinutes,
    this.toUserMinutes,
    this.dispatchStatus,
    this.zsqDispatchStatus,
    this.canRedispatch = false,
    this.missingOpenOrderId,
    this.logs = const [],
  });

  factory ZsqRiderTracking.fromJson(
    Map<String, Object?> json, {
    bool canRedispatch = false,
    int? missingOpenOrderId,
  }) {
    final tracking = json['tracking'] is Map
        ? (json['tracking'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final rider = tracking['rider'] is Map
        ? (tracking['rider'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final effective = tracking['effectiveState'] is Map
        ? (tracking['effectiveState'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final platformEta = tracking['platformEta'] is Map
        ? (tracking['platformEta'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final computedEta = tracking['computedEta'] is Map
        ? (tracking['computedEta'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return ZsqRiderTracking(
      riderName: _asNullableString(rider['name']),
      riderPhone: _asNullableString(rider['phone']),
      phase: _asNullableString(effective['phase'] ?? tracking['phase']),
      statusDesc: _asNullableString(
        effective['statusDesc'] ?? tracking['deliverySendStatusDesc'],
      ),
      platformDistanceText: _asNullableString(platformEta['distanceText']),
      platformDurationText: _asNullableString(platformEta['durationText']),
      toShopMinutes: _asInt(computedEta['toShopMinutes']),
      toUserMinutes: _asInt(computedEta['toUserMinutes']),
      dispatchStatus: _asNullableString(
        tracking['dispatchStatus'] ?? json['dispatchStatus'],
      ),
      zsqDispatchStatus: _asNullableString(
        tracking['zsqDispatchStatus'] ?? json['zsqDispatchStatus'],
      ),
      canRedispatch: canRedispatch,
      missingOpenOrderId: missingOpenOrderId,
      logs: _asObjectList(tracking['orderLogs'])
          .map(ZsqTrackingLog.fromJson)
          .where((log) => log.text.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String? riderName;
  final String? riderPhone;
  final String? phase;
  final String? statusDesc;
  final String? platformDistanceText;
  final String? platformDurationText;
  final int? toShopMinutes;
  final int? toUserMinutes;
  final String? dispatchStatus;
  final String? zsqDispatchStatus;
  final bool canRedispatch;
  final int? missingOpenOrderId;
  final List<ZsqTrackingLog> logs;
}

List<DeliveryFeeTier> _parseDeliveryTiers(Object? value) {
  if (value == null) {
    return const [];
  }
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => DeliveryFeeTier.fromJson(e.cast<String, Object?>()))
        .toList(growable: false);
  }
  final text = '$value'.trim();
  if (text.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => DeliveryFeeTier.fromJson(e.cast<String, Object?>()))
          .toList(growable: false);
    }
  } catch (_) {
    // ignore malformed tier json
  }
  return const [];
}

class PagedTakeoutDeliveries {
  const PagedTakeoutDeliveries({required this.items, this.total = 0});

  factory PagedTakeoutDeliveries.fromJson(Map<String, Object?> json) {
    return PagedTakeoutDeliveries(
      items: _asObjectList(
        json['list'] ?? json['items'],
      ).map(TakeoutDeliveryRecord.fromJson).toList(growable: false),
      total: _asInt(json['total']) ?? 0,
    );
  }

  final List<TakeoutDeliveryRecord> items;
  final int total;
}

// ============================================================
// 权限中心 v2：动态策略引擎 / SoD 冲突防护 / 有效权限
// ============================================================

/// 权限策略类型（对齐服务端 AccessPolicy.TYPE_*）。
class CashierAccessPolicyType {
  static const maxAmount = 'MAX_AMOUNT';
  static const minDiscountRate = 'MIN_DISCOUNT_RATE';
  static const maxDiscountAmount = 'MAX_DISCOUNT_AMOUNT';
  static const maxDailyCount = 'MAX_DAILY_COUNT';
  static const orderStatus = 'ORDER_STATUS';
  static const timeWindow = 'TIME_WINDOW';

  static String label(String? type) {
    switch (type) {
      case maxAmount:
        return '金额上限';
      case minDiscountRate:
        return '折扣底线';
      case maxDiscountAmount:
        return '折扣金额上限';
      case maxDailyCount:
        return '日次数上限';
      case orderStatus:
        return '订单状态限制';
      case timeWindow:
        return '时间窗口限制';
      default:
        return type == null || type.isEmpty ? '-' : type;
    }
  }
}

/// 权限策略默认作用（对齐服务端 AccessPolicy.EFFECT_*）。
class CashierAccessPolicyEffect {
  static const allow = 'ALLOW';
  static const deny = 'DENY';

  static String label(String? effect) {
    switch (effect) {
      case allow:
        return '放行';
      case deny:
        return '拒绝';
      default:
        return effect == null || effect.isEmpty ? '-' : effect;
    }
  }
}

/// 权限策略（GET/POST/PUT/DELETE /admin/access/policies）。
/// 服务端实体字段为 snake_case（policy_code 等），前端提交时保持一致。
class CashierAccessPolicy {
  const CashierAccessPolicy({
    this.id,
    this.policyCode = '',
    this.policyName = '',
    this.permissionCode = '',
    this.policyType = '',
    this.effect = CashierAccessPolicyEffect.allow,
    this.priority = 100,
    this.enabled = 1,
    this.configJson,
  });

  factory CashierAccessPolicy.fromJson(Map<String, Object?> json) {
    return CashierAccessPolicy(
      id: _asInt(json['id']),
      policyCode: '${json['policy_code'] ?? json['policyCode'] ?? ''}'.trim(),
      policyName: '${json['policy_name'] ?? json['policyName'] ?? ''}'.trim(),
      permissionCode:
          '${json['permission_code'] ?? json['permissionCode'] ?? ''}'.trim(),
      policyType: '${json['policy_type'] ?? json['policyType'] ?? ''}'.trim(),
      effect: '${json['effect'] ?? CashierAccessPolicyEffect.allow}'
          .trim()
          .toUpperCase(),
      priority: _asInt(json['priority']) ?? 100,
      enabled: _asInt(json['enabled']) ?? 1,
      configJson: json['config_json'] is String
          ? (json['config_json'] as String)
          : (json['config_json'] is Map
              ? jsonEncode(json['config_json'])
              : null),
    );
  }

  /// 提交给服务端的请求体（对齐 AccessPolicy 实体 snake_case 字段）。
  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'policy_code': policyCode,
        'policy_name': policyName,
        'permission_code': permissionCode,
        'policy_type': policyType,
        'effect': effect,
        'priority': priority,
        'enabled': enabled,
        if (configJson != null && configJson!.isNotEmpty) 'config_json': configJson,
      };

  final int? id;
  final String policyCode;
  final String policyName;
  final String permissionCode;
  final String policyType;
  final String effect;
  final int priority;
  final int enabled;
  final String? configJson;

  bool get isEnabled => enabled == 1;
}

/// SoD 职责分离冲突条目（POST /admin/access/conflicts/check 返回 conflicts 项）。
class CashierAccessConflict {
  const CashierAccessConflict({
    this.ruleId,
    this.permissionA = '',
    this.permissionB = '',
    this.severity = 'SOFT',
    this.message = '',
  });

  factory CashierAccessConflict.fromJson(Map<String, Object?> json) {
    return CashierAccessConflict(
      ruleId: _asInt(json['ruleId'] ?? json['rule_id']),
      permissionA:
          '${json['permissionA'] ?? json['permission_a'] ?? ''}'.trim(),
      permissionB:
          '${json['permissionB'] ?? json['permission_b'] ?? ''}'.trim(),
      severity: '${json['severity'] ?? 'SOFT'}'.trim().toUpperCase(),
      message: '${json['message'] ?? ''}'.trim(),
    );
  }

  final int? ruleId;
  final String permissionA;
  final String permissionB;
  final String severity;
  final String message;

  /// HARD 级别严禁冲突：分配时后端直接拦截，仅超级管理员可凭 forceReason 豁免。
  bool get isHard => severity == 'HARD';
}

/// 员工个性化权限覆盖（AdminPermissionOverride：ALLOW/DENY 显式覆盖，可定向门店）。
class CashierAccessOverride {
  const CashierAccessOverride({
    this.id,
    this.permissionCode = '',
    this.effect = CashierAccessPolicyEffect.allow,
    this.shopId,
    this.source = '',
    this.reason = '',
  });

  factory CashierAccessOverride.fromJson(Map<String, Object?> json) {
    return CashierAccessOverride(
      id: _asInt(json['id']),
      permissionCode:
          '${json['permission_code'] ?? json['permissionCode'] ?? ''}'.trim(),
      effect: '${json['effect'] ?? CashierAccessPolicyEffect.allow}'
          .trim()
          .toUpperCase(),
      shopId: _asInt(json['shop_id'] ?? json['shopId']),
      source: '${json['source'] ?? ''}'.trim(),
      reason: '${json['reason'] ?? ''}'.trim(),
    );
  }

  final int? id;
  final String permissionCode;
  final String effect;
  final int? shopId;
  final String source;
  final String reason;
}

/// 员工最终有效权限（GET /admin/access/employees/{id}/effective-permissions）。
class CashierEffectivePermissions {
  const CashierEffectivePermissions({
    this.adminId = 0,
    this.userName = '',
    this.realName = '',
    this.accountStatus = CashierAccessEmployeeStatus.active,
    this.permissionVersion = 1,
    this.roles = const [],
    this.permissions = const [],
    this.overrides = const [],
  });

  factory CashierEffectivePermissions.fromJson(Map<String, Object?> json) {
    return CashierEffectivePermissions(
      adminId: _asInt(json['adminId'] ?? json['admin_id']) ?? 0,
      userName: '${json['userName'] ?? json['username'] ?? ''}'.trim(),
      realName: '${json['realName'] ?? json['real_name'] ?? ''}'.trim(),
      accountStatus:
          '${json['accountStatus'] ?? json['account_status'] ?? CashierAccessEmployeeStatus.active}'
              .trim()
              .toUpperCase(),
      permissionVersion:
          _asInt(json['permissionVersion'] ?? json['permission_version']) ?? 1,
      roles: _asObjectList(json['roles'],
      )
          .map(CashierAccessRoleRef.fromJson)
          .toList(growable: false),
      permissions: _asStringList(json['permissions']),
      overrides: _asObjectList(json['overrides'],
      )
          .map(CashierAccessOverride.fromJson)
          .toList(growable: false),
    );
  }

  final int adminId;
  final String userName;
  final String realName;
  final String accountStatus;
  final int permissionVersion;
  final List<CashierAccessRoleRef> roles;

  /// RBAC 角色汇聚的权限码集合。
  final List<String> permissions;

  /// 个性化 ALLOW/DENY 覆盖（显式覆盖，DENY 优先于角色权限）。
  final List<CashierAccessOverride> overrides;
}
