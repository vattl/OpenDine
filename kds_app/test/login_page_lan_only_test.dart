import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/device/kds_device_code_resolver.dart';
import 'package:kds_app/features/auth/login_page.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('login exposes the fixed cloud-first manual-switch policy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _CapturingSessionNotifier()),
      ],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.byType(DropdownButtonFormField<KdsConnectionMode>), findsNothing);
    expect(find.text('云端直连优先 · 可选局域网'), findsOneWidget);
    expect(find.text('收银端局域网地址'), findsNothing);
    expect(find.text('云端服务地址 (主通道)'), findsOneWidget);
  });

  testWidgets('login does not require LAN address and connects directly to cloud',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    final notifier = _CapturingSessionNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('收银端局域网地址'), findsNothing);
    expect(find.text('门店 ID'), findsNothing);
    expect(find.text('API 基址'), findsNothing);

    final loginButton = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(loginButton);
    await tester.pump();
    await tester.tap(loginButton);
    await tester.pump();

    expect(notifier.loginCalls, 1);
    expect(notifier.loginChannels, [KdsActiveChannel.cloud]);
  });

  testWidgets('device code field is read-only and displays copy button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    final notifier = _CapturingSessionNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final deviceCodeFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText?.contains('本机硬件设备码') == true,
    );
    expect(deviceCodeFinder, findsOneWidget);
    final textField = tester.widget<TextField>(deviceCodeFinder);
    expect(textField.readOnly, isTrue);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets(
      'login exposes one-time pairing code and forwards it to cloud auth',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    final notifier = _CapturingSessionNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final codeFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '一次性配对码',
    );
    expect(codeFinder, findsOneWidget);
    expect(tester.widget<TextField>(codeFinder).obscureText, isFalse);
    await tester.enterText(codeFinder, 'abcdefgh');

    final loginButton = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(notifier.loginCalls, 1);
    expect(notifier.lastPairingCode, 'ABCDEFGH');
  });

  testWidgets('cloud login failure asks before retrying through LAN proxy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    final notifier =
        _CapturingSessionNotifier(failCloudWithLanSuggestion: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final loginButton = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(find.text('云端响应异常'), findsOneWidget);
    expect(find.text('使用局域网代理'), findsOneWidget);
    expect(notifier.loginChannels, [KdsActiveChannel.cloud]);

    await tester.tap(find.byKey(const ValueKey('login-switch-to-lan')));
    await tester.pumpAndSettle();

    expect(
        notifier.loginChannels, [KdsActiveChannel.cloud, KdsActiveChannel.lan]);
  });

  testWidgets(
      'cloud re-pair rejection requires credential instead of LAN retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await KdsDeviceCodeResolver().resolve();
    final notifier = _CapturingSessionNotifier(
      failCloudWithLanSuggestion: true,
      rePairRequired: true,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final loginButton = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(find.text('设备 Token 已失效，请在收银端生成一次性配对码后重新登录'), findsOneWidget);
    expect(find.text('设备需要重新配对'), findsNothing);
    expect(find.text('通过收银端重新配对'), findsNothing);
    expect(notifier.loginChannels, [KdsActiveChannel.cloud]);
  });
}

class _CapturingSessionNotifier extends SessionNotifier {
  _CapturingSessionNotifier({
    this.failCloudWithLanSuggestion = false,
    this.rePairRequired = false,
  });

  final bool failCloudWithLanSuggestion;
  final bool rePairRequired;
  int loginCalls = 0;
  String? lastPairingCode;
  String? lastDeviceCode;
  final List<KdsActiveChannel> loginChannels = [];

  @override
  SessionState build() => const SessionState();

  @override
  Future<bool> login({
    required String deviceCode,
    required KdsScreenTag screenTag,
    int? shopId,
    String? kdsPin,
    List<KdsWorkflow> workflows = const [],
    List<String> screenTags = const [],
    String? deviceName,
    String? pairingCode,
    required String apiBase,
    String? cloudApiBase,
    KdsConnectionMode mode = KdsConnectionMode.cloudFirst,
    KdsActiveChannel initialChannel = KdsActiveChannel.cloud,
  }) async {
    loginCalls++;
    loginChannels.add(initialChannel);
    lastPairingCode = pairingCode;
    lastDeviceCode = deviceCode;
    if (failCloudWithLanSuggestion &&
        initialChannel == KdsActiveChannel.cloud) {
      state = state.copyWith(
        loading: false,
        error: rePairRequired
            ? '设备 Token 已失效，请在收银端生成一次性配对码后重新登录'
            : '云端延迟过高或无响应，可切换局域网代理重试',
        lanLoginSuggested: !rePairRequired,
      );
      return false;
    }
    return false;
  }
}
