import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/app_state.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/presentation/kds_devices_page.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements HttpTransport {
  _FakeTransport({
    required this.devices,
    this.failBind = false,
    this.failUnbind = false,
  });

  final List<Map<String, Object?>> devices;
  final bool failBind;
  final bool failUnbind;
  final List<String> requests = <String>[];
  final List<String> postBodies = <String>[];

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    requests.add('$method ${uri.path}');
    if (method == 'POST' && uri.path == '/admin/kds/device/bind') {
      postBodies.add(body ?? '');
      if (failBind) {
        return const HttpResponseData(
          statusCode: 503,
          body: '{"code":503,"msg":"cloud unavailable"}',
        );
      }
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 0,
          'msg': 'ok',
          'device': {
            'shop_id': 1,
            'device_code': 'KDS-GRILL-01',
            'device_name': '烤台一',
            'screen_tag': 'workflow_board',
            'screen_tags': ['veg_grill', 'seafood_special'],
            'enabled': 1,
          },
        }),
      );
    }
    if (method == 'POST' && uri.path == '/admin/kds/device/unbind') {
      postBodies.add(body ?? '');
      if (failUnbind) {
        return const HttpResponseData(
          statusCode: 503,
          body: '{"code":503,"msg":"cloud unavailable"}',
        );
      }
      if (body != null) {
        final parsed = jsonDecode(body) as Map<String, dynamic>;
        final code = parsed['device_code'] ?? parsed['deviceCode'];
        devices.removeWhere(
          (d) => d['device_code'] == code || d['deviceCode'] == code,
        );
      }
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({'code': 0, 'msg': 'ok'}),
      );
    }
    if (method == 'POST' && uri.path == '/admin/kds/device/pairing-ticket') {
      postBodies.add(body ?? '');
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 0,
          'data': {
            'device_code': 'KDS-CLOUD-01',
            'pairing_code': 'ABCDEFGH',
            'expires_at_ms': DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          },
        }),
      );
    }
    if (method == 'GET' && uri.path == '/admin/kds/device/list') {
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({'code': 0, 'msg': 'ok', 'list': devices}),
      );
    }
    return const HttpResponseData(
      statusCode: 404,
      body: '{"code":404,"msg":"not found"}',
    );
  }
}

AppState _appState() {
  final state = AppState();
  state.applySession(
    const LoginSession(
      token: 'token',
      scope: 'SHOP',
      permissions: {'kds:config'},
      shops: [ShopSummary(id: 1, code: 'S1', name: '一店')],
    ),
  );
  return state;
}

