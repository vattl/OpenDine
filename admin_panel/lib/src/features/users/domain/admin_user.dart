class AdminUser {
  const AdminUser({
    required this.id,
    required this.openid,
    required this.name,
    required this.avatar,
    required this.phone,
    required this.points,
    required this.balance,
    required this.principalBalance,
    required this.giftBalance,
    required this.time,
    required this.userType,
    required this.level,
    required this.birthday,
    required this.consumeAmount,
    required this.inviteRegisteredCount,
    required this.availableCouponCount,
  });

  final int id;
  final String openid;
  final String name;
  final String avatar;
  final String phone;
  final int points;
  final double balance;
  final double principalBalance;
  final double giftBalance;
  final String time;
  final int userType;
  final int? level;
  final String birthday;
  final double consumeAmount;
  final int inviteRegisteredCount;
  final int availableCouponCount;

  bool get isMember => userType == 1;

  factory AdminUser.fromJson(Map<String, Object?> json) {
    return AdminUser(
      id: _int(json['id']),
      openid: _string(json['openid']),
      name: _string(json['name']),
      avatar: _string(json['avatar']),
      phone: _string(json['phone']),
      points: _int(json['points']),
      balance: _double(json['balance']),
      principalBalance: _double(json['principal_balance']),
      giftBalance: _double(json['gift_balance']),
      time: _string(json['time']),
      userType: _int(json['user_type']),
      level: json['level'] == null ? null : _int(json['level']),
      birthday: _string(json['birthday']),
      consumeAmount: _double(json['consume_amount']),
      inviteRegisteredCount: _int(json['invite_registered_count']),
      availableCouponCount: _int(json['available_coupon_count']),
    );
  }

  static String _string(Object? value) => value == null ? '' : '$value';

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
