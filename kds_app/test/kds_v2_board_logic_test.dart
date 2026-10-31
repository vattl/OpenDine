import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/board/kds_line_wait_time.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_logic.dart';
import 'package:kds_app/features/board_v2/kds_undo_toast.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';

void main() {
  group('kdsCardHeaderColor', () {
    test('default dine-in header is dark gray', () {
      expect(
        kdsCardHeaderColor(
            overdue: false,
            rushed: false,
            held: false,
            addDish: false,
            combo: false,
            channel: 'dine_in'),
        KdsColors.headerDefault,
      );
    });

    test('overdue and rushed are red, and win over other states', () {
      for (final (overdue, rushed) in const [(true, false), (false, true)]) {
        expect(
          kdsCardHeaderColor(
              overdue: overdue,
              rushed: rushed,
              held: true,
              addDish: true,
              combo: true,
              channel: 'takeout'),
          KdsColors.headerOverdue,
        );
      }
    });

    test('held purple beats add-dish blue; add-dish beats channel green', () {
      expect(
        kdsCardHeaderColor(
            overdue: false,
            rushed: false,
            held: true,
            addDish: true,
            combo: false,
            channel: 'takeout'),
        KdsColors.headerHold,
      );
      expect(
        kdsCardHeaderColor(
            overdue: false,
            rushed: false,
            held: false,
            addDish: true,
            combo: false,
            channel: 'pickup'),
        KdsColors.headerAddDish,
      );
    });

    test('pickup and takeout channels are green, pack is dark green', () {
      for (final channel in const ['pickup', 'takeout', 'delivery']) {
        expect(
          kdsCardHeaderColor(
              overdue: false,
              rushed: false,
              held: false,
              addDish: false,
              combo: false,
              channel: channel),
          KdsColors.headerTakeout,
        );
      }
      expect(
        kdsCardHeaderColor(
            overdue: false,
            rushed: false,
            held: false,
            addDish: false,
            combo: false,
            channel: 'pack'),
        KdsColors.headerPack,
      );
    });
  });
  test('fixed catalog follows category then dish order with stable id fallback',
      () {
    final catalog = [
      const KdsV2CatalogItem(
        dishId: 30,
        dishName: '鸡翅',
        unit: '串',
        sequence: 1,
        categoryId: 2,
        categoryName: '串类',
        categorySequence: 1,
      ),
      const KdsV2CatalogItem(
        dishId: 20,
        dishName: '油边王',
        unit: '串',
        sequence: 0,
        categoryId: 2,
        categoryName: '串类',
        categorySequence: 1,
      ),
      const KdsV2CatalogItem(
        dishId: 10,
        dishName: '凉菜',
        unit: '份',
        sequence: 0,
        categoryId: 1,
        categoryName: '凉菜',
        categorySequence: 0,
      ),
      const KdsV2CatalogItem(
        dishId: 19,
        dishName: '同序菜品',
        unit: '串',
        sequence: 0,
        categoryId: 2,
        categoryName: '串类',
        categorySequence: 1,
      ),
    ]..sort(compareKdsCatalogItems);

    expect(catalog.map((item) => item.dishId), [10, 19, 20, 30]);
  });

  test(
      'fixed catalog sorts by catalog id when present, ignoring duplicates '
      'in legacy sequence fields', () {
    final catalog = [
      const KdsV2CatalogItem(
        id: 3,
        dishId: 30,
        dishName: '鸡翅',
        unit: '串',
        sequence: 0,
        categoryId: 2,
        categoryName: '串类',
        categorySequence: 1,
      ),
      const KdsV2CatalogItem(
        id: 1,
        dishId: 10,
        dishName: '凉菜',
        unit: '份',
        sequence: 0,
        categoryId: 1,
        categoryName: '凉菜',
        categorySequence: 0,
      ),
      const KdsV2CatalogItem(
        id: 2,
        dishId: 20,
        dishName: '油边王',
        unit: '串',
        sequence: 0,
        categoryId: 2,
        categoryName: '串类',
        categorySequence: 1,
      ),
    ]..sort(compareKdsCatalogItems);

    // 排序字段重复/冲突时以 id 为唯一依据
    expect(catalog.map((item) => item.dishId), [10, 20, 30]);
  });

  test('catalog item parses id and catalog_id alias', () {
    final byId = KdsV2CatalogItem.fromJson(const {
      'id': 7,
      'dish_id': 88,
      'dish_name': '油边王',
      'unit': '串',
    });
    final byAlias = KdsV2CatalogItem.fromJson(const {
      'catalog_id': 9,
      'dish_id': 88,
      'dish_name': '油边王',
      'unit': '串',
    });
    final legacy = KdsV2CatalogItem.fromJson(const {
      'dish_id': 88,
      'dish_name': '油边王',
      'unit': '串',
    });
    expect(byId.id, 7);
    expect(byAlias.id, 9);
    expect(legacy.id, 0);
  });

  test('order projection includes full order and marks off-queue dishes', () {
    final lines = [
      _line(
        detailId: 1,
        dishName: '油边王',
        prep: 0,
        cook: 2,
        ready: 2,
      ),
      _line(
        detailId: 2,
        dishName: '拍黄瓜',
        prep: 0,
        cook: 0,
        ready: 0,
      ),
    ];

    final display = projectOrderDetails(
      lines: lines,
      orderId: 7,
      currentQueue: 'pending_cook',
    );

    expect(display.map((line) => line.dishName), ['油边王', '拍黄瓜']);
    expect(display.map((line) => line.isInCurrentQueue), [true, false]);
    expect(display.map((line) => line.quantity), [2, 1]);
  });

  test(
      'order projection retains refunded details removed from operational pool',
      () {
    final active = _line(
      detailId: 1,
      dishName: '油边王',
      prep: 0,
      cook: 2,
      ready: 2,
    );
    final display = projectOrderDetails(
      lines: [active],
      orderDetails: [
        _orderDetail(detailId: 1, dishName: '油边王', quantity: 2),
        _orderDetail(
          detailId: 2,
          dishName: '拍黄瓜',
          quantity: 1,
          refunded: true,
        ),
      ],
      orderId: 7,
      currentQueue: 'pending_cook',
    );

    expect(display.map((line) => line.dishName), ['油边王', '拍黄瓜']);
    expect(display.map((line) => line.isInCurrentQueue), [true, false]);
    expect(display.last.quantity, 1);
    expect(display.last.removed, isTrue);
  });

  test(
      'order projection keeps its dish serving duration without an active line',
      () {
    final display = projectOrderDetails(
      lines: const [],
      orderDetails: [
        _orderDetail(
          detailId: 2,
          dishName: '拍黄瓜',
          quantity: 1,
          servingDurationMinutes: 6,
        ),
      ],
      orderId: 7,
      currentQueue: 'pending_cook',
    );

    expect(KdsLineWaitTime.servingDurationMinutes(display.single.raw), 6);
  });

  test('order projection resolves spec and taste text per line', () {
    // 权威行 raw 带 selectedSpicy 时优先；无权威行时回退
    // order_details.specification（JSON 规格只显示可读值）
    final lines = [
      _line(
        detailId: 1,
        dishName: '油边王',
        prep: 0,
        cook: 2,
        ready: 2,
      ),
    ];
    final display = projectOrderDetails(
      lines: lines,
      orderDetails: [
        _orderDetail(
          detailId: 1,
          dishName: '油边王',
          quantity: 2,
          specification: '{"辣度":"微辣","成熟度":"9成熟"}',
        ),
        _orderDetail(
          detailId: 2,
          dishName: '拍黄瓜',
          quantity: 1,
          specification: '免辣',
        ),
      ],
      orderId: 7,
      currentQueue: 'pending_cook',
    );

    expect(display[0].specText, contains('微辣'));
    expect(display[1].specText, '免辣');
  });

  test('order projection without spec leaves specText null', () {
    final lines = [
      _line(detailId: 1, dishName: '油边王', prep: 0, cook: 1, ready: 1),
    ];
    final display = projectOrderDetails(
      lines: lines,
      orderId: 7,
      currentQueue: 'pending_cook',
    );

    expect(display.single.specText, isNull);
  });

  test('done slices sort by latest completion time first', () {
    final older = _line(
      detailId: 1,
      dishName: '油边王',
      prep: 0,
      cook: 0,
      ready: 0,
      completedAtMs: 100,
    ).slices.single;
    final newer = _line(
      detailId: 2,
      dishName: '鸡翅',
      prep: 0,
      cook: 0,
      ready: 0,
      completedAtMs: 200,
    ).slices.single;
    final slices = [older, newer]..sort(compareCompletedSlices);

    expect(slices.map((line) => line.detailId), [2, 1]);
  });

  test('completed time reads the cashier completed_at_ms field', () {
    expect(completedAtMs(const {'completed_at_ms': 123}), 123);
  });

  test('advance command masks only the source queue immediately', () {
    final lines = [
      _line(
        detailId: 1,
        dishName: '油边王',
        prep: 0,
        cook: 2,
        ready: 2,
      ),
    ];
    final keys = optimisticAdvanceKeys(
      lines: lines,
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(
        detailId: 1,
        fromQueue: 'pending_cook',
      ),
    );

    expect(keys, {'1:pending_cook'});
  });

  test('prep flow cannot be disabled while prep quantity remains', () {
    final prepLines = [
      _line(
        detailId: 1,
        dishName: '油边王',
        prep: 1,
        cook: 1,
        ready: 1,
      ),
    ];

    expect(canDisablePrepFlow(prepLines), isFalse);
    expect(prepFlowBusyMessage, '当前配菜流程仍有菜品，请完成配菜后在关闭');
    expect(canDisablePrepFlow(const []), isTrue);
  });

  test('prepLinesToAdvance sweeps all pending prep lines without filter', () {
    final lines = [
      _line(
          detailId: 1, dishName: '油边王', orderId: 7, prep: 1, cook: 1, ready: 1),
      _line(
          detailId: 2, dishName: '韭菜', orderId: 8, prep: 0, cook: 1, ready: 1),
      _line(
          detailId: 3, dishName: '羊肉串', orderId: 9, prep: 2, cook: 2, ready: 2),
    ];

    expect(prepLinesToAdvance(lines).map((line) => line.detailId), [1, 3]);
  });

  test('prepLinesToAdvance keeps only lines of orders involved in the event',
      () {
    // 订单 9 是历史滞留的加菜行，不在本次事件范围内，不得被捎带推进。
    final lines = [
      _line(
          detailId: 1, dishName: '油边王', orderId: 7, prep: 1, cook: 1, ready: 1),
      _line(
          detailId: 3, dishName: '羊肉串', orderId: 9, prep: 2, cook: 2, ready: 2),
    ];

    expect(prepLinesToAdvance(lines, onlyOrderIds: {7}).map((l) => l.detailId),
        [1]);
    expect(prepLinesToAdvance(lines, onlyOrderIds: {9}).map((l) => l.detailId),
        [3]);
    expect(prepLinesToAdvance(lines, onlyOrderIds: {42}), isEmpty);
    expect(prepLinesToAdvance(lines, onlyOrderIds: const {}), isEmpty);
  });

  test('prepLinesToAdvance never touches lines already past prep', () {
    // 同一张单：detail 1 仍在待配菜，detail 2 已进入待传菜。
    // 逐明细推进只返回 detail 1，整单推进会把 detail 2 也划走。
    final lines = [
      _line(
          detailId: 1, dishName: '油边王', orderId: 7, prep: 1, cook: 1, ready: 1),
      _line(
          detailId: 2, dishName: '韭菜', orderId: 7, prep: 0, cook: 0, ready: 1),
    ];

    final targets = prepLinesToAdvance(lines, onlyOrderIds: {7});
    expect(targets.map((l) => l.detailId), [1]);
  });

  test('orderLinesToAdvance only touches lines in the source queue', () {
    // 整单推进到待传菜：只有流程=待制作的行可被推进，
    // 待配菜、待传菜（已完成制作）的行不受影响，严格单一流程。
    final lines = [
      _line(
          detailId: 1, dishName: '油边王', orderId: 7, prep: 0, cook: 1, ready: 1),
      _line(
          detailId: 2, dishName: '韭菜', orderId: 7, prep: 1, cook: 1, ready: 1),
      _line(
          detailId: 3, dishName: '羊肉串', orderId: 7, prep: 0, cook: 0, ready: 1),
      _line(
          detailId: 4, dishName: '鸡翅', orderId: 8, prep: 0, cook: 2, ready: 2),
    ];

    // pending_cook：只有 detail 1（detail 2 仍在待配菜，detail 3 已进待传菜）
    final cookTargets =
        orderLinesToAdvance(lines, orderId: 7, fromQueue: 'pending_cook');
    expect(cookTargets.map((l) => l.detailId), [1]);

    // 换源队列验证单一流程语义
    expect(
        orderLinesToAdvance(lines, orderId: 7, fromQueue: 'pending_prep')
            .map((l) => l.detailId),
        [2]);
    expect(
        orderLinesToAdvance(lines, orderId: 7, fromQueue: 'ready_serve')
            .map((l) => l.detailId),
        [3]);
    expect(orderLinesToAdvance(lines, orderId: 9, fromQueue: 'pending_cook'),
        isEmpty);
  });

  group('advanceDestQueue', () {
    test('prefers authoritative slice diff over workflow inference', () {
      // 待制作划 2 份 → 待传菜 +2
      expect(
        advanceDestQueue('pending_cook', const {'pending_cook': 3}, const {'pending_cook': 1, 'ready_serve': 2}),
        'ready_serve',
      );
      // 待传菜划到已完成 → done +2
      expect(
        advanceDestQueue('ready_serve', const {'ready_serve': 2}, const {'ready_serve': 0, 'done': 2}),
        'done',
      );
    });

    test('detects dest when line was not tracked before (fresh partial line)', () {
      // before 无该明细；after 出现 done 切片（例如跳过传菜直接完成）
      expect(
        advanceDestQueue('pending_cook', const {}, const {'done': 2}),
        'done',
      );
    });

    test('falls back to workflow order when no diff is found', () {
      expect(advanceDestQueue('pending_prep', const {}, const {}), 'pending_cook');
      expect(advanceDestQueue('pending_cook', const {}, const {}), 'ready_serve');
      expect(advanceDestQueue('ready_serve', const {}, const {}), 'done');
      expect(advanceDestQueue('unknown', const {}, const {}), 'done');
    });
  });

  group('undoBatchSummary', () {
    test('single item', () {
      final batch = KdsAdvanceUndoBatch(
        items: const [KdsAdvanceUndoItem(detailId: 1, orderId: 9, dishName: '烤茄子', unit: '份', quantity: 3, destQueue: 'done')],
        generatedAt: DateTime(2026, 9, 5),
      );
      expect(undoBatchSummary(batch), '3份 烤茄子');
    });

    test('single item with table number', () {
      final batch = KdsAdvanceUndoBatch(
        items: const [
          KdsAdvanceUndoItem(
            detailId: 1,
            orderId: 9,
            dishName: '烤茄子',
            unit: '份',
            quantity: 3,
            destQueue: 'done',
            tableOrPickupCode: 'A01',
          ),
        ],
        generatedAt: DateTime(2026, 9, 5),
      );
      expect(undoBatchSummary(batch), 'A01 · 3份 烤茄子');
    });

    test('single item with pickup code', () {
      final batch = KdsAdvanceUndoBatch(
        items: const [
          KdsAdvanceUndoItem(
            detailId: 1,
            orderId: 9,
            dishName: '炸鸡',
            unit: '份',
            quantity: 1,
            destQueue: 'done',
            tableOrPickupCode: '打包 13909',
          ),
        ],
        generatedAt: DateTime(2026, 9, 5),
      );
      expect(undoBatchSummary(batch), '打包 13909 · 1份 炸鸡');
    });

    test('two items joined', () {
      final batch = KdsAdvanceUndoBatch(
        items: const [
          KdsAdvanceUndoItem(detailId: 1, orderId: 9, dishName: '烤茄子', unit: '份', quantity: 3, destQueue: 'done'),
          KdsAdvanceUndoItem(detailId: 2, orderId: 9, dishName: '韭菜', unit: '串', quantity: 2, destQueue: 'ready_serve'),
        ],
        generatedAt: DateTime(2026, 9, 5),
      );
      expect(undoBatchSummary(batch), '3份 烤茄子、2串 韭菜');
    });

    test('more than two items collapses', () {
      final batch = KdsAdvanceUndoBatch(
        items: const [
          KdsAdvanceUndoItem(detailId: 1, orderId: 9, dishName: '烤茄子', unit: '份', quantity: 3, destQueue: 'done'),
          KdsAdvanceUndoItem(detailId: 2, orderId: 9, dishName: '韭菜', unit: '串', quantity: 2, destQueue: 'done'),
          KdsAdvanceUndoItem(detailId: 3, orderId: 9, dishName: '生蚝', unit: '只', quantity: 6, destQueue: 'done'),
        ],
        generatedAt: DateTime(2026, 9, 5),
      );
      expect(undoBatchSummary(batch), '3份 烤茄子、2串 韭菜 等 3 项');
    });
  });

  group('resolveLineTableOrPickupCode', () {
    test('resolves table number for dine_in', () {
      expect(
        resolveLineTableOrPickupCode(
          channel: 'dine_in',
          raw: {'table_number': '12'},
        ),
        '12',
      );
    });

    test('resolves pickup code for takeout and pack', () {
      expect(
        resolveLineTableOrPickupCode(
          channel: 'takeout',
          raw: const {},
          cloudOrderId: 8848,
        ),
        '外卖 8848',
      );
      expect(
        resolveLineTableOrPickupCode(
          channel: 'pack',
          raw: const {},
          cloudOrderId: 996,
        ),
        '打包 996',
      );
    });
  });

  group('kdsPickupCode / orderDisplayId', () {
    test('cloud_order_id (t_order.id) is used as pickup code', () {
      final line = _line(detailId: 1, dishName: '烤羊排', prep: 0, cook: 1, ready: 1)
          .withRawFields({'cloud_order_id': 13909});
      expect(kdsPickupCode(line.slices.first), '13909');
      expect(orderDisplayId(line.slices.first), '13909');
    });

    test('fills cloud id from another detail of the same order', () {
      final missing =
          _line(detailId: 1, dishName: '烤羊排', prep: 0, cook: 1, ready: 1);
      final known = _line(detailId: 2, dishName: '韭菜', prep: 0, cook: 1, ready: 1)
          .withRawFields({'cloud_order_id': 13910});
      expect(
        kdsPickupCode(missing.slices.first, [
          missing.slices.first,
          known.slices.first,
        ]),
        '13910',
      );
    });

    test('returns null / empty when no cloud_order_id exists (never uses local orderId)', () {
      final line = _line(detailId: 1, dishName: '烤羊排', prep: 0, cook: 1, ready: 1)
          .withRawFields({'cloud_order_id': null, 'order_no': 'ORD2026'});
      expect(kdsPickupCode(line.slices.first), isNull);
      expect(orderDisplayId(line.slices.first), '');
    });
  });

  group('countBoardSlices', () {
    test('order view counts unique orders regardless of dish count', () {
      // 1单5菜：订单视图显示 1
      final order1Lines = [
        _line(detailId: 1, dishName: '菜1', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 2, dishName: '菜2', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 3, dishName: '菜3', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 4, dishName: '菜4', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 5, dishName: '菜5', prep: 0, cook: 1, ready: 1, orderId: 101),
      ];
      final slices1 = order1Lines.map((l) => l.slices.first).toList();
      expect(countBoardSlices(slices: slices1, isDishView: false), 1);

      // 加入第 2 单：订单视图显示 2
      final order2Lines = [
        _line(detailId: 6, dishName: '菜A', prep: 0, cook: 1, ready: 1, orderId: 102),
        _line(detailId: 7, dishName: '菜B', prep: 0, cook: 1, ready: 1, orderId: 102),
      ];
      final allSlices = [...slices1, ...order2Lines.map((l) => l.slices.first)];
      expect(countBoardSlices(slices: allSlices, isDishView: false), 2);
    });

    test('dish view counts 5 for 5 different dishes', () {
      // 1单5菜：菜品视图显示 5
      final orderLines = [
        _line(detailId: 1, dishName: '菜1', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 2, dishName: '菜2', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 3, dishName: '菜3', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 4, dishName: '菜4', prep: 0, cook: 1, ready: 1, orderId: 101),
        _line(detailId: 5, dishName: '菜5', prep: 0, cook: 1, ready: 1, orderId: 101),
      ];
      final slices = orderLines.map((l) => l.slices.first).toList();
      expect(countBoardSlices(slices: slices, isDishView: true), 5);
    });

    test('dish view respects fixed dish merge and name merge', () {
      // 两桌各点了相同的菜品（同一个 dishId 101，堂食）
      final line1 = _line(
        detailId: 1,
        dishName: '羊肉串',
        prep: 0,
        cook: 5,
        ready: 5,
        orderId: 1,
        dishId: 101,
        quantity: 5,
      );
      final line2 = _line(
        detailId: 2,
        dishName: '羊肉串',
        prep: 0,
        cook: 10,
        ready: 10,
        orderId: 2,
        dishId: 101,
        quantity: 10,
      );
      final slices = [line1.slices.first, line2.slices.first];

      // 固定菜位模式：相同 dishId+渠道 合并为 1 张卡
      expect(countBoardSlices(slices: slices, isDishView: true, fixedDishOrderEnabled: true), 1);

      // 非固定同名合并：相同 dishName+渠道 合并为 1 张卡
      expect(countBoardSlices(slices: slices, isDishView: true, fixedDishOrderEnabled: false, mergeSameDishNameEnabled: true), 1);

      // 不合并：2 张独立卡
      expect(countBoardSlices(slices: slices, isDishView: true, fixedDishOrderEnabled: false, mergeSameDishNameEnabled: false), 2);

      // 已完成队列：不合并，保留独立批次卡片
      expect(countBoardSlices(slices: slices, isDishView: true, isDone: true, fixedDishOrderEnabled: true), 2);
    });

    test('empty slices returns 0', () {
      expect(countBoardSlices(slices: const [], isDishView: true), 0);
      expect(countBoardSlices(slices: const [], isDishView: false), 0);
    });
  });
}

