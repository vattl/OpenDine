import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  const AuthRepository(this.client);

  final AdminApiClient client;

  Future<LoginSession> login({
    required String username,
    required String password,
  }) async {
    // 工号登录：workNo 优先匹配（后端先按 work_no 精确匹配），
    // 同时保留 userName 兼容老部署（后端无 work_no 命中时回退 userName）。
    final loginData = await client.post(
      adminLoginEndpoint,
      body: {'userName': username, 'workNo': username, 'password': password},
    );
    var session = LoginSession.fromLoginData(loginData);
    if (session.token.isEmpty) {
      throw const ApiException('登录响应缺少 token');
    }

    final authed = client.copyWith(token: session.token);
    final permissionData = await authed.get(adminPermissionsEndpoint);
    final shopData = await authed.get(adminMeShopsEndpoint);
    session = session.merge(permissionData: permissionData, shopData: shopData);
    return session;
  }
}
