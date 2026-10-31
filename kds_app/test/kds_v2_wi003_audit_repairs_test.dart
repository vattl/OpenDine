import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

class _MockCapturingBoardNotifier extends KdsV2BoardNotifier {
  _MockCapturingBoardNotifier(this._state);

  final KdsV2State _state;
  final List<KdsV2CommandType> sentCommands = [];
  final List<KdsV2CommandTarget> sentTargets = [];

  @override
  KdsV2State build() => _state;

  @override
  Future<void> send({
    required KdsV2CommandType type,
    required KdsV2CommandTarget target,
    int? quantity,
    int? expectedRevision,
    Map<int, int>? expectedRevisions,
    bool? setSoldOut,
    String? remark,
  }) async {
    sentCommands.add(type);
    sentTargets.add(target);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WI-003 Business Logic & Engineering Quality Reinforcement', () {
    testWidgets('P0: Rush dish slices are sorted to the very top regardless of FIFO sort mode',
        (tester) async {
      // 普通菜品：下单时间早（createdAt = 1000），等待时间长
      final normalLine = KdsV2Line(
        detailId: 101,
        orderId: 10,
        dishId: 1,
        dishName: '红烧肉',
        quantity: 1,
        queue: 'pending_cook',
        fulfillmentBucket: 'dine_in',
        revision: 1,
        raw: {
          'table_number': 'A01',
          'created_at_ms': 1000,
          'wait_seconds': 500,
          'rushed': false,
        },
      );

      // 催菜菜品：下单时间晚（createdAt = 50000），等待时间短，但被标记为催菜
      final rushedLine = KdsV2Line(
        detailId: 102,
        orderId: 11,
        dishId: 2,
        dishName: '清蒸鲈鱼',
        quantity: 1,
        queue: 'pending_cook',
        fulfillmentBucket: 'dine_in',
        revision: 1,
        raw: {
          'table_number': 'A02',
          'created_at_ms': 50000,
          'wait_seconds': 10,
          'rushed': true,
        },
      );

      final state = KdsV2State(
        connected: true,
        lines: [normalLine, rushedLine],
      );

      final notifier = _MockCapturingBoardNotifier(state);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kdsV2BoardProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 600,
                child: KdsV2QueueColumn(
                  queue: 'pending_cook',
                  label: '待制作',
                  state: state,
                  fixedDishOrderEnabled: false,
                  mergeSameDishNameEnabled: false,
                  sortMode: BoardSortMode.fifo,
                ),
              ),
            ),
          ),
        ),
      );

      // 验证催菜和普通菜卡片均存在
      expect(find.text('清蒸鲈鱼'), findsOneWidget);
      expect(find.text('红烧肉'), findsOneWidget);

      // 催菜应置于首位（排在普通菜前面或上方）
      final rushedTopLeft = tester.getTopLeft(find.text('清蒸鲈鱼'));
      final normalTopLeft = tester.getTopLeft(find.text('红烧肉'));
      expect(rushedTopLeft.dx, lessThan(normalTopLeft.dx));
    });

    testWidgets('P0: Refund alert banner displays prominently and dismisses on user confirmation',
        (tester) async {
      final alertsNotifier = ValueNotifier<List<KdsRefundAlertItem>>([
        KdsRefundAlertItem(
          id: 'alert-1',
          tableOrPickupCode: '08号桌',
          dishName: '水煮牛肉',
          quantity: 2,
          unit: '份',
          occurredAt: DateTime.now(),
        ),
      ]);

      String? dismissedId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: const KdsV2State(connected: true),
              workflows: const [],
              refundAlerts: alertsNotifier,
              onDismissRefundAlert: (id) => dismissedId = id,
            ),
          ),
        ),
      );

      // 验证横幅显式展示退菜信息
      expect(find.text('退菜提醒'), findsOneWidget);
      expect(find.text('08号桌 · 水煮牛肉 x2份 已退菜，请立即停止烹饪！'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);

      // 点击确认关闭
      await tester.tap(find.text('我知道了'));
      await tester.pump();

      expect(dismissedId, 'alert-1');

      // 清空提醒后横幅消失
      alertsNotifier.value = const [];
      await tester.pump();
      expect(find.text('退菜提醒'), findsNothing);
    });

    testWidgets('P1: Held dish card renders quick release button and dispatches releaseItem command',
        (tester) async {
      final heldLine = KdsV2Line(
        detailId: 888,
        orderId: 88,
        dishId: 1,
        dishName: '招牌牛排',
        quantity: 1,
        queue: 'pending_cook',
        fulfillmentBucket: 'dine_in',
        revision: 1,
        raw: {
          'table_number': 'B05',
          'held': true,
          'wait_seconds': 60,
        },
      );

      final state = KdsV2State(
        connected: true,
                config: const {
          'allowed_commands': ['advance_item', 'release_item']
        },
        lines: [heldLine],
      );

      final notifier = _MockCapturingBoardNotifier(state);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kdsV2BoardProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 800,
                child: KdsV2QueueColumn(
                  queue: 'pending_cook',
                  label: '待制作',
                  state: state,
                  fixedDishOrderEnabled: false,
                  mergeSameDishNameEnabled: false,
                ),
              ),
            ),
          ),
        ),
      );

      // 卡片上存在起菜按钮且等叫标签呈现
      final releaseBtn = find.widgetWithText(TextButton, '起菜');
      expect(releaseBtn, findsOneWidget);

      // 点击起菜
      await tester.tap(releaseBtn);
      await tester.pumpAndSettle();

      // 验证向后厨分发了 releaseItem 指令
      expect(notifier.sentCommands, contains(KdsV2CommandType.releaseItem));
      expect(notifier.sentTargets.first.detailId, 888);
    });

    testWidgets('P1: Advance failure notice renders high-contrast alert preventing double-cooking',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showKdsAdvanceFailureNotice(
                    context,
                    Exception('Outbox synchronization failed'),
                    action: '划菜',
                  );
                },
                child: const Text('触发失败'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发失败'));
      await tester.pump();

      // 验证高反差防呆警示文案
      expect(find.textContaining('划菜失败'), findsOneWidget);
      expect(find.textContaining('卡片已恢复原状，请勿提前出餐！'), findsOneWidget);
    });

    testWidgets('P2: addDishIndependentEnabled partitions add-dish into an independent ticket with (加单) label',
        (tester) async {
      final originalDish = KdsV2Line(
        detailId: 901,
        orderId: 90,
        dishId: 1,
        dishName: '西湖醋鱼',
        quantity: 1,
        queue: 'pending_cook',
        fulfillmentBucket: 'dine_in',
        revision: 1,
        raw: {
          'table_number': 'T09',
          'add_dish': false,
        },
      );

      final addedDish = KdsV2Line(
        detailId: 902,
        orderId: 90,
        dishId: 2,
        dishName: '东坡肉',
        quantity: 1,
        queue: 'pending_cook',
        fulfillmentBucket: 'dine_in',
        revision: 1,
        raw: {
          'table_number': 'T09',
          'add_dish': true,
        },
      );

      final state = KdsV2State(
        connected: true,
        lines: [originalDish, addedDish],
      );

      final notifier = _MockCapturingBoardNotifier(state);

      // 1. 当 addDishIndependentEnabled = false 时：同一桌单合并为一个卡片
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kdsV2BoardProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 800,
                child: KdsV2QueueColumn(
                  queue: 'pending_cook',
                  label: '待制作',
                  state: state,
                  isDishView: false,
                  addDishIndependentEnabled: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('order-card-90')), findsOneWidget);
      expect(find.textContaining('(加单)'), findsNothing);

      // 2. 当 addDishIndependentEnabled = true 时：加菜独立成单，显示 (加单)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kdsV2BoardProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 800,
                child: KdsV2QueueColumn(
                  queue: 'pending_cook',
                  label: '待制作',
                  state: state,
                  isDishView: false,
                  addDishIndependentEnabled: true,
                ),
              ),
            ),
          ),
        ),
      );

      // 分裂为普通单与加订单两个独立卡片
      expect(find.byKey(const ValueKey('order-card-90')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-card-90:add_dish')), findsOneWidget);
      expect(find.textContaining('(加单)'), findsOneWidget);
    });
  });
}