void main() {
  testWidgets('device list renders screen_tags labels (D026)', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-GRILL-01',
          'device_name': '烤台一',
          'screen_tag': 'workflow_board',
          'screen_tags': ['meat_grill', 'seafood_special'],
          'enabled': 1,
        },
        {
          'shop_id': 1,
          'device_code': 'KDS-OLD-02',
          'device_name': '',
          'screen_tag': 'workflow_board',
          'screen_tags': <String>[],
          'enabled': 0,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('烤台一'), findsOneWidget);
    expect(find.textContaining('可见岗：荤烤、海鲜'), findsOneWidget);
    expect(find.textContaining('三岗全选'), findsOneWidget);
  });

  testWidgets('bind form submits selected screenTags (D026)', (tester) async {
    final transport = _FakeTransport(devices: const []);
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('绑定设备'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '设备编号（deviceCode）*'),
      'KDS-GRILL-09',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '屏幕类型（screenTag）*'),
      'workflow_board',
    );
    await tester.tap(find.text('素烤（veg_grill）'));
    await tester.tap(find.text('海鲜（seafood_special）'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(transport.postBodies, hasLength(1));
    final body =
        jsonDecode(transport.postBodies.single) as Map<String, dynamic>;
    expect(body['deviceCode'], 'KDS-GRILL-09');
    expect(body['screenTag'], 'workflow_board');
    expect((body['screenTags'] as List).toSet(), {
      'veg_grill',
      'seafood_special',
    });
  });

  testWidgets('bind without tags omits screenTags (legacy compatible)', (
    tester,
  ) async {
    final transport = _FakeTransport(devices: const []);
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('绑定设备'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '设备编号（deviceCode）*'),
      'KDS-OLD-03',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '屏幕类型（screenTag）*'),
      'workflow_board',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final body =
        jsonDecode(transport.postBodies.single) as Map<String, dynamic>;
    expect(body.containsKey('screenTags'), isFalse);
  });

  testWidgets('sync to cloud never uploads cached device tokens', (
    tester,
  ) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-CLOUD-ONLY-01',
          'device_name': '后厨主屏',
          'screen_tag': 'workflow_board',
          'device_token': 'must-not-leave-cashier',
          'enabled': 1,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步到云端'));
    await tester.pumpAndSettle();

    final body =
        jsonDecode(transport.postBodies.single) as Map<String, dynamic>;
    expect(body.containsKey('deviceToken'), isFalse);
    expect(body.containsKey('device_token'), isFalse);
    expect(body.values, isNot(contains('must-not-leave-cashier')));
  });

  testWidgets('editing an existing device pre-fills screen_tags (D026)', (
    tester,
  ) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-GRILL-01',
          'device_name': '烤台一',
          'screen_tag': 'workflow_board',
          'screen_tags': ['veg_grill'],
          'enabled': 1,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('烤台一'));
    await tester.pumpAndSettle();

    expect(find.text('编辑设备（可见岗）'), findsOneWidget);
    final vegCheckbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '素烤（veg_grill）'),
    );
    expect(vegCheckbox.value, isTrue);
    final meatCheckbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '荤烤（meat_grill）'),
    );
    expect(meatCheckbox.value, isFalse);
  });

  testWidgets('delete device from list triggers confirmation and unbind', (
    tester,
  ) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-GRILL-01',
          'device_name': '烤台一',
          'screen_tag': 'workflow_board',
          'screen_tags': ['veg_grill'],
          'enabled': 1,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('烤台一'), findsOneWidget);

    // Click delete icon button
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('删除设备'), findsOneWidget);
    expect(find.textContaining('确定要删除/解绑设备'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    // Verify unbind request was sent
    expect(
      transport.requests.contains('POST /admin/kds/device/unbind'),
      isTrue,
    );
    final lastBody =
        jsonDecode(transport.postBodies.last) as Map<String, dynamic>;
    expect(lastBody['device_code'], 'KDS-GRILL-01');

    // List is now empty
    expect(find.text('暂无设备，点击右上角「绑定设备」添加'), findsOneWidget);
  });

  testWidgets('delete device from edit dialog triggers unbind', (tester) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-GRILL-02',
          'device_name': '烤台二',
          'screen_tag': 'workflow_board',
          'screen_tags': ['meat_grill'],
          'enabled': 1,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(appState: _appState(), client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click to edit
    await tester.tap(find.textContaining('烤台二'));
    await tester.pumpAndSettle();

    expect(find.text('编辑设备（可见岗）'), findsOneWidget);
    expect(find.text('删除设备'), findsOneWidget);

    // Click delete device button inside dialog
    await tester.tap(find.widgetWithText(TextButton, '删除设备'));
    await tester.pumpAndSettle();

    // Confirm deletion
    expect(find.textContaining('确定要删除/解绑设备'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    // Verify unbind request
    expect(
      transport.requests.contains('POST /admin/kds/device/unbind'),
      isTrue,
    );
    final lastBody =
        jsonDecode(transport.postBodies.last) as Map<String, dynamic>;
    expect(lastBody['device_code'], 'KDS-GRILL-02');

    // List refreshed
    expect(find.text('暂无设备，点击右上角「绑定设备」添加'), findsOneWidget);
  });

  testWidgets(
    'proxy-only device management keeps bind/delete and hides legacy pairing tools',
    (tester) async {
      final transport = _FakeTransport(
        devices: [
          {
            'shop_id': 1,
            'device_code': 'KDS-PROXY-01',
            'device_name': '后厨主屏',
            'screen_tag': 'workflow_board',
            'screen_tags': <String>[],
            'enabled': 1,
          },
        ],
      );
      final client = AdminApiClient(
        baseUrl: 'http://localhost',
        transport: transport,
        token: 'token',
        shopId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KdsDevicesPage(
              appState: _appState(),
              client: client,
              showLanPairing: false,
              showCloudSync: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('绑定设备'), findsOneWidget);
      expect(find.byTooltip('删除'), findsOneWidget);
      expect(find.text('局域网连接与厨显配对'), findsNothing);
      expect(find.text('同步到云端'), findsNothing);
    },
  );

  testWidgets('read-only device management hides all mutation controls', (
    tester,
  ) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-READONLY-01',
          'device_name': '只读设备',
          'screen_tag': 'workflow_board',
          'screen_tags': <String>[],
          'enabled': 1,
        },
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(
            appState: _appState(),
            client: client,
            canManage: false,
            showLanPairing: false,
            showCloudSync: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('只读设备'), findsOneWidget);
    expect(find.text('绑定设备'), findsNothing);
    expect(find.byTooltip('编辑'), findsNothing);
    expect(find.byTooltip('删除'), findsNothing);
  });

  testWidgets('failed cloud bind does not create a local-only binding', (
    tester,
  ) async {
    final transport = _FakeTransport(devices: [], failBind: true);
    final runtime = _FakeDevicesKdsRuntime(
      lanAddress: 'http://192.168.1.188:17026',
      pairingCode: '654321',
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(
            appState: _appState(),
            client: client,
            kdsRuntime: runtime,
            showLanPairing: false,
            showCloudSync: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('绑定设备'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '设备编号（deviceCode）*'),
      'KDS-CLOUD-FAIL-01',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(runtime.upsertCalls, 0);
    expect(find.textContaining('cloud unavailable'), findsOneWidget);
    expect(find.text('绑定设备（可见岗）'), findsOneWidget);
  });

  testWidgets('failed cloud unbind preserves the local device cache', (
    tester,
  ) async {
    final transport = _FakeTransport(
      devices: [
        {
          'shop_id': 1,
          'device_code': 'KDS-CLOUD-FAIL-02',
          'device_name': '不可误删设备',
          'screen_tag': 'workflow_board',
          'screen_tags': <String>[],
          'enabled': 1,
        },
      ],
      failUnbind: true,
    );
    final runtime = _FakeDevicesKdsRuntime(
      lanAddress: 'http://192.168.1.188:17026',
      pairingCode: '654321',
      devices: const [
        CashierKdsDevice(
          shopId: 1,
          deviceCode: 'KDS-CLOUD-FAIL-02',
          deviceName: '不可误删设备',
          screenTag: 'workflow_board',
          workflows: ['prep', 'cook', 'serve'],
          pairedAtMs: 0,
          lastHeartbeatAtMs: 0,
          enabled: true,
        ),
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(
            appState: _appState(),
            client: client,
            kdsRuntime: runtime,
            showLanPairing: false,
            showCloudSync: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(runtime.unbindCalls, 0);
    expect(find.textContaining('删除设备失败'), findsOneWidget);
    expect(find.textContaining('不可误删设备'), findsOneWidget);
  });

  testWidgets('an empty cloud device list does not surface stale local cache', (
    tester,
  ) async {
    final transport = _FakeTransport(devices: []);
    final runtime = _FakeDevicesKdsRuntime(
      lanAddress: 'http://192.168.1.188:17026',
      pairingCode: '654321',
      devices: const [
        CashierKdsDevice(
          shopId: 1,
          deviceCode: 'KDS-STALE-LOCAL-01',
          deviceName: '本地旧缓存设备',
          screenTag: 'workflow_board',
          workflows: ['prep', 'cook', 'serve'],
          pairedAtMs: 0,
          lastHeartbeatAtMs: 0,
          enabled: true,
        ),
      ],
    );
    final client = AdminApiClient(
      baseUrl: 'http://localhost',
      transport: transport,
      token: 'token',
      shopId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsDevicesPage(
            appState: _appState(),
            client: client,
            kdsRuntime: runtime,
            showLanPairing: false,
            showCloudSync: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无设备，点击右上角「绑定设备」添加'), findsOneWidget);
    expect(find.textContaining('本地旧缓存设备'), findsNothing);
  });

  testWidgets(
    'renders LAN connection and generates pairing code with countdown',
    (tester) async {
      final transport = _FakeTransport(
        devices: [
          {
            'device_code': 'KDS-CLOUD-01',
            'device_name': '后厨主屏',
            'screen_tag': 'workflow_board',
            'enabled': 1,
          },
        ],
      );
      final client = AdminApiClient(
        baseUrl: 'http://localhost',
        transport: transport,
        token: 'token',
        shopId: 1,
      );
      final fakeRuntime = _FakeDevicesKdsRuntime(
        lanAddress: 'http://192.168.1.188:17026',
        pairingCode: '654321',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KdsDevicesPage(
              appState: _appState(),
              client: client,
              kdsRuntime: fakeRuntime,
              canManage: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify LAN address card
      expect(find.text('局域网连接与厨显配对'), findsOneWidget);
      expect(find.text('http://192.168.1.188:17026'), findsOneWidget);
      expect(find.text('生成配对码'), findsOneWidget);
      expect(find.textContaining('KDS-CLOUD-01'), findsWidgets);

      // Tap generate pairing code
      await tester.ensureVisible(
        find.byKey(const Key('kds-generate-pairing-code-btn')),
      );
      final generateButton = tester.widget<FilledButton>(
        find.byKey(const Key('kds-generate-pairing-code-btn')),
      );
      generateButton.onPressed!();
      await tester.pumpAndSettle();

      expect(
        transport.requests,
        contains('POST /admin/kds/device/pairing-ticket'),
      );
      // Verify cloud-issued pairing code is displayed
      expect(find.textContaining('A  B  C  D  E  F  G  H'), findsOneWidget);
      expect(find.textContaining('05:00'), findsOneWidget);

      // Advance 1 second
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('04:59'), findsOneWidget);
    },
  );
}

class _FakeDevicesKdsRuntime implements CashierKdsRuntime {
  _FakeDevicesKdsRuntime({
    required this.lanAddress,
    required this.pairingCode,
    this.devices = const [],
  });

  final String lanAddress;
  final String pairingCode;
  final List<CashierKdsDevice> devices;
  int upsertCalls = 0;
  int unbindCalls = 0;

  @override
  String get lanStatus => 'active';

  @override
  int get lanPort => 17026;

  @override
  int get configuredPort => 17026;

  @override
  String get cashierDeviceCode => 'CASHIER-DEV-01';

  @override
  int get connectedDeviceCount => 0;

  @override
  List<CashierKdsDevice> get pairedDevices => devices;

  @override
  Future<List<String>> lanAddresses() async => [lanAddress];

  @override
  Future<void> syncBoundDevices(
    List<Map<String, Object?>> devices, {
    required int shopId,
  }) async {}

  @override
  String generatePairingCode({
    Duration validity = const Duration(minutes: 5),
  }) => pairingCode;

  @override
  Future<CashierKdsDevice> upsertBoundDevice({
    required int shopId,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    List<String> workflows = const ['prep', 'cook', 'serve'],
    List<String> screenTags = const [],
    bool enabled = true,
  }) async {
    upsertCalls++;
    return CashierKdsDevice(
      shopId: shopId,
      deviceCode: deviceCode,
      deviceName: deviceName,
      screenTag: screenTag,
      workflows: workflows,
      screenTags: screenTags,
      pairedAtMs: 0,
      lastHeartbeatAtMs: 0,
      enabled: enabled,
    );
  }

  @override
  Future<void> unbindDevice({
    required int shopId,
    required String deviceCode,
  }) async {
    unbindCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
