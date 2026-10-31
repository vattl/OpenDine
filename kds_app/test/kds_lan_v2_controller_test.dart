import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';

void main() {
  test('records the exact dish load source for bootstrap, websocket and poll',
      () async {
    final traces = <KdsDishLoadTrace>[];
    final transport = FakeTransport()..bootstrapResult = _bootstrap(1);
    final controller = KdsV2Controller(
      transport,
      onDishLoad: traces.add,
      channelLabel: () => 'cloud',
    );

    await controller.start();
    await controller.ingest(
      _event(2, 'ws-2', 2),
      source: KdsDishLoadSource.websocketPush,
    );
    transport.changesResult = KdsV2Changes(
      eventSeq: 3,
      snapshotRequired: false,
      events: [_event(3, 'poll-3', 3)],
    );
    await controller.poll();

    expect(
      traces.map((trace) => trace.source),
      [
        KdsDishLoadSource.bootstrapHttp,
        KdsDishLoadSource.websocketPush,
        KdsDishLoadSource.changesPoll,
      ],
    );
    expect(traces.last.eventSeq, 3);
    expect(traces.last.eventId, 'poll-3');
    expect(traces.last.patchCount, 1);
    expect(traces.every((trace) => trace.channel == 'cloud'), isTrue);
  });

  test('dish load diagnostics never interrupt authoritative state updates',
      () async {
    final controller = KdsV2Controller(
      FakeTransport()..bootstrapResult = _bootstrap(1),
      onDishLoad: (_) => throw StateError('diagnostic sink failed'),
    );

    await controller.start();

    expect(controller.state.eventSeq, 1);
    expect(controller.state.lines, hasLength(1));
  });

  test('cold start is empty and disconnected state is read-only', () {
    final controller = KdsV2Controller(FakeTransport());
    expect(controller.state.lines, isEmpty);
    expect(controller.state.canMutate, isFalse);
    expect(controller.state.realtimeReady, isFalse);
  });

  test('malformed protocol data locks mutations and exposes an error',
      () async {
    final controller = KdsV2Controller(
      FakeTransport()..bootstrapResult = _bootstrap(1),
    );
    await controller.start();
    controller.setConnected(true);

    controller.rejectProtocol(
      const FormatException('invalid cumulative quantities'),
    );

    expect(controller.state.error, contains('invalid cumulative quantities'));
    expect(controller.state.canMutate, isFalse);
  });

  test('gap pulls changes and applies each event exactly once', () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = KdsV2Changes(
        eventSeq: 7,
        snapshotRequired: false,
        events: [_event(6, 'e6', 2), _event(7, 'e7', 3)],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    await controller.ingest(_event(7, 'e7', 3));
    await controller.ingest(_event(7, 'e7', 99));

    expect(transport.changeRequests, [5]);
    expect(controller.state.eventSeq, 7);
    expect(controller.state.lines.single.quantity, 3);
  });

  test('expired changes force an authoritative bootstrap', () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(4)
      ..changesResult = const KdsV2Changes(
        eventSeq: 8,
        snapshotRequired: true,
        events: [],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    transport.bootstrapResult = _bootstrap(10);
    controller.setConnected(true);

    await controller.ingest(_event(8, 'e8', 8));

    expect(transport.bootstrapCalls, 2);
    expect(controller.state.eventSeq, 10);
  });

  test('incomplete changes cannot silently drop the triggering event',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = KdsV2Changes(
        eventSeq: 8,
        snapshotRequired: false,
        events: [_event(6, 'e6', 2)],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    await controller.ingest(_event(8, 'e8', 8));

    expect(transport.bootstrapCalls, 2);
  });

  test('disconnect preserves display and allows provider offline queueing',
      () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(1);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);
    expect(controller.state.canMutate, isTrue);

    controller.setConnected(false);
    expect(controller.state.lines, hasLength(1));
    expect(controller.state.canMutate, isTrue);
    expect(
      () => controller.command(KdsV2Command(
        commandId: 'cmd',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(detailId: 11),
      )),
      throwsStateError,
    );
  });

  test('an event arriving during recovery is replayed after the gap closes',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = KdsV2Changes(
        eventSeq: 7,
        snapshotRequired: false,
        events: [_event(6, 'e6', 2), _event(7, 'e7', 3)],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();

    await Future.wait([
      controller.ingest(_event(7, 'e7', 3)),
      controller.ingest(_event(8, 'e8', 4)),
    ]);

    expect(controller.state.eventSeq, 8);
    expect(controller.state.lines.single.quantity, 4);
  });

  test('cold start replays websocket events that arrived after bootstrap tail',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = KdsV2Changes(
        eventSeq: 7,
        snapshotRequired: false,
        events: [_event(6, 'early-6', 2), _event(7, 'early-7', 3)],
      );
    final controller = KdsV2Controller(transport);

    await controller.startWithBufferedEvents([
      _event(7, 'early-7', 3),
    ]);

    expect(transport.bootstrapCalls, 1);
    expect(transport.changeRequests, [5]);
    expect(controller.state.eventSeq, 7);
    expect(controller.state.lines.single.quantity, 3);
  });

  test('new config version bootstraps once and refreshes fixed catalog',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(
        5,
        configVersion: 1,
        catalogDishName: '旧目录菜',
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);
    transport.bootstrapResult = _bootstrap(
      6,
      configVersion: 2,
      catalogDishName: '新目录菜',
    );
    final changed = _configEvent(6, 'config-2', 2);

    final refreshing = controller.ingest(changed);
    expect(controller.state.loading, isTrue);
    expect(controller.state.catalog.single.dishName, '旧目录菜');
    expect(controller.state.canMutate, isFalse);
    await refreshing;

    expect(transport.bootstrapCalls, 2);
    expect(controller.state.configVersion, 2);
    expect(controller.state.catalog.single.dishName, '新目录菜');
    expect(controller.state.canMutate, isTrue);

    await controller.ingest(changed);
    expect(transport.bootstrapCalls, 2);

    await controller.ingest(_event(7, 'same-config', 3, configVersion: 2));
    expect(transport.bootstrapCalls, 2);
    expect(controller.state.lines.single.quantity, 3);
  });

  test('reconnect catches up while locked before enabling commands', () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = KdsV2Changes(
        eventSeq: 6,
        snapshotRequired: false,
        events: [_event(6, 'reconnect-6', 2)],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);
    controller.setConnected(false);

    final reconnecting = controller.reconnect();
    expect(controller.state.loading, isTrue);
    expect(controller.state.canMutate, isFalse);
    expect(controller.state.lines.single.quantity, 1);
    await reconnecting;

    expect(transport.changeRequests, [5]);
    expect(controller.state.eventSeq, 6);
    expect(controller.state.lines.single.quantity, 2);
    expect(controller.state.canMutate, isTrue);
    expect(controller.state.realtimeReady, isTrue);
  });

  test('connected transport with failed catch-up is not realtime ready',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesError = TimeoutException('catch-up timed out');
    final controller = KdsV2Controller(transport);
    await controller.start();

    await expectLater(controller.reconnect(), throwsA(isA<TimeoutException>()));

    expect(controller.state.connected, isTrue);
    expect(controller.state.realtimeReady, isFalse);
    expect(controller.state.canMutate, isFalse);
  });

  test('reconnect snapshot_required performs authoritative bootstrap',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(5)
      ..changesResult = const KdsV2Changes(
        eventSeq: 9,
        snapshotRequired: true,
        events: [],
      );
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(false);
    transport.bootstrapResult = _bootstrap(9);

    await controller.reconnect();

    expect(transport.changeRequests, [5]);
    expect(transport.bootstrapCalls, 2);
    expect(controller.state.eventSeq, 9);
    expect(controller.state.canMutate, isTrue);
  });

  test('reconnect follows paged changes until the authoritative tail',
      () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(5);
    transport.changeResults.addAll([
      KdsV2Changes(
        eventSeq: 1205,
        snapshotRequired: false,
        events: List.generate(500, (index) => _cursorEvent(index + 6)),
      ),
      KdsV2Changes(
        eventSeq: 1205,
        snapshotRequired: false,
        events: List.generate(500, (index) => _cursorEvent(index + 506)),
      ),
      KdsV2Changes(
        eventSeq: 1205,
        snapshotRequired: false,
        events: List.generate(200, (index) => _cursorEvent(index + 1006)),
      ),
    ]);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(false);

    final reconnecting = controller.reconnect();
    expect(controller.state.loading, isTrue);
    expect(controller.state.canMutate, isFalse);
    await reconnecting;

    expect(transport.changeRequests, [5, 505, 1005]);
    expect(controller.state.eventSeq, 1205);
    expect(controller.state.canMutate, isTrue);
  });

  test('ambiguous command retries reuse id but changed payload gets a new id',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..commandErrors.addAll([
        TimeoutException('ambiguous send'),
        TimeoutException('ambiguous changed send'),
      ])
      ..commandResult = _commandResult(2);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    Future<void> send(String id, int quantity) => controller.command(
          KdsV2Command(
            commandId: id,
            type: KdsV2CommandType.advanceItem,
            target: const KdsV2CommandTarget(
              detailId: 11,
              fromQueue: 'pending_cook',
            ),
            quantity: quantity,
            expectedRevision: 1,
          ),
        );

    await expectLater(send('generated-1', 1), throwsA(isA<TimeoutException>()));
    await expectLater(send('generated-2', 2), throwsA(isA<TimeoutException>()));
    await send('generated-3', 1);

    expect(transport.commandIds, ['generated-1', 'generated-2', 'generated-1']);
  });

  test('LAN proxy 503 keeps the same command id for authority recovery',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..commandErrors.add(ApiException(
        'cloud authority unavailable behind LAN proxy',
        code: 5030,
        statusCode: 503,
      ))
      ..commandResult = _commandResult(2);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    Future<void> send(String id) => controller.command(
          KdsV2Command(
            commandId: id,
            type: KdsV2CommandType.advanceItem,
            target: const KdsV2CommandTarget(
              detailId: 11,
              fromQueue: 'pending_cook',
            ),
            quantity: 1,
            expectedRevision: 1,
          ),
        );

    await expectLater(send('generated-503'), throwsA(isA<ApiException>()));
    await send('new-local-id');

    expect(transport.commandIds, ['generated-503', 'generated-503']);
  });

  test('identical in-flight commands share one transport request', () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..commandCompleter = Completer<KdsV2CommandResult>();
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);
    KdsV2Command command(String id) => KdsV2Command(
          commandId: id,
          type: KdsV2CommandType.advanceItem,
          target: const KdsV2CommandTarget(
            detailId: 11,
            fromQueue: 'pending_cook',
          ),
          quantity: 1,
          expectedRevision: 1,
        );

    final first = controller.command(command('generated-1'));
    final second = controller.command(command('generated-2'));
    await Future<void>.delayed(Duration.zero);
    expect(transport.commandIds, ['generated-1']);

    transport.commandCompleter!.complete(_commandResult(2, 'generated-1'));
    await Future.wait([first, second]);
  });

  test('revision conflict refreshes state without replaying the command',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..changesResult = KdsV2Changes(
        eventSeq: 2,
        snapshotRequired: false,
        events: [_event(2, 'conflict-refresh', 2)],
      )
      ..commandErrors.add(ApiException(
        'local revision mismatch',
        code: 4090,
        statusCode: 409,
      ));
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    await expectLater(
      controller.command(KdsV2Command(
        commandId: 'stale-command',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(
          detailId: 11,
          fromQueue: 'pending_cook',
        ),
        expectedRevision: 1,
      )),
      throwsA(isA<ApiException>()),
    );

    expect(transport.commandIds, ['stale-command']);
    expect(transport.changeRequests, [1]);
    expect(controller.state.eventSeq, 2);
    expect(controller.state.lines.single.quantity, 2);
    expect(controller.state.canMutate, isTrue);
  });

  test('malformed command response locks further mutations', () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..commandErrors.add(const FormatException('malformed line patch'));
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    await expectLater(
      controller.command(KdsV2Command(
        commandId: 'bad-response',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(detailId: 11),
      )),
      throwsFormatException,
    );
    expect(controller.state.error, contains('malformed line patch'));
    expect(controller.state.canMutate, isFalse);
  });

  test('stale bootstrap cannot overwrite a newer websocket event', () async {
    final delayed = Completer<KdsV2Bootstrap>();
    final transport = FakeTransport()..bootstrapResult = _bootstrap(1);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);
    transport.bootstrapCompleter = delayed;

    final refreshing = controller.start();
    await controller.ingest(_event(2, 'newer-2', 2));
    delayed.complete(_bootstrap(1));
    await refreshing;

    expect(controller.state.eventSeq, 2);
    expect(controller.state.lines.single.quantity, 2);
    expect(controller.state.loading, isFalse);
  });

  test('recovered order_created is emitted once to accepted event callback',
      () async {
    final accepted = <String>[];
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..changesResult = KdsV2Changes(
        eventSeq: 2,
        snapshotRequired: false,
        events: [
          KdsV2Envelope(
            eventSeq: 2,
            eventId: 'order-2',
            type: 'order_created',
            patches: const [],
            queueCounts: const {},
          ),
        ],
      );
    final controller = KdsV2Controller(
      transport,
      onEnvelopeApplied: (event) => accepted.add(event.eventId),
    );
    await controller.start();
    controller.setConnected(false);

    await controller.reconnect();
    await controller.ingest(KdsV2Envelope(
      eventSeq: 2,
      eventId: 'order-2',
      type: 'order_created',
      patches: const [],
      queueCounts: const {},
    ));

    expect(accepted, ['order-2']);
  });

  test('mismatched command acknowledgement is rejected and locks writes',
      () async {
    final transport = FakeTransport()
      ..bootstrapResult = _bootstrap(1)
      ..commandAckOverride = 'another-command';
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.setConnected(true);

    await expectLater(
      controller.command(KdsV2Command(
        commandId: 'expected-command',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(
          detailId: 11,
          fromQueue: 'pending_cook',
        ),
        expectedRevision: 1,
      )),
      throwsFormatException,
    );
    expect(controller.state.canMutate, isFalse);
  });

  test('restoreSnapshot keeps the board usable when bootstrap fails offline',
      () async {
    final transport = FakeTransport()
      ..bootstrapError = TimeoutException('cashier unreachable');
    final controller = KdsV2Controller(transport);
    controller.restoreSnapshot(
        KdsV2State.fromBootstrap(_bootstrap(9), connected: false));

    await expectLater(controller.start(), throwsA(isA<TimeoutException>()));

    // 恢复的缓存快照仍在；显式离线（未连接）时快照可信，可离线划菜。
    expect(controller.state.lines, isNotEmpty);
    expect(controller.state.error, isNotNull);
    expect(controller.state.connected, isFalse);
    expect(controller.state.canMutate, isTrue);
  });

  test(
      'restoreSnapshot zeroes event_seq so a stale cache never blocks bootstrap',
      () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(5);
    final controller = KdsV2Controller(transport);
    // 缓存来自更晚的 seq 9，收银端重启后引导 seq 仅 5；
    // 恢复时必须归零，否则 start() 的 seq 守卫会跳过权威引导。
    controller.restoreSnapshot(
        KdsV2State.fromBootstrap(_bootstrap(9), connected: false));

    await controller.start();

    expect(transport.bootstrapCalls, 1);
    expect(controller.state.eventSeq, 5);
    expect(controller.state.canMutate, isTrue);
  });

  test('business-day history rejects unfinished and outside-window orders', () {
    final controller = KdsV2Controller(FakeTransport());
    controller.mergeBusinessDayOrders({
      'business_day_start_ms': 2000,
      'business_day_end_ms': 5000,
      'orders': [
        _businessOrder(1, [_businessDetail(101, 3, '昨日', 1)]),
        {
          ..._businessOrder(2, [_businessDetail(201, 3, '制作中', 2)]),
          'completed': false
        },
        _businessOrder(3, [_businessDetail(301, 3, '完成', 2)],
            completedAtMs: 4000),
        _businessOrder(5, [_businessDetail(501, 3, '边界', 1)]),
      ],
    });
    expect(controller.state.lines.map((line) => line.detailId), [301]);
  });

  test('same-window empty snapshot keeps completed history rows', () async {
    final controller = KdsV2Controller(FakeTransport());
    controller.mergeBusinessDayOrders({
      'orders': [
        _businessOrder(1, [_businessDetail(101, 3, '旧历史', 1)])
      ]
    });
    await controller.refreshBusinessDayOrders();
    // 同一营业时段内快照归档/缺页不能清除已完成历史（持久化诉求）。
    expect(controller.state.lines, hasLength(1));
    expect(controller.state.lines.single.detailId, 101);
  });

  test('business-day window change rebuilds done history', () async {
    final transport = FakeTransport()
      ..businessDayStartMs = 1000
      ..businessDayEndMs = 2000
      ..businessDayOrderPages = [
        [
          _businessOrder(1, [_businessDetail(101, 3, '完成单', 1)],
              completedAtMs: 1500)
        ]
      ];
    final controller = KdsV2Controller(transport);
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, hasLength(1));

    // 同窗口第二次空快照：历史行保留。
    transport.businessDayOrderPages = [[]];
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, hasLength(1));

    // 营业时段切换（新一天开市）：旧窗口历史行清除重建。
    transport.businessDayStartMs = 3000;
    transport.businessDayEndMs = 4000;
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, isEmpty);
  });

  test('window change + empty snapshot keeps bootstrap done rows (BUG: done '
      'page emptied by window cleanup)', () async {
    final transport = FakeTransport()
      ..businessDayStartMs = 2000
      ..businessDayEndMs = 3000
      ..businessDayOrderPages = [[]];
    // bootstrap 返回已完成行，created_at_ms 在窗口 end 之后（服务端窗口
    // 未滚动/订单超窗）：当天营业日订单必须保留，不能按 end 过滤误删
    transport.bootstrapResult = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'fixed_catalog': [],
      'queues': {
        'done': [
          _doneBootstrapLine(101, createdAtMs: 4000),
        ]
      },
    });
    final controller = KdsV2Controller(transport);
    await controller.start();
    expect(controller.state.lines, hasLength(1));

    // 快照为空 + 窗口变化：bootstrap 的当天已完成行必须保留
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, hasLength(1),
        reason: '空快照 + 窗口变化不能清空当天营业日的已完成行');
    expect(controller.state.lines.single.detailId, 101);
  });

  test('done rows older than business-day start are dropped (history hidden)',
      () async {
    final transport = FakeTransport()
      ..businessDayStartMs = 2000
      ..businessDayEndMs = 3000
      ..businessDayOrderPages = [[]];
    // bootstrap 同时返回：当天订单（created 2000）与历史订单（created 1000）
    transport.bootstrapResult = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'fixed_catalog': [],
      'queues': {
        'done': [
          _doneBootstrapLine(101, createdAtMs: 1000),
          _doneBootstrapLine(102, createdAtMs: 2000),
        ]
      },
    });
    final controller = KdsV2Controller(transport);
    await controller.start();
    expect(controller.state.lines, hasLength(2));

    // 快照空 + 窗口变化：历史订单（created < start）清除，当天订单保留
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines.map((l) => l.detailId), [102],
        reason: '历史营业日订单不得显示在已完成页');
  });

  test('bootstrap rebuild keeps completed_at_ms for done rows (duration frozen)',
      () async {
    final transport = FakeTransport();
    final controller = KdsV2Controller(transport);
    // 本地先有已完成行：completed_at_ms = 5000（划菜完成事件写入）
    controller.mergeBusinessDayOrders({
      'orders': [
        {
          'completed': true,
          'order_id': 1,
          'order_no': 'O-1',
          'table_number': '20',
          'fulfillment_type': 'dine_in',
          'created_at_ms': 1000,
          'completed_at_ms': 5000,
          'details': [_businessDetail(101, 3, '烤茄子', 2)],
        }
      ]
    });
    expect(controller.state.lines.single.raw['completed_at_ms'], 5000);

    // 重连 bootstrap：返回同 detailId 但缺 completed_at_ms 的 done 行
    // （completed_at_ms 非必需字段，服务端可能不带）
    transport.bootstrapResult = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 2,
      'fixed_catalog': [],
      'queues': {
        'done': [_doneBootstrapLine(101, createdAtMs: 1000)],
      },
    });
    await controller.start();
    final line = controller.state.lines.singleWhere((l) => l.detailId == 101);
    expect(line.raw['completed_at_ms'], 5000,
        reason: '重连后已完成行不得丢失完成时间（耗时需固定）');
  });

  test('window change keeps done history rows inside the new business day',
      () async {
    final transport = FakeTransport()
      ..businessDayStartMs = 1000
      ..businessDayEndMs = 2000
      ..businessDayOrderPages = [
        [
          _businessOrder(1, [_businessDetail(101, 3, '完成单', 1)],
              createdMs: 1500, completedAtMs: 1800)
        ]
      ];
    final controller = KdsV2Controller(transport);
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, hasLength(1));

    // 窗口向未来滚动（如重连后新窗口），但历史行 created 仍在窗口内：
    // 不得误删（正常流程消失的根因之一）。
    transport.businessDayStartMs = 1500;
    transport.businessDayEndMs = 2500;
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, hasLength(1),
        reason: '当天窗口内的已完成行在窗口变化时不得被清除');
    expect(controller.state.lines.single.detailId, 101);

    // 窗口继续滚动越过该行 created：跨天清理生效。
    transport.businessDayStartMs = 3000;
    transport.businessDayEndMs = 4000;
    await controller.refreshBusinessDayOrders();
    expect(controller.state.lines, isEmpty);
  });

  test('refreshBusinessDayOrders pages through the whole business day',
      () async {
    final transport = FakeTransport()
      ..businessDayOrderPages = [
        [
          _businessOrder(1, [_businessDetail(101, 3, '烤羊排', 2)])
        ],
        [
          _businessOrder(2, [_businessDetail(201, 3, '韭菜', 1)])
        ],
      ];
    final controller = KdsV2Controller(transport);

    await controller.refreshBusinessDayOrders(pageSize: 1);

    // 两页 + 一次空页收尾：游标 after_id 逐步推进
    expect(transport.businessDayOrderRequests, hasLength(3));
    expect(transport.businessDayOrderRequests[0].$1, isNull);
    expect(transport.businessDayOrderRequests[1].$1, 1);
    expect(transport.businessDayOrderRequests[2].$1, 2);
    expect(controller.state.lines, hasLength(2));
    expect(
      controller.state.lines.map((line) => line.dishName).toSet(),
      {'烤羊排', '韭菜'},
    );
  });

  test('mergeBusinessDayOrders never overwrites a live active detail',
      () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(1);
    final controller = KdsV2Controller(transport);
    await controller.start();
    // bootstrap 行 detail 11 仍在 pending_cook（cook_remaining=1 → 活动切片）
    // 营业快照把同一 detail 整单标为已完成，不应覆盖 live 活动行。
    controller.mergeBusinessDayOrders({
      'data': {
        'orders': [
          _businessOrder(5, [_businessDetail(11, 3, '烤羊排', 1)]),
        ],
      },
    });

    final line = controller.state.lines.singleWhere((l) => l.detailId == 11);
    expect(line.slices.any((slice) => slice.queue != 'done'), isTrue);
    expect(line.raw['workflow_queue'], 'pending_cook');
  });

  test('business-day history accepts done-but-unsettled order details',
      () async {
    final controller = KdsV2Controller(FakeTransport());
    // 划菜完成但未结账：收银端下发 done 标记明细 → 应进已完成页
    // （方案A：营业日内已完成菜品从服务端初始化）。
    // 使用本地收银端 LAN API 真实字段格式：驼峰 workflowQueue（与云端一致）。
    controller.mergeBusinessDayOrders({
      'business_day_start_ms': 2000,
      'business_day_end_ms': 5000,
      'orders': [
        {
          ..._businessOrder(4, [
            {..._businessDetail(701, 3, '烤羊排', 2),
                'workflowQueue': 'done'},
          ]),
          'completed': false,
        },
      ],
    });
    final line = controller.state.lines.single;
    expect(line.detailId, 701);
    expect(line.queue, 'done');
    expect(line.quantity, 2);
  });

  test('unsettled order merges only done details, active ones stay out',
      () async {
    final controller = KdsV2Controller(FakeTransport());
    // 未结账订单混排：701 已划完（done），702 还在制作（pending_cook）
    // → 只合并 done 明细，活动明细由 bootstrap/changes 实时提供。
    controller.mergeBusinessDayOrders({
      'business_day_start_ms': 2000,
      'business_day_end_ms': 5000,
      'orders': [
        {
          ..._businessOrder(4, [
            {..._businessDetail(701, 3, '烤羊排', 2),
                'workflow_queue': 'done'},
            {..._businessDetail(702, 3, '羊肉串', 1),
                'workflow_queue': 'pending_cook'},
          ]),
          'completed': false,
        },
      ],
    });
    final ids = controller.state.lines.map((line) => line.detailId);
    expect(ids, [701]);
  });

  test('history refreshes historical details without inventing completion time',
      () async {
    final transport = FakeTransport();
    final controller = KdsV2Controller(transport);
    // 完成时间缺失时保留未知，不能拿下单时间充当完成时间。
    controller.mergeBusinessDayOrders({
      'data': {
        'orders': [
          _businessOrder(9, [_businessDetail(201, 3, '韭菜', 1)],
              createdMs: 7000),
        ],
      },
    });
    var line = controller.state.lines.singleWhere((l) => l.detailId == 201);
    expect(line.slices.single.queue, 'done');
    expect(line.raw['completed_at_ms'], 0);

    // 完全完成的行可被新快照覆盖（数量与完成时间更新）
    controller.mergeBusinessDayOrders({
      'data': {
        'orders': [
          _businessOrder(9, [_businessDetail(201, 3, '韭菜', 2)],
              completedAtMs: 9000),
        ],
      },
    });
    line = controller.state.lines.singleWhere((l) => l.detailId == 201);
    expect(line.slices.single.quantity, 2);
    expect(line.raw['completed_at_ms'], 9000);
  });

  test('refreshBusinessDayOrders does not publish partial pages on failure',
      () async {
    final transport = FakeTransport()
      ..businessDayOrderPages = [
        [
          _businessOrder(1, [_businessDetail(101, 3, '烤羊排', 2)])
        ],
      ]
      ..businessDayOrdersError = TimeoutException('second page down');
    final controller = KdsV2Controller(transport);

    await expectLater(
      controller.refreshBusinessDayOrders(pageSize: 1),
      throwsA(isA<TimeoutException>()),
    );

    // 分页失败不能发布半份营业日快照。
    expect(controller.state.lines, isEmpty);
  });

  test('bootstrap keeps completed history rows when rebuilding the board',
      () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(5);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.mergeBusinessDayOrders({
      'data': {
        'orders': [
          _businessOrder(9, [_businessDetail(201, 3, '韭菜', 1)],
              completedAtMs: 7000),
        ],
      },
    });
    expect(controller.state.lines.map((line) => line.detailId), contains(201));

    // config_changed / 重连触发的 bootstrap 重建：已完成历史行必须保留，
    // 活动队列行以 bootstrap 权威为准。
    transport.bootstrapResult = _bootstrap(6);
    await controller.start();
    final ids = controller.state.lines.map((line) => line.detailId).toSet();
    expect(ids, contains(201));
    expect(ids, contains(11));
    expect(controller.state.eventSeq, 6);
  });

  test('bootstrap keeps live done rows and notifies onBootstrapApplied',
      () async {
    var applied = 0;
    final transport = FakeTransport()..bootstrapResult = _bootstrap(5);
    final controller = KdsV2Controller(transport,
        onBootstrapApplied: () => applied++);
    await controller.start();
    // 划菜完成 → detail 21 全部进入 done（live 完成行，订单未结账）
    await controller.ingest(KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': 6,
      'event_id': 'done-6',
      'type': 'line_changed',
      'patches': [
        {
          ..._linePatch(2, 2),
          'detail_id': 21,
          'order_id': 21,
          'order_no': 'O-21',
          'prep_remaining': 0,
          'cook_remaining': 0,
          'ready_remaining': 0,
          'workflow_queue': 'done',
        }
      ],
      'queue_counts': {'done': 2},
    }));
    final doneLine =
        controller.state.lines.singleWhere((line) => line.detailId == 21);
    expect(doneLine.slices.single.queue, 'done');

    transport.bootstrapResult = _bootstrap(6);
    await controller.start();
    expect(applied, 2);
    final line = controller.state.lines.singleWhere((line) => line.detailId == 21);
    expect(line.slices.single.queue, 'done');
    expect(controller.state.lines, hasLength(2));
  });

  test('config_changed rebuild keeps done rows', () async {
    final transport = FakeTransport()..bootstrapResult = _bootstrap(5);
    final controller = KdsV2Controller(transport);
    await controller.start();
    controller.mergeBusinessDayOrders({
      'data': {
        'orders': [
          _businessOrder(9, [_businessDetail(201, 3, '韭菜', 1)],
              completedAtMs: 7000),
        ],
      },
    });
    expect(controller.state.lines.map((line) => line.detailId), contains(201));

    // 今天日志实证：config_changed ×3 是清空已完成页的元凶之一
    transport.bootstrapResult = _bootstrap(6, configVersion: 2);
    await controller.ingest(_configEvent(6, 'cfg-6', 2));
    expect(controller.state.lines.map((line) => line.detailId), contains(201));
    expect(controller.state.configVersion, 2);
  });
}

