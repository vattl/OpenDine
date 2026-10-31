enum KdsScreenTag {
  skewerAggregate('skewer_aggregate', '抓串屏'),
  meatGrill('meat_grill', '荤烤屏'),
  vegGrill('veg_grill', '素烤屏'),
  seafoodSpecial('seafood_special', '海鲜屏'),
  expedition('expedition', '出餐屏'),
  bossOverview('boss_overview', '收银总览'),
  workflowBoard('workflow_board', '统一工作流看板');

  const KdsScreenTag(this.value, this.label);
  final String value;
  final String label;

  static KdsScreenTag? fromValue(String? v) {
    if (v == null) return null;
    for (final t in values) {
      if (t.value == v) return t;
    }
    return null;
  }

  bool get isOverview =>
      this == expedition || this == bossOverview || this == workflowBoard;
  bool get isGrill =>
      this == meatGrill || this == vegGrill || this == seafoodSpecial;

  /// 出餐屏待传菜可划菜传菜
  bool get canExpeditionServe => this == expedition;
}

enum KdsWorkflow {
  prep('prep', '配菜'),
  cook('cook', '制作'),
  serve('serve', '传菜');

  const KdsWorkflow(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static KdsWorkflow? fromValue(String? v) {
    if (v == null) return null;
    for (final w in values) {
      if (w.apiValue == v) return w;
    }
    return null;
  }
}

/// 解析服务端 workflows 数组（login / device/me / workflow/board）
List<KdsWorkflow> parseKdsWorkflows(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => KdsWorkflow.fromValue('$e'))
      .whereType<KdsWorkflow>()
      .toList();
}

/// 由 workflows 推导可见 Tab（prep/cook/serve + done）
/// [skewerGate]=0 时跳过配菜 Tab（创单即 skewer_picked=1，见回归矩阵 §6.3）
List<BoardQueue> boardQueuesForWorkflows(
  List<KdsWorkflow> workflows, {
  int? skewerGate,
}) {
  const order = [KdsWorkflow.prep, KdsWorkflow.cook, KdsWorkflow.serve];
  final skipPrep = skewerGate == 0;
  return [
    for (final w in order)
      if (workflows.contains(w) && !(skipPrep && w == KdsWorkflow.prep))
        w.queue,
    BoardQueue.done,
  ];
}

enum BoardQueue { pendingPrep, pendingCook, readyServe, done }

extension BoardQueueX on BoardQueue {
  String get apiValue => switch (this) {
        BoardQueue.pendingPrep => 'pending_prep',
        BoardQueue.pendingCook => 'pending_cook',
        BoardQueue.readyServe => 'ready_serve',
        BoardQueue.done => 'done',
      };

  String get label => switch (this) {
        BoardQueue.pendingPrep => '待配菜',
        BoardQueue.pendingCook => '待制作',
        BoardQueue.readyServe => '待传菜',
        BoardQueue.done => '已完成',
      };
}

extension KdsWorkflowX on KdsWorkflow {
  BoardQueue get queue => switch (this) {
        KdsWorkflow.prep => BoardQueue.pendingPrep,
        KdsWorkflow.cook => BoardQueue.pendingCook,
        KdsWorkflow.serve => BoardQueue.readyServe,
      };
}

enum BoardDining { all, dineIn, takeout, pack }

extension BoardDiningX on BoardDining {
  String get apiValue => switch (this) {
        BoardDining.all => 'all',
        BoardDining.dineIn => 'dine_in',
        BoardDining.takeout => 'takeout',
        BoardDining.pack => 'pack',
      };

  String get label => switch (this) {
        BoardDining.all => '全部',
        BoardDining.dineIn => '堂食',
        BoardDining.takeout => '外卖',
        // pack/pickup 桶对应自提类订单（取餐码 A 前缀）
        BoardDining.pack => '自提',
      };
}

enum BoardExtraFilter { overdue, rush, addDish, hold }

extension BoardExtraFilterX on BoardExtraFilter {
  String get apiValue => switch (this) {
        BoardExtraFilter.overdue => 'overdue',
        BoardExtraFilter.rush => 'rush',
        BoardExtraFilter.addDish => 'add_dish',
        BoardExtraFilter.hold => 'hold',
      };

