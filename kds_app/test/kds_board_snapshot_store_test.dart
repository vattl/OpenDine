import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/storage/kds_board_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  KdsV2Line line(int detailId, String queue) => KdsV2Line.fromLegacyJson({
        'detail_id': detailId,
        'order_id': 5,
        'dish_id': 3,
        'dish_name': '烤羊排',
        'quantity': 2,
        'workflow_queue': queue,
        'fulfillment_type': 'dine_in',
        'fulfillment_channel': 'dine_in',
        'order_no': 'O-5',
        'table_number': 'A1',
        'unit': '份',
        'local_revision': 1,
        'order_revision': 1,
        'created_at_ms': 1720000000000,
      });

  KdsV2State buildState() => KdsV2State(
        eventSeq: 9,
        lines: List.unmodifiable([
          line(11, 'pending_cook'),
          line(12, 'done'),
        ]),
        queueCounts: const {'pending_cook': 2, 'done': 2},
        catalog: List.unmodifiable([
          const KdsV2CatalogItem(
            dishId: 3,
            dishName: '烤羊排',
            unit: '份',
            sequence: 0,
            id: 7,
            categoryId: 1,
            categoryName: '烧烤',
            categorySequence: 0,
          ),
        ]),
      );

  test('save then load round-trips lines, catalog and queue counts', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    await store.save(buildState(), shopId: 42);
    final restored = store.load(expectedShopId: 42);

    expect(restored, isNotNull);
    expect(restored!.lines.length, 2);
    expect(restored.lines.first.detailId, 11);
    expect(restored.lines.first.dishName, '烤羊排');
    expect(restored.lines.first.queue, 'pending_cook');
    expect(restored.lines[1].queue, 'done');
    expect(restored.queueCounts['pending_cook'], 2);
    expect(restored.catalog.single.dishId, 3);
    expect(restored.catalog.single.categoryName, '烧烤');
  });

  test('load returns null for a different shop (shop isolation)', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    await store.save(buildState(), shopId: 42);

    expect(store.load(expectedShopId: 42), isNotNull);
    expect(store.load(expectedShopId: 99), isNull);
    expect(store.load(expectedShopId: null), isNull);
  });

  test('empty state save does not overwrite an existing snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    await store.save(buildState(), shopId: 42);
    await store.save(const KdsV2State(), shopId: 42);

    final restored = store.load(expectedShopId: 42);
    expect(restored, isNotNull);
    expect(restored!.lines, isNotEmpty);
  });

  test('corrupt lines are skipped while valid lines survive', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);
    final valid = line(11, 'pending_cook');

    await prefs.setString('kds_board_snapshot_v1', jsonEncode({
      'shop_id': 42,
      'event_seq': 9,
      'lines': [
        {'queue': 'pending_cook', 'raw': valid.raw},
        {
          'queue': 'pending_cook',
          'raw': {'detail_id': 'broken'},
        },
      ],
      'catalog': const [],
      'queue_counts': const {'pending_cook': 1},
    }));

    final restored = store.load(expectedShopId: 42);
    expect(restored, isNotNull);
    expect(restored!.lines.length, 1);
    expect(restored.lines.single.detailId, 11);
  });

  test('load returns null when nothing cached or payload is garbage', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    expect(store.load(expectedShopId: 42), isNull);

    await prefs.setString('kds_board_snapshot_v1', 'not-json');
    expect(store.load(expectedShopId: 42), isNull);

    await prefs.setString('kds_board_snapshot_v1', jsonEncode({'nope': 1}));
    expect(store.load(expectedShopId: 42), isNull);
  });

  test('clear removes the cached snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    await store.save(buildState(), shopId: 42);
    expect(store.load(expectedShopId: 42), isNotNull);

    await store.clear();
    expect(store.load(expectedShopId: 42), isNull);
  });

  test('save keeps old done rows when a rebuild state drops them', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = KdsBoardSnapshotStore(prefs);

    // 先落盘含已完成行的状态
    await store.save(buildState(), shopId: 1);
    expect(store.load(expectedShopId: 1)!.lines.length, 2);

    // 模拟 bootstrap 中间态：新状态只剩活动行（done 被清空）→ 落盘
    await store.save(
      KdsV2State(eventSeq: 10, lines: List.unmodifiable([line(11, 'pending_cook')])),
      shopId: 1,
    );

    // 已完成行不能被清空态覆盖：旧 done 行保留
    final loaded = store.load(expectedShopId: 1);
    final ids = loaded!.lines.map((l) => l.detailId).toSet();
    expect(ids, contains(12));
    expect(ids, contains(11));
  });
}
