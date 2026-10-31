/// 优惠券域模型（M-J 优惠券管理）：券模板、兑换码、用户券、Excel 批量发券结果。
/// 字段按 openapi v1.2.278 Coupon / UserCouponDTO schema 定义，snake_case 容错。

/// 优惠券模板（t_coupon）。status: 0-未启用 1-可用 2-已下架；stock -1 为无限库存。
class CouponTemplate {
  const CouponTemplate({
    required this.id,
    required this.name,
    this.couponType = '',
    this.status = 0,
    this.discountValue = 0,
    this.minAmount = 0,
    this.startTime,
    this.endTime,
    this.stock = 0,
    this.grantedCount = 0,
    this.description,
    this.validityTime,
    this.applyDishIds,
    this.applyDiningType = 'all',
  });

  final int id;
  final String name;
  final String couponType;
  final int status;
  final double discountValue;
  final double minAmount;
  final String? startTime;
  final String? endTime;
  final int stock;
  final int grantedCount;
  final String? description;
  final int? validityTime;

  /// 适用菜品 ID 数组的 JSON 字符串（如 "[1,2]"），空/空串表示不限制。
  final String? applyDishIds;
  final String applyDiningType;

  static CouponTemplate fromJson(Map<String, Object?> json) =>
      CouponTemplate(
        id: _int(json['id']) ?? 0,
        name: _str(_first(json, const ['coupon_name', 'name'])) ?? '',
        couponType:
            _str(_first(json, const ['coupon_type', 'couponType'])) ?? '',
        status: _int(json['status']) ?? 0,
        discountValue:
            _num(_first(json, const ['discount_value', 'discountValue'])) ?? 0,
        minAmount: _num(_first(json, const ['min_amount', 'minAmount'])) ?? 0,
        startTime: _str(_first(json, const ['start_time', 'startTime'])),
        endTime: _str(_first(json, const ['end_time', 'endTime'])),
        stock: _int(json['stock']) ?? 0,
        grantedCount:
            _int(_first(json, const ['granted_count', 'grantedCount'])) ?? 0,
        description: _str(_first(json, const ['description'])),
        validityTime:
            _int(_first(json, const ['validity_time', 'validityTime'])),
        applyDishIds:
            _str(_first(json, const ['apply_dish_ids', 'applyDishIds'])),
    applyDiningType:
        _str(_first(json, const ['apply_dining_type', 'applyDiningType'])) ??
        'all',
  );

  /// 新增/编辑提交体（openapi Coupon schema 字段，snake_case）。
  /// [applyDishIds]/[applyShopIds] 为适用菜品/门店 ID 数组的 JSON 字符串，
  /// 为空表示不限（add 时服务端默认写入仅当前门店）。
  Map<String, Object?> toSaveJson({
    String? applyDiningType,
    String? applyDishIds,
    String? applyShopIds,
  }) => {
    if (id != 0) 'id': id,
    'coupon_name': name,
    'coupon_type': couponType,
    'apply_dining_type': applyDiningType ?? this.applyDiningType,
    if ((applyDishIds ?? this.applyDishIds) != null)
      'apply_dish_ids': (applyDishIds ?? this.applyDishIds)!.trim(),
    if (applyShopIds != null && applyShopIds.trim().isNotEmpty)
      'apply_shop_ids': applyShopIds.trim(),
    'discount_value': discountValue,
    'min_amount': minAmount,
    if (startTime != null && startTime!.isNotEmpty) 'start_time': startTime,
    if (endTime != null && endTime!.isNotEmpty) 'end_time': endTime,
    'status': status,
    'stock': stock,
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (validityTime != null) 'validity_time': validityTime,
  };
}

/// 兑换码核销记录。status: 0-未核销 1-已核销。
class CouponRedeemCode {
  const CouponRedeemCode({
    required this.id,
    this.couponId,
    this.redeemCode = '',
    this.status = 0,
    this.usedOpenid,
    this.usedTime,
    this.createTime,
  });

