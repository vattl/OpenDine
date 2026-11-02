/// 营销域模型（M-G 营销配置）：首单返利/邀请海报/九宫格配置、首单活动、资格评估。
/// 字段按 openapi v1.2.278 定义，解析对 snake_case 与 camelCase 双形态容错。

/// 邀请好友首单余额返利规则。
class MarketingInviteReward {
  const MarketingInviteReward({
    required this.enabled,
    required this.rewardPercent,
  });

  final bool enabled;

  /// 0～100，按实付金额的比例（如 5 表示 5%）。
  final double rewardPercent;

  static MarketingInviteReward fromJson(Map<String, Object?> json) =>
      MarketingInviteReward(
        enabled: _bool(_first(json, const ['enabled'])) ?? false,
        rewardPercent:
            _num(_first(json, const ['rewardPercent', 'reward_percent'])) ?? 0,
      );

  Map<String, Object?> toSaveJson() => {
        'enabled': enabled,
        'rewardPercent': rewardPercent,
      };
}

/// 邀请海报配置（二维码位置叠加在背景图上）。
class MarketingInvitePoster {
  const MarketingInvitePoster({
    required this.backgroundPath,
    this.qrX = 0,
    this.qrY = 0,
    this.qrSize = 0,
  });

  final String backgroundPath;
  final int qrX;
  final int qrY;
  final int qrSize;

  static MarketingInvitePoster fromJson(Map<String, Object?> json) {
    final qrRaw = json['qr'];
    final qr = qrRaw is Map ? qrRaw.cast<String, Object?>() : const {};
    return MarketingInvitePoster(
      backgroundPath:
          _str(_first(json, const ['backgroundPath', 'background_path'])) ?? '',
      qrX: _int(qr['x']) ?? 0,
      qrY: _int(qr['y']) ?? 0,
      qrSize: _int(qr['size']) ?? 0,
    );
  }

  Map<String, Object?> toSaveJson() => {
        'backgroundPath': backgroundPath,
        'qr': {'x': qrX, 'y': qrY, 'size': qrSize},
      };
}

/// 微信统一下单夜间九折规则（openapi /admin/payment/ninefold，九宫格废弃路径的统一入口）。
class MarketingNinefoldConfig {
  const MarketingNinefoldConfig({
    required this.enabled,
    required this.payRate,
    required this.minBaseYuan,
    required this.timeStart,
    required this.timeEnd,
    required this.zoneId,
    required this.eligibleDiningTypes,
    this.hasOwnConfig = false,
    this.inheritsGlobal = false,
  });

  final bool enabled;
  final double payRate;
  final double minBaseYuan;
  final String timeStart;
  final String timeEnd;
  final String zoneId;
  final List<String> eligibleDiningTypes;
  final bool hasOwnConfig;
  final bool inheritsGlobal;

  static MarketingNinefoldConfig fromJson(Map<String, Object?> json) =>
      MarketingNinefoldConfig(
        enabled: _bool(_first(json, const ['enabled'])) ?? false,
        payRate: _num(_first(json, const ['payRate', 'pay_rate'])) ?? 0,
        minBaseYuan:
            _num(_first(json, const ['minBaseYuan', 'min_base_yuan'])) ?? 0,
        timeStart: _str(_first(json, const ['timeStart', 'time_start'])) ?? '',
        timeEnd: _str(_first(json, const ['timeEnd', 'time_end'])) ?? '',
        zoneId: _str(_first(json, const ['zoneId', 'zone_id'])) ?? '',
        eligibleDiningTypes: _strings(_first(
          json,
          const ['eligibleDiningTypes', 'eligible_dining_types'],
        )),
        hasOwnConfig:
            _bool(_first(json, const ['hasOwnConfig', 'has_own_config'])) ??
                false,
        inheritsGlobal:
            _bool(_first(json, const ['inheritsGlobal', 'inherits_global'])) ??
                false,
      );

  Map<String, Object?> toSaveJson() => {
        'enabled': enabled,
        'payRate': payRate,
        'minBaseYuan': minBaseYuan,
        'timeStart': timeStart,
        'timeEnd': timeEnd,
        'zoneId': zoneId,
        'eligibleDiningTypes': eligibleDiningTypes,
      };
}

/// 首单活动（列表行/详情）。campaignType: DISCOUNT/GIFT/FREEBIE；status: DRAFT/ACTIVE/PAUSED/EXPIRED。
class MarketingCampaign {
  const MarketingCampaign({
    required this.id,
    required this.name,
    required this.campaignType,
    required this.status,
    this.thresholdAmount = 0,
    this.discountValue = 0,
    this.discountDesc,
    this.startTime,
    this.endTime,
    this.redemptions = 0,
    this.restorations = 0,
    this.version,
  });

  final int id;
  final String name;
  final String campaignType;
  final String status;
  final double thresholdAmount;
  final double discountValue;
  final String? discountDesc;
  final String? startTime;
  final String? endTime;
  final int redemptions;
  final int restorations;
  final int? version;

  static MarketingCampaign fromJson(Map<String, Object?> json) {
    final statsRaw = json['stats'];
    final stats =
        statsRaw is Map ? statsRaw.cast<String, Object?>() : const {};
    return MarketingCampaign(
      id: _int(json['id']) ?? 0,
      name: _str(json['name']) ?? '',
      campaignType:
          _str(_first(json, const ['campaignType', 'campaign_type'])) ?? '',
      status: _str(json['status']) ?? 'DRAFT',
      thresholdAmount:
          _num(_first(json, const ['thresholdAmount', 'threshold_amount'])) ??
              0,
      discountValue:
          _num(_first(json, const ['discountValue', 'discount_value'])) ?? 0,
      discountDesc:
          _str(_first(json, const ['discountDesc', 'discount_desc'])),
      startTime: _str(_first(json, const ['startTime', 'start_time'])),
      endTime: _str(_first(json, const ['endTime', 'end_time'])),
      redemptions: _int(stats['redemptions']) ?? 0,
      restorations: _int(stats['restorations']) ?? 0,
      version: _int(json['version']),
    );
  }

