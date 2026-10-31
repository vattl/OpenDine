class CashierMember {
  const CashierMember({
    required this.id,
    required this.name,
    required this.phone,
    this.openid,
    this.userType,
    this.birthday,
    this.level,
    this.points = 0,
    this.balance = 0,
  });

  factory CashierMember.fromJson(Map<String, Object?> json) => CashierMember(
    id: _int(json['id']),
    name: _string(json['name']).isEmpty ? '未命名会员' : _string(json['name']),
    phone: _string(json['phone']),
    openid: _nullableString(json['openid']),
    userType: json['user_type'] == null ? null : _int(json['user_type']),
    birthday: _nullableString(json['birthday']),
    level: json['level'] == null ? null : _int(json['level']),
    points: _int(json['points']),
    balance: _double(json['balance']),
  );

  final int id;
  final String name;
  final String phone;
  final String? openid;
  final int? userType;
  final String? birthday;
  final int? level;
  final int points;
  final double balance;

  bool get hasOpenid => openid?.trim().isNotEmpty == true;
}

class CashierMemberProfile {
  const CashierMemberProfile({
    required this.member,
    required this.orderCount,
    required this.totalAmount,
    required this.avgOrderValue,
    required this.tags,
    this.consumeAmount,
    this.lastConsumeTime,
    this.inviteRegisteredCount,
    this.availableCouponCount,
  });

  factory CashierMemberProfile.fromJson(Map<String, Object?> json) {
    final rawProfile = json['profile'];
    final profile = rawProfile is Map
        ? rawProfile.cast<String, Object?>()
        : json;
    final rawUser = profile['user'];
    if (rawUser is! Map) {
      throw const FormatException('会员画像缺少 profile.user');
    }
    return CashierMemberProfile(
      member: CashierMember.fromJson(rawUser.cast<String, Object?>()),
      orderCount: _int(profile['orderCount']),
      totalAmount: _double(profile['totalAmount']),
      avgOrderValue: _double(profile['avgOrderValue']),
      tags: _profileTags(profile),
      // D023 统计口径（后端画像接口后期补齐，null 时前端展示占位）：
      // consume_amount/last_consume_time/invite_registered_count/available_coupon_count
      consumeAmount: _firstNullableDouble(profile, const [
        'consume_amount',
        'consumeAmount',
      ]),
      lastConsumeTime: _firstNullableString(profile, const [
        'last_consume_time',
        'lastConsumeTime',
      ]),
      inviteRegisteredCount: _firstNullableInt(profile, const [
        'invite_registered_count',
        'inviteRegisteredCount',
      ]),
      availableCouponCount: _firstNullableInt(profile, const [
        'available_coupon_count',
        'availableCouponCount',
      ]),
    );
  }

  final CashierMember member;
  final int orderCount;
  final double totalAmount;
  final double avgOrderValue;
  final List<String> tags;

  /// 累计消费（实付净额，D023 口径，null=无记录或接口未返回）。
  final double? consumeAmount;

  /// 最近一次成功支付时间（null=无记录或接口未返回）。
  final String? lastConsumeTime;

  /// 邀请注册人数（null=接口未返回）。
  final int? inviteRegisteredCount;

  /// 可用优惠券张数（null=接口未返回）。
  final int? availableCouponCount;
}

class MemberConsumptionRecord {
  const MemberConsumptionRecord({
    required this.id,
    required this.orderNo,
    required this.amount,
    required this.paidAt,
    required this.tableNumber,
    required this.paymentMethod,
    this.orderType = '',
  });

