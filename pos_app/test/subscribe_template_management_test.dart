import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/subscribe_template.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_notification_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';

class _MockCashierSettingsRepository implements CashierSettingsRepository {
  List<SubscribeSceneTemplate> templates = [
    const SubscribeSceneTemplate(
      id: 1,
      sceneCode: 'ORDER_PICKUP',
      templateId: 'WFf0k7CN73QlWQnsRIi3WDQIpJzRHDI4AogDrERzbQc',
      title: '取餐通知',
      triggerPoint: 'SUBMIT_ORDER',
      isActive: 1,
      remark: '全单出餐完成时通知顾客前往取餐',
      paramMappingJson: '{"character_string1": "order_no", "phrase2": "pickup_code"}',
    ),
    const SubscribeSceneTemplate(
      id: 2,
      sceneCode: 'ORDER_STATUS',
      templateId: '7t69W_Uq212bO1uH8mUu4t2zGk0_1234567890abcdef',
      title: '接单制作通知',
      triggerPoint: 'SUBMIT_ORDER',
      isActive: 1,
      remark: '后厨接单并开始备餐时通知顾客',
      paramMappingJson: '{"character_string1": "order_no"}',
    ),
  ];

  List<SubscribeSendLog> logs = [
    const SubscribeSendLog(
      id: 101,
      bizNo: 'O2026103100812',
      openid: 'oP3Z_6abcd1234wxyz',
      sceneCode: 'ORDER_PICKUP',
      templateId: 'WFf0k7CN73...zbQc',
      sendStatus: 'SUCCESS',
      quotaBefore: 2,
      quotaAfter: 1,
      durationMs: 114,
      errcode: 0,
      errmsg: 'ok',
      payloadSummary: '{"touser":"oP3Z_6abcd1234wxyz","template_id":"WFf0...","data":{"phrase2":{"value":"A-018"}}}',
      createdAt: '2026-10-31 09:18:24',
    ),
    const SubscribeSendLog(
      id: 102,
      bizNo: 'O2026103100809',
      openid: 'oP3Z_6xyz7890mnop',
      sceneCode: 'ORDER_PICKUP',
      templateId: 'WFf0k7CN73...zbQc',
      sendStatus: 'FAILED',
      quotaBefore: 1,
      quotaAfter: 0,
      durationMs: 182,
      errcode: 43101,
      errmsg: 'user refuse to accept the msg hint: [wx_sub_err_43101]',
      payloadSummary: '{"errcode":43101,"errmsg":"user refuse to accept the msg"}',
      createdAt: '2026-10-31 09:14:02',
    ),
  ];

  Map<String, dynamic>? lastCreatedData;
  Map<String, dynamic>? lastUpdatedData;
  String? lastUpdatedSceneCode;
  String? lastDeletedSceneCode;
  Map<String, dynamic>? lastLogsFilter;

  @override
  Future<List<SubscribeSceneTemplate>> listSubscribeSceneTemplates() async {
    return templates;
  }

  @override
  Future<bool> createSubscribeSceneTemplate(Map<String, dynamic> data) async {
    lastCreatedData = data;
    templates.add(SubscribeSceneTemplate.fromJson(data));
    return true;
  }

  @override
  Future<bool> updateSubscribeSceneTemplate(
    String sceneCode,
    Map<String, dynamic> data,
  ) async {
    lastUpdatedSceneCode = sceneCode;
    lastUpdatedData = data;
    final idx = templates.indexWhere((t) => t.sceneCode == sceneCode);
    if (idx != -1) {
      templates[idx] = SubscribeSceneTemplate.fromJson(data);
    }
    return true;
  }

  @override
  Future<bool> deleteSubscribeSceneTemplate(String sceneCode) async {
    lastDeletedSceneCode = sceneCode;
    templates.removeWhere((t) => t.sceneCode == sceneCode);
    return true;
  }

  @override
  Future<List<SubscribeSendLog>> listSubscribeSendLogs({
    String? bizNo,
    String? openid,
    String? scene,
    String? status,
    int limit = 50,
  }) async {
    lastLogsFilter = {
      'bizNo': bizNo,
      'openid': openid,
      'scene': scene,
      'status': status,
      'limit': limit,
    };
    return logs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WeChat Subscribe Template & Audit Management (WI-080)', () {
    test('Domain model serialization & status logic', () {
      const template = SubscribeSceneTemplate(
        id: 1,
        sceneCode: 'ORDER_PICKUP',
        templateId: 'tmpl_123',
        title: '取餐通知',
        triggerPoint: 'SUBMIT_ORDER',
        isActive: 1,
        remark: '出餐提示',
      );

      expect(template.active, isTrue);
      final json = template.toJson();
      expect(json['scene_code'], 'ORDER_PICKUP');
      expect(json['template_id'], 'tmpl_123');

      final copied = template.copyWith(isActive: 0);
      expect(copied.active, isFalse);

      const log = SubscribeSendLog(
        id: 10,
        bizNo: 'O123',
        openid: 'openid_abc',
        sceneCode: 'ORDER_PICKUP',
        templateId: 'tmpl_123',
        sendStatus: 'FAILED',
        errcode: 43101,
        errmsg: 'user refuse',
        quotaBefore: 1,
        quotaAfter: 0,
      );

      expect(log.isFailed, isTrue);
      expect(log.isSuccess, isFalse);
      expect(log.errcode, 43101);
    });

    testWidgets('Templates View: Renders cards and toggles active state', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Metric Strip
      expect(find.text('📋 微信订阅消息模板与唤起策略'), findsOneWidget);
      expect(find.text('活跃订阅场景'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);

      // Verify Scene Cards
      expect(find.text('取餐通知'), findsWidgets);
      expect(find.text('接单制作通知'), findsWidgets);
      expect(find.text('ORDER_PICKUP'), findsOneWidget);
      expect(find.text('ORDER_STATUS'), findsOneWidget);

      // Verify Quick Active Toggle Switch
      final switchPill = find.byType(ManageSwitchPill).first;
      expect(switchPill, findsOneWidget);
      await tester.tap(switchPill);
      await tester.pumpAndSettle();

      expect(mockRepo.lastUpdatedSceneCode, 'ORDER_PICKUP');
      expect(mockRepo.lastUpdatedData?['is_active'], 0);
    });

    testWidgets('Templates View: Search and filter templates (查)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search text "取餐"
      final searchInput = find.byType(TextField).first;
      await tester.enterText(searchInput, '取餐');
      await tester.pumpAndSettle();

      // Only "取餐通知" card should be visible, "接单制作通知" filtered out
      expect(find.text('ORDER_PICKUP'), findsOneWidget);
      expect(find.text('ORDER_STATUS'), findsNothing);

      // Clear search
      await tester.enterText(searchInput, '');
      await tester.pumpAndSettle();
      expect(find.text('ORDER_PICKUP'), findsOneWidget);
      expect(find.text('ORDER_STATUS'), findsOneWidget);
    });

