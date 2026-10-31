import 'dart:convert';

import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化最近一次权威看板快照，用于收银端不可达时的离线兜底渲染。
///
/// 场景：应用重启 / 看板重新挂载时收银端恰好关闭，bootstrap 失败后
/// KDS 不应整板阻塞。先恢复此缓存快照展示剩余菜品，厨房仍可划菜，
/// 划菜指令进入待同步队列；收银端恢复后以 bootstrap 权威数据覆盖。
///
/// 仅做本地兜底展示，不写回收银端；容量有上限，单行损坏自动跳过。
class KdsBoardSnapshotStore {
  KdsBoardSnapshotStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'kds_board_snapshot_v1';

  /// 缓存行数上限：优先保留活动队列（待配菜/待制作/待传菜）行，
  /// 剩余额度给已完成历史尾部，避免营业高峰时缓存无限膨胀。
  static const _lineCap = 800;

  Future<void> save(KdsV2State state, {int? shopId}) async {
    // 空快照不落盘，避免以空覆盖上一次有效缓存。
    if (state.lines.isEmpty) return;

    // 已完成持久化保护：新状态的已完成行少于上次缓存时，保留缓存中
    // 独有的已完成行（防止 bootstrap 中间态/清空态覆盖本地历史，
    // 保证"划菜完成的菜品一直存在"跨重启/重建成立）。
    final previous = load(expectedShopId: shopId);
    final active = state.lines
        .where((line) => line.queue != 'done')
        .toList(growable: false);
    final doneById = <int, KdsV2Line>{
      for (final line in state.lines.where((line) => line.queue == 'done'))
        line.detailId: line,
    };
    if (previous != null) {
      for (final line in previous.lines) {
        if (line.queue != 'done') continue;
        doneById.putIfAbsent(line.detailId, () => line);
      }
    }
    final kept = <KdsV2Line>[...active];
    if (kept.length < _lineCap) {
      kept.addAll(doneById.values.take(_lineCap - kept.length));
    }

    final payload = <String, dynamic>{
      if (shopId != null) 'shop_id': shopId,
      'event_seq': state.eventSeq,
      if (state.configVersion != null) 'config_version': state.configVersion,
      'queue_counts': state.queueCounts,
      'lines': [
        for (final line in kept) {'queue': line.queue, 'raw': line.raw},
      ],
      'catalog': [
        for (final item in state.catalog)
          {
            'dish_id': item.dishId,
            'dish_name': item.dishName,
            'unit': item.unit,
            'sequence': item.sequence,
            'id': item.id,
            'category_id': item.categoryId,
            'category_name': item.categoryName,
            'category_sequence': item.categorySequence,
            'sold_out': item.soldOut,
          },
      ],
    };
    await _prefs.setString(_key, jsonEncode(payload));
  }

  /// 读取缓存快照；无缓存、损坏、解析后无行或门店不匹配时返回 null。
  KdsV2State? load({int? expectedShopId}) {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      // 门店隔离：换店登录时不得恢复上一家店的订单快照。
      final cachedShopId = json['shop_id'] is num
          ? (json['shop_id'] as num).toInt()
          : null;
      if (cachedShopId != expectedShopId) return null;
      final lines = <KdsV2Line>[];
      for (final entry in (json['lines'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final rawLine = entry['raw'];
        if (rawLine is! Map) continue;
        try {
          final line = KdsV2Line.fromLegacyJson(
            Map<String, dynamic>.from(rawLine),
            queueFallback: entry['queue'] as String?,
          );
          // 单行基础校验：detailId/数量非法则视为损坏行跳过。
          if (line.detailId <= 0 || line.quantity <= 0) continue;
          lines.add(line);
        } on FormatException {
          // 单条损坏行跳过，不影响其余缓存行。
        }
      }
      if (lines.isEmpty) return null;

      final catalog = <KdsV2CatalogItem>[];
      for (final entry in (json['catalog'] as List? ?? const [])) {
        if (entry is! Map) continue;
        try {
          catalog
              .add(KdsV2CatalogItem.fromJson(Map<String, dynamic>.from(entry)));
        } on FormatException {
          // 单条目录损坏跳过。
        }
      }

      final queueCounts = <String, int>{};
      final rawCounts = json['queue_counts'];
      if (rawCounts is Map) {
        for (final entry in rawCounts.entries) {
          final value = entry.value is num ? (entry.value as num).toInt() : 0;
          if (value > 0) queueCounts['${entry.key}'] = value;
        }
      }

      return KdsV2State(
        eventSeq: json['event_seq'] is num ? (json['event_seq'] as num).toInt() : 0,
        lines: List.unmodifiable(lines),
        queueCounts: Map.unmodifiable(queueCounts),
        catalog: List.unmodifiable(catalog),
        configVersion:
            json['config_version'] is num ? (json['config_version'] as num).toInt() : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