  factory MemberConsumptionRecord.fromJson(Map<String, Object?> json) {
    final explicitNet = _firstNullableDouble(json, const [
      'net_amount',
      'netAmount',
      'paid_amount',
      'paidAmount',
      'actual_amount',
      'actualAmount',
      'amount',
    ]);
    final gross = _firstDouble(json, const ['sett_amount', 'settAmount']);
    final calculatedNet =
        gross -
        _firstDouble(json, const ['discount_amount', 'discountAmount']) +
        _firstDouble(json, const ['service_fee', 'serviceFee']) -
        _firstDouble(json, const ['refund_amount', 'refundAmount']) -
        _firstDouble(json, const ['pay_amount_gift', 'payAmountGift']);
    return MemberConsumptionRecord(
      id: _int(json['id']),
      orderNo: _firstString(json, const ['order_no', 'orderNo']),
      amount: explicitNet ?? _money(calculatedNet < 0 ? 0 : calculatedNet),
      paidAt: _firstString(json, const [
        'pay_time',
        'payTime',
        'order_time',
        'orderTime',
        'created_at',
      ]),
      tableNumber: _firstString(json, const ['table_number', 'tableNumber']),
      paymentMethod: _firstString(json, const [
        'payment_method',
        'paymentMethod',
      ]),
      orderType: _firstString(json, const [
        'dineInOrTakeOut',
        'dine_in_or_take_out',
        'order_type',
        'orderType',
      ]),
    );
  }

  final int id;
  final String orderNo;
  final double amount;
  final String paidAt;
  final String tableNumber;
  final String paymentMethod;
  final String orderType;
}

class MemberConsumptionDetail {
  const MemberConsumptionDetail({required this.record, required this.lines});

  final MemberConsumptionRecord record;
  final List<MemberConsumptionLine> lines;
}

class MemberConsumptionLine {
  const MemberConsumptionLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.totalPrice,
    this.unit = '',
    this.specification = '',
    this.unitPrice = 0,
  });

  factory MemberConsumptionLine.fromJson(Map<String, Object?> json) {
    final quantity = _int(json['quantity'] ?? json['number'] ?? json['count']);
    final explicitUnitPrice = _firstNullableDouble(json, const [
      'unitprice',
      'unit_price',
      'unitPrice',
      'price',
    ]);
    final explicitTotal = _firstNullableDouble(json, const [
      'total_price',
      'totalPrice',
      'subtotal',
    ]);
    final unitPrice =
        explicitUnitPrice ??
        (quantity > 0 && explicitTotal != null ? explicitTotal / quantity : 0);
    final totalPrice = explicitTotal ?? unitPrice * quantity;
    return MemberConsumptionLine(
      id: _int(json['id'] ?? json['detail_id'] ?? json['detailId']),
      name: _firstString(json, const ['name', 'dish_name', 'dishName']),
      quantity: quantity,
      unit: _string(json['unit']),
      specification: _firstString(json, const [
        'selectedSpicy',
        'selected_spicy',
        'specification',
        'spec',
      ]),
      unitPrice: _money(unitPrice),
      totalPrice: _money(totalPrice),
    );
  }

  final int id;
  final String name;
  final int quantity;
  final String unit;
  final String specification;
  final double unitPrice;
  final double totalPrice;
}

class MemberRechargeRecord {
  const MemberRechargeRecord({
    required this.id,
    required this.orderNo,
    required this.principalAmount,
    required this.giftAmount,
    required this.totalAmount,
    required this.channel,
    required this.status,
    required this.createdAt,
  });

  factory MemberRechargeRecord.fromJson(Map<String, Object?> json) {
    final principal = _firstDouble(json, const [
      'recharge_amount',
      'rechargeAmount',
      'amount',
    ]);
    final gift = _firstDouble(json, const ['gift_amount', 'giftAmount']);
    return MemberRechargeRecord(
      id: _int(json['id']),
      orderNo: _firstString(json, const ['order_no', 'orderNo']),
      principalAmount: principal,
      giftAmount: gift,
      totalAmount: _firstDouble(json, const [
        'total_amount',
        'totalAmount',
      ], fallback: principal + gift),
      channel: _string(json['channel']),
      status: _string(json['status']),
      createdAt: _firstString(json, const [
        'created_at',
        'createdAt',
        'pay_time',
      ]),
    );
  }

  final int id;
  final String orderNo;
  final double principalAmount;
  final double giftAmount;
  final double totalAmount;
  final String channel;
  final String status;
  final String createdAt;
}

class MemberRechargeResult {
  const MemberRechargeResult({this.newBalance});

  factory MemberRechargeResult.fromJson(Object? value) {
    if (value is! Map) return const MemberRechargeResult();
    final json = value.cast<String, Object?>();
    final nested = json['user'];
    final nestedBalance = nested is Map ? nested['balance'] : null;
    final raw =
        json['newBalance'] ??
        json['new_balance'] ??
        json['balance'] ??
        nestedBalance;
    return MemberRechargeResult(newBalance: raw == null ? null : _double(raw));
  }

