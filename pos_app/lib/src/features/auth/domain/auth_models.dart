import '../../../core/shop_summary.dart';

class LoginSession {
  const LoginSession({
    required this.token,
    required this.scope,
    required this.permissions,
    required this.shops,
    this.adminId = 0,
    this.workNo = '',
    this.realName = '',
    this.jobTitle = '',
    this.displayName = '',
    this.userName = '',
    this.actorName = '',
    this.isSuperAdmin = false,
  });

  final String token;
  final String scope;
  final Set<String> permissions;
  final List<ShopSummary> shops;
  final int adminId;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String displayName;
  final String userName;
  final String actorName;
  final bool isSuperAdmin;

  /// 格式化操作人标识: "张晓明 [店长]" 或 "张晓明"
  String get badgeText =>
      jobTitle.isNotEmpty ? '$displayName [$jobTitle]' : displayName;

  /// 完整身份凭据: "张晓明 (EMP1001) · 店长"
  String get fullIdentityText =>
      '$displayName${workNo.isNotEmpty ? ' ($workNo)' : ''} · ${jobTitle.isNotEmpty ? jobTitle : "员工"}';

  factory LoginSession.fromLoginData(Object? data) {
    final map = data is Map
        ? data.cast<String, Object?>()
        : <String, Object?>{};

    final rawRealName = _string(map['realName'] ?? map['real_name']).trim();
    final rawUserName = _string(map['userName'] ?? map['username']).trim();
    final rawWorkNo = _string(map['workNo'] ?? map['work_no']).trim();
    final rawJobTitle = _string(map['jobTitle'] ?? map['job_title']).trim();
    final rawDisplayName = _string(
      map['displayName'] ?? map['display_name'] ?? map['name'],
    ).trim();
    final rawActor = _string(
      map['userName'] ?? map['adminName'] ?? map['name'] ?? map['username'],
    ).trim();

    final effectiveDisplayName = rawDisplayName.isNotEmpty
        ? rawDisplayName
        : (rawRealName.isNotEmpty
              ? rawRealName
              : (rawUserName.isNotEmpty
                    ? rawUserName
                    : (rawWorkNo.isNotEmpty ? rawWorkNo : '操作员')));

    return LoginSession(
      token: _string(
        map['token'] ??
            map['accessToken'] ??
            map['jwt'] ??
            map['Authorization'] ??
            map['authorization'],
      ).replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), ''),
      adminId: _int(map['adminId'] ?? map['admin_id'] ?? map['id']),
      workNo: rawWorkNo,
      realName: rawRealName,
      jobTitle: rawJobTitle,
      displayName: effectiveDisplayName,
      userName: rawUserName.isNotEmpty
          ? rawUserName
          : (rawActor.isNotEmpty ? rawActor : rawWorkNo),
      scope: _string(map['scope']).isEmpty ? 'SHOP' : _string(map['scope']),
      permissions: _stringSet(map['permissions'] ?? map['permissionCodes']),
      shops: _shops(map['shops']),
      actorName: effectiveDisplayName.isNotEmpty
          ? effectiveDisplayName
          : rawActor,
      isSuperAdmin: _bool(map['isSuperAdmin'] ?? map['is_super_admin']),
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

    final pWorkNo = _string(
      permissionMap['workNo'] ?? permissionMap['work_no'],
    ).trim();
    final pRealName = _string(
      permissionMap['realName'] ?? permissionMap['real_name'],
    ).trim();
    final pJobTitle = _string(
      permissionMap['jobTitle'] ?? permissionMap['job_title'],
    ).trim();
    final pUserName = _string(
      permissionMap['userName'] ?? permissionMap['username'],
    ).trim();
    final pDisplayName = _string(
      permissionMap['displayName'] ??
          permissionMap['display_name'] ??
          permissionMap['name'],
    ).trim();

    final effectiveWorkNo = pWorkNo.isNotEmpty ? pWorkNo : workNo;
    final effectiveRealName = pRealName.isNotEmpty ? pRealName : realName;
    final effectiveJobTitle = pJobTitle.isNotEmpty ? pJobTitle : jobTitle;
    final effectiveUserName = pUserName.isNotEmpty ? pUserName : userName;
    final effectiveDisplayName = pDisplayName.isNotEmpty
        ? pDisplayName
        : (displayName.isNotEmpty
              ? displayName
              : (effectiveRealName.isNotEmpty
                    ? effectiveRealName
                    : effectiveUserName));

    final nextAdminId =
        permissionMap.containsKey('adminId') ||
            permissionMap.containsKey('admin_id')
        ? _int(permissionMap['adminId'] ?? permissionMap['admin_id'])
        : adminId;

    return LoginSession(
      token: token,
      adminId: nextAdminId,
      workNo: effectiveWorkNo,
      realName: effectiveRealName,
      jobTitle: effectiveJobTitle,
      displayName: effectiveDisplayName,
      userName: effectiveUserName,
      scope: _string(permissionMap['scope']).isEmpty
          ? scope
          : _string(permissionMap['scope']),
      permissions: permissionData == null ? permissions : nextPermissions,
      shops: shopData == null ? shops : nextShops,
      actorName: effectiveDisplayName.isNotEmpty
          ? effectiveDisplayName
          : actorName,
      isSuperAdmin:
          permissionMap.containsKey('isSuperAdmin') ||
              permissionMap.containsKey('is_super_admin')
          ? _bool(
              permissionMap['isSuperAdmin'] ?? permissionMap['is_super_admin'],
            )
          : isSuperAdmin,
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
  final unique = <int, ShopSummary>{};
  for (final item in value.whereType<Map>()) {
    final map = item.cast<String, Object?>();
    final id = _int(map['id'] ?? map['shop_id'] ?? map['shopId']);
    if (id > 0 && !unique.containsKey(id)) {
      unique[id] = ShopSummary(
        id: id,
        code: _string(map['code'] ?? map['shop_code'] ?? map['shopCode']),
        name: _string(map['name'] ?? map['shop_name'] ?? map['shopName']),
      );
    }
  }
  return unique.values.toList(growable: false);
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch ('$value'.trim().toLowerCase()) {
    'true' || '1' || 'yes' => true,
    _ => false,
  };
}