  final int id;
  final int? couponId;
  final String redeemCode;
  final int status;
  final String? usedOpenid;
  final String? usedTime;
  final String? createTime;

  static CouponRedeemCode fromJson(Map<String, Object?> json) =>
      CouponRedeemCode(
        id: _int(json['id']) ?? 0,
        couponId: _int(_first(json, const ['coupon_id', 'couponId'])),
        redeemCode:
            _str(_first(json, const ['redeem_code', 'redeemCode'])) ?? '',
        status: _int(_first(json, const ['status'])) ?? 0,
        usedOpenid: _str(_first(json, const ['used_openid', 'usedOpenid'])),
        usedTime: _str(_first(json, const ['used_time', 'usedTime'])),
        createTime: _str(_first(json, const ['create_time', 'createTime'])),
      );
}

/// 用户持券明细（t_user_coupon 关联 t_coupon）。status: 0-未使用 1-已使用 2-已失效。
class UserCoupon {
  const UserCoupon({
    required this.id,
    this.openid,
    this.couponId,
    this.couponName,
    this.status = 0,
    this.orderNo,
    this.getTime,
    this.useTime,
    this.expireTime,
    this.discountValue = 0,
    this.minAmount = 0,
  });

  final int id;
  final String? openid;
  final int? couponId;
  final String? couponName;
  final int status;
  final String? orderNo;
  final String? getTime;
  final String? useTime;
  final String? expireTime;
  final double discountValue;
  final double minAmount;

  static UserCoupon fromJson(Map<String, Object?> json) => UserCoupon(
    id: _int(json['id']) ?? 0,
    openid: _str(_first(json, const ['user_openid', 'openid'])),
    couponId: _int(_first(json, const ['coupon_id', 'couponId'])),
    couponName: _str(_first(json, const ['coupon_name', 'couponName'])),
    status: _int(json['status']) ?? 0,
    orderNo: _str(_first(json, const ['order_no', 'orderNo'])),
    getTime: _str(_first(json, const ['get_time', 'getTime'])),
    useTime: _str(_first(json, const ['use_time', 'useTime'])),
    expireTime: _str(_first(json, const ['expire_time', 'expireTime'])),
    discountValue:
        _num(_first(json, const ['discount_value', 'discountValue'])) ?? 0,
    minAmount: _num(_first(json, const ['min_amount', 'minAmount'])) ?? 0,
  );
}

/// Excel 批量发券结果（couponId/fileName/readCount/duplicateCount/targetOpenidCount/grantedCount）。
class CouponGrantExcelResult {
  const CouponGrantExcelResult({
    this.couponId,
    this.fileName,
    this.readCount = 0,
    this.duplicateCount = 0,
    this.targetOpenidCount = 0,
    this.grantedCount = 0,
  });

  final int? couponId;
  final String? fileName;
  final int readCount;
  final int duplicateCount;
  final int targetOpenidCount;
  final int grantedCount;

  static CouponGrantExcelResult fromJson(Map<String, Object?> json) =>
      CouponGrantExcelResult(
        couponId: _int(_first(json, const ['couponId', 'coupon_id'])),
        fileName: _str(_first(json, const ['fileName', 'file_name'])),
        readCount: _int(_first(json, const ['readCount', 'read_count'])) ?? 0,
        duplicateCount:
            _int(_first(json, const ['duplicateCount', 'duplicate_count'])) ??
                0,
        targetOpenidCount: _int(_first(
          json,
          const ['targetOpenidCount', 'target_openid_count']),
            ) ??
            0,
        grantedCount:
            _int(_first(json, const ['grantedCount', 'granted_count'])) ?? 0,
      );
}

Object? _first(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return json[key];
  }
  return null;
}

String? _str(Object? value) => value == null ? null : '$value';

double? _num(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