KdsV2Line _line({
  required int detailId,
  required String dishName,
  required int prep,
  required int cook,
  required int ready,
  int? completedAtMs,
  int orderId = 7,
  int? dishId,
  int? quantity,
  String bucket = 'dine_in',
}) =>
    KdsV2Line.fromJson({
      'detail_id': detailId,
      'order_id': orderId,
      'dish_id': dishId ?? (detailId + 100),
      'dish_name': dishName,
      'line_quantity': quantity ?? (detailId == 2 ? 1 : 2),
      'refunded_quantity': 0,
      'prep_remaining': prep,
      'cook_remaining': cook,
      'ready_remaining': ready,
      'local_revision': 1,
      'order_revision': 1,
      'workflow_queue': ready == 0 ? 'done' : 'pending_cook',
      'fulfillment_bucket': bucket,
      'table_number': '20',
      'order_no': 'O-7',
      'specification': null,
      'unit': '串',
      'remark': null,
      'created_at_ms': detailId,
      if (completedAtMs != null) 'completed_at_ms': completedAtMs,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    });

KdsV2OrderDetail _orderDetail({
  required int detailId,
  required String dishName,
  required int quantity,
  bool refunded = false,
  String specification = '',
  int? servingDurationMinutes,
}) =>
    KdsV2OrderDetail.fromJson({
      'order_id': 7,
      'order_no': 'O-7',
      'table_number': '20',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': detailId,
      'dish_id': detailId + 100,
      'dish_name': dishName,
      'specification': specification,
      'unit': '份',
      'quantity': quantity,
      'refunded_quantity': refunded ? quantity : 0,
      'remaining_quantity': refunded ? 0 : quantity,
      'status': refunded ? 'refunded' : 'active',
      'removed': refunded,
      'remark': '',
      if (servingDurationMinutes != null)
        'serving_duration_minutes': servingDurationMinutes,
    });
