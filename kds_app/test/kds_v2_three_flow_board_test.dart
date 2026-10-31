import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';
import 'package:kds_app/shared/widgets/kds_filter_chip.dart';

void main() {
  testWidgets('restores workflow tabs and shows one queue at a time',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: _state(),
        workflows: const [
          KdsWorkflow.prep,
          KdsWorkflow.cook,
          KdsWorkflow.serve,
        ],
      ),
    ));

    expect(find.text('待配菜'), findsOneWidget);
    expect(find.text('待制作'), findsOneWidget);
    expect(find.text('待传菜'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('queue-board-pending_prep')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('queue-board-pending_cook')), findsNothing);

    await tester.tap(find.text('待制作'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('queue-board-pending_prep')), findsNothing);
    expect(
        find.byKey(const ValueKey('queue-board-pending_cook')), findsOneWidget);
  });

  testWidgets('workflow tab badges follow local projection, not server counts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(
          connected: true,
          // 服务端残留计数：本屏没有任何待配菜/待传菜明细
          queueCounts: const {
            'pending_prep': 9,
            'pending_cook': 8,
            'ready_serve': 7,
          },
          lines: [
            _line(detailId: 11, dishName: '油边王', bucket: 'dine_in'),
            _line(detailId: 12, dishName: '羊排', bucket: 'takeout'),
          ],
        ),
        workflows: const [
          KdsWorkflow.prep,
          KdsWorkflow.cook,
          KdsWorkflow.serve,
        ],
      ),
    ));

    // 本地待制作共 2 份 → 角标显示 2；服务端残留的 9/8/7 不得显示
    expect(find.text('2'), findsOneWidget);
    expect(find.text('9'), findsNothing);
    expect(find.text('8'), findsNothing);
    expect(find.text('7'), findsNothing);
    expect(find.text('待传菜'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('workflow tab badges follow current dining filter selection',
      (tester) async {
    final dineIn1 = _line(detailId: 11, dishName: '堂食菜1', bucket: 'dine_in');
    final dineIn2 = _line(detailId: 12, dishName: '堂食菜2', bucket: 'dine_in');
    final takeout = _line(detailId: 13, dishName: '外卖菜', bucket: 'takeout');
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(
          connected: true,
          lines: [dineIn1, dineIn2, takeout],
        ),
        workflows: const [
          KdsWorkflow.cook,
        ],
      ),
    ));

    // 全部：待制作角标为 3 份
    expect(
      find.descendant(
        of: find.byType(KdsMainTab),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    // 切换到【堂食】
    await tester.tap(find.text('堂食 2'));
    await tester.pumpAndSettle();

    // 堂食：待制作角标变为 2 份
    expect(
      find.descendant(
        of: find.byType(KdsMainTab),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(KdsMainTab),
        matching: find.text('3'),
      ),
      findsNothing,
    );
  });

  testWidgets('disabled prep flow starts the board at pending cook',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: _state(),
        prepFlowEnabled: false,
        workflows: const [
          KdsWorkflow.prep,
          KdsWorkflow.cook,
          KdsWorkflow.serve,
        ],
      ),
    ));

    expect(find.text('待配菜'), findsNothing);
    expect(find.byKey(const ValueKey('queue-board-pending_cook')),
        findsOneWidget);
  });

  testWidgets(
      'disabled prep flow automatically merges pending_prep items into pending_cook',
      (tester) async {
    final prepDish = KdsV2Line(
      detailId: 99,
      orderId: 1,
      dishId: 1,
      dishName: '待配菜番茄牛腩',
      quantity: 2,
      queue: 'pending_prep',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: {
        'table_number': 'A01',
        'line_quantity': 2,
        'prep_remaining': 2,
        'cook_remaining': 2,
        'ready_remaining': 2,
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(connected: true, lines: [prepDish]),
        prepFlowEnabled: false,
        workflows: const [
          KdsWorkflow.prep,
          KdsWorkflow.cook,
          KdsWorkflow.serve,
        ],
      ),
    ));

    expect(find.text('待配菜'), findsNothing);
    expect(find.text('待配菜番茄牛腩'), findsOneWidget);
  });

  testWidgets('visible_queues from bootstrap permissions controls tabs',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(
          connected: true,
          config: {
            'visible_queues': ['pending_cook', 'done'],
            'allowed_commands': <String>[],
          },
        ),
        workflows: [
          KdsWorkflow.prep,
          KdsWorkflow.cook,
          KdsWorkflow.serve,
        ],
      ),
    ));

    expect(find.text('待配菜'), findsNothing);
    expect(find.text('待制作'), findsOneWidget);
    expect(find.text('待传菜'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('dining filter projects the selected workflow in memory',
      (tester) async {
    final dineIn = _line(detailId: 11, dishName: '堂食菜', bucket: 'dine_in');
    final takeout = _line(detailId: 12, dishName: '外卖菜', bucket: 'takeout');
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(connected: true, lines: [dineIn, takeout]),
        workflows: const [KdsWorkflow.cook],
      ),
    ));

    expect(find.text('堂食菜'), findsOneWidget);
    expect(find.text('外卖菜'), findsOneWidget);

    await tester.tap(find.text('外卖 1'));
    await tester.pumpAndSettle();

    expect(find.text('堂食菜'), findsNothing);
    expect(find.text('外卖菜'), findsOneWidget);
  });

  testWidgets('view toggle switches from dish groups to order cards',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(
          connected: true,
          lines: [
            _line(detailId: 11, dishName: '油边王', bucket: 'dine_in'),
          ],
        ),
        workflows: const [KdsWorkflow.cook],
      ),
    ));

    expect(find.byKey(const ValueKey('active-pending_cook-11:dine_in')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('order-card-11')), findsNothing);

    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('active-pending_cook-11:dine_in')),
        findsNothing);
    expect(find.byKey(const ValueKey('order-card-11')), findsOneWidget);
  });

  testWidgets('manual refresh button triggers the refresh callback',
      (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: _state(),
        workflows: const [KdsWorkflow.cook],
        onRefresh: () => refreshed++,
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('board-manual-refresh')));
    await tester.pump();
    expect(refreshed, 1);
  });

  testWidgets('fulfillment_channel overrides bucket for tags and filters',
      (tester) async {
    // bucket 为 takeout，但细分渠道 fulfillment_channel 为 pickup：
    // 应显示「自」标签并归入自提筛选，而非外卖
    final line = KdsV2Line.fromJson({
      'detail_id': 21,
      'order_id': 21,
      'dish_id': 21,
      'dish_name': '自提菜',
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': 1,
      'order_revision': 1,
      'workflow_queue': 'pending_cook',
      'fulfillment_bucket': 'takeout',
      'fulfillment_channel': 'pickup',
      'table_number': 'A101',
      'order_no': 'O-21',
      'specification': null,
      'unit': '份',
      'remark': null,
      'created_at_ms': 1720000000000,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(connected: true, lines: [line]),
        workflows: const [KdsWorkflow.cook],
      ),
    ));

    expect(find.text('自'), findsOneWidget);
    expect(find.text('外'), findsNothing);

    // 外卖筛选下不显示；自提筛选下显示
    await tester.tap(find.text('外卖'));
    await tester.pumpAndSettle();
    expect(find.text('自提菜'), findsNothing);
    await tester.tap(find.text('自提 1'));
    await tester.pumpAndSettle();
    expect(find.text('自提菜'), findsOneWidget);
  });

  testWidgets(
      'queue tab badge and dining count follow view mode: 5 dishes in dish view, 1 order in order view',
      (tester) async {
    // 1 张单（orderId=99）包含 5 道不同菜品
    final lines = [
      _line(detailId: 1, dishName: '菜品1', bucket: 'dine_in', orderId: 99),
      _line(detailId: 2, dishName: '菜品2', bucket: 'dine_in', orderId: 99),
      _line(detailId: 3, dishName: '菜品3', bucket: 'dine_in', orderId: 99),
      _line(detailId: 4, dishName: '菜品4', bucket: 'dine_in', orderId: 99),
      _line(detailId: 5, dishName: '菜品5', bucket: 'dine_in', orderId: 99),
    ];
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(connected: true, lines: lines),
        workflows: const [KdsWorkflow.cook],
      ),
    ));

    // 1. 默认菜品视图：待制作 Tab 角标显示 5，堂食筛选显示「堂食 5」
    expect(
      find.descendant(
        of: find.widgetWithText(KdsMainTab, '待制作'),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.text('堂食 5'), findsOneWidget);

    // 2. 切换至【订单】视图：待制作 Tab 角标变为 1（单），堂食筛选显示「堂食 1」
    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(KdsMainTab, '待制作'),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('堂食 1'), findsOneWidget);

    // 3. 切回【菜品】视图：角标动态恢复为 5
    await tester.tap(find.text('菜品'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(KdsMainTab, '待制作'),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.text('堂食 5'), findsOneWidget);
  });

  testWidgets(
      'overdue and rush filter chip badges follow view mode',
      (tester) async {
    // 2 张单：
    // 单 1（orderId=99）：包含 2 道超时菜品，其中 1 道被催
    // 单 2（orderId=100）：包含 1 道普通菜品被催
    final lines = [
      _line(
        detailId: 1,
        dishName: '超时催菜1',
        bucket: 'dine_in',
        orderId: 99,
        waitSeconds: 3600,
        servingDurationMinutes: 10,
        rushed: true,
      ),
      _line(
        detailId: 2,
        dishName: '超时菜2',
        bucket: 'dine_in',
        orderId: 99,
        waitSeconds: 3600,
        servingDurationMinutes: 10,
        rushed: false,
      ),
      _line(
        detailId: 3,
        dishName: '催菜3',
        bucket: 'dine_in',
        orderId: 100,
        waitSeconds: 60,
        rushed: true,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: KdsV2ThreeFlowBoard(
        state: KdsV2State(connected: true, lines: lines),
        workflows: const [KdsWorkflow.cook],
      ),
    ));

    // 1. 菜品视图：超时菜品共 2 道（角标 2），催菜菜品共 2 道（角标 2）
    expect(
      find.descendant(
        of: find.widgetWithText(KdsFilterChip, '超时'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(KdsFilterChip, '催菜'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    // 2. 切换至订单视图：
    // 超时订单共 1 张（orderId 99），催菜订单共 2 张（orderId 99, 100）
    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(KdsFilterChip, '超时'),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(KdsFilterChip, '催菜'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });
}

KdsV2State _state() => const KdsV2State(
      connected: true,
      queueCounts: {
        'pending_prep': 3,
        'pending_cook': 5,
        'ready_serve': 7,
        'done': 2,
      },
      catalog: [
        KdsV2CatalogItem(
          dishId: 1,
          dishName: '油边王',
          unit: '串',
          sequence: 0,
        ),
      ],
    );

KdsV2Line _line({
  required int detailId,
  required String dishName,
  required String bucket,
  int? orderId,
  int? waitSeconds,
  int? servingDurationMinutes,
  bool rushed = false,
}) =>
    KdsV2Line.fromJson({
      'detail_id': detailId,
      'order_id': orderId ?? detailId,
      'dish_id': detailId,
      'dish_name': dishName,
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': 1,
      'order_revision': 1,
      'workflow_queue': 'pending_cook',
      'fulfillment_bucket': bucket,
      'table_number': 'A1',
      'order_no': 'O-${orderId ?? detailId}',
      'specification': null,
      'unit': '份',
      'remark': null,
      'created_at_ms': 1720000000000,
      if (waitSeconds != null) 'wait_seconds': waitSeconds,
      if (servingDurationMinutes != null)
        'serving_duration_minutes': servingDurationMinutes,
      'held': false,
      'rushed': rushed,
      'lacked': false,
      'removed': false,
    });
