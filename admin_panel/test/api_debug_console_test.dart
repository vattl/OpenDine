import 'package:admin_panel_flutter/src/core/api_debug_log.dart';
import 'package:admin_panel_flutter/src/features/api_debug/presentation/api_debug_console_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filters requests, opens details and clears the log', (
    tester,
  ) async {
    final store = ApiDebugLogStore(maxEntries: 10)
      ..add(
        ApiDebugLogEntry(
          id: 'success-1',
          startedAt: DateTime(2026, 8, 8, 10, 30),
          method: 'GET',
          uri: Uri.parse('https://api.test/admin/dish/list?pageNum=1'),
          requestHeaders: const {'X-Shop-Id': '2'},
          requestBody: '',
          statusCode: 200,
          responseBody: '{"code":200,"data":{"total":1}}',
          duration: const Duration(milliseconds: 48),
          succeeded: true,
          error: '',
        ),
      )
      ..add(
        ApiDebugLogEntry(
          id: 'error-1',
          startedAt: DateTime(2026, 8, 8, 10, 31),
          method: 'POST',
          uri: Uri.parse('https://api.test/cashier/order/checkout'),
          requestHeaders: const {'X-Shop-Id': '2'},
          requestBody: '{"order_no":"ORD40"}',
          statusCode: 400,
          responseBody: '{"code":40021,"msg":"支付失败"}',
          duration: const Duration(milliseconds: 120),
          succeeded: false,
          error: '支付失败',
        ),
      );

    await tester.pumpWidget(
      MaterialApp(home: ApiDebugConsolePage(store: store)),
    );

    expect(find.text('接口调试'), findsOneWidget);
    expect(find.text('/admin/dish/list'), findsOneWidget);
    expect(find.text('/cashier/order/checkout'), findsOneWidget);

    await tester.tap(find.byKey(const Key('api-debug-filter-errors')));
    await tester.pump();
    expect(find.text('/admin/dish/list'), findsNothing);
    expect(find.text('/cashier/order/checkout'), findsOneWidget);

    await tester.tap(find.byKey(const Key('api-debug-entry-error-1')));
    await tester.pumpAndSettle();
    expect(find.text('请求详情'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump();
    expect(find.text('支付失败'), findsWidgets);

    await tester.tap(find.byKey(const Key('api-debug-detail-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-debug-clear')));
    await tester.pump();

    expect(store.entries, isEmpty);
    expect(find.text('暂无接口记录'), findsOneWidget);
  });
}
