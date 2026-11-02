import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_interaction_log.dart';
import 'package:admin_panel_flutter/src/features/kds_local/presentation/cashier_kds_diagnostics_page.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_runtime.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_tls.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/admin_api_cashier_kds_proxy_client.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  test(
    'authenticated shop starts LAN proxy without authority or delivery polling',
    () async {
      final root = await Directory.systemTemp.createTemp('kds-proxy-start-');
      addTearDown(() => root.delete(recursive: true));
      final runtime = await CashierKdsRuntime.start(
        applicationDataRoot: root,
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(runtime.close);
      final transport = FakeHttpTransport(const {});
      final proxy = AdminApiCashierKdsProxyClient(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
        cashierDeviceCode: runtime.cashierDeviceCode,
      );

      runtime.setActiveShop(1);
      runtime.configureCloudProxy(proxy);
      await runtime.refreshProxyListener();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(runtime.lanStatus, 'active');
      expect(runtime.isAvailable, isTrue);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'logout stops LAN proxy without consulting cloud configuration',
    () async {
      final root = await Directory.systemTemp.createTemp('kds-proxy-stop-');
      addTearDown(() => root.delete(recursive: true));
      final runtime = await CashierKdsRuntime.start(
        applicationDataRoot: root,
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );
      addTearDown(runtime.close);

      runtime.setActiveShop(1);
      runtime.configureCloudProxy(
        AdminApiCashierKdsProxyClient(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: FakeHttpTransport(const {}),
          ),
          cashierDeviceCode: runtime.cashierDeviceCode,
        ),
      );
      await runtime.refreshProxyListener();
      expect(runtime.isAvailable, isTrue);

      runtime.configureCloudProxy(null);
      runtime.setActiveShop(null);
      await runtime.refreshProxyListener();

      expect(runtime.isAvailable, isFalse);
      expect(runtime.lanStatus, 'waiting_for_login');
    },
  );

  test(
    'private LAN proxy fails closed when TLS identity is not configured',
    () async {
      final root = await Directory.systemTemp.createTemp('kds-address-');
      addTearDown(() => root.delete(recursive: true));
      final runtime = await CashierKdsRuntime.start(
        applicationDataRoot: root,
        bindAddress: InternetAddress('192.168.10.25'),
        port: 17026,
        autoGenerateTls: false,
      );
      addTearDown(runtime.close);

      expect(runtime.lanStatus, 'waiting_for_login');
      runtime.setActiveShop(1);
      runtime.configureCloudProxy(
        AdminApiCashierKdsProxyClient(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: FakeHttpTransport(const {}),
          ),
          cashierDeviceCode: runtime.cashierDeviceCode,
        ),
      );
      await runtime.refreshProxyListener();

      expect(runtime.lanStatus, 'listen_blocked');
      expect(runtime.lanError, contains('TLS'));
      expect(await runtime.lanAddresses(), isEmpty);
    },
  );

  test('configured private LAN address is advertised as HTTPS', () async {
    final root = await Directory.systemTemp.createTemp('kds-tls-address-');
    addTearDown(() => root.delete(recursive: true));
    final runtime = await CashierKdsRuntime.start(
      applicationDataRoot: root,
      bindAddress: InternetAddress('192.168.10.25'),
      port: 17026,
      tlsConfiguration: CashierKdsTlsConfiguration(
        securityContext: SecurityContext(withTrustedRoots: false),
        certificateSha256: 'TEST-FINGERPRINT',
      ),
    );
    addTearDown(runtime.close);

    expect(runtime.lanCertificateSha256, 'TEST-FINGERPRINT');
    expect(
      await runtime.lanAddresses(),
      contains('https://192.168.10.25:17026'),
    );
  });

  test('runtime refuses an injected wildcard listener', () async {
    final root = await Directory.systemTemp.createTemp('kds-wildcard-bind-');
    addTearDown(() => root.delete(recursive: true));
    final runtime = await CashierKdsRuntime.start(
      applicationDataRoot: root,
      bindAddress: InternetAddress.anyIPv4,
      port: 0,
    );
    addTearDown(runtime.close);
    runtime.setActiveShop(1);
    runtime.configureCloudProxy(
      AdminApiCashierKdsProxyClient(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: FakeHttpTransport(const {}),
        ),
        cashierDeviceCode: runtime.cashierDeviceCode,
      ),
    );
    await runtime.refreshProxyListener();

    expect(runtime.isAvailable, isFalse);
    expect(runtime.lanStatus, 'listen_blocked');
    expect(await runtime.lanAddresses(), isEmpty);
  });

  test('runtime supports in-memory fallback mode without touching disk database', () async {
    final runtime = await CashierKdsRuntime.start(
      inMemory: true,
      port: 0,
    );
    addTearDown(runtime.close);
    expect(runtime.isAvailable, isFalse);
    expect(runtime.database, isNotNull);
    expect(runtime.cashierDeviceCode, isNotEmpty);
  });

  testWidgets(
    'connection panel exposes proxy state without authority controls',
    (tester) async {
      final runtime = _FakeProxyRuntime();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierKdsConnectionPanel(runtime: runtime, canManage: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('KDS 连接'), findsOneWidget);
      expect(find.text('局域网代理'), findsOneWidget);
      expect(find.text('代理转发接口请求'), findsNothing);
      expect(find.textContaining('主收银'), findsNothing);
      expect(find.textContaining('权威'), findsNothing);
      expect(find.textContaining('云同步队列'), findsNothing);
      expect(find.textContaining('云端时间'), findsNothing);
      expect(find.byKey(const Key('kds-connection-refresh')), findsOneWidget);
    },
  );
}

class _FakeProxyRuntime implements CashierKdsRuntime {
  @override
  String get lanStatus => 'active';

  @override
  int get lanPort => 17026;

  @override
  int get configuredPort => 17026;

  @override
  int get connectedDeviceCount => 2;

  @override
  String get cashierDeviceCode => 'CASHIER-TEST-01';

  @override
  String? get lanError => null;

  @override
  String? get lanCertificateSha256 => 'TEST-FINGERPRINT';

  @override
  List<CashierKdsInteractionLog> get interactionLogs => const [];

  @override
  int get droppedInteractionLogCount => 0;

  @override
  Future<List<String>> lanAddresses() async => const [
    'https://192.168.1.10:17026',
  ];

  @override
  Future<void> refreshProxyListener() async {}

  @override
  Future<void> restartLanServer() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
