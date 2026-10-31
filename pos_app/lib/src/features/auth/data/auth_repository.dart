import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/cashier_operation_audit.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  const AuthRepository(this.client);

  final AdminApiClient client;

  Future<LoginSession> restoreSession(
    String token, {
    String actorName = '',
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const ApiException('本地登录状态无效，请重新登录');
    }
    final authed = client.copyWith(token: cleanToken);
    final permissionData = await authed.get(adminPermissionsEndpoint);
    final shopData = await _loadAllAuthorizedShops(authed);
    var session = LoginSession(
      token: cleanToken,
      scope: 'SHOP',
      permissions: const {},
      shops: const [],
      actorName: actorName,
    ).merge(permissionData: permissionData, shopData: shopData);
    if (permissionData is Map) {
      final map = permissionData.cast<String, Object?>();
      if (map['data'] is Map) {
        session = session.merge(permissionData: map['data']);
      }
    }
    return session;
  }

  Future<LoginSession> login({
    required String username,
    required String password,
  }) async {
    final cleanAccount = username.trim();
    try {
      final loginData = await client.post(
        adminLoginEndpoint,
        body: {
          'workNo': cleanAccount,
          'userName': cleanAccount,
          'password': password,
        },
      );
      var session = LoginSession.fromLoginData(loginData);
      if (session.token.isEmpty) {
        throw const ApiException('登录响应缺少 token');
      }
      if (session.actorName.isEmpty) {
        session = LoginSession(
          token: session.token,
          scope: session.scope,
          permissions: session.permissions,
          shops: session.shops,
          adminId: session.adminId,
          workNo: session.workNo,
          realName: session.realName,
          jobTitle: session.jobTitle,
          displayName: session.displayName.isNotEmpty ? session.displayName : cleanAccount,
          userName: session.userName.isNotEmpty ? session.userName : cleanAccount,
          actorName: cleanAccount,
        );
      }

      final authed = client.copyWith(token: session.token);
      final permissionData = await authed.get(adminPermissionsEndpoint);
      final shopData = await _loadAllAuthorizedShops(authed);
      session = session.merge(
        permissionData: permissionData,
        shopData: shopData,
      );
      if (permissionData is Map) {
        final map = permissionData.cast<String, Object?>();
        if (map['data'] is Map) {
          session = session.merge(permissionData: map['data']);
        }
      }

      final actorLabel = session.displayName.isNotEmpty
          ? session.displayName
          : (session.realName.isNotEmpty ? session.realName : cleanAccount);

      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'auth',
          action: 'login',
          result: 'success',
          actorId: session.workNo.isNotEmpty ? session.workNo : cleanAccount,
          actorName: actorLabel,
          detail: {
            'username': cleanAccount,
            'workNo': session.workNo,
            'realName': session.realName,
            'jobTitle': session.jobTitle,
          },
        ),
      );
      return session;
    } catch (error) {
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'auth',
          action: 'login',
          result: 'failed',
          actorId: cleanAccount,
          actorName: cleanAccount,
          errorMsg: '$error',
        ),
      );
      rethrow;
    }
  }

  Future<Object?> _loadAllAuthorizedShops(AdminApiClient authed) async {
    const pageSize = 200;
    final first = await authed.get(
      adminMeShopsEndpoint,
      query: const {'page': 1, 'pageSize': pageSize},
    );
    if (first is! Map) return first;

    final firstPage = first.cast<String, Object?>();
    final firstList = firstPage['list'] ?? firstPage['shops'];
    final total = _nonNegativeInt(firstPage['total']);
    if (firstList is! Iterable || total == null || firstList.length >= total) {
      return first;
    }

    final shops = <Object?>[...firstList];
    final pageCount = (total + pageSize - 1) ~/ pageSize;
    for (var page = 2; page <= pageCount && shops.length < total; page++) {
      final next = await authed.get(
        adminMeShopsEndpoint,
        query: {'page': page, 'pageSize': pageSize},
      );
      if (next is! Map) {
        throw const ApiException('授权门店分页响应格式错误');
      }
      final values = next['list'] ?? next['shops'];
      if (values is! Iterable || values.isEmpty) {
        throw const ApiException('授权门店分页数据不完整，请重新登录');
      }
      shops.addAll(values);
    }
    if (shops.length < total) {
      throw const ApiException('授权门店分页数据不完整，请重新登录');
    }
    return {...firstPage, 'list': shops};
  }
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}
