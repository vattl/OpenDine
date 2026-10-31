class CashierMember {
  const CashierMember({
    required this.id,
    required this.name,
    required this.phone,
    this.openid,
    this.userType,
    this.birthday,
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
    points: _int(json['points']),
    balance: _double(json['balance']),
  );

  final int id;
  final String name;
  final String phone;
  final String? openid;
  final int? userType;
  final String? birthday;
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
    );
  }

  final CashierMember member;
  final int orderCount;
  final double totalAmount;
  final double avgOrderValue;
  final List<String> tags;
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
