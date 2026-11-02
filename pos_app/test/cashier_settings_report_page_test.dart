import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_report_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('CashierSettingsReportPage DateTime parser & formatter', () {
    test('parses exact user input format 2026-9-30 16:00:00', () {
      final dt = parseCustomDateTime('2026-9-30 16:00:00');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 30);
      expect(dt.hour, 16);
      expect(dt.minute, 0);
      expect(dt.second, 0);
      expect(dt.millisecond, 0);
    });

    test('parses zero-padded standard format 2026-09-30 16:00:00', () {
      final dt = parseCustomDateTime('2026-09-30 16:00:00');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 30);
      expect(dt.hour, 16);
      expect(dt.minute, 0);
      expect(dt.second, 0);
    });

    test('parses milliseconds precision: .123 and .5', () {
      final dt1 = parseCustomDateTime('2026-09-30 16:00:00.123');
      expect(dt1, isNotNull);
      expect(dt1!.millisecond, 123);

      final dt2 = parseCustomDateTime('2026-09-30 16:00:00.5');
      expect(dt2, isNotNull);
      expect(dt2!.millisecond, 500);

      final dt3 = parseCustomDateTime('2026-09-30 16:00:00.000');
      expect(dt3, isNotNull);
      expect(dt3!.millisecond, 0);
    });

    test('parses slash date format 2026/09/30 16:00:00', () {
      final dt = parseCustomDateTime('2026/09/30 16:00:00');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 30);
      expect(dt.hour, 16);
    });

    test('parses date-only format 2026-09-30', () {
      final dt = parseCustomDateTime('2026-09-30');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 30);
      expect(dt.hour, 0);
      expect(dt.minute, 0);
      expect(dt.second, 0);
    });

    test('returns null for invalid inputs', () {
      expect(parseCustomDateTime(''), isNull);
      expect(parseCustomDateTime('   '), isNull);
      expect(parseCustomDateTime('not-a-date'), isNull);
      expect(parseCustomDateTime('2026-99-99 99:99:99'), isNull);
    });

    test('fmtReportDateTime formats with zero padding and optional milliseconds', () {
      final t1 = DateTime(2026, 9, 30, 16, 0, 0);
      expect(fmtReportDateTime(t1), '2026-09-30 16:00:00');

      final t2 = DateTime(2026, 5, 4, 3, 2, 1);
      expect(fmtReportDateTime(t2), '2026-05-04 03:02:01');

      final t3 = DateTime(2026, 9, 30, 16, 0, 0, 45);
      expect(fmtReportDateTime(t3), '2026-09-30 16:00:00.045');

      final t4 = DateTime(2026, 9, 30, 16, 0, 0, 500);
      expect(fmtReportDateTime(t4), '2026-09-30 16:00:00.500');
    });
  });

  group('CashierSettingsReportPage UI widget tests', () {
    late FakeHttpTransport transport;
    late AdminApiClient client;

    setUp(() {
      transport = FakeHttpTransport({
        'GET /admin/analytics/business/trend': jsonEncode({
          'code': 200,
          'data': {
            'natural_calendar': {
              'window': {'startTime': '2026-09-24 00:00:00', 'endTime': '2026-09-30 23:59:59'},
              'series': [],
            },
            'business_day': {
              'window': {'startTime': '2026-09-24 16:00:00', 'endTime': '2026-09-30 16:00:00'},
              'series': [],
            },
          },
        }),
        'GET /admin/analytics/business': jsonEncode({
          'code': 200,
          'data': {
            'core': {'order_count': 10, 'gross_sales': 500.0, 'net_sales': 480.0},
            'business_day': {'derived': {}},
            'natural_calendar': {'derived': {}},
            'payment_channels': [],
          },
        }),
        'GET /admin/analytics/dishes': jsonEncode({
          'code': 200,
          'data': [],
        }),
      });
      client = AdminApiClient(
        baseUrl: 'https://test.example.com',
        transport: transport,
      );
    });

    Widget buildTestWidget({required SettingsSectionSpec section}) {
      return MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const [
            CashierTokens.light,
          ],
        ),
        home: Scaffold(
          body: CashierSettingsReportPage(
            client: client,
            section: section,
            storeName: '测试门店',
          ),
        ),
      );
    }

    testWidgets('renders report page and opens custom date-time dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const section = SettingsSectionSpec(
        'catalog',
        '营业报表',
        Icons.bar_chart,
      );

      await tester.pumpWidget(buildTestWidget(section: section));
      await tester.pumpAndSettle();

      final customChipFinder = find.text('自定义');
      expect(customChipFinder, findsOneWidget);

      await tester.tap(customChipFinder);
      await tester.pumpAndSettle();

      expect(find.text('自定义时间范围'), findsOneWidget);
      expect(find.text('快捷时间段预设：'), findsOneWidget);
      expect(find.text('今日至今 (00:00~现在)'), findsOneWidget);
      expect(find.text('昨日整天'), findsOneWidget);
      expect(find.text('近7天 (今天-6 00:00~现在)'), findsOneWidget);
      expect(find.text('本月至今'), findsOneWidget);
      // v1.2.280：预设不再含 16:00 硬编码。
      expect(find.text('营业日 (昨16:00~今16:00)'), findsNothing);
      expect(find.text('00:00:00'), findsWidgets);
      expect(find.text('16:00:00'), findsWidgets);
      expect(find.text('23:59:59'), findsWidgets);
      expect(find.text('当前时间'), findsWidgets);
      expect(find.text('确定应用'), findsOneWidget);

      await tester.tap(find.text('今日至今 (00:00~现在)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确定应用'));
      await tester.pumpAndSettle();

      expect(find.text('自定义时间范围'), findsNothing);

      final businessReq = transport.requests.lastWhere(
        (r) => r.uri.path == '/admin/analytics/business' &&
               r.uri.queryParameters.containsKey('startTime'),
      );
      // 自定义窗口保留时分秒（精确保留输入区间）。
      expect(businessReq.uri.queryParameters['startTime'], contains('00:00:00'));
      expect(businessReq.uri.queryParameters['endTime'], isNotNull);
    });

    testWidgets('preset ranges send date-only start/end (v1.2.280)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const section = SettingsSectionSpec(
        'catalog',
        '营业报表',
        Icons.bar_chart,
      );

      await tester.pumpWidget(buildTestWidget(section: section));
      await tester.pumpAndSettle();

      // 初始快捷预设为近7天：请求只带年月日，不传时分秒。
      final businessReq = transport.requests.lastWhere(
        (r) => r.uri.path == '/admin/analytics/business' &&
               r.uri.queryParameters.containsKey('startTime'),
      );
      final start = businessReq.uri.queryParameters['startTime']!;
      final end = businessReq.uri.queryParameters['endTime']!;
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(start), isTrue,
          reason: '快捷预设 startTime 应只传年月日，实际: $start');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(end), isTrue,
          reason: '快捷预设 endTime 应只传年月日，实际: $end');
    });
  });
}
