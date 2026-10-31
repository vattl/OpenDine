import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/diagnostics/kds_inspector_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    KdsTraceHub.clear();
  });

  testWidgets('KdsInspectorWindow displays host and transmission channel info',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sessionState = SessionState(
      apiBase: 'http://192.168.1.100:8000',
      cloudApiBase: 'https://api.cloud.example.com',
      activeChannel: KdsActiveChannel.lan,
      device: KdsDevice(
        id: 1,
        deviceCode: 'KDS-001',
        deviceName: '后厨出餐大屏',
        shopId: 10,
        screenTag: KdsScreenTag.expedition,
        deviceToken: 'dummy-token',
        workflows: const [KdsWorkflow.cook],
      ),
    );

    KdsTraceHub.recordSend(
      channel: KdsActiveChannel.lan,
      action: 'POST /kds/v2/advance',
      summary: '推进菜品状态',
      endpoint: '/kds/v2/advance',
      metadata: {'host': '192.168.1.100:8000'},
    );

    KdsTraceHub.recordFetch(
      channel: KdsActiveChannel.cloud,
      action: 'GET /kds/v2/orders',
      summary: '拉取云端订单增量',
      endpoint: '/kds/v2/orders',
      metadata: {'host': 'api.cloud.example.com'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            () => _MockSessionNotifier(sessionState),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: KdsInspectorWindow(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 顶部态势 Bar
    expect(find.textContaining('当前传输: 局域网传输 [192.168.1.100:8000]'), findsOneWidget);
    expect(find.textContaining('局域网传输: 192.168.1.100:8000'), findsOneWidget);

    // Tab 1 传输模式横幅
    expect(find.text('局域网传输 (LAN)'), findsWidgets);
    expect(find.text('192.168.1.100:8000'), findsWidgets);
    expect(find.text('api.cloud.example.com'), findsWidgets);

    // 列表项 Host 徽章验证
    expect(find.text('局域网 · 192.168.1.100:8000'), findsWidgets);
    expect(find.text('云端 · api.cloud.example.com'), findsOneWidget);
  });
}

class _MockSessionNotifier extends SessionNotifier {
  _MockSessionNotifier(this._initialState);
  final SessionState _initialState;

  @override
  SessionState build() => _initialState;
}
