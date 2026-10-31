import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用偏好（新单提示音、sync since 等）
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _soundKey = 'new_order_sound';
  static const _sinceKey = 'sync_since_ms';
  static const _mergeDisplayKey = 'kds_merge_display_mode';
  static const _batchAdvancePrefix = 'kds_batch_advance_';
  static const _mergeRulesPrefix = 'kds_merge_rules_';
  static const _mergeOverridePrefix = 'kds_merge_override_';
  static const _splitPackPrefix = 'kds_split_pack_';
  static const _slaMinutesKey = 'kds_sla_minutes';
  static const _cashierWriteBackKey = 'kds_cashier_write_back';
  static const _servePrintKey = 'kds_serve_print';
  static const _crossOrderMergeKey = 'kds_cross_order_merge';
  static const _addDishIndependentKey = 'kds_add_dish_independent';
  static const _comboIndependentKey = 'kds_combo_independent';
  static const _dinePackInlineKey = 'kds_dine_pack_inline';
  static const _fixedDishOrderKey = 'kds_fixed_dish_order';
  static const _mergeSameDishNameKey = 'kds_merge_same_dish_name';
  static const _prepFlowEnabledKey = 'kds_prep_flow_enabled';
  static const _advanceQuantityDialogKey = 'kds_advance_quantity_dialog';
  static const _cardScalePercentKey = 'kds_card_scale_percent';

  static Future<AppPrefs> load() async {
    return AppPrefs(await SharedPreferences.getInstance());
  }

  bool get newOrderSoundEnabled => _prefs.getBool(_soundKey) ?? true;

  Future<void> setNewOrderSoundEnabled(bool v) => _prefs.setBool(_soundKey, v);

  int get syncSinceMs =>
      _prefs.getInt(_sinceKey) ?? DateTime.now().millisecondsSinceEpoch;

  Future<void> setSyncSinceMs(int ms) => _prefs.setInt(_sinceKey, ms);

  Future<void> bumpSyncSince() =>
      setSyncSinceMs(DateTime.now().millisecondsSinceEpoch);

  int get slaMinutes => _prefs.getInt(_slaMinutesKey) ?? 10;

  Future<void> setSlaMinutes(int minutes) =>
      _prefs.setInt(_slaMinutesKey, minutes.clamp(1, 240));

  bool get cashierWriteBackEnabled =>
      _prefs.getBool(_cashierWriteBackKey) ?? true;

  Future<void> setCashierWriteBackEnabled(bool v) =>
      _prefs.setBool(_cashierWriteBackKey, v);

  bool get servePrintEnabled => _prefs.getBool(_servePrintKey) ?? true;

  Future<void> setServePrintEnabled(bool v) =>
      _prefs.setBool(_servePrintKey, v);

  bool get crossOrderMergeEnabled =>
      _prefs.getBool(_crossOrderMergeKey) ?? true;

  Future<void> setCrossOrderMergeEnabled(bool v) =>
      _prefs.setBool(_crossOrderMergeKey, v);

  bool get addDishIndependentEnabled =>
      _prefs.getBool(_addDishIndependentKey) ?? true;

  Future<void> setAddDishIndependentEnabled(bool v) =>
      _prefs.setBool(_addDishIndependentKey, v);

  bool get comboIndependentEnabled =>
      _prefs.getBool(_comboIndependentKey) ?? false;

  Future<void> setComboIndependentEnabled(bool v) =>
      _prefs.setBool(_comboIndependentKey, v);

  bool get dinePackInlineEnabled => _prefs.getBool(_dinePackInlineKey) ?? true;

  Future<void> setDinePackInlineEnabled(bool v) =>
      _prefs.setBool(_dinePackInlineKey, v);

  bool get fixedDishOrderEnabled => _prefs.getBool(_fixedDishOrderKey) ?? true;

  Future<void> setFixedDishOrderEnabled(bool v) =>
      _prefs.setBool(_fixedDishOrderKey, v);

  /// 非固定菜品模式下是否按菜品名称合并（忽略规格）。
  /// 默认开启，与固定菜品模式的合并口径保持一致。
  bool get mergeSameDishNameEnabled =>
      _prefs.getBool(_mergeSameDishNameKey) ?? true;

  Future<void> setMergeSameDishNameEnabled(bool v) =>
      _prefs.setBool(_mergeSameDishNameKey, v);

  bool get prepFlowEnabled => _prefs.getBool(_prepFlowEnabledKey) ?? true;

  Future<void> setPrepFlowEnabled(bool v) =>
      _prefs.setBool(_prepFlowEnabledKey, v);

  /// 划菜数量弹窗：打开后单击卡片先弹数量选择；关闭后单击整卡划出、长按选数量
  bool get advanceQuantityDialogEnabled =>
      _prefs.getBool(_advanceQuantityDialogKey) ?? false;

  Future<void> setAdvanceQuantityDialogEnabled(bool v) =>
      _prefs.setBool(_advanceQuantityDialogKey, v);

  /// 看板卡片缩放百分比（70–160，默认 100）
  int get cardScalePercent =>
      (_prefs.getInt(_cardScalePercentKey) ?? 100).clamp(70, 160);

  Future<void> setCardScalePercent(int v) =>
      _prefs.setInt(_cardScalePercentKey, v.clamp(70, 160));

  KdsMergeDisplayMode get mergeDisplayMode =>
      KdsMergeDisplayMode.fromStorage(_prefs.getString(_mergeDisplayKey)) ??
      KdsMergeDisplayMode.followShop;

  Future<void> setMergeDisplayMode(KdsMergeDisplayMode mode) =>
      _prefs.setString(_mergeDisplayKey, mode.storageValue);

  KdsBatchAdvanceMode getBatchAdvanceMode(BoardQueue queue) {
    if (queue == BoardQueue.done) return KdsBatchAdvanceMode.quantityOnly;
    return KdsBatchAdvanceMode.fromStorage(
          _prefs.getString('$_batchAdvancePrefix${queue.apiValue}'),
        ) ??
        KdsBatchAdvanceMode.quantityOnly;
  }

  Future<void> setBatchAdvanceMode(
          BoardQueue queue, KdsBatchAdvanceMode mode) =>
      _prefs.setString(
          '$_batchAdvancePrefix${queue.apiValue}', mode.storageValue);

  /// 旧版按 Tab 合并偏好（兼容读取，新设置请用 [mergeDisplayMode]）
  BoardMergeSettings? getMergeSettings(BoardQueue queue) {
    final overrideRaw =
        _prefs.getString('$_mergeOverridePrefix${queue.apiValue}');
    final rulesRaw = _prefs.getString('$_mergeRulesPrefix${queue.apiValue}');
    final splitPack =
        _prefs.getBool('$_splitPackPrefix${queue.apiValue}') ?? false;

    if (overrideRaw != null) {
      final override = BoardMergeOverride.fromStorage(overrideRaw) ??
          BoardMergeOverride.followShop;
      return BoardMergeSettings(
        override: override,
        customRules: _parseRulesList(rulesRaw),
        splitPackTakeout: splitPack,
      );
    }

    if (rulesRaw == null) return null;
    if (rulesRaw == 'none' || rulesRaw.isEmpty) {
      return BoardMergeSettings(
        override: BoardMergeOverride.detailFifo,
        splitPackTakeout: splitPack,
      );
    }
    return BoardMergeSettings(
      override: BoardMergeOverride.custom,
      customRules: _parseRulesList(rulesRaw),
      splitPackTakeout: splitPack,
    );
  }

  List<BoardMergeRule> _parseRulesList(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return const [];
    return raw
        .split(',')
        .map(BoardMergeRule.fromValue)
        .whereType<BoardMergeRule>()
        .toList();
  }

  Future<void> setMergeSettings(
      BoardQueue queue, BoardMergeSettings settings) async {
    await _prefs.setString(
      '$_mergeOverridePrefix${queue.apiValue}',
      settings.override.storageValue,
    );
    await _prefs.setString(
      '$_mergeRulesPrefix${queue.apiValue}',
      settings.customRules.isEmpty
          ? 'none'
          : settings.customRules.map((r) => r.apiValue).join(','),
    );
    await _prefs.setBool(
        '$_splitPackPrefix${queue.apiValue}', settings.splitPackTakeout);
  }

  List<BoardMergeRule>? getMergeRules(BoardQueue queue) {
    return getMergeSettings(queue)?.customRules;
  }

  Future<void> setMergeRules(
      BoardQueue queue, List<BoardMergeRule> rules) async {
    await setMergeSettings(
      queue,
      BoardMergeSettings(
          override: BoardMergeOverride.custom, customRules: rules),
    );
  }
}

final appPrefsProvider = FutureProvider<AppPrefs>((ref) => AppPrefs.load());
