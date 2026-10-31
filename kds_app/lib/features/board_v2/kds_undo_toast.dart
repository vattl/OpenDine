import 'package:flutter/foundation.dart';

/// 一次可撤销的划菜记录：用于「待传菜划到已完成成功 → 顶部 5s 撤回」提示条。
///
/// [destQueue] 是划菜后明细实际所处的新队列（撤销命令 revoke_item 的
/// from_queue），由服务端确认后的切片数量差权威判定；无法判定时按
/// prep→cook→serve→done 工作流推断（见 [advanceDestQueue]）。
@immutable
class KdsAdvanceUndoItem {
  const KdsAdvanceUndoItem({
    required this.detailId,
    required this.orderId,
    required this.dishName,
    required this.unit,
    required this.quantity,
    required this.destQueue,
    this.tableOrPickupCode = '',
  });

  final int detailId;
  final int orderId;
  final String dishName;
  final String unit;
  final int quantity;

  /// 划菜后明细所在队列（撤销时的 from_queue），如 ready_serve / done
  final String destQueue;

  /// 堂食台号或自提/外卖/打包取餐码，如「A01」、「自提 13909」
  final String tableOrPickupCode;
}

/// 一条可撤回的划菜记录（提示条数据）。仅承载最近一次「待传菜→已完成」的
/// 划菜：新划菜直接替换旧的，不支持合并/全部撤回；点击「撤回」退回该次划菜。
@immutable
class KdsAdvanceUndoBatch {
  const KdsAdvanceUndoBatch({
    required this.items,
    required this.generatedAt,
  });

  final List<KdsAdvanceUndoItem> items;
  final DateTime generatedAt;
}

/// 划菜成功后确定明细所处的新队列（撤销命令的 from_queue）：
/// 优先通过前后切片数量差定位（权威：哪个队列的数量增加了，划菜后就在哪），
/// 找不到增量时按工作流 prep→cook→serve→done 推断。
String advanceDestQueue(
  String sourceQueue,
  Map<String, int> before,
  Map<String, int> after,
) {
  for (final entry in after.entries) {
    if (entry.value > (before[entry.key] ?? 0)) {
      return entry.key;
    }
  }
  return switch (sourceQueue) {
    'pending_prep' => 'pending_cook',
    'pending_cook' => 'ready_serve',
    'ready_serve' => 'done',
    _ => 'done',
  };
}

/// 撤回提示条文案：单条「A01 · 3份 烤茄子」或「3份 烤茄子」；多条时 ≤2 条用「、」连接，
/// 更多显示「前两项 等 N 项」（当前仅单条场景使用，保留通用折叠逻辑）。
String undoBatchSummary(KdsAdvanceUndoBatch batch) {
  final parts = <String>[
    for (final item in batch.items)
      if (item.tableOrPickupCode.isNotEmpty)
        '${item.tableOrPickupCode} · ${item.quantity}${item.unit} ${item.dishName}'
      else
        '${item.quantity}${item.unit} ${item.dishName}',
  ];
  if (parts.length <= 2) return parts.join('、');
  return '${parts.take(2).join('、')} 等 ${parts.length} 项';
}
