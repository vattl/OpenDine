import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

void main() {
  testWidgets('board header shows the current LAN or cloud channel',
      (tester) async {
    const state = KdsV2State(connected: true);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: state,
              workflows: [],
              activeChannel: KdsActiveChannel.cloud,
            ),
          ),
        ),
      ),
    );

    expect(find.text('云端模式'), findsOneWidget);
    expect(find.text('局域网模式'), findsNothing);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: state,
              workflows: [],
              activeChannel: KdsActiveChannel.lan,
            ),
          ),
        ),
      ),
    );

    expect(find.text('局域网模式'), findsOneWidget);
    expect(find.text('云端模式'), findsNothing);
  });

  testWidgets('active channel badge is a manual channel switch entry',
      (tester) async {
    var switchRequests = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: const KdsV2State(connected: true),
              workflows: const [],
              activeChannel: KdsActiveChannel.cloud,
              onChannelSwitch: () => switchRequests++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('active-channel-cloud')),
    );
    await tester.pump();

    expect(switchRequests, 1);
  });

  testWidgets('board header keeps queue tasks out of the primary actions',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: const KdsV2State(
                connected: true,
                pendingSyncCount: 3,
              ),
              workflows: const [],
              onQueueTasks: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('board-queue-tasks')), findsNothing);
  });

  testWidgets('catalog slots stay fixed and active dine-in never duplicates',
      (tester) async {
    await tester.pumpWidget(_harness(_state()));

    expect(find.byKey(const ValueKey('active-pending_cook-1:dine_in')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('placeholder-pending_cook-1:dine_in')),
        findsNothing);
    expect(find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')),
        matching: find.text('—'),
      ),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('active-pending_cook-1:takeout')),
        findsOneWidget);
    final dineY = tester
        .getTopLeft(find.byKey(const ValueKey('active-pending_cook-1:dine_in')))
        .dy;
    final placeholderY = tester
        .getTopLeft(
            find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')))
        .dy;
    final takeoutY = tester
        .getTopLeft(find.byKey(const ValueKey('active-pending_cook-1:takeout')))
        .dy;
    expect(dineY, lessThan(placeholderY));
    expect(takeoutY, lessThan(placeholderY));
  });

  testWidgets(
      'detail shows table spec quantity wait and hides forbidden commands',
      (tester) async {
    await tester.pumpWidget(_harness(_state()));
    await tester.tap(find.text('详情>').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('A12'), findsOneWidget);
    expect(find.text('A13'), findsOneWidget);
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('做法：微辣')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.text('3分钟')),
      findsNWidgets(2),
    );
    // 推进交互已由明细卡单击/长按承担，逐桌划菜按钮已移除
    expect(find.text('逐桌划菜'), findsNothing);
    expect(find.text('缺货'), findsNothing);
    expect(find.text('归档整单'), findsNothing);
  });

  testWidgets('dish card follows Group 51 typography and hierarchy',
      (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'dish_name': '油边王',
      'specification': '微辣',
      'remark': '不要辣',
      'serving_duration_minutes': 10,
      'wait_seconds': 1800,
      'add_dish': true,
    });
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    final table = tester.widget<Text>(find.text('B08'));
    final details = tester.widget<Text>(find.text('详情>'));
    final dish = tester.widget<Text>(find.text('油边王'));
    final spec = tester.widget<Text>(find.text('做法：微辣'));
    final remark = tester.widget<Text>(find.text('备注：不要辣'));
    final wait = tester.widget<Text>(find.text('30分钟'));
    final quantity = tester.widget<Text>(find.text('1份'));

    expect(table.style?.fontSize, 32);
    expect(details.style?.fontSize, 24);
    expect(dish.style?.fontSize, 40);
    expect(spec.style?.fontSize, 24);
    // 做法红色加粗凸显，防止厨房环境看不清
    expect(spec.style?.color, KdsColors.headerOverdue);
    expect(spec.style?.fontWeight, FontWeight.w800);
    expect(remark.style?.fontSize, 24);
    expect(remark.style?.color, KdsColors.headerOverdue);
    expect(wait.style?.fontSize, 24);
    expect(quantity.style?.fontSize, 34);
    expect(quantity.style?.fontWeight, FontWeight.w800);
    expect(find.text('整卡划菜'), findsNothing);
    expect(tester.getTopLeft(find.text('油边王')).dx,
        greaterThan(tester.getTopLeft(find.text('超')).dx));
    final footerY = tester.getTopLeft(find.text('30分钟')).dy;
    final remarkY = tester.getTopLeft(find.text('备注：不要辣')).dy;
    expect(footerY - remarkY, greaterThanOrEqualTo(45));
    final footerBottomY = tester.getBottomLeft(find.text('30分钟')).dy;
    final quantityBottomY = tester.getBottomLeft(find.text('1份')).dy;
    expect((footerBottomY - quantityBottomY).abs(), lessThanOrEqualTo(2));
  });

  testWidgets('whole dish card is the advance hit area', (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line.fromJson(_canonicalPatch());
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: KdsV2State(
                connected: true,
                config: const {
                  'allowed_commands': ['advance_item']
                },
                lines: [detail],
              ),
            ),
          ),
        ),
      ),
    ));

    // 点击卡片任意位置（菜名）即可整卡推进
    await tester.tap(find.text('羊排'));
    await tester.pump();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastQuantity, 1);
    expect(notifier.lastTarget?.detailId, 91);
  });

  testWidgets(
      'quantity dialog switch on: tap opens dialog and advances selected count',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'line_quantity': 3,
      'cook_remaining': 3,
      'ready_remaining': 3,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              advanceQuantityDialogEnabled: true,
              state: KdsV2State(
                connected: true,
                config: const {
                  'allowed_commands': ['advance_item']
                },
                lines: [detail],
              ),
            ),
          ),
        ),
      ),
    ));

    // 开关打开：单击卡片先弹数量弹窗，不直接推进
    await tester.tap(find.text('羊排'));
    await tester.pumpAndSettle();
    expect(find.text('全部划出 (3份)'), findsOneWidget);
    expect(notifier.lastType, isNull);

    // 减一份后确认，按所选数量推进
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认划出 2 份'));
    await tester.pumpAndSettle();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastQuantity, 2);
    expect(notifier.lastTarget?.detailId, 91);
    expect(notifier.lastExpectedRevision, 1);
  });

  testWidgets('switch off: long press opens the quantity dialog',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'line_quantity': 3,
      'cook_remaining': 3,
      'ready_remaining': 3,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: KdsV2State(
                connected: true,
                config: const {
                  'allowed_commands': ['advance_item']
                },
                lines: [detail],
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.longPress(find.text('羊排'));
    await tester.pumpAndSettle();
    expect(find.text('全部划出 (3份)'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(notifier.lastType, isNull);
  });

  testWidgets('detail card long press opens quantity dialog and advances count',
      (tester) async {
    final notifier = _CapturingBoardNotifier()..currentState = _state();
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: _state(),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('详情>').first);
    await tester.pumpAndSettle();

    // 长按明细卡弹数量弹窗，按数量推进该行
    await tester.longPress(find.text('A12'));
    await tester.pumpAndSettle();
    expect(find.text('全部划出 (2份)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认划出 1 份'));
    await tester.pumpAndSettle();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastQuantity, 1);
    expect(notifier.lastTarget?.detailId, 'A12'.hashCode & 0x7fffffff);
  });

  testWidgets(
      'detail dialog quantity follows board state after partial advance',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    Map<String, dynamic> patch(
            {required int remaining, required int revision}) =>
        {
          ..._canonicalPatch(),
          'dish_name': '油边王',
          'specification': '微辣',
          'line_quantity': 2,
          'cook_remaining': remaining,
          'ready_remaining': remaining,
          'local_revision': revision,
        };
    KdsV2State boardState({required int remaining, required int revision}) =>
        KdsV2State(
          connected: true,
          config: const {
            'allowed_commands': ['advance_item']
          },
          lines: [
            KdsV2Line.fromJson(patch(remaining: remaining, revision: revision)),
          ],
        );
    notifier.currentState = boardState(remaining: 2, revision: 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: notifier.currentState,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('2份')),
      findsOneWidget,
    );

    // 长按明细卡弹数量弹窗，划出 1 份
    await tester.longPress(find.descendant(
      of: dialog,
      matching: find.text('B08'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认划出 1 份'));
    await tester.pumpAndSettle();
    expect(notifier.lastQuantity, 1);

    // 模拟权威 ACK：剩余 2 → 1，弹窗内明细卡数量必须同步更新
    notifier.emitState(boardState(remaining: 1, revision: 2));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('1份')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('2份')),
      findsNothing,
    );
  });

  testWidgets(
      'json specification renders parsed value in red bold, not raw json',
      (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'dish_name': '油边王',
      'specification': '{"辣度":"微辣","做法":"少油"}',
    });
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    // 不显示原始 JSON
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('辣度'), findsNothing);
    // 只显示解析后的做法值，且红色加粗
    final spec = tester.widget<Text>(find.text('做法：微辣,少油'));
    expect(spec.style?.color, KdsColors.headerOverdue);
    expect(spec.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('empty specification falls back to plain 默认 label',
      (tester) async {
    final detail = KdsV2Line.fromJson(_canonicalPatch());
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    final spec = tester.widget<Text>(find.text('做法：默认'));
    expect(spec.style?.color, isNot(KdsColors.headerOverdue));
  });

  testWidgets('dish card renders channel and status tags', (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'fulfillment_bucket': 'takeout',
      'add_dish': true,
      'rushed': true,
      'is_combo': true,
      'wait_seconds': 30,
    });
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    expect(find.text('外'), findsOneWidget);
    expect(find.text('加'), findsOneWidget);
    expect(find.text('催'), findsOneWidget);
    expect(find.text('套'), findsOneWidget);
    // 未超时、非自提/打包：不应出现 超/打/自
    expect(find.text('打'), findsNothing);
    expect(find.text('超'), findsNothing);
    expect(find.text('自'), findsNothing);
  });

  testWidgets('pickup bucket renders 自 tag', (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'fulfillment_bucket': 'pickup',
      'wait_seconds': 30,
    });
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    expect(find.text('自'), findsOneWidget);
    expect(find.text('外'), findsNothing);
    expect(find.text('打'), findsNothing);
  });

  testWidgets('pack bucket renders 打 tag and overdue renders 超',
      (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'fulfillment_bucket': 'pack',
      'serving_duration_minutes': 10,
      'wait_seconds': 3600,
    });
    await tester.pumpWidget(_harness(KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [detail],
    )));

    expect(find.text('打'), findsOneWidget);
    expect(find.text('超'), findsOneWidget);
    expect(find.text('外'), findsNothing);
  });

  test(
      'order header uses table for dine_in and pickup code (cloud_order_id) for pickup/takeout',
      () {
    KdsV2LineSlice line(String channel, {int? cloudId, int orderId = 1}) =>
        KdsV2Line.fromJson({
          ..._canonicalPatch(),
          'order_id': orderId,
          'fulfillment_bucket': channel,
          'fulfillment_channel': channel,
          'table_number': '20',
          'order_no': 'ORD20260905',
          'cloud_order_id': cloudId,
        }).slices.first;
    expect(orderHeaderLabel(line('dine_in', cloudId: 99)), '20');
    expect(lineTableOrPickupCode(line('dine_in', cloudId: 99)), '20');

    for (final channel in ['pack', 'pickup']) {
      expect(orderHeaderLabel(line(channel, cloudId: 99)), '自提 99');
      // 无 cloud_order_id 时只显示渠道前缀，绝不使用本地收银 orderId (如 7)
      expect(orderHeaderLabel(line(channel, orderId: 7)), '自提');
      expect(orderHeaderLabel(line(channel), [line(channel, cloudId: 99)]),
          '自提 99');
      expect(
          orderHeaderLabel(
              line(channel), [line(channel, cloudId: 99, orderId: 2)]),
          '自提');
      expect(lineTableOrPickupCode(line(channel, cloudId: 99)), '自提 99');
      expect(lineTableOrPickupCode(line(channel)), '自提');
    }

    for (final channel in ['takeout', 'delivery']) {
      expect(orderHeaderLabel(line(channel, cloudId: 99)), '外卖 99');
      // 无 cloud_order_id 时只显示渠道前缀，绝不使用本地收银 orderId (如 8)
      expect(orderHeaderLabel(line(channel, orderId: 8)), '外卖');
      expect(orderHeaderLabel(line(channel), [line(channel, cloudId: 99)]),
          '外卖 99');
      expect(
          orderHeaderLabel(
              line(channel), [line(channel, cloudId: 99, orderId: 2)]),
          '外卖');
      expect(lineTableOrPickupCode(line(channel, cloudId: 99)), '外卖 99');
      expect(lineTableOrPickupCode(line(channel)), '外卖');
    }
  });

  testWidgets('order header shows cloud order id for pickup/takeout',
      (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'order_id': 13758,
      'cloud_order_id': 13758,
      'fulfillment_bucket': 'pack',
      'table_number': '打包台',
      'order_no': 'ORD20260905052010001',
    });
    await tester.pumpWidget(_harness(
      KdsV2State(
        connected: true,
        config: const {
          'allowed_commands': ['advance_item']
        },
        lines: [detail],
      ),
      isDishView: false,
    ));

    expect(find.text('自提 13758'), findsOneWidget);
    expect(find.textContaining('订单ID:'), findsNothing);
    expect(find.text('打包台'), findsNothing);
  });

  testWidgets('sold out catalog placeholder shows 估清', (tester) async {
    await tester.pumpWidget(_harness(const KdsV2State(
      connected: true,
      config: {'allowed_commands': <String>[]},
      catalog: [
        KdsV2CatalogItem(
            dishId: 1, dishName: '羊排', unit: '份', sequence: 0, soldOut: true),
      ],
    )));

    expect(find.text('估清'), findsOneWidget);
  });

  testWidgets('lack item marks catalog sold out and omits from_queue',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'lack_item', 'refund_item']
      },
      lines: [KdsV2Line.fromJson(_canonicalPatch())],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('缺货'));
    await tester.pumpAndSettle();

    // 估清闭环：同步标记目录售罄；rush/lack 类不下发 from_queue
    expect(notifier.lastType, KdsV2CommandType.lackItem);
    expect(notifier.lastSetSoldOut, isTrue);
    expect(notifier.lastTarget?.fromQueue, isNull);
    expect(notifier.lastExpectedRevision, 1);
  });

  testWidgets('refund keeps from_queue per contract', (tester) async {
    final notifier = _CapturingBoardNotifier();
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'refund_item']
      },
      lines: [KdsV2Line.fromJson(_canonicalPatch())],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退菜'));
    await tester.pumpAndSettle();

    // 退菜需二次确认（涉及金额，不可撤销）
    expect(find.text('确认退菜？'), findsOneWidget);
    expect(notifier.lastType, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '确认退菜'));
    await tester.pumpAndSettle();

    expect(notifier.lastType, KdsV2CommandType.refundItem);
    expect(notifier.lastTarget?.fromQueue, 'pending_cook');
    expect(notifier.lastSetSoldOut, isNull);
    // 成功反馈
    expect(find.text('已退菜 1 份 羊排'), findsOneWidget);
  });

  testWidgets('refund with multiple quantities asks count then confirms',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'refund_item']
      },
      lines: [
        KdsV2Line.fromJson({
          ..._canonicalPatch(),
          'line_quantity': 3,
          'cook_remaining': 3,
          'ready_remaining': 3,
        }),
      ],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退菜'));
    await tester.pumpAndSettle();

    // 多份先弹数量选择（退菜文案）
    expect(find.text('全部退 (3份)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认退 2 份'));
    await tester.pumpAndSettle();

    // 再二次确认
    expect(find.text('确认退菜？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认退菜'));
    await tester.pumpAndSettle();

    expect(notifier.lastType, KdsV2CommandType.refundItem);
    expect(notifier.lastQuantity, 2);
    expect(find.text('已退菜 2 份 羊排'), findsOneWidget);
  });

  testWidgets('refund cancelled at confirmation sends nothing', (tester) async {
    final notifier = _CapturingBoardNotifier();
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'refund_item']
      },
      lines: [KdsV2Line.fromJson(_canonicalPatch())],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退菜'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(notifier.lastType, isNull);
  });

  testWidgets('detail dialog cards follow the same card scale', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_state(), cardScale: 1.6));
    await tester.tap(find.text('详情>').first);
    await tester.pumpAndSettle();

    // 明细卡与看板卡片同尺寸：卡槽高 = 283 × 1.6
    final slot = tester.getRect(
        find.byKey(ValueKey('detail-wrap-${'A12'.hashCode & 0x7fffffff}')));
    expect(
        slot.height, moreOrLessEquals(KdsSpacing.cardHeight * 1.6, epsilon: 1));
    expect(slot.width, moreOrLessEquals(310 * 1.6, epsilon: 1));
  });

  testWidgets('detail dialog orders tables by earliest creation first',
      (tester) async {
    KdsV2Line lineAt(int detailId, String table, int createdAtMs) =>
        KdsV2Line.fromJson({
          ..._canonicalPatch(),
          'detail_id': detailId,
          'order_id': detailId,
          'table_number': table,
          'created_at_ms': createdAtMs,
          'wait_seconds': 121,
        });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [
        lineAt(2, 'A13', 2000), // 后下单
        lineAt(1, 'A12', 1000), // 先下单
      ],
    );
    final notifier = _CapturingBoardNotifier()..currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();

    // 先下单的 A12 排在 A13 前面（Wrap 从左到右）
    final firstX = tester
        .getTopLeft(find.descendant(
            of: find.byType(Dialog), matching: find.text('A12')))
        .dx;
    final secondX = tester
        .getTopLeft(find.descendant(
            of: find.byType(Dialog), matching: find.text('A13')))
        .dx;
    expect(firstX, lessThan(secondX));
  });

  testWidgets('detail advance disappears immediately while request is pending',
      (tester) async {
    final notifier = _BlockingBoardNotifier()..currentState = _state();
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: _state(),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('详情>').first);
    await tester.pumpAndSettle();
    expect(find.text('A12'), findsOneWidget);
    expect(find.text('A13'), findsOneWidget);

    // 单击明细卡直接推进，乐观隐藏
    await tester.tap(find.text('A12'));
    await tester.pump();

    expect(find.text('A12'), findsNothing);
    expect(find.text('A13'), findsOneWidget);
    expect(notifier.lastQuantity, 2);
    notifier.complete();
    await tester.pump();
  });

  testWidgets('done queue without fixed dish never renders placeholders',
      (tester) async {
    await tester.pumpWidget(
        _harness(_state(), queue: 'done', fixedDishOrderEnabled: false));
    expect(
        find.byKey(const ValueKey('placeholder-done-2:dine_in')), findsNothing);
  });

  testWidgets('done queue never merges same dish completion records',
      (tester) async {
    final first = KdsV2Line(
      detailId: 701,
      orderId: 70,
      dishId: 1,
      dishName: '羊排',
      quantity: 1,
      queue: 'done',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: {
        'table_number': 'A01',
        'completed_at_ms': 1000,
      },
    );
    final second = KdsV2Line(
      detailId: 702,
      orderId: 71,
      dishId: 1,
      dishName: '羊排',
      quantity: 1,
      queue: 'done',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: {
        'table_number': 'A02',
        'completed_at_ms': 2000,
      },
    );

    await tester.pumpWidget(_harness(
      _state().copyWith(lines: [first, second]),
      queue: 'done',
      fixedDishOrderEnabled: true,
      mergeSameDishNameEnabled: true,
    ));

    expect(find.byKey(const ValueKey('detail-card-done-701')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-card-done-702')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-group-done-羊排:dine_in')),
        findsNothing);
  });

  testWidgets('optimistic advance hides source card before server response',
      (tester) async {
    final state = _state().copyWith(
      optimisticHiddenSlices: {'${_state().lines.first.detailId}:pending_cook'},
    );
    await tester.pumpWidget(_harness(state));

    expect(find.text('A12'), findsNothing);
    expect(find.text('A13'), findsOneWidget);
  });

  testWidgets('fixed dish off renders FIFO details without merging',
      (tester) async {
    await tester.pumpWidget(_harness(_state(),
        fixedDishOrderEnabled: false, mergeSameDishNameEnabled: false));

    expect(
        find.byKey(
            ValueKey('detail-card-pending_cook-${_state().lines[0].detailId}')),
        findsOneWidget);
    expect(
        find.byKey(
            ValueKey('detail-card-pending_cook-${_state().lines[1].detailId}')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')),
        findsNothing);
  });

  testWidgets('non-fixed mode merges same dish names while ignoring specs',
      (tester) async {
    final first = _line(1, 'dine_in', table: 'A12');
    final second = _line(99, 'dine_in', table: 'A13')
        .withRawFields({'specification': '不辣'});
    await tester.pumpWidget(_harness(
      _state().copyWith(lines: [first, second]),
      fixedDishOrderEnabled: false,
      mergeSameDishNameEnabled: true,
    ));

    expect(find.byKey(const ValueKey('detail-group-pending_cook-羊排:dine_in')),
        findsOneWidget);
    expect(find.byKey(ValueKey('detail-card-pending_cook-${first.detailId}')),
        findsNothing);
    expect(find.byKey(ValueKey('detail-card-pending_cook-${second.detailId}')),
        findsNothing);
  });

  testWidgets(
      'fixed dish with dining filter (takeout) hides empty placeholders',
      (tester) async {
    await tester.pumpWidget(_harness(
      _state(),
      fixedDishOrderEnabled: true,
      dining: BoardDining.takeout,
    ));

    // 外卖卡片正常展示
    expect(find.byKey(const ValueKey('active-pending_cook-1:takeout')),
        findsOneWidget);
    // 堂食卡和未点菜品的空位占位卡被过滤隐藏
    expect(find.byKey(const ValueKey('active-pending_cook-1:dine_in')),
        findsNothing);
    expect(find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')),
        findsNothing);
  });

  testWidgets(
      'fixed dish with extra filter (rush) hides non-rush cards and placeholders',
      (tester) async {
    final rushed =
        _line(1, 'dine_in', table: 'A12').withRawFields({'rushed': true});
    final normal =
        _line(1, 'dine_in', table: 'A13').withRawFields({'rushed': false});
    await tester.pumpWidget(_harness(
      _state().copyWith(lines: [rushed, normal]),
      fixedDishOrderEnabled: true,
      extra: BoardExtraFilter.rush,
    ));

    expect(find.byKey(const ValueKey('active-pending_cook-1:dine_in')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('placeholder-pending_cook-2:dine_in')),
        findsNothing);
  });

  testWidgets('order view shows full order and strikes off-queue dishes',
      (tester) async {
    final cooking = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '油边王',
      'line_quantity': 2,
      'cook_remaining': 2,
      'ready_remaining': 2,
    });
    await tester.pumpWidget(_harness(
      KdsV2State(
        connected: true,
        lines: [cooking],
        orderDetails: [
          _orderDetail(detailId: 101, dishName: '油边王', quantity: 2),
          _orderDetail(
            detailId: 102,
            dishName: '拍黄瓜',
            quantity: 1,
            refunded: true,
          ),
        ],
      ),
      isDishView: false,
    ));

    expect(find.text('油边王'), findsOneWidget);
    final completedText = tester.widget<Text>(find.text('拍黄瓜'));
    expect(completedText.style?.decoration, TextDecoration.lineThrough);
    expect(completedText.style?.color, KdsOrderSpacing.lineMutedColor);
  });

  testWidgets(
      'one partial detail renders in three queues with slice quantities',
      (tester) async {
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 91,
      'order_id': 9,
      'dish_id': 1,
      'dish_name': '羊排',
      'fulfillment_bucket': 'dine_in',
      'local_revision': 8,
      'line_quantity': 4,
      'prep_remaining': 1,
      'cook_remaining': 3,
      'ready_remaining': 4,
      'done_quantity': 0,
      'table_number': 'B08',
    });
    final state = KdsV2State(
      connected: true,
      catalog: const [
        KdsV2CatalogItem(dishId: 1, dishName: '羊排', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );

    for (final queueAndQuantity in const [
      ('pending_prep', 1),
      ('pending_cook', 2),
      ('ready_serve', 1),
    ]) {
      await tester.pumpWidget(_harness(state, queue: queueAndQuantity.$1));
      expect(find.byKey(ValueKey('active-${queueAndQuantity.$1}-1:dine_in')),
          findsOneWidget);
      expect(find.text('${queueAndQuantity.$2}份'), findsOneWidget);
    }
  });

  testWidgets('single-line card advance uses detail revision contract',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 91,
      'order_id': 9,
      'dish_id': 1,
      'dish_name': '羊排',
      'fulfillment_bucket': 'dine_in',
      'local_revision': 8,
      'line_quantity': 4,
      'prep_remaining': 1,
      'cook_remaining': 3,
      'ready_remaining': 4,
      'done_quantity': 0,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      catalog: const [
        KdsV2CatalogItem(dishId: 1, dishName: '羊排', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('2份'));
    await tester.pump();

    expect(notifier.lastTarget?.detailId, 91);
    expect(notifier.lastTarget?.detailIds, isEmpty);
    expect(notifier.lastTarget?.fromQueue, 'pending_cook');
    expect(notifier.lastQuantity, 2);
    expect(notifier.lastExpectedRevision, 8);
    expect(notifier.lastExpectedRevisions, isEmpty);
  });

  testWidgets('multi-line card advance keeps merged revision contract',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final first = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 91,
      'order_id': 9,
      'local_revision': 8,
      'line_quantity': 2,
      'prep_remaining': 0,
      'cook_remaining': 2,
      'ready_remaining': 2,
      'created_at_ms': 1720000000000,
    });
    final second = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 92,
      'order_id': 10,
      'local_revision': 9,
      'line_quantity': 1,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'created_at_ms': 1720000001000,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [first, second],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('3份'));
    await tester.pump();

    expect(notifier.lastTarget?.detailId, isNull);
    expect(notifier.lastTarget?.detailIds, [91, 92]);
    expect(notifier.lastQuantity, 3);
    expect(notifier.lastExpectedRevision, isNull);
    expect(notifier.lastExpectedRevisions, {91: 8, 92: 9});
  });

  testWidgets('order actions use order_revision instead of line revision',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 91,
      'order_id': 9,
      'dish_id': 1,
      'dish_name': '羊排',
      'local_revision': 8,
      'order_revision': 42,
      'table_number': 'B08',
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'complete_order']
      },
      catalog: const [
        KdsV2CatalogItem(dishId: 1, dishName: '羊排', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );
    notifier.currentState = state;

    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成整单'));
    await tester.pumpAndSettle();

    expect(find.text('确认强制完成整单？'), findsOneWidget);
    expect(notifier.lastType, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '确认完成'));
    await tester.pumpAndSettle();

    expect(notifier.lastType, KdsV2CommandType.completeOrder);
    expect(notifier.lastTarget?.orderId, 9);
    expect(notifier.lastTarget?.detailId, isNull);
    expect(notifier.lastExpectedRevision, 42);

    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text('B08'),
    ));
    await tester.pump();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastTarget?.detailId, 91);
    expect(notifier.lastExpectedRevision, 8);
  });

  testWidgets('held dish group cannot be advanced as a whole', (tester) async {
    final notifier = _CapturingBoardNotifier();
    final held = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'held': true,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'release_item']
      },
      lines: [held],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('dish-group-advance-1:dine_in')));
    await tester.pump();
    expect(notifier.lastType, isNull);
    expect(find.text('该菜品处于等叫状态，请先点击【起菜】后再制作！'), findsOneWidget);
  });

  testWidgets('scaled-down cards fill grid cells and more columns fit',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _state();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kdsV2BoardProvider.overrideWith(
            () => _CapturingBoardNotifier()..currentState = state),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: KdsV2QueueColumn(
            queue: 'pending_cook',
            label: '待制作',
            state: state,
            cardScale: 0.7,
          ),
        ),
      ),
    ));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    // 1200 宽、0.7 缩放：每行 5 列（默认 1.0 时 3 列）
    expect(delegate.crossAxisCount, 5);

    // 卡片绘制尺寸铺满格子（不因变换被二次缩小）
    final rect = tester
        .getRect(find.byKey(const ValueKey('active-pending_cook-1:dine_in')));
    final cellWidth = (1200 - 20 - 4 * 10) / 5;
    expect(rect.width, moreOrLessEquals(cellWidth, epsilon: 1));
    expect(
        rect.height, moreOrLessEquals(KdsSpacing.cardHeight * 0.7, epsilon: 1));
  });

  testWidgets('card scale adjusts grid card height and column width',
      (tester) async {
    double extentOf(double scale) {
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.mainAxisExtent!;
    }

    await tester.pumpWidget(_harness(_state()));
    expect(extentOf(1.0), KdsSpacing.cardHeight);

    await tester.pumpWidget(_harness(_state(), cardScale: 1.6));
    expect(extentOf(1.6), KdsSpacing.cardHeight * 1.6);

    await tester.pumpWidget(_harness(_state(), cardScale: 0.7));
    expect(extentOf(0.7), KdsSpacing.cardHeight * 0.7);
  });

  testWidgets('order card sorts active lines before done and strikes done',
      (tester) async {
    // 油边王 2 份全做完（不在当前队列），拍黄瓜 1 份在待制作
    final doneLine = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '油边王',
      'line_quantity': 2,
      'cook_remaining': 0,
      'ready_remaining': 0,
      'created_at_ms': 1720000000000,
    });
    final activeLine = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 102,
      'order_id': 77,
      'dish_id': 2,
      'dish_name': '拍黄瓜',
      'created_at_ms': 1720000001000,
    });
    await tester.pumpWidget(_harness(
      KdsV2State(
        connected: true,
        config: const {
          'allowed_commands': ['advance_order']
        },
        lines: [doneLine, activeLine],
        orderDetails: [
          _orderDetail(detailId: 101, dishName: '油边王', quantity: 2),
          _orderDetail(detailId: 102, dishName: '拍黄瓜', quantity: 1),
        ],
      ),
      isDishView: false,
    ));

    // 未划的拍黄瓜排在已划的油边王之上
    final activeY = tester.getTopLeft(find.text('拍黄瓜')).dy;
    final doneY = tester.getTopLeft(find.text('油边王')).dy;
    expect(activeY, lessThan(doneY));

    // 已划行灰色删除线
    final doneText = tester.widget<Text>(find.text('油边王'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
    expect(doneText.style?.color, KdsOrderSpacing.lineMutedColor);

    // 传菜进度：共 3 份活跃，已传 2
    expect(find.text('已传2/3'), findsOneWidget);
  });

  testWidgets('order view shows current queue quantity after partial advance',
      (tester) async {
    final partiallyAdvanced = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '羊肉串',
      'unit': '串',
      'line_quantity': 2,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 2,
      'local_revision': 9,
    });
    final orderDetail = KdsV2OrderDetail.fromJson({
      'order_id': 77,
      'order_no': 'O-77',
      'table_number': 'A12',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': 101,
      'dish_id': 101,
      'dish_name': '羊肉串',
      'specification': '',
      'unit': '串',
      'quantity': 2,
      'refunded_quantity': 0,
      'remaining_quantity': 2,
      'status': 'active',
      'removed': false,
      'remark': '',
    });

    await tester.pumpWidget(_harness(
      KdsV2State(
        connected: true,
        config: const {
          'allowed_commands': ['advance_item', 'advance_order']
        },
        lines: [partiallyAdvanced],
        orderDetails: [orderDetail],
      ),
      isDishView: false,
    ));

    expect(find.text('1串'), findsOneWidget);
    expect(find.text('2串'), findsNothing);
  });

  testWidgets('order line tap advances that line like the dish dimension',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final lineA = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '油边王',
      'line_quantity': 2,
      'cook_remaining': 2,
      'ready_remaining': 2,
      'local_revision': 8,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item', 'advance_order']
      },
      lines: [lineA],
      orderDetails: [
        _orderDetail(detailId: 101, dishName: '油边王', quantity: 2),
      ],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
              isDishView: false,
            ),
          ),
        ),
      ),
    ));

    // 单击菜品行：直接推进该行（detailId + from_queue + 行 revision）
    await tester.tap(find.text('油边王'));
    await tester.pump();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastTarget?.detailId, 101);
    expect(notifier.lastTarget?.fromQueue, 'pending_cook');
    expect(notifier.lastExpectedRevision, 8);
    expect(notifier.lastQuantity, 2);
  });

  testWidgets('order line tap sends only the current queue quantity',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final partiallyReady = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 201,
      'order_id': 77,
      'dish_name': '牛肉串',
      'line_quantity': 2,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 2,
      'local_revision': 11,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [partiallyReady],
      orderDetails: [
        _orderDetail(detailId: 201, dishName: '牛肉串', quantity: 2),
      ],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
              isDishView: false,
            ),
          ),
        ),
      ),
    ));

    expect(find.text('1份'), findsOneWidget);
    expect(find.text('2份'), findsNothing);
    await tester.tap(find.text('牛肉串'));
    await tester.pump();

    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastTarget?.detailId, 201);
    expect(notifier.lastTarget?.fromQueue, 'pending_cook');
    expect(notifier.lastQuantity, 1);
    expect(notifier.lastExpectedRevision, 11);
  });

  testWidgets('order line long press opens the quantity dialog',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final lineA = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '油边王',
      'line_quantity': 3,
      'cook_remaining': 3,
      'ready_remaining': 3,
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      lines: [lineA],
      orderDetails: [
        _orderDetail(detailId: 101, dishName: '油边王', quantity: 3),
      ],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
              isDishView: false,
            ),
          ),
        ),
      ),
    ));

    await tester.longPress(find.text('油边王'));
    await tester.pumpAndSettle();
    expect(find.text('全部划出 (3份)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认划出 2 份'));
    await tester.pumpAndSettle();
    expect(notifier.lastType, KdsV2CommandType.advanceItem);
    expect(notifier.lastQuantity, 2);
  });

  testWidgets('order card height adapts to its line count', (tester) async {
    KdsV2Line lineOf(int orderId, int detailId, String dishName) =>
        KdsV2Line.fromJson({
          ..._canonicalPatch(),
          'detail_id': detailId,
          'order_id': orderId,
          'dish_id': detailId,
          'dish_name': dishName,
        });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_order']
      },
      lines: [
        lineOf(101, 1001, '单行菜'),
        lineOf(102, 1002, '多行菜一'),
        lineOf(102, 1003, '多行菜二'),
        lineOf(102, 1004, '多行菜三'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 1200,
          child: KdsV2QueueColumn(
            queue: 'pending_cook',
            label: '待制作',
            state: state,
            isDishView: false,
          ),
        ),
      ),
    ));

    final singleLine =
        tester.getSize(find.byKey(const ValueKey('order-card-101')));
    final multiLine =
        tester.getSize(find.byKey(const ValueKey('order-card-102')));
    expect(multiLine.height, greaterThan(singleLine.height));

    // 卡片列间有间隔，不贴在一起
    final singleRect =
        tester.getRect(find.byKey(const ValueKey('order-card-101')));
    final multiRect =
        tester.getRect(find.byKey(const ValueKey('order-card-102')));
    expect(multiRect.left - singleRect.right, greaterThanOrEqualTo(10));
  });

  testWidgets('order advance delegates to per-line advance for that order',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    // 打包/外卖单加菜后各行 revision 不一致：逐明细推进按行 revision
    // 做乐观锁，不再依赖整单 order_revision
    final older = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 91,
      'order_id': 9,
      'order_revision': 3,
      'fulfillment_bucket': 'pickup',
      'table_number': '自提A101',
    });
    final newer = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 92,
      'order_id': 9,
      'dish_id': 2,
      'dish_name': '鸡翅',
      'order_revision': 7,
      'fulfillment_bucket': 'pickup',
      'table_number': '自提A101',
    });
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_order']
      },
      lines: [older, newer],
    );
    notifier.currentState = state;
    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'pending_cook',
              label: '待制作',
              state: state,
              isDishView: false,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('整单制作'));
    await tester.pump();

    // 整单推进 = 逐明细推进：只推该订单当前队列的行
    expect(notifier.advanceOrderId, 9);
    expect(notifier.advanceFromQueue, 'pending_cook');
    expect(notifier.lastType, isNull);
  });

  testWidgets('order card shows order-level rush tag from order_details',
      (tester) async {
    final cooking = KdsV2Line.fromJson({
      ..._canonicalPatch(),
      'detail_id': 101,
      'order_id': 77,
      'dish_name': '油边王',
      'line_quantity': 2,
      'cook_remaining': 2,
      'ready_remaining': 2,
    });
    await tester.pumpWidget(_harness(
      KdsV2State(
        connected: true,
        lines: [cooking],
        orderDetails: [
          _orderDetail(
              detailId: 101, dishName: '油边王', quantity: 2, orderRushed: true),
        ],
      ),
      isDishView: false,
    ));

    // 整单催菜标记显示在订单卡头部
    expect(find.text('催'), findsOneWidget);
  });

  testWidgets('archive order is exposed only from the done queue',
      (tester) async {
    final detail = KdsV2Line.fromJson(_canonicalPatch());
    Future<void> pumpQueue(String queue) {
      final state = KdsV2State(
        connected: true,
        config: const {
          'allowed_commands': ['archive_order']
        },
        lines: [detail],
      );
      return tester.pumpWidget(ProviderScope(
        overrides: [
          kdsV2BoardProvider.overrideWith(
              () => _CapturingBoardNotifier()..currentState = state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 800,
              child: KdsV2QueueColumn(
                queue: queue,
                label: queue,
                state: state,
              ),
            ),
          ),
        ),
      ));
    }

    await pumpQueue('pending_cook');
    await tester.tap(find.text('详情>'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<KdsV2CommandType>));
    await tester.pumpAndSettle();
    expect(find.text('归档整单'), findsNothing);
  });

  testWidgets(
      'done queue card renders fixed completion duration and gray header',
      (tester) async {
    final nowMs = 1700000000000;
    final createdMs = nowMs - (8 * 60 * 1000);
    final completedMs = nowMs;
    final detail = KdsV2Line(
      detailId: 901,
      orderId: 90,
      dishId: 1,
      dishName: '烤鱼',
      quantity: 1,
      queue: 'done',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: {
        'detail_id': 901,
        'order_id': 90,
        'dish_id': 1,
        'dish_name': '烤鱼',
        'table_number': 'A01',
        'created_at_ms': createdMs,
        'completed_at_ms': completedMs,
        'completed_wait_seconds': 480,
      },
    );
    final state = KdsV2State(
      connected: true,
      catalog: const [
        KdsV2CatalogItem(dishId: 1, dishName: '烤鱼', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );

    await tester.pumpWidget(_harness(state, queue: 'done'));
    expect(find.text('8分钟'), findsOneWidget);
    expect(find.text('A01'), findsOneWidget);
  });

  testWidgets('done queue keeps manual revoke available after quick undo expires',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line(
      detailId: 901,
      orderId: 90,
      dishId: 1,
      dishName: '烤鱼',
      quantity: 1,
      queue: 'done',
      fulfillmentBucket: 'dine_in',
      revision: 7,
      raw: const {
        'detail_id': 901,
        'order_id': 90,
        'dish_id': 1,
        'dish_name': '烤鱼',
        'table_number': 'A01',
      },
    );
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['revoke_item']
      },
      lines: [detail],
    );
    notifier.currentState = state;

    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'done',
              label: '已完成',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('回撤'));
    await tester.pumpAndSettle();

    // 弹出数量选择弹窗，点击确认回撤
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(notifier.lastType, KdsV2CommandType.revokeItem);
    expect(notifier.lastTarget?.detailId, 901);
    expect(notifier.lastTarget?.fromQueue, 'done');
    expect(notifier.lastQuantity, 1);
    expect(notifier.lastExpectedRevision, 7);
  });

  testWidgets(
      'done queue revoke with multiple quantity opens quantity dialog and revokes selected amount',
      (tester) async {
    final notifier = _CapturingBoardNotifier();
    final detail = KdsV2Line(
      detailId: 905,
      orderId: 95,
      dishId: 5,
      dishName: '烤羊肉串',
      quantity: 5,
      queue: 'done',
      fulfillmentBucket: 'dine_in',
      revision: 3,
      raw: const {
        'detail_id': 905,
        'order_id': 95,
        'dish_id': 5,
        'dish_name': '烤羊肉串',
        'table_number': 'A08',
        'unit': '串',
      },
    );
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['revoke_item']
      },
      lines: [detail],
    );
    notifier.currentState = state;

    await tester.pumpWidget(ProviderScope(
      overrides: [kdsV2BoardProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: 'done',
              label: '已完成',
              state: state,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('回撤'));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('烤羊肉串')),
        findsOneWidget);
    expect(find.text('当前共 5 串，请选择回撤数量'), findsOneWidget);

    // 选中 2 串
    await tester.tap(find.text('2 串'));
    await tester.pumpAndSettle();

    // 确认回撤
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(notifier.lastType, KdsV2CommandType.revokeItem);
    expect(notifier.lastTarget?.detailId, 905);
    expect(notifier.lastQuantity, 2);
  });

  testWidgets(
      'dish card header title wraps in FittedBox for adaptive font scaling',
      (tester) async {
    final detail = KdsV2Line(
      detailId: 906,
      orderId: 96,
      dishId: 6,
      dishName: '大盘鸡',
      quantity: 1,
      queue: 'pending_cook',
      fulfillmentBucket: 'pack',
      revision: 1,
      raw: const {
        'detail_id': 906,
        'order_id': 96,
        'dish_id': 6,
        'dish_name': '大盘鸡',
        'cloud_order_id': 202610050012,
        'channel': 'pack',
      },
    );
    final state = KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      catalog: const [
        KdsV2CatalogItem(dishId: 6, dishName: '大盘鸡', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );

    await tester.pumpWidget(_harness(state));
    await tester.pumpAndSettle();

    final fittedBox = tester.widget<FittedBox>(find.descendant(
      of: find.byType(Card),
      matching: find.byType(FittedBox),
    ).first);
    expect(fittedBox.fit, BoxFit.scaleDown);
    expect(find.text('自提 202610050012'), findsOneWidget);
  });

  testWidgets(
      'disconnected state keeps board operational without disruptive red banner',
      (tester) async {
    final detail = KdsV2Line(
      detailId: 902,
      orderId: 92,
      dishId: 2,
      dishName: '宫保鸡丁',
      quantity: 1,
      queue: 'pending_cook',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: {
        'detail_id': 902,
        'order_id': 92,
        'dish_id': 2,
        'dish_name': '宫保鸡丁',
        'table_number': 'B02',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final state = KdsV2State(
      connected: false, // 断网状态
      pendingSyncCount: 1, // 1 条离线操作待同步
      catalog: const [
        KdsV2CatalogItem(dishId: 2, dishName: '宫保鸡丁', unit: '份', sequence: 0),
      ],
      lines: [detail],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kdsV2BoardProvider.overrideWith(
              () => _CapturingBoardNotifier()..currentState = state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(
              state: state,
              workflows: const [],
            ),
          ),
        ),
      ),
    );

    // 菜品卡片正常显示
    expect(find.text('宫保鸡丁'), findsWidgets);

    // 绝对不显示过去的阻塞锁定红色条
    expect(find.textContaining('所有操作已锁定'), findsNothing);
    expect(find.textContaining('局域网连接已断开'), findsNothing);

    // 显示不占布局高度的待同步状态提示
    expect(
      find.byKey(const ValueKey('pending-sync-floating-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('pending sync indicator does not shift the card grid vertically',
      (tester) async {
    final online = _state();

    Future<void> pumpBoard(KdsV2State state) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: KdsV2ThreeFlowBoard(
                state: state,
                workflows: const [KdsWorkflow.cook],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpBoard(online);
    final card = find.byKey(
      const ValueKey('active-pending_cook-1:dine_in'),
    );
    final cardTopBefore = tester.getTopLeft(card).dy;

    await pumpBoard(online.copyWith(pendingSyncCount: 1));
    final cardTopWhileSyncing = tester.getTopLeft(card).dy;

    expect(cardTopWhileSyncing, cardTopBefore);
    expect(
      find.byKey(const ValueKey('pending-sync-floating-indicator')),
      findsOneWidget,
    );
    expect(find.text('正在同步 1 项'), findsOneWidget);
    expect(find.textContaining('离线运行中'), findsNothing);
  });

  testWidgets('both channels unavailable shows a pinned non-blocking warning',
      (tester) async {
    final state = KdsV2State(
      connected: false,
      allChannelsUnavailable: true,
      catalog: const [
        KdsV2CatalogItem(dishId: 2, dishName: '宫保鸡丁', unit: '份', sequence: 0),
      ],
      lines: [
        KdsV2Line(
          detailId: 902,
          orderId: 92,
          dishId: 2,
          dishName: '宫保鸡丁',
          quantity: 1,
          queue: 'pending_cook',
          fulfillmentBucket: 'dine_in',
          revision: 1,
          raw: const {'detail_id': 902, 'order_id': 92, 'dish_id': 2},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kdsV2BoardProvider.overrideWith(
              () => _CapturingBoardNotifier()..currentState = state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(state: state, workflows: const []),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('all-channels-offline-banner')),
        findsOneWidget);
    expect(find.textContaining('云端和局域网均不可用'), findsOneWidget);
    expect(find.text('宫保鸡丁'), findsWidgets);
    expect(find.textContaining('所有操作已锁定'), findsNothing);
  });

  testWidgets('stale cloud snapshot displays an explicit non-blocking warning',
      (tester) async {
    final state = KdsV2State(
      isStale: true,
      cacheAgeSeconds: 37,
      servedVia: 'lan-cache',
      connected: false,
      catalog: const [
        KdsV2CatalogItem(dishId: 3, dishName: '缓存菜品', unit: '份', sequence: 0),
      ],
      lines: [
        KdsV2Line(
          detailId: 903,
          orderId: 93,
          dishId: 3,
          dishName: '缓存菜品',
          quantity: 1,
          queue: 'pending_cook',
          fulfillmentBucket: 'dine_in',
          revision: 1,
          raw: const {
            'detail_id': 903,
            'order_id': 93,
            'dish_id': 3,
            'dish_name': '缓存菜品',
            'table_number': 'C03',
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kdsV2BoardProvider.overrideWith(
              () => _CapturingBoardNotifier()..currentState = state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: KdsV2ThreeFlowBoard(state: state, workflows: const []),
          ),
        ),
      ),
    );

    expect(find.textContaining('正在展示 37 秒前的缓存数据'), findsOneWidget);
    expect(find.textContaining('操作将进入待确认队列'), findsOneWidget);
    expect(find.text('缓存菜品'), findsWidgets);
  });

  testWidgets(
      'overlay status does not pollute dish tags and is displayed as subtle indicator in card',
      (tester) async {
    final line = KdsV2Line(
      detailId: 904,
      orderId: 94,
      dishId: 4,
      dishName: '待传烤羊排',
      quantity: 1,
      queue: 'pending_cook',
      fulfillmentBucket: 'dine_in',
      revision: 1,
      raw: const {
        'detail_id': 904,
        'order_id': 94,
        'dish_id': 4,
        'dish_name': '待传烤羊排',
        'table_number': 'C04',
      },
      optimisticQueues: const {
        'pending_cook': KdsOverlayStatus.pending,
      },
    );
    final state = KdsV2State(
      connected: true,
      lines: [line],
      catalog: const [
        KdsV2CatalogItem(dishId: 4, dishName: '待传烤羊排', unit: '份', sequence: 0),
      ],
    );

    await tester.pumpWidget(_harness(state, queue: 'pending_cook'));

    // 菜品名称正常展示
    expect(find.text('待传烤羊排'), findsWidgets);
    // 待同步作为弱化角标/小字展示，不作为菜品标签阻断业务
    expect(find.text('待同步'), findsWidgets);
  });
}

KdsV2OrderDetail _orderDetail({
  required int detailId,
  required String dishName,
  required int quantity,
  bool refunded = false,
  bool orderRushed = false,
}) =>
    KdsV2OrderDetail.fromJson({
      'order_id': 77,
      'order_no': 'O-77',
      'table_number': 'A12',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': detailId,
      'dish_id': detailId,
      'dish_name': dishName,
      'specification': '',
      'unit': '份',
      'quantity': quantity,
      'refunded_quantity': refunded ? quantity : 0,
      'remaining_quantity': refunded ? 0 : quantity,
      'status': refunded ? 'refunded' : 'active',
      'removed': refunded,
      'order_rushed': orderRushed,
      'remark': '',
    });

Map<String, dynamic> _canonicalPatch() => {
      'detail_id': 91,
      'order_id': 9,
      'dish_id': 1,
      'dish_name': '羊排',
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': 1,
      'order_revision': 1,
      'workflow_queue': 'pending_cook',
      'fulfillment_bucket': 'dine_in',
      'table_number': 'B08',
      'order_no': 'O-9',
      'specification': null,
      'unit': '份',
      'remark': null,
      'created_at_ms': 1720000000000,
      'wait_seconds': 121,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    };

class _CapturingBoardNotifier extends KdsV2BoardNotifier {
  KdsV2CommandType? lastType;
  KdsV2CommandTarget? lastTarget;
  int? lastQuantity;
  int? lastExpectedRevision;
  bool? lastSetSoldOut;
  Map<int, int>? lastExpectedRevisions;

  /// 供给明细弹窗等直接监听 provider 的组件；测试可用其模拟权威状态推进
  KdsV2State currentState = const KdsV2State();

  @override
  KdsV2State build() => currentState;

  /// 模拟服务端 ACK/patch 推进权威状态并通知监听方
  void emitState(KdsV2State next) {
    currentState = next;
    state = next;
  }

  @override
  Future<void> send({
    required KdsV2CommandType type,
    required KdsV2CommandTarget target,
    int? quantity,
    int? expectedRevision,
    String? remark,
    bool? setSoldOut,
    Map<int, int> expectedRevisions = const {},
  }) async {
    lastType = type;
    lastTarget = target;
    lastQuantity = quantity;
    lastExpectedRevision = expectedRevision;
    lastSetSoldOut = setSoldOut;
    lastExpectedRevisions = expectedRevisions;
  }

  int? advanceOrderId;
  String? advanceFromQueue;

  @override
  Future<int> advanceOrderLines({
    required int orderId,
    required String fromQueue,
    bool includePrep = false,
  }) async {
    advanceOrderId = orderId;
    advanceFromQueue = fromQueue;
    return 1;
  }
}

class _BlockingBoardNotifier extends _CapturingBoardNotifier {
  final Completer<void> _completer = Completer<void>();

  @override
  Future<void> send({
    required KdsV2CommandType type,
    required KdsV2CommandTarget target,
    int? quantity,
    int? expectedRevision,
    String? remark,
    bool? setSoldOut,
    Map<int, int> expectedRevisions = const {},
  }) async {
    await super.send(
      type: type,
      target: target,
      quantity: quantity,
      expectedRevision: expectedRevision,
      remark: remark,
      setSoldOut: setSoldOut,
      expectedRevisions: expectedRevisions,
    );
    return _completer.future;
  }

  void complete() => _completer.complete();
}

Widget _harness(
  KdsV2State state, {
  String queue = 'pending_cook',
  bool fixedDishOrderEnabled = true,
  bool mergeSameDishNameEnabled = true,
  bool isDishView = true,
  double cardScale = 1.0,
  BoardDining dining = BoardDining.all,
  BoardExtraFilter? extra,
}) =>
    ProviderScope(
      // 明细弹窗直接监听 provider，覆盖并注入同一状态源
      overrides: [
        kdsV2BoardProvider.overrideWith(
            () => _CapturingBoardNotifier()..currentState = state),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 800,
            child: KdsV2QueueColumn(
              queue: queue,
              label: '待制作',
              state: state,
              dining: dining,
              extra: extra,
              fixedDishOrderEnabled: fixedDishOrderEnabled,
              mergeSameDishNameEnabled: mergeSameDishNameEnabled,
              isDishView: isDishView,
              cardScale: cardScale,
            ),
          ),
        ),
      ),
    );

KdsV2State _state() => KdsV2State(
      connected: true,
      config: const {
        'allowed_commands': ['advance_item']
      },
      catalog: const [
        KdsV2CatalogItem(dishId: 1, dishName: '羊排', unit: '份', sequence: 0),
        KdsV2CatalogItem(dishId: 2, dishName: '鸡翅', unit: '份', sequence: 1),
      ],
      lines: [
        _line(1, 'dine_in', table: 'A12'),
        _line(1, 'dine_in', table: 'A13'),
        _line(1, 'takeout', table: '外卖1'),
      ],
    );

KdsV2Line _line(int dishId, String bucket, {required String table}) =>
    KdsV2Line(
      detailId: table.hashCode & 0x7fffffff,
      orderId: 5,
      dishId: dishId,
      dishName: '羊排',
      quantity: 2,
      queue: 'pending_cook',
      fulfillmentBucket: bucket,
      revision: 3,
      raw: {
        'table_number': table,
        'specification': '微辣',
        'wait_seconds': 121,
      },
    );
