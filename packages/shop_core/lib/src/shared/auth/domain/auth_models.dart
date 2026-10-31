import '../../../core/shop_summary.dart';

/// 登录返回的角色信息（一个账号可关联多个角色）。
class UserRole {
  const UserRole({required this.roleCode, required this.roleName});

  final String roleCode;
  final String roleName;

  /// 归一化编码（小写），用于角色匹配。
  String get normalizedCode => roleCode.toLowerCase();

  factory UserRole.fromMap(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : <String, Object?>{};
    return UserRole(
      roleCode: _string(
        map['roleCode'] ?? map['role_code'] ?? map['roleCode'] ?? '',
      ),
      roleName: _string(map['roleName'] ?? map['role_name'] ?? ''),
    );
  }

  Map<String, String> toJson() => {
        'roleCode': roleCode,
        'roleName': roleName,
      };
}

class LoginSession {
  const LoginSession({
    required this.token,
    required this.scope,
    required this.permissions,
    required this.shops,
    this.roles = const [],
    this.userName = '',
    this.workNo = '',
    this.realName = '',
    this.displayName = '',
  });

  final String token;
  final String scope;
  final Set<String> permissions;
  final List<ShopSummary> shops;
  final List<UserRole> roles;

  /// 当前登录管理账号用户名（后端 /adminLogin 返回 userName）。
  final String userName;

  /// 员工工号（优先使用工号匹配登录，workNo 返回）。
  final String workNo;

  /// 员工真实姓名（realName 返回，可能为空）。
  final String realName;

  /// 界面展示名称（displayName/name：优先姓名，次之用户名）。
  final String displayName;

  factory LoginSession.fromLoginData(Object? data) {
    final map = data is Map
        ? data.cast<String, Object?>()
        : <String, Object?>{};
    final userName = _string(map['userName'] ?? map['user_name']);
    return LoginSession(
      token: _string(
        map['token'] ??
            map['accessToken'] ??
            map['jwt'] ??
            map['Authorization'] ??
            map['authorization'],
      ).replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), ''),
      scope: _string(map['scope']).isEmpty ? 'SHOP' : _string(map['scope']),
      permissions: _stringSet(map['permissions'] ?? map['permissionCodes']),
      shops: _shops(map['shops']),
      roles: _roles(map['roles']),
      userName: userName,
      workNo: _string(map['workNo'] ?? map['work_no']),
      realName: _string(map['realName'] ?? map['real_name']),
      displayName: _string(
        map['displayName'] ?? map['name'] ?? map['realName'] ?? map['real_name'] ?? userName,
      ),
    );
  }

  LoginSession merge({Object? permissionData, Object? shopData}) {
    final permissionMap = permissionData is Map
        ? permissionData.cast<String, Object?>()
        : <String, Object?>{};
    final shopMap = shopData is Map
        ? shopData.cast<String, Object?>()
        : <String, Object?>{};
    final nextPermissions = _stringSet(
      permissionMap['permissions'] ?? permissionMap['permissionCodes'],
    );
    final nextShops = _shops(shopMap['shops'] ?? shopMap['list'] ?? shopData);
    return LoginSession(
      token: token,
      scope: _string(permissionMap['scope']).isEmpty
          ? scope
          : _string(permissionMap['scope']),
      permissions: permissionData == null ? permissions : nextPermissions,
      shops: shopData == null ? shops : nextShops,
      roles: roles,
      userName: userName,
      workNo: _string(permissionMap['workNo'] ?? permissionMap['work_no'] ?? workNo),
      realName: _string(
        permissionMap['realName'] ?? permissionMap['real_name'] ?? realName,
      ),
      displayName: _string(
        permissionMap['displayName'] ??
            permissionMap['name'] ??
            permissionMap['realName'] ??
            permissionMap['real_name'] ??
            displayName,
      ),
    );
  }
}

String _string(Object? value) => value == null ? '' : '$value';

Set<String> _stringSet(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toSet();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }
  return {};
}

List<ShopSummary> _shops(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((item) {
        final map = item.cast<String, Object?>();
        return ShopSummary(
          id: _int(map['id'] ?? map['shop_id'] ?? map['shopId']),
          code: _string(map['code'] ?? map['shop_code'] ?? map['shopCode']),
          name: _string(map['name'] ?? map['shop_name'] ?? map['shopName']),
        );
      })
      .where((shop) => shop.id > 0)
      .toList(growable: false);
}

List<UserRole> _roles(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .map(UserRole.fromMap)
      .where((r) => r.roleCode.isNotEmpty)
      .toList(growable: false);
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