  String get label => switch (this) {
        BoardExtraFilter.overdue => '超时',
        BoardExtraFilter.rush => '催菜',
        BoardExtraFilter.addDish => '加菜',
        BoardExtraFilter.hold => '等叫',
      };
}

enum BoardSortMode { fifo, overdueFirst, rushFirst }

extension BoardSortModeX on BoardSortMode {
  String get apiValue => switch (this) {
        BoardSortMode.fifo => 'order_time',
        BoardSortMode.overdueFirst => 'overdue_first',
        BoardSortMode.rushFirst => 'rush_first',
      };

  String get label => switch (this) {
        BoardSortMode.fifo => '先进先出',
        BoardSortMode.overdueFirst => '超时优先',
        BoardSortMode.rushFirst => '催菜优先',
      };

  /// FIFO 为默认排序，请求 workflow/board 时可省略 sort 参数
  bool get omitFromWorkflowApi => this == BoardSortMode.fifo;
}

/// 看板合并规则（OpenAPI merge_rules，可组合）
enum BoardMergeRule {
  dish('dish', '按菜品合并'),
  dining('dining', '按用餐类型'),
  tags('tags', '按特殊标签');

  const BoardMergeRule(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BoardMergeRule? fromValue(String? v) {
    if (v == null) return null;
    final key = v.trim().toLowerCase();
    for (final r in values) {
      if (r.apiValue == key) return r;
    }
    return null;
  }
}

/// 前端合并覆盖模式（v1.2.127：默认跟随门店 t_kds_shop_config）
enum BoardMergeOverride {
  followShop('follow_shop', '跟随门店'),
  detailFifo('detail', '明细一行'),
  custom('custom', '自定义规则');

  const BoardMergeOverride(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static BoardMergeOverride? fromStorage(String? v) {
    if (v == null) return null;
    for (final o in values) {
      if (o.storageValue == v) return o;
    }
    return null;
  }
}

/// 单 Tab 合并偏好（持久化 + 请求 workflow/board）
class BoardMergeSettings {
  const BoardMergeSettings({
    this.override = BoardMergeOverride.followShop,
    this.customRules = const [],
    this.splitPackTakeout = false,
  });

  final BoardMergeOverride override;
  final List<BoardMergeRule> customRules;

  /// true 时请求带 split_pack_takeout=1（打包/外卖单独成行）
  final bool splitPackTakeout;

  BoardMergeSettings copyWith({
    BoardMergeOverride? override,
    List<BoardMergeRule>? customRules,
    bool? splitPackTakeout,
  }) {
    return BoardMergeSettings(
      override: override ?? this.override,
      customRules: customRules ?? this.customRules,
      splitPackTakeout: splitPackTakeout ?? this.splitPackTakeout,
    );
  }
}

/// 看板合并展示（设置页二选一，默认跟随门店）
enum KdsMergeDisplayMode {
  followShop('follow_shop', '跟随门店设置', '使用门店后台合并配置（跨单/堂打包/套餐等）'),
  noMerge('no_merge', '不合并', '明细一行展示，请求 merge_rules=none');

  const KdsMergeDisplayMode(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static KdsMergeDisplayMode? fromStorage(String? v) {
    if (v == null) return null;
    for (final m in values) {
      if (m.storageValue == v) return m;
    }
    return null;
  }

  BoardMergeSettings toMergeSettings() => BoardMergeSettings(
        override: this == followShop
            ? BoardMergeOverride.followShop
            : BoardMergeOverride.detailFifo,
      );
}

/// 分批操作方式（按工序 Tab 独立设置，默认点击数量分批）
enum KdsBatchAdvanceMode {
  quantityOnly(
    'quantity_only',
    '点击数量分批',
    '点击卡片右下角数量弹出数字键盘；点击卡片整卡推进，适合非高频分批',
  ),
  alwaysKeyboard(
    'always_keyboard',
    '点击弹出数字键盘',
    '点击卡片始终弹出数字键盘实现分批，适合高频分批操作',
  );