  final double? newBalance;
}

List<String> _profileTags(Map<String, Object?> profile) {
  final tags = <String>[];
  void collect(Object? value) {
    if (value is Map) {
      for (final nested in value.values) collect(nested);
    } else if (value is Iterable) {
      for (final nested in value) collect(nested);
    } else {
      final text = _string(value).trim();
      if (text.isNotEmpty && text != 'null' && !tags.contains(text))
        tags.add(text);
    }
  }

  for (final key in const [
    'tags',
    'basicTags',
    'behaviorTags',
    'dishTags',
    'valueTier',
    'suggestedPersona',
  ]) {
    collect(profile[key]);
  }
  return List.unmodifiable(tags);
}

String _firstString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _string(json[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

double _firstDouble(
  Map<String, Object?> json,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    if (json[key] != null) return _double(json[key]);
  }
  return fallback;
}

double? _firstNullableDouble(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    if (json[key] != null) return _double(json[key]);
  }
  return null;
}

String? _firstNullableString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _nullableString(json[key]);
    if (value != null) return value;
  }
  return null;
}

int? _firstNullableInt(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    if (json[key] != null) return _int(json[key]);
  }
  return null;
}

double _money(double value) => (value * 100).round() / 100;

String _string(Object? value) => value == null ? '' : '$value';
String? _nullableString(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

/// 会员列表行（来源：POST /admin/order/getUserInfo 每行 t_user + 统计字段）。
class CashierMemberRow {
  const CashierMemberRow({
    required this.id,
    required this.name,
    required this.phone,
    this.level,
    this.userType,
    this.points = 0,
    this.balance = 0,
    this.consumeAmount = 0,
    this.lastConsumeTime,
  });

  factory CashierMemberRow.fromJson(Map<String, Object?> json) =>
      CashierMemberRow(
        id: _int(json['id']),
        name: _string(json['name']).isEmpty
            ? '未命名会员'
            : _string(json['name']),
        phone: _string(json['phone']),
        level: json['level'] == null ? null : _int(json['level']),
        userType: json['user_type'] == null ? null : _int(json['user_type']),
        points: _int(json['points']),
        balance: _double(json['balance']),
        consumeAmount: _double(json['consume_amount'] ?? json['consumeAmount']),
        lastConsumeTime: _nullableString(
          json['last_consume_time'] ?? json['lastConsumeTime'],
        ),
      );

  final int id;
  final String name;
  final String phone;
  final int? level;
  final int? userType;
  final int points;
  final double balance;
  final double consumeAmount;
  final String? lastConsumeTime;
}

/// 会员列表分页结果。
class PagedCashierMembers {
  const PagedCashierMembers({required this.rows, required this.total});

  final List<CashierMemberRow> rows;
  final int total;
}

/// 会员看板统计（来源：GET /admin/member/stats，v1.3 当月口径）。
///
/// 「当月」= 本月 1 号 0 点至今（所有营业日累计；未营业日无数据）。
/// 会员看板统计（GET /admin/member/stats，v1.2.231 全量口径）。
class CashierMemberStats {
  const CashierMemberStats({
    this.memberCount = 0,
    this.todayNewCount = 0,
    this.totalBalance = 0,
    this.totalPoints = 0,
  });

  factory CashierMemberStats.fromJson(Map<String, Object?> json) =>
      CashierMemberStats(
        memberCount: _int(json['memberCount'] ?? json['member_count']),
        todayNewCount: _int(json['todayNewCount'] ?? json['today_new_count']),
        totalBalance:
            _double(json['totalBalance'] ?? json['total_balance']),
        totalPoints: _int(json['totalPoints'] ?? json['total_points']),
      );

  /// 会员总数（全部注册用户数，与会员列表 total 同口径）。
  final int memberCount;

  /// 今日新增（今日 00:00 起注册数）。
  final int todayNewCount;

  /// 储值总额（t_user.balance 合计，含本金+赠送金）。
  final double totalBalance;

  /// 积分发放（t_user.points 合计）。
  final int totalPoints;
}

/// 运营端充值记录行（来源：GET /admin/member/recharge/list，单查/全查共用）。
class RechargeLogRow {
  const RechargeLogRow({
    required this.id,
    required this.rechargeAmount,
    required this.giftAmount,
    required this.totalAmount,
    required this.channel,
    required this.payTime,
    this.orderNo = '',
    this.name = '',
    this.phone = '',
    this.remark = '',
  });

  factory RechargeLogRow.fromJson(Map<String, Object?> json) => RechargeLogRow(
    id: _int(json['id']),
    orderNo: _firstString(json, const ['order_no', 'orderNo']),
    name: _string(json['name']),
    phone: _string(json['phone']),
    rechargeAmount: _firstDouble(json, const [
      'recharge_amount',
      'rechargeAmount',
      'amount',
    ]),
    giftAmount: _firstDouble(json, const ['gift_amount', 'giftAmount']),
    totalAmount: _firstDouble(
      json,
      const ['total_amount', 'totalAmount'],
      fallback: (_firstDouble(json, const ['recharge_amount', 'rechargeAmount'])) +
          _firstDouble(json, const ['gift_amount', 'giftAmount']),
    ),
    channel: _string(json['channel']),
    payTime: _firstString(json, const ['pay_time', 'payTime', 'created_at', 'createdAt']),
    remark: _string(json['remark']),
  );

  final int id;
  final String orderNo;
  final String name;
  final String phone;
  final double rechargeAmount;
  final double giftAmount;
  final double totalAmount;
  final String channel;
  final String payTime;
  final String remark;
}

/// 充值记录分页结果。
class PagedRechargeLogs {
  const PagedRechargeLogs({required this.rows, required this.total});

  final List<RechargeLogRow> rows;
  final int total;
}

/// 优惠券模板（来源：GET /admin/coupon/list，供一键发券选择）。
class CashierCoupon {
  const CashierCoupon({
    required this.id,
    required this.name,
    required this.type,
    this.discountValue = 0,
    this.minAmount = 0,
    this.startTime,
    this.endTime,
    this.status = 0,
  });

  factory CashierCoupon.fromJson(Map<String, Object?> json) => CashierCoupon(
    id: _int(json['id']),
    name: _string(json['coupon_name']),
    type: _string(json['coupon_type']),
    discountValue: _double(json['discount_value']),
    minAmount: _double(json['min_amount']),
    startTime: _nullableString(json['start_time']),
    endTime: _nullableString(json['end_time']),
    status: _int(json['status']),
  );

  final int id;
  final String name;
  final String type;
  final double discountValue;
  final double minAmount;
  final String? startTime;
  final String? endTime;
  final int status;

  /// 0-未启用 1-可用 2-已下架（t_coupon.status）。
  bool get isUsable => status == 1;

  String get summary {
    switch (type) {
      case 'full_reduction':
        if (minAmount > 0) return '满${_fmtMoney(minAmount)}减${_fmtMoney(discountValue)}';
        return '减${_fmtMoney(discountValue)}';
      case 'discount':
        if (discountValue <= 0) return name;
        return discountValue < 1
            ? '${_fmtMoney(discountValue * 10)}折'
            : '${_fmtMoney(discountValue)}折';
      case 'direct_reduction':
        return '立减${_fmtMoney(discountValue)}';
      default:
        return name;
    }
  }
}

/// 会员等级展示口径：0=普通会员、1=白银会员、2=黄金会员、3=铂金会员；未知为「—」。
/// 后端仅存整数等级无文案配置，该映射为前端展示约定（与设计稿一致）。
String memberLevelLabel(int? level) {
  switch (level) {
    case 0:
      return '普通会员';
    case 1:
      return '白银会员';
    case 2:
      return '黄金会员';
    case 3:
      return '铂金会员';
    default:
      return '—';
  }
}

/// 手机号脱敏：保留前 3 后 4，中间 ****；非 11 位数字原样返回。
String maskedPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 11) return phone;
  return '${digits.substring(0, 3)}****${digits.substring(7)}';
}

String _fmtMoney(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

class CashierPersonaTag {
  const CashierPersonaTag({
    required this.label,
    required this.type,
  });

  final String label;
  final String type;

  factory CashierPersonaTag.fromJson(Map<String, Object?> json) {
    return CashierPersonaTag(
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? 'behavior',
    );
  }
}