Map<String, dynamic> _businessOrder(
    int orderId, List<Map<String, dynamic>> details,
    {int? completedAtMs, int? createdMs}) {
  return {
    'completed': true,
    'order_id': orderId,
    'order_no': 'O-$orderId',
    'table_number': '20',
    'fulfillment_type': 'dine_in',
    'created_at_ms': createdMs ?? orderId * 1000,
    if (completedAtMs != null) 'completed_at_ms': completedAtMs,
    'details': details,
  };
}

Map<String, dynamic> _businessDetail(
    int detailId, int dishId, String name, int quantity,
    {int refunded = 0}) {
  return {
    'detail_id': detailId,
    'dish_id': dishId,
    'dish_name': name,
    'quantity': quantity,
    'refunded_quantity': refunded,
    'unit': '份',
    'specification': '',
  };
}

/// 构造 bootstrap done 队列的规范行（KDS v2 全字段）。
Map<String, dynamic> _doneBootstrapLine(int detailId,
    {required int createdAtMs, int orderId = 1, int quantity = 2}) {
  return {
    'detail_id': detailId,
    'order_id': orderId,
    'dish_id': 3,
    'dish_name': '烤茄子',
    'line_quantity': quantity,
    'quantity': quantity,
    'refunded_quantity': 0,
    'prep_remaining': 0,
    'cook_remaining': 0,
    'ready_remaining': 0,
    'local_revision': 1,
    'order_revision': 1,
    'fulfillment_bucket': 'dine_in',
    'fulfillment_channel': 'dine_in',
    'table_number': '20',
    'order_no': 'O-$detailId',
    'specification': '',
    'unit': '份',
    'remark': '',
    'created_at_ms': createdAtMs,
    'workflow_queue': 'done',
    'held': false,
    'rushed': false,
    'lacked': false,
    'removed': false,
  };
}

