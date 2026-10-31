import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('cloud and LAN channels always share the single authority token', () {
    const session = SessionState(
      token: 'cloud-authority-token',
      activeChannel: KdsActiveChannel.cloud,
    );

    expect(session.effectiveActiveToken, 'cloud-authority-token');
  });

  test('pairing login enforces cloud-first and skips admin-only health',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    Map<String, dynamic>? loginBody;
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/kds/v2/health') {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({'code': 401, 'msg': '缺少或无效的收银管理员凭证'}),
        );
      } else if (request.uri.path == '/kds/device/login') {
        final bodyText = await utf8.decoder.bind(request).join();
        loginBody = jsonDecode(bodyText) as Map<String, dynamic>;
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {
              'protocol_version': 2,
              'shop_id': 1,
              'device_code': 'KDS-LOGIN-01',
              'device_token': 'device-token',
              'screen_tag': 'workflow_board',
              'workflows': ['prep'],
              'screen_tags': ['meat_grill'],
            },
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response
            .write(jsonEncode({'code': 401, 'msg': 'unauthorized'}));
      }
      await request.response.close();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final succeeded = await notifier.login(
      deviceCode: 'KDS-LOGIN-01',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.prep],
      screenTags: const ['meat_grill'],
      pairingCode: '123456',
      apiBase: 'http://127.0.0.1:${server.port}',
      cloudApiBase: 'http://127.0.0.1:${server.port}',
      // Historical callers may still pass this value; the session boundary
      // must prevent it from bypassing the cloud-authority policy.
      mode: KdsConnectionMode.lanOnly,
    );

    expect(succeeded, isTrue);
    expect(
      container.read(sessionProvider).connectionMode,
      KdsConnectionMode.cloudFirst,
    );
    expect(
      container.read(sessionProvider.notifier).storage.getConnectionModeRaw(),
      KdsConnectionMode.cloudFirst.value,
    );
    expect(paths, contains('/kds/device/login'));
    expect(paths, isNot(contains('/kds/v2/health')));
    // D026：登录请求体携带 screen_tags；响应回显并持久化到会话。
    expect(loginBody?['screen_tags'], ['meat_grill']);
    expect(container.read(sessionProvider).device?.screenTags, ['meat_grill']);
    final persisted =
        container.read(sessionProvider.notifier).storage.readSessionJson();
    expect(
        (persisted?['screen_tags'] as List?)?.cast<String>(), ['meat_grill']);
  });
}
