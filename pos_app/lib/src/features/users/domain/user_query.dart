import '../../../core/api_contract.dart';

class UserQuery {
  const UserQuery({
    this.pageNum = 1,
    this.pageSize = 20,
    this.query = '',
    this.phone = '',
    this.userType,
    this.registerStartTime,
    this.registerEndTime,
    this.minAmount,
    this.maxAmount,
    this.amountSort,
    // D023：用户列表展示消费/邀请/券统计列，恒需全量聚合，默认显式传 true。
    this.includeStats = true,
  });

  final int pageNum;
  final int pageSize;
  final String query;
  final String phone;
  final int? userType;
  final String? registerStartTime;
  final String? registerEndTime;
  final double? minAmount;
  final double? maxAmount;
  final String? amountSort;
  final bool includeStats;

  UserQuery copyWith({
    int? pageNum,
    int? pageSize,
    String? query,
    String? phone,
    Object? userType = _sentinel,
    Object? registerStartTime = _sentinel,
    Object? registerEndTime = _sentinel,
    Object? minAmount = _sentinel,
    Object? maxAmount = _sentinel,
    Object? amountSort = _sentinel,
  }) {
    return UserQuery(
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
      query: query ?? this.query,
      phone: phone ?? this.phone,
      userType: identical(userType, _sentinel)
          ? this.userType
          : userType as int?,
      registerStartTime: identical(registerStartTime, _sentinel)
          ? this.registerStartTime
          : registerStartTime as String?,
      registerEndTime: identical(registerEndTime, _sentinel)
          ? this.registerEndTime
          : registerEndTime as String?,
      minAmount: identical(minAmount, _sentinel)
          ? this.minAmount
          : minAmount as double?,
      maxAmount: identical(maxAmount, _sentinel)
          ? this.maxAmount
          : maxAmount as double?,
      amountSort: identical(amountSort, _sentinel)
          ? this.amountSort
          : amountSort as String?,
    );
  }

  Map<String, Object?> toRequestBody() {
    return compactBody({
      'pageNum': pageNum,
      'pageSize': pageSize > 100 ? 100 : pageSize,
      'includeStats': includeStats,
      'query': query.trim(),
      'phone': phone.trim(),
      'userType': userType,
      'registerStartTime': registerStartTime,
      'registerEndTime': registerEndTime,
      'minAmount': minAmount,
      'maxAmount': maxAmount,
      'amountSort': amountSort == 'asc' || amountSort == 'desc'
          ? amountSort
          : null,
    });
  }

  AdminRequest toAdminRequest({required String token, required int shopId}) {
    return AdminRequest(
      endpoint: getUserInfoEndpoint,
      body: toRequestBody(),
      headers: adminHeaders(
        token: token,
        shopId: shopId,
        endpoint: getUserInfoEndpoint,
      ),
    );
  }
}

const Object _sentinel = Object();
