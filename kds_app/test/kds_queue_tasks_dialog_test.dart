import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/features/board_v2/kds_queue_tasks_dialog.dart';

void main() {
  testWidgets('queue tasks dialog shows a clear empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KdsQueueTasksDialog(tasks: [], pendingCount: 0),
        ),
      ),
    );

    expect(find.text('队列任务'), findsOneWidget);
    expect(find.text('队列为空'), findsOneWidget);
    expect(find.textContaining('所有操作均已获得权威端确认'), findsOneWidget);
  });

  testWidgets('queue tasks dialog exposes status target retries and error',
      (tester) async {
    final tasks = [
      KdsV2OptimisticOverlay(
        commandId: 'cmd-advance-001',
        aggregateKey: 'order:18',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(
          orderId: 18,
          detailId: 201,
          fromQueue: 'pending_cook',
        ),
        quantity: 2,
        fromQueue: 'pending_cook',
        toQueue: 'ready_serve',
        createdAt: DateTime(2026, 10, 2, 12, 3, 4),
        status: KdsOverlayStatus.sending,
        originChannel: 'cloud',
        retryCount: 1,
      ),
      KdsV2OptimisticOverlay(
        commandId: 'cmd-unknown-002',
        aggregateKey: 'order:19',
        commandType: KdsV2CommandType.refundItem,
        target: const KdsV2CommandTarget(orderId: 19, detailId: 202),
        createdAt: DateTime(2026, 10, 2, 12, 4, 5),
        status: KdsOverlayStatus.unknown,
        originChannel: 'lan',
        retryCount: 3,
        lastError: '连接超时',
        requiresResolution: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KdsQueueTasksDialog(tasks: tasks, pendingCount: 2),
        ),
      ),
    );

    expect(find.text('2 项待处理'), findsOneWidget);
    expect(find.text('划菜'), findsOneWidget);
    expect(find.text('发送中'), findsOneWidget);
    expect(find.textContaining('待制作 → 待传菜'), findsOneWidget);
    expect(find.text('退款'), findsOneWidget);
    expect(find.text('待查证'), findsOneWidget);
    expect(find.textContaining('已尝试 3 次'), findsOneWidget);
    expect(find.textContaining('连接超时'), findsOneWidget);
    expect(find.textContaining('等待云端账本裁决'), findsOneWidget);
  });
}