class FakeTransport implements KdsV2Transport {
  KdsV2Bootstrap bootstrapResult = _bootstrap(0);
  KdsV2Changes changesResult = const KdsV2Changes(
    eventSeq: 0,
    snapshotRequired: false,
    events: [],
  );
  int bootstrapCalls = 0;
  final changeRequests = <int>[];
  final changeResults = <KdsV2Changes>[];
  Object? changesError;
  Object? bootstrapError;
  final commandErrors = <Object>[];
  final commandIds = <String>[];
  KdsV2CommandResult commandResult = _commandResult(1);
  Completer<KdsV2CommandResult>? commandCompleter;
  Completer<KdsV2Bootstrap>? bootstrapCompleter;
  String? commandAckOverride;

  @override
  Future<KdsV2Bootstrap> bootstrap() async {
    bootstrapCalls++;
    if (bootstrapError case final error?) throw error;
    if (bootstrapCompleter case final completer?) return completer.future;
    return bootstrapResult;
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {}

  List<List<Map<String, dynamic>>> businessDayOrderPages = [];
  final businessDayOrderRequests = <(int?, int)>[];
  Object? businessDayOrdersError;
  int businessDayStartMs = 0;
  int businessDayEndMs = 0;

  // complete 不返回：协议中"未设"表示还有更多页，
  // 空页 + 未设 complete 时 controller 视为取完收尾。
  Map<String, dynamic> _ordersBody(List<Map<String, dynamic>> orders) => {
        'data': {
          'orders': orders,
          'business_day_start_ms': businessDayStartMs,
          'business_day_end_ms': businessDayEndMs,
        }
      };

  @override
  Future<Map<String, dynamic>> businessDayOrders(
      {int? afterId, int limit = 200}) async {
    businessDayOrderRequests.add((afterId, limit));
    // 仅对后续分页（afterId != null）抛错：模拟翻页中途失败，
    // 让"已合并页保留"语义可被验证。
    if (businessDayOrdersError case final error?) {
      if (afterId != null) throw error;
    }
    if (businessDayOrderPages.isEmpty) {
      return _ordersBody(const []);
    }
    final all = <Map<String, dynamic>>[];
    for (final page in businessDayOrderPages) {
      all.addAll(page);
    }
    final filtered = all.where((order) {
      final id = (order['order_id'] ?? order['orderId']);
      final asInt = id is num ? id.toInt() : int.tryParse('$id') ?? 0;
      return afterId == null || asInt > afterId;
    }).toList();
    return _ordersBody(filtered.take(limit).toList());
  }

  @override
  Future<KdsV2Changes> changes(int afterSeq) async {
    changeRequests.add(afterSeq);
    if (changesError case final error?) throw error;
    if (changeResults.isNotEmpty) return changeResults.removeAt(0);
    return changesResult;
  }

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async {
    commandIds.add(command.commandId);
    if (commandCompleter case final completer?) return completer.future;
    if (commandErrors.isNotEmpty) throw commandErrors.removeAt(0);
    return _commandResult(
      commandResult.eventSeq,
      commandAckOverride ?? command.commandId,
    );
  }
}

KdsV2CommandResult _commandResult(int eventSeq,
        [String commandId = 'server-ack']) =>
    KdsV2CommandResult.fromJson({
      'data': {
        'command_id': commandId,
        'duplicate': false,
        'event_seq': eventSeq,
        'patches': const [],
        'queue_counts': const {},
      }
    });

KdsV2Bootstrap _bootstrap(
  int seq, {
  int? configVersion,
  String catalogDishName = '烤羊排',
}) =>
    KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': seq,
      if (configVersion != null) 'config_version': configVersion,
      'fixed_catalog': [
        {
          'dish_id': 3,
          'dish_name': catalogDishName,
          'unit': '份',
          'sequence': 0,
        }
      ],
      'queues': {
        'pending_cook': [
          {
            ..._linePatch(1, 1),
          }
        ]
      },
    });