    testWidgets('Templates View: Opens create dialog, inserts variable placeholders and adds template (增)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "+ 新增场景"
      final addBtn = find.widgetWithText(ManageButton, '+ 新增场景');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Verify create dialog open
      expect(find.text('新增微信订阅场景模板'), findsOneWidget);
      expect(find.text('点击快捷插入点餐系统通用业务占位符：'), findsOneWidget);
      expect(find.text('{pickup_code}'), findsOneWidget);
      expect(find.text('{order_no}'), findsOneWidget);
      expect(find.text('{shop_name}'), findsOneWidget);

      // Fill in basic fields inside the Dialog
      final dialogFinder = find.byType(Dialog);
      final textFields = find.descendant(of: dialogFinder, matching: find.byType(TextField));
      await tester.enterText(textFields.at(0), 'QUEUE_CALL');
      await tester.enterText(textFields.at(1), '排队叫号通知');
      await tester.enterText(textFields.at(2), 'mock_template_id_queue_call_1234567890');
      await tester.enterText(textFields.at(3), '排到叫号时提醒顾客前往入座');
      await tester.pumpAndSettle();

      // Check that chips are rendered
      expect(find.text('{pickup_code}'), findsOneWidget);
      expect(find.text('{pay_amount}'), findsOneWidget);

      // Save
      final saveBtn = find.widgetWithText(ElevatedButton, '创建场景模板');
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(mockRepo.lastCreatedData?['scene_code'], 'QUEUE_CALL');
      expect(mockRepo.lastCreatedData?['title'], '排队叫号通知');
    });

    testWidgets('Templates View: Opens edit dialog and saves configuration (改)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find "配置模板" button for first card
      final configBtn = find.widgetWithText(ManageButton, '配置模板').first;
      await tester.tap(configBtn);
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('编辑场景模板 - 取餐通知'), findsOneWidget);
      expect(find.text('微信模板 ID (template_id)'), findsOneWidget);

      // Tap "保存配置" button in dialog
      final saveBtn = find.widgetWithText(ElevatedButton, '保存配置');
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(mockRepo.lastUpdatedSceneCode, 'ORDER_PICKUP');
      expect(mockRepo.lastUpdatedData?['template_id'], 'WFf0k7CN73QlWQnsRIi3WDQIpJzRHDI4AogDrERzbQc');
    });

    testWidgets('Templates View: Deletes template with confirmation dialog (删)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "删除" on first card
      final delBtn = find.widgetWithText(OutlinedButton, '删除').first;
      await tester.tap(delBtn);
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('确认删除场景模板？'), findsOneWidget);
      expect(find.text('确定删除'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.widgetWithText(ElevatedButton, '确定删除'));
      await tester.pumpAndSettle();

      expect(mockRepo.lastDeletedSceneCode, 'ORDER_PICKUP');
    });

    testWidgets('Deliveries View: Renders audit logs and opens payload detail', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockCashierSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsNotificationPage(
              repository: mockRepo,
              section: const SettingsSectionSpec('deliveries', '投递审计日志', Icons.receipt_long_outlined),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Logs
      expect(find.text('📊 微信订阅消息下发审计与台账流水'), findsOneWidget);
      expect(find.text('O2026103100812'), findsOneWidget);
      expect(find.text('O2026103100809'), findsOneWidget);

      // Verify Status Badges (Success and Failed with 43101 error code)
      expect(find.text('✓ 成功 (0)'), findsOneWidget);
      expect(find.text('✗ 失败 (43101)'), findsOneWidget);

      // Verify Quota change indicators
      expect(find.text('2 → 1'), findsOneWidget);
      expect(find.text('1 → 0'), findsOneWidget);

      // Tap "报文" button to inspect JSON payload
      final payloadBtn = find.widgetWithText(OutlinedButton, '报文').first;
      await tester.tap(payloadBtn);
      await tester.pumpAndSettle();

      expect(find.text('微信订阅下发报文详情 (ID: 101)'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    });
  });
}
