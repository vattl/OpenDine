import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/board_v2/kds_queue_tasks_dialog.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';
import 'package:kds_app/features/settings/kds_v2_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSessionNotifier extends SessionNotifier {
  String? deviceName = '后厨平板-1';

  @override
  SessionState build() => SessionState(
        device: KdsDevice(
          id: 7,
          shopId: 1,
          screenTag: KdsScreenTag.workflowBoard,
          deviceCode: 'D7',
          deviceToken: 'token',
          workflows: [KdsWorkflow.prep, KdsWorkflow.cook, KdsWorkflow.serve],
          deviceName: deviceName,
        ),
        token: 'token',
        apiBase: 'http://192.168.1.3:17026',
      );
}

class _FakeBoardNotifier extends KdsV2BoardNotifier {
  @override
  KdsV2State build() => const KdsV2State(
        connected: true,
        configVersion: 776,
        config: {'allowed_queues': 'prep,cook,serve'},
        catalog: [
          KdsV2CatalogItem(
            dishId: 1,
            dishName: '油边王',
            unit: '份',
            sequence: 0,
          ),
        ],
      );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appPrefsProvider.overrideWith((ref) => AppPrefs.load()),
      sessionProvider.overrideWith(() => _FakeSessionNotifier()),
      kdsV2BoardProvider.overrideWith(() => _FakeBoardNotifier()),
    ],
    child: const MaterialApp(home: KdsV2SettingsPage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings renders device hero with WS online status',
      (tester) async {
    await _pump(tester);

    expect(find.text('设备设置'), findsOneWidget);
    // 设备概览卡
    expect(find.text('后厨平板-1'), findsOneWidget);
    expect(find.textContaining('门店 #1'), findsOneWidget);
    expect(find.textContaining('屏幕'), findsOneWidget);
    expect(find.text('云端离线'), findsOneWidget);
    // 收银端地址与 KV 配置区
    expect(find.text('收银端地址'), findsOneWidget);
    expect(find.text('http://192.168.1.3:17026'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('固定目录'), findsOneWidget);
    expect(find.text('1 项'), findsOneWidget);
  });

  testWidgets('settings renders all switch rows', (tester) async {
    await _pump(tester);

    expect(find.text('固定菜品'), findsOneWidget);
    expect(find.text('非固定模式同名合并'), findsOneWidget);
    expect(find.text('划菜数量弹窗'), findsOneWidget);
    expect(find.text('配菜流程'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('新单提示音'), 120);
    expect(find.text('新单提示音'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(5));
  });

  testWidgets('settings exposes queue tasks after top bar simplification',
      (tester) async {
    await _pump(tester);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-queue-tasks')), 320);
    expect(find.text('队列任务'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-queue-tasks')));
    await tester.pumpAndSettle();
    expect(find.byType(KdsQueueTasksDialog), findsOneWidget);
  });

  testWidgets('connection policy is fixed and cannot open a mode picker',
      (tester) async {
    await _pump(tester);

    expect(find.text('连接模式'), findsOneWidget);
    expect(find.textContaining('云端优先'), findsOneWidget);
    await tester.tap(find.text('连接模式'));
    await tester.pumpAndSettle();
    expect(find.text('选择连接模式'), findsNothing);
  });

  testWidgets('content is width-constrained for landscape reading',
      (tester) async {
    await _pump(tester);

    final box = tester.widget<ConstrainedBox>(
      find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 680,
      ),
    );
    expect(box.constraints.maxWidth, 680);
  });

  testWidgets('copy address shows bottom toast', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') return null;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester);

    await tester.tap(find.text('收银端地址'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已复制收银端地址'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('logout requires second confirmation', (tester) async {
    await _pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出设备'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('settings page keeps working when device name is missing',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appPrefsProvider.overrideWith((ref) => AppPrefs.load()),
        sessionProvider.overrideWith(
          () => _FakeSessionNotifier()..deviceName = null,
        ),
        kdsV2BoardProvider.overrideWith(() => _FakeBoardNotifier()),
      ],
      child: const MaterialApp(home: KdsV2SettingsPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('后厨设备 #7'), findsOneWidget);
    expect(find.text('云端离线'), findsOneWidget);
  });

  testWidgets('edit lan address dialog opens with test availability button',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appPrefsProvider.overrideWith((ref) => AppPrefs.load()),
        sessionProvider.overrideWith(() => _FakeSessionNotifier()),
        kdsV2BoardProvider.overrideWith(() => _FakeBoardNotifier()),
      ],
      child: const MaterialApp(home: KdsV2SettingsPage()),
    ));
    await tester.pumpAndSettle();

    final editButton = find.byTooltip('修改局域网地址');
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('修改收银端局域网地址'), findsOneWidget);
    expect(find.text('测试地址可用性'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