KdsV2Envelope _event(int seq, String id, int quantity, {int? configVersion}) =>
    KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': seq,
      'event_id': id,
      'type': 'line_changed',
      if (configVersion != null) 'config_version': configVersion,
      'patches': [
        _linePatch(quantity, seq),
      ],
      'queue_counts': {'pending_cook': quantity},
    });

Map<String, dynamic> _linePatch(int quantity, int revision) => {
      'detail_id': 11,
      'order_id': 5,
      'dish_id': 3,
      'dish_name': '烤羊排',
      'line_quantity': quantity,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': quantity,
      'ready_remaining': quantity,
      'local_revision': revision,
      'order_revision': revision,
      'workflow_queue': 'pending_cook',
      'fulfillment_bucket': 'dine_in',
      'table_number': 'A1',
      'order_no': 'O-5',
      'specification': null,
      'unit': '份',
      'remark': null,
      'created_at_ms': 1720000000000,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    };

KdsV2Envelope _configEvent(int seq, String id, int configVersion) =>
    KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': seq,
      'event_id': id,
      'type': 'config_changed',
      'config_version': configVersion,
      'patches': const [],
      'queue_counts': const {},
    });

KdsV2Envelope _cursorEvent(int seq) => KdsV2Envelope(
      eventSeq: seq,
      eventId: 'cursor-$seq',
      type: 'cursor_advanced',
      patches: const [],
      queueCounts: const {},
    );