  const KdsBatchAdvanceMode(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static KdsBatchAdvanceMode? fromStorage(String? v) {
    if (v == null) return null;
    for (final m in values) {
      if (m.storageValue == v) return m;
    }
    return null;
  }
}

/// 待配菜 / 待制作 / 待传菜 可配置分批的 Tab
const kdsBatchAdvanceQueues = [
  BoardQueue.pendingPrep,
  BoardQueue.pendingCook,
  BoardQueue.readyServe,
];

/// 门店合并配置（workflow/board 响应 v1.2.127）
class KdsShopMergeConfig {
  const KdsShopMergeConfig({
    this.mergeSameDish = true,
    this.packInlineMerge = true,
    this.comboMerge = false,
    this.crossOrderMerge = false,
    this.splitPackTakeoutActive = false,
  });

  final bool mergeSameDish;
  final bool packInlineMerge;
  final bool comboMerge;
  final bool crossOrderMerge;
  final bool splitPackTakeoutActive;

  factory KdsShopMergeConfig.fromBoardJson(Map<String, dynamic> data) {
    bool flag(dynamic v, {bool defaultTrue = false}) {
      if (v == null) return defaultTrue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      return defaultTrue;
    }

    return KdsShopMergeConfig(
      mergeSameDish: flag(data['merge_same_dish'], defaultTrue: true),
      packInlineMerge: flag(data['pack_inline_merge'], defaultTrue: true),
      comboMerge: flag(data['combo_merge']),
      crossOrderMerge: flag(data['cross_order_merge']),
      splitPackTakeoutActive: flag(data['split_pack_takeout']),
    );
  }

  String get shortLabel {
    if (!mergeSameDish) return '门店·明细一行';
    final parts = <String>['门店·跨单合并'];
    if (packInlineMerge && !splitPackTakeoutActive) {
      parts.add('堂打包内嵌');
    } else {
      parts.add('渠道拆行');
    }
    if (comboMerge) parts.add('套餐合并');
    return parts.join('·');
  }
}

List<BoardMergeRule> parseMergeRules(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) return const [];
  return raw
      .map((e) => BoardMergeRule.fromValue('$e'))
      .whereType<BoardMergeRule>()
      .toList();
}

/// 编码 merge_rules；null 表示不传参（跟随门店配置）
String? mergeRulesQueryParam(BoardMergeSettings settings) {
  switch (settings.override) {
    case BoardMergeOverride.followShop:
      return null;
    case BoardMergeOverride.detailFifo:
      return 'none';
    case BoardMergeOverride.custom:
      if (settings.customRules.isEmpty) return 'none';
      return settings.customRules.map((r) => r.apiValue).join(',');
  }
}

@Deprecated('Use mergeRulesQueryParam(BoardMergeSettings)')
String mergeRulesQueryValue(List<BoardMergeRule> rules) {
  if (rules.isEmpty) return 'none';
  return rules.map((r) => r.apiValue).join(',');
}

String mergeSettingsSummary(
  BoardMergeSettings settings, {
  KdsShopMergeConfig? shop,
}) {
  final base = switch (settings.override) {
    BoardMergeOverride.followShop => BoardMergeOverride.followShop.label,
    BoardMergeOverride.detailFifo => BoardMergeOverride.detailFifo.label,
    BoardMergeOverride.custom => settings.customRules.isEmpty
        ? BoardMergeOverride.detailFifo.label
        : settings.customRules.map((r) => r.label).join('+'),
  };
  if (settings.splitPackTakeout &&
      settings.override == BoardMergeOverride.custom) {
    return '$base·打包拆行';
  }
  return base;
}

@Deprecated('Use mergeSettingsSummary')
String mergeRulesSummary(List<BoardMergeRule> rules) {
  if (rules.isEmpty) return '明细FIFO';
  return rules.map((r) => r.label).join('+');
}

/// @deprecated v1.2.127 默认跟随门店
List<BoardMergeRule> defaultMergeRulesForQueue(BoardQueue queue) => const [];
