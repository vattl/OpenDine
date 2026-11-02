import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_runtime_diagnostics_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_log_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('CashierSettingsLogPage refactored tests', () {
    late FakeHttpTransport transport;
    late AdminApiClient client;

    final mockLogsResponse = jsonEncode({
      'code': 200,
      'total': 1,
      'list': [
        {
          'id': 1001,
          'createdAt': '2026-10-05T12:30:00',
          'module': 'order',
          'action': 'cashier_order_create',
          'category': 'business',
          'targetId': 'ORD-20261005-001',
          'realName': '张店长',
          'workNo': 'E001',
          'jobTitle': '店长',
          'shopName': '总店',
          'ip': '192.168.1.100',
          'traceId': 'TRACE-abc-123',
          'resultStatus': 'SUCCESS',
          'resultCode': '200',
          'reason': '订单正常创建',
          'requestSnapshot': '{"items": [{"name": "烤五花", "qty": 2}]}',
          'beforeState': '{"status": "INIT"}',
          'afterState': '{"status": "PAID", "amount": 58.0}',
        },
      ],
    });

    final mockDeviceLogsResponse = jsonEncode({
      'code': 200,
      'total': 1,
      'list': [
        {
          'id': 2002,
          'createdAt': '2026-10-05T12:35:00',
          'module': 'kds',
          'action': 'kds_status_sync',
          'category': 'system',
          'targetId': 'DEV-KDS-01',
          'shopName': '总店',
          'ip': '192.168.1.105',
          'resultStatus': 'SUCCESS',
          'resultCode': '200',
          'reason': '厨显屏心跳同步正常',
          'requestSnapshot': '{"screenId": 1, "online": true}',
        },
      ],
    });

    setUp(() {
      transport = FakeHttpTransport({
        'GET /admin/logs': mockLogsResponse,
        'POST /admin/logs/archive-search': jsonEncode({
          'code': 200,
          'data': {'jobId': 8801},
        }),
        'GET /admin/logs/archive-search/8801': jsonEncode({
          'code': 200,
          'data': {
            'jobId': 8801,
            'status': 'DONE',
            'resultSummary': '检索到 42 条归档日志，已生成归档包',
          },
        }),
        'POST /admin/logs/exports': jsonEncode({
          'code': 200,
          'data': {
            'jobId': 9901,
            'auditNo': 'AUDIT-20261005-9901'},
        }),
      });
      client = AdminApiClient(
        baseUrl: 'https://test.example.com',
        transport: transport,
      );
    });

    Widget buildTestWidget({
      required SettingsSectionSpec section,
      Set<String> permissions = const {'log:view', 'log:export', 'admin:manage',
      },
      Size viewportSize = const Size(1280, 900),
    }) {
      return MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: [
            CashierTokens.light]),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(size: viewportSize),
            child: SizedBox(
              width: viewportSize.width,
              height: viewportSize.height,
              child: CashierSettingsLogPage(
                client: client,
                section: section,
                storeName: '总店',
                permissions: permissions,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Operations log renders fully scrollable table and opens detail dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('operations', '操作日志', Icons.manage_search_outlined,
            ),
        ),
      );
      await tester.pumpAndSettle();

      // Table headers
      expect(find.text('时间'), findsOneWidget);
      expect(find.text('模块'), findsNWidgets(2),
        ); // in filter & in table header
      expect(find.text('类型'), findsNWidgets(2),
        ); // in filter & in table header
      expect(find.text('操作'), findsNWidgets(2),
        ); // in filter & in table header
      expect(find.text('对象'), findsOneWidget);
      expect(find.text('操作人'), findsNWidgets(2),
        ); // in filter & in table header
      expect(find.text('门店'), findsOneWidget);
      expect(find.text('结果'), findsOneWidget);

      // Data row content
      expect(find.text('张店长'), findsOneWidget);
      expect(find.text('ORD-20261005-001'), findsOneWidget);
      expect(find.text('业务'), findsOneWidget);
      expect(find.text('成功'), findsOneWidget);

      // Tapping "详情" opens _LogDetailDialog
      final detailBtn = find.text('详情');
      expect(detailBtn, findsOneWidget);
      await tester.tap(detailBtn);
      await tester.pumpAndSettle();

      // In dialog
      expect(find.text('操作日志详情'), findsOneWidget);
      expect(find.text('数据快照与状态变更'), findsOneWidget);
      expect(find.text('请求快照'), findsOneWidget);
      expect(find.text('变更前'), findsOneWidget);
      expect(find.text('变更后'), findsOneWidget);

      // Switch to "变更前" tab
      await tester.tap(find.text('变更前'));
      await tester.pumpAndSettle();
      expect(find.text('变更前 beforeState'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('操作日志详情'), findsNothing);
    },
    );

    testWidgets('Devices log renders scrollable table and opens detail dialog', (tester) async {
      transport = FakeHttpTransport({
        'GET /admin/logs': mockDeviceLogsResponse,
      });
      client = AdminApiClient(
        baseUrl: 'https://test.example.com',
        transport: transport,
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('devices', '设备日志', Icons.devices_outlined,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设备运行日志'), findsOneWidget);
      expect(find.text('设备模块'), findsNWidgets(2));
      expect(find.text('对象 / 说明'), findsOneWidget);
      expect(find.text('DEV-KDS-01'), findsOneWidget);

      // Detail button on device log row
      final detailBtn = find.text('详情');
      expect(detailBtn, findsOneWidget);
      await tester.tap(detailBtn);
      await tester.pumpAndSettle();

      expect(find.text('操作日志详情'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('操作日志详情'), findsNothing);
    },
    );

    testWidgets('Archive search submits task, displays in table and opens detail dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('archive', '归档查询', Icons.archive_outlined,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('归档日志检索'), findsOneWidget);
      expect(find.text('提交检索任务'), findsOneWidget);

      // Submit search
      await tester.tap(find.byKey(const Key('archive-submit')));
      await tester.pumpAndSettle();

      // Should find the job in table
      expect(find.text('#8801'), findsOneWidget);
      expect(find.text('检索任务列表'), findsOneWidget);

      // Click detail on job
      final detailBtn = find.text('详情');
      expect(detailBtn, findsOneWidget);
      await tester.tap(detailBtn);
      await tester.pumpAndSettle();

      expect(find.text('归档检索任务详情'), findsOneWidget);
      expect(find.text('刷新状态'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('归档检索任务详情'), findsNothing);
    },
    );

    testWidgets('Exports view validates purpose, renders export table and detail dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('exports', '导出任务', Icons.download_outlined,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('日志导出（仅超级管理员）'), findsOneWidget);

      // Tapping submit without purpose
      await tester.tap(find.byKey(const Key('export-submit')));
      await tester.pumpAndSettle();
      expect(find.text('请填写导出用途（用于合规审计）'), findsOneWidget);

      // Enter purpose
      await tester.enterText(
        find.byKey(const Key('export-purpose-input')),
        '2026年度业务审计核查',
      );
      await tester.pumpAndSettle();

      // Submit export
      await tester.tap(find.byKey(const Key('export-submit')));
      await tester.pumpAndSettle();

      // Now table should display the record
        final request = transport.requests.lastWhere(
          (r) => r.method == 'POST' && r.uri.path == '/admin/logs/exports',
        );
        final payload = jsonDecode(request.body!);
        expect(payload['purpose'], '2026年度业务审计核查');
        expect(payload['query'], isA<Map>());
        expect(payload.containsKey('module'), isFalse);
        expect(find.text('本次会话导出记录'), findsOneWidget);
      expect(find.text('AUDIT-20261005-9901'), findsOneWidget);
      expect(find.text('2026年度业务审计核查'), findsOneWidget);

      // Click detail
      final detailBtn = find.text('详情');
      expect(detailBtn, findsOneWidget);
      await tester.tap(detailBtn);
      await tester.pumpAndSettle();

      expect(find.text('日志导出审计详情'), findsOneWidget);
      expect(find.text('复制审计编号'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('日志导出审计详情'), findsNothing);
    },
    );

    testWidgets('Low resolution viewport (800x600) renders safely with zero overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('operations', '操作日志', Icons.manage_search_outlined,
            ),
          viewportSize: const Size(800, 600),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex overflow exception
      expect(tester.takeException(), isNull);
    },
    );

    testWidgets('Runtime diagnostics section renders CashierRuntimeDiagnosticsPage with terminal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestWidget(
          section: const SettingsSectionSpec('runtime', '运行日志', Icons.bug_report_outlined,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CashierRuntimeDiagnosticsPage), findsOneWidget);
      expect(find.text('本机运行诊断'), findsOneWidget);
      expect(find.text('运行日志'), findsOneWidget);
      expect(find.text('复制运行日志'), findsOneWidget);
      expect(find.text('崩溃快照'), findsOneWidget);
    },
    );
  });
}
