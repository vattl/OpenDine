import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('cloud-first login uses cloud and does not contact LAN when cloud works',
      () async {
    var cloudCalls = 0;
    var lanCalls = 0;
    final cloud = await _loginServer(() => cloudCalls++);
    final lan = await _loginServer(() => lanCalls++);
    addTearDown(() => cloud.close(force: true));
    addTearDown(() => lan.close(force: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final result = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: _base(cloud),
      mode: KdsConnectionMode.cloudFirst,
    );

    expect(result, isTrue);
    expect(cloudCalls, 1);
    expect(lanCalls, 0);
    expect(
        container.read(sessionProvider).activeChannel, KdsActiveChannel.cloud);
  });

  test(
      'cloud re-login sends a persisted device token when session metadata is missing',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'kds_device_token': 'persisted-cloud-token',
    });
    var cloudCalls = 0;
    final cloud = await _tokenProtectedLoginServer(() => cloudCalls++);
    final lan = await _loginServer(() {});
    addTearDown(() => cloud.close(force: true));
    addTearDown(() => lan.close(force: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final result = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: _base(cloud),
      mode: KdsConnectionMode.cloudFirst,
    );

    expect(result, isTrue);
    expect(cloudCalls, 1);
  });

  test('cloud link failure requires confirmation before LAN proxy login',
      () async {
    final unavailableCloud = await _abortingServer();
    final cloudBase = _base(unavailableCloud);
    addTearDown(() => unavailableCloud.close(force: true));
    var lanCalls = 0;
    final lan = await _loginServer(() => lanCalls++);
    addTearDown(() => lan.close(force: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final cloudResult = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: cloudBase,
      mode: KdsConnectionMode.cloudFirst,
    );

    expect(cloudResult, isFalse);
    expect(lanCalls, 0);
    expect(
        container.read(sessionProvider).activeChannel, KdsActiveChannel.cloud);
    expect(container.read(sessionProvider).lanLoginSuggested, isTrue);

    final lanResult = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: cloudBase,
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
    );

    expect(lanResult, isTrue);
    expect(lanCalls, 1);
    expect(container.read(sessionProvider).activeChannel, KdsActiveChannel.lan);
    expect(container.read(sessionProvider).lanLoginSuggested, isFalse);
  });

  test(
      'cloud re-pair rejection requires a credential and never retries via LAN',
      () async {
    var cloudCalls = 0;
    var lanCalls = 0;
    final cloud = await _repairRequiredLoginServer(() => cloudCalls++);
    final lan = await _loginServer(() => lanCalls++);
    addTearDown(() => cloud.close(force: true));
    addTearDown(() => lan.close(force: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final cloudResult = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: _base(cloud),
      mode: KdsConnectionMode.cloudFirst,
    );

    expect(cloudResult, isFalse);
    expect(cloudCalls, 1);
    expect(lanCalls, 0);
    expect(container.read(sessionProvider).lanLoginSuggested, isFalse);
    expect(
      container.read(sessionProvider).error,
      contains('一次性配对码'),
    );
  });

  test('cloud authentication rejection never falls back to LAN', () async {
    var cloudCalls = 0;
    var lanCalls = 0;
    final cloud = await _rejectingLoginServer(() => cloudCalls++);
    final lan = await _loginServer(() => lanCalls++);
    addTearDown(() => cloud.close(force: true));
    addTearDown(() => lan.close(force: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    await notifier.bootstrap();

    final result = await notifier.login(
      deviceCode: 'KDS-CLOUD-FIRST',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.cook],
      apiBase: _base(lan),
      cloudApiBase: _base(cloud),
      mode: KdsConnectionMode.cloudFirst,
    );

    expect(result, isFalse);
    expect(cloudCalls, 1);
    expect(lanCalls, 0);
    expect(
        container.read(sessionProvider).activeChannel, KdsActiveChannel.cloud);
  });
}

Future<HttpServer> _loginServer(void Function() onLogin) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/kds/device/login') {
      onLogin();
      await utf8.decoder.bind(request).join();
      request.response.write(jsonEncode({
        'code': 0,
        'data': {
          'protocol_version': 2,
          'shop_id': 1,
          'device_code': 'KDS-CLOUD-FIRST',
          'device_token': 'cloud-issued-token',
          'screen_tag': 'workflow_board',
          'workflows': ['cook'],
          'screen_tags': <String>[],
        },
      }));
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'code': 404, 'msg': 'not found'}));
    }
    await request.response.close();
  });
  return server;
}

String _base(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

Future<HttpServer> _abortingServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await request.response.detachSocket();
    socket.destroy();
  });
  return server;
}

Future<HttpServer> _rejectingLoginServer(void Function() onLogin) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onLogin();
    await utf8.decoder.bind(request).join();
    request.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'code': 401, 'msg': '设备凭据无效'}));
    await request.response.close();
  });
  return server;
}

Future<HttpServer> _repairRequiredLoginServer(void Function() onLogin) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onLogin();
    await utf8.decoder.bind(request).join();
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'code': 403,
        'msg': '设备重新登录需要有效设备 Token 或重新配对',
      }));
    await request.response.close();
  });
  return server;
}

Future<HttpServer> _tokenProtectedLoginServer(void Function() onLogin) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onLogin();
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (request.headers.value('X-Kds-Device-Token') !=
        'persisted-cloud-token') {
      request.response.write(jsonEncode({
        'code': 403,
        'msg': '设备重新登录需要有效设备 Token 或重新配对',
      }));
    } else {
      request.response.write(jsonEncode({
        'code': 0,
        'data': {
          'protocol_version': 2,
          'shop_id': 1,
          'device_code': 'KDS-CLOUD-FIRST',
          'device_token': 'rotated-cloud-token',
          'screen_tag': 'workflow_board',
          'workflows': ['cook'],
          'screen_tags': <String>[],
        },
      }));
    }
    await request.response.close();
  });
  return server;
}