  /// 创建/更新提交体（openapi first-order campaigns schema；
  /// 更新时 [includeVersion] 为 true 则携带 version 乐观锁字段）。
  Map<String, Object?> toSaveJson({bool includeVersion = false}) => {
    'name': name,
    'campaignType': campaignType,
    'thresholdAmount': thresholdAmount,
    'discountValue': discountValue,
    if (discountDesc != null && discountDesc!.isNotEmpty)
      'discountDesc': discountDesc,
    'startTime': startTime ?? '',
    'endTime': endTime ?? '',
    'status': status,
    if (includeVersion && version != null) 'version': version,
  };
}

/// 首单资格评估结果（eligible/reason/conflicts[]/campaign）。
class MarketingEligibilityResult {
  const MarketingEligibilityResult({
    required this.eligible,
    this.reason,
    this.conflicts = const [],
    this.campaignName,
  });

  final bool eligible;
  final String? reason;
  final List<String> conflicts;
  final String? campaignName;

  static MarketingEligibilityResult fromJson(Map<String, Object?> json) {
    final campaignRaw = json['campaign'];
    final campaign = campaignRaw is Map
        ? campaignRaw.cast<String, Object?>()
        : const <String, Object?>{};
    return MarketingEligibilityResult(
      eligible: _bool(_first(json, const ['eligible'])) ?? false,
      reason: _str(_first(json, const ['reason'])),
      conflicts: _strings(_first(json, const ['conflicts'])),
      campaignName: _str(_first(campaign, const ['name'])),
    );
  }
}

Object? _first(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return json[key];
  }
  return null;
}

String? _str(Object? value) => value == null ? null : '$value';

bool? _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = '$value'.trim().toLowerCase();
  if (const {'true', '1', 'yes', 'enabled'}.contains(text)) return true;
  if (const {'false', '0', 'no', 'disabled'}.contains(text)) return false;
  return null;
}

double? _num(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

List<String> _strings(Object? value) => value is Iterable
    ? value.map((item) => '$item').where((item) => item.isNotEmpty).toList()
    : const [];

/// 轮播图（t_banner；列表/新增/删除，openapi 无更新端点）。
class MarketingBanner {
  const MarketingBanner({
    required this.id,
    this.image,
    this.url,
    this.status = 1,
    this.type = 'home',
  });

  final int id;
  final String? image;
  final String? url;
  final int status;
  final String type;

  static MarketingBanner fromJson(Map<String, Object?> json) =>
      MarketingBanner(
        id: _int(json['id']) ?? 0,
        image: _str(json['image']),
        url: _str(json['url']),
        status: _int(json['status']) ?? 1,
        type: _str(json['type']) ?? 'home',
      );

  Map<String, Object?> toSaveJson() => {
        if (image != null && image!.isNotEmpty) 'image': image,
        if (url != null && url!.isNotEmpty) 'url': url,
        'status': status,
        'type': type,
      };
}

/// 活动弹窗（t_activity_popup；服务端实体字段 snake_case，openapi 未收录管理端端点，
/// 以服务端 ActivityController 真实实现为准）。适用门店 apply_shop_ids 为 JSON 数组字符串，
/// NULL/空/[] 表示全部门店。
class MarketingPopup {
  const MarketingPopup({
    this.id,
    this.name,
    this.popupImage,
    this.imageUrl,
    this.targetUser,
    this.startTime,
    this.endTime,
    this.isEnabled = 1,
    this.maxShowCount,
    this.sorting,
    this.type,
    this.applyShopIds,
  });

  final int? id;
  final String? name;
  final String? popupImage;
  final String? imageUrl;
  final String? targetUser;
  final String? startTime;
  final String? endTime;
  final int isEnabled;
  final int? maxShowCount;
  final int? sorting;
  final String? type;
  final String? applyShopIds;

  static MarketingPopup fromJson(Map<String, Object?> json) =>
      MarketingPopup(
        id: _int(json['id']),
        name: _str(json['name']),
        popupImage: _str(json['popup_image']),
        imageUrl: _str(json['image_url']),
        targetUser: _str(json['target_user']),
        startTime: _str(json['start_time']),
        endTime: _str(json['end_time']),
        isEnabled: _int(json['is_enabled']) ?? 1,
        maxShowCount: _int(json['max_show_count']),
        sorting: _int(json['sorting']),
        type: _str(json['type']),
        applyShopIds: _str(json['apply_shop_ids']),
      );

  Map<String, Object?> toSaveJson() => {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (popupImage != null && popupImage!.isNotEmpty)
          'popup_image': popupImage,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
        if (targetUser != null && targetUser!.isNotEmpty)
          'target_user': targetUser,
        if (startTime != null && startTime!.isNotEmpty)
          'start_time': startTime,
        if (endTime != null && endTime!.isNotEmpty) 'end_time': endTime,
        'is_enabled': isEnabled,
        if (maxShowCount != null) 'max_show_count': maxShowCount,
        if (sorting != null) 'sorting': sorting,
        if (type != null && type!.isNotEmpty) 'type': type,
        if (applyShopIds != null && applyShopIds!.isNotEmpty)
          'apply_shop_ids': applyShopIds,
      };
}
