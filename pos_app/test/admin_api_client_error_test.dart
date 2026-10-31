import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HTTP JSON errors expose a user-facing message and business code',
    () async {
      final transport = _ErrorTransport(
        jsonEncode({'code': 40021, 'msg': '新密码不符合安全要求'}),
      );
      final client = AdminApiClient(
        baseUrl: 'https://example.com',
        transport: transport,
        token: 'token',
        shopId: 1,
      );

      await expectLater(
        client.post(
          adminModifyPasswordEndpoint,
          body: const {'userName': 'admin', 'newPassword': 'bad'},
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.message, 'message', '新密码不符合安全要求')
              .having((error) => error.code, 'code', 40021)
              .having((error) => error.statusCode, 'statusCode', 400),
        ),
      );
    },
  );

  test('HTTP 200 with an explicit failure flag throws the API message', () {
    expect(
      () => unwrapResponse(
        jsonEncode({'code': 200, 'success': false, 'msg': '菜品价格校验失败'}),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '菜品价格校验失败',
        ),
      ),
    );
  });

  test('nested explicit failure keeps the backend error message', () {
    expect(
      () => unwrapResponse(
        jsonEncode({
          'code': 200,
          'data': {'success': false, 'message': '库存不足，仅剩 1 份'},
        }),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '库存不足，仅剩 1 份',
        ),
      ),
    );
  });

  test('HTML 502 Bad Gateway response is sanitized into friendly message', () async {
    const rawHtml = '<html>\r\n<head><title>502 Bad Gateway</title></head>\r\n<body>\r\n<center><h1>502 Bad Gateway</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>';
    final transport = _ErrorTransport(rawHtml, statusCode: 502);
    final client = AdminApiClient(
      baseUrl: 'https://example.com',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await expectLater(
      client.post(adminLoginEndpoint, body: const {'username': 'a', 'password': 'b'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.message, 'message', '服务器网关连接异常（502 Bad Gateway），请稍后重试')
            .having((error) => error.statusCode, 'statusCode', 502),
      ),
    );
  });
  test('account lock predicate matches 423 login lock and ACCESS_ACCOUNT_LOCKED', () {
    const loginLocked = ApiException('账号已被锁定，请联系管理员或稍后重试', statusCode: 423);
    expect(loginLocked.isAccountLocked, isTrue);
    const interceptorLocked = ApiException('ACCESS_ACCOUNT_LOCKED: 账号已被锁定');
    expect(interceptorLocked.isAccountLocked, isTrue);
    const wrongPassword = ApiException('用户名或者密码错误！');
    expect(wrongPassword.isAccountLocked, isFalse);
  });

  test('cashier authorize 401 (wrong store manager credential) does NOT terminate session', () async {
    var terminated = 0;
    final client = AdminApiClient(
      baseUrl: 'https://example.com',
      transport: _ErrorTransport(
        jsonEncode({'code': 401, 'error': 'ACCESS_INVALID_CREDENTIALS', 'msg': '店长密码错误'}),
        statusCode: 401,
      ),
      token: 'token',
      shopId: 1,
      onSessionTerminated: () => terminated++,
    );

    await expectLater(
      client.post(cashierAccessAuthorizeEndpoint, body: const {'account': '10242', 'password': 'bad'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', '店长密码错误'),
      ),
    );
    // 授权人（店长）凭证错误属于授权业务失败，由授权弹窗展示，不应把当前收银会话判定为终止。
    expect(terminated, 0);
  });

  test('other protected endpoints with HTTP 401 still terminate session', () async {
    var terminated = 0;
    final client = AdminApiClient(
      baseUrl: 'https://example.com',
      transport: _ErrorTransport(
        jsonEncode({'code': 401, 'msg': '未登录或登录已过期'}),
        statusCode: 401,
      ),
      token: 'token',
      shopId: 1,
      onSessionTerminated: () => terminated++,
    );

    await expectLater(
      client.get(adminAccessApprovalsEndpoint),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
    expect(terminated, 1);
  });
}

class _ErrorTransport implements HttpTransport {
  const _ErrorTransport(this.body, {this.statusCode = 400});

  final String body;
  final int statusCode;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,  }) async => HttpResponseData(statusCode: statusCode, body: this.body);
}
