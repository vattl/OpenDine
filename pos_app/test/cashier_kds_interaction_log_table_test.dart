import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_interaction_log.dart';
import 'package:admin_panel_flutter/src/features/kds_local/presentation/cashier_kds_interaction_log_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows proxy request status and opens sanitized request detail', (
    tester,
  ) async {
    const log = CashierKdsInteractionLog(
      id: 1,
      traceId: 'trace-1',
      shopId: 1,
      orderId: 12,
      orderNo: 'ORDER-12',
      eventId: 'event-1',
      operationId: 'operation-1',
      source: KdsInteractionSide.kds,
      target: KdsInteractionSide.cloud,
      direction: KdsInteractionDirection.outbound,
      stage: KdsInteractionStage.proxyHttpForward,
      action: 'POST /kds/v2/commands',
      status: KdsInteractionStatus.retrying,
      attempt: 2,
      durationMs: 180,
      errorType: 'network_timeout',
      errorSummary: 'connection timed out',
      deviceCode: 'KDS-A01',
      httpStatus: 503,
      metadata: {
        'method': 'POST',
        'path': '/kds/v2/commands',
        'served_via': 'lan-proxy',
      },
      occurredAtMs: 1000,
      createdAtMs: 1000,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CashierKdsInteractionLogTable(logs: [log], droppedLogCount: 0),
        ),
      ),
    );

    expect(find.text('代理转发接口请求'), findsOneWidget);
    expect(find.text('KDS-A01'), findsOneWidget);
    expect(find.text('/kds/v2/commands'), findsOneWidget);
    expect(find.text('503 等待重试'), findsOneWidget);

    await tester.tap(find.text('KDS-A01'));
    await tester.pumpAndSettle();
    expect(find.text('代理请求详情'), findsOneWidget);
    expect(find.textContaining('trace-1'), findsWidgets);
    expect(find.textContaining('connection timed out'), findsWidgets);
  });
}
