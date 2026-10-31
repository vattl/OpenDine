import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'combo_editor_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_section_visibility.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../data/cashier_catalog_repository.dart';
import '../domain/cashier_dish.dart';
import 'dish_specification_editor.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class CashierDishStatusPage extends StatefulWidget {
  const CashierDishStatusPage({
    super.key,
    required this.repository,
    required this.canManage,
  });

  final CashierCatalogRepository repository;
  final bool canManage;

  @override
  State<CashierDishStatusPage> createState() => _CashierDishStatusPageState();
}

class _CashierDishStatusPageState extends State<CashierDishStatusPage>
    with CashierSectionVisibilityMixin {
  List<CashierDishCategory> _categories = const [];
  List<CashierDish> _dishes = const [];
  String? _selectedCategoryKey;
  int? _submittingId;
  int? _deletingCategoryId;
  bool _loading = true;
  bool _creating = false;
  bool _creatingCombo = false;
  bool _creatingCategory = false;
  bool _reordering = false;
  String? _error;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'all';

  /// 排序成功轻提示（页面内浮层，非 SnackBar）。
  String? _savedTip;
  Timer? _savedTipTimer;

  CashierDishCategory? get _selectedCategory {
    final key = _selectedCategoryKey;
    if (key == null) return null;
    for (final category in _categories) {
      if (category.key == key) return category;
    }
    return null;
  }

  List<CashierDish> get _dishesInCategory {
    final category = _selectedCategory;
    if (category == null) return _dishes;
    return _dishes.where(category.matches).toList(growable: false);
  }

  List<CashierDish> get _visibleDishes {
    var result = _dishesInCategory;
    if (_selectedStatusFilter == 'sufficient') {
      result = result
          .where((d) => d.availability == CashierDishAvailability.sufficient)
          .toList(growable: false);
    } else if (_selectedStatusFilter == 'low') {
      result = result
          .where((d) => d.availability == CashierDishAvailability.lowStock)
          .toList(growable: false);
    } else if (_selectedStatusFilter == 'soldout') {
      result = result
          .where((d) => d.availability == CashierDishAvailability.soldOut)
          .toList(growable: false);
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((d) {
        final nameMatch = d.name.toLowerCase().contains(query);
        final catMatch = d.categoryName.toLowerCase().contains(query);
        final specMatch = d.specification.toLowerCase().contains(query);
        final codeMatch = d.categoryCode.toLowerCase().contains(query);
        return nameMatch || catMatch || specMatch || codeMatch;
      }).toList(growable: false);
    }
    return result;
  }

  bool get _busy =>
      _submittingId != null ||
      _deletingCategoryId != null ||
      _creating ||
      _creatingCategory;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  /// 侧边栏切回可见 / 可见轮询：静默刷新菜品列表；
  /// 页面正在编辑/提交时跳过本轮，避免覆盖进行中操作。
  @override
  Future<void> refreshSectionSilently() async {
    if (_busy) return;
    await _load(silent: true);
  }

  Future<bool> _load({bool initial = false, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // 菜品接口已内嵌每个菜品的分类（type），初始加载不再单独请求分类接口：
      // 分类从菜品聚合，保留上一次的分类（含手动新建的空分类）并由菜品内嵌 type 自动补全。
      final loadedDishes = await widget.repository.loadAllDishes(query: '');
      if (!mounted) return false;
      final mergedCategories = mergeCashierCategoriesWithDishes(
        categories: _categories,
        dishes: loadedDishes,
      );
      setState(() {
        _categories = mergedCategories;
        _dishes = loadedDishes;
        if (!silent) _loading = false;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (!silent) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
      return false;
    }
  }

  Future<void> _toggleSoldOut(CashierDish dish) async {
    // 恢复可售：先设置库存数量再恢复
    if (dish.soldOut) {
      await _restockDish(dish);
      return;
    }
    // 设为售罄：确认后直接下架库存
    final confirmed = await showPosNotice(
      context,
      title: '售罄提示',
      message: '确定将“${dish.name}”设为售罄吗？\n该菜品将不能继续下单。',
      tone: PosNoticeTone.warning,
      primaryLabel: '确认售罄',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() => _submittingId = dish.id);
    try {
      await widget.repository.updateSoldOut(dish: dish, soldOut: true);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _submittingId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submittingId = null);
      await _showError('设置售罄失败', error);
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  /// 恢复可售：弹出数量设置，确定后保存新库存并恢复为可售。
  Future<void> _restockDish(CashierDish dish) async {
    final stock = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RestockDialog(name: dish.name),
    );
    if (stock == null || !mounted) return;
    setState(() => _submittingId = dish.id);
    try {
      await widget.repository.saveDish(
        CashierDishInput(
          id: dish.id,
          name: dish.name,
          specification: dish.specification,
          price: dish.price,
          unit: dish.unit,
          stock: stock,
          onSale: dish.onSale,
          soldOut: false,
          typeId: dish.typeId,
          image: dish.image,
          sorting: dish.sorting,
          quantity: dish.quantity,
          servingDurationMinutes: dish.servingDurationMinutes,
        ),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _submittingId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submittingId = null);
      await _showError('恢复可售失败', error);
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  /// 快速增量加库存 (+5/+10 快捷步进)
  Future<void> _quickAddStock(CashierDish dish, int count) async {
    if (_busy) return;
    setState(() => _submittingId = dish.id);
    try {
      final currentStock = (dish.stock != null && dish.stock! > 0) ? dish.stock! : 0;
      final int newStock = currentStock + count;
      await widget.repository.saveDish(
        CashierDishInput(
          id: dish.id,
          name: dish.name,
          specification: dish.specification,
          price: dish.price,
          unit: dish.unit,
          stock: newStock,
          onSale: dish.onSale,
          soldOut: false,
          typeId: dish.typeId,
          image: dish.image,
          sorting: dish.sorting,
          quantity: dish.quantity,
          servingDurationMinutes: dish.servingDurationMinutes,
        ),
      );
      if (!mounted) return;
      await _load(silent: true);
    } catch (error) {
      if (mounted) await _showError('加量失败', error);
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  Future<void> _editDish([CashierDish? dish]) async {
    final result = await showDialog<_DishEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DishEditorDialog(
            dish: dish,
            categories: _categories,
            repository: widget.repository,
          ),
    );
    if (result == null || !mounted) return;
    if (result is _DishEditorDelete) {
      final target = dish;
      if (target != null) await _deleteDish(target);
      return;
    }
    final input = (result as _DishEditorSave).input;
    setState(() {
      if (dish == null) {
        _creating = true;
      } else {
        _submittingId = dish.id;
      }
    });
    try {
      await widget.repository.saveDish(input);
      if (dish != null && input.onSale != dish.onSale) {
        await widget.repository.updateOnSale(dish: dish, onSale: input.onSale);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() {
        _creating = false;
        _submittingId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _submittingId = null;
      });
      await _showError(dish == null ? '增加菜品失败' : '编辑菜品失败', error);
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
          _submittingId = null;
        });
      }
    }
  }

  Future<void> _configCombo(CashierDish dish) async {
    final changed = await ComboEditorDialog.show(
      context: context,
      headerDish: dish,
      repository: widget.repository,
      categories: _categories,
      allDishes: _dishes,
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _createCombo() async {
    final result = await showDialog<_DishEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DishEditorDialog(
        dish: null,
        categories: _categories,
        repository: widget.repository,
        isCombo: true,
      ),
    );
    if (result == null || !mounted || result is! _DishEditorSave) return;
    final input = result.input;
    setState(() => _creatingCombo = true);
    try {
      await widget.repository.saveDish(input);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _creatingCombo = false);

      CashierDish? newlyCreated;
      for (final d in _dishes) {
        if (d.name == input.name) {
          newlyCreated = d;
          break;
        }
      }
      if (newlyCreated != null && mounted) {
        await _configCombo(newlyCreated);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _creatingCombo = false);
      await _showError('新增套餐失败', error);
    } finally {
      if (mounted) setState(() => _creatingCombo = false);
    }
  }

  Future<void> _deleteDish(CashierDish dish) async {
    final confirmed = await showPosNotice(
      context,
      title: '删除菜品',
      message:
          '确定删除“${dish.name}”吗？\n删除后点餐页不再显示该菜品，且无法恢复；历史订单中的记录不受影响。',
      tone: PosNoticeTone.warning,
      primaryLabel: '确认删除',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() => _submittingId = dish.id);
    try {
      await widget.repository.deleteDish(dish.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _submittingId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submittingId = null);
      await _showError('删除菜品失败', error);
    } finally {
      if (mounted) setState(() => _submittingId = null);
    }
  }

  Future<void> _createCategory() async {
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _CategoryEditorDialog(),
    );
    if (name == null || !mounted) return;
    setState(() => _creatingCategory = true);
    try {
      final nextSorting =
          _categories.fold<int>(
            0,
            (maximum, category) =>
                category.sorting > maximum ? category.sorting : maximum,
          ) +
          1;
      await widget.repository.addCategory(name: name, sorting: nextSorting);
      final categories = await widget.repository.loadCategories();
      if (!mounted) return;
      final merged = mergeCashierCategoriesWithDishes(
        categories: categories,
        dishes: _dishes,
      );
      setState(() {
        _categories = merged;
        _creatingCategory = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _creatingCategory = false);
      await _showError('新建分类失败', error);
    } finally {
      if (mounted) setState(() => _creatingCategory = false);
    }
  }

  Future<void> _deleteCategory(
    CashierDishCategory category,
    int dishCount,
  ) async {
    if (dishCount > 0) {
      await showPosNotice(
        context,
        title: '分类仍有菜品',
        message: '“${category.name}”下还有 $dishCount 个菜品，请先将菜品移动到其他分类后再删除。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final confirmed = await showPosNotice(
      context,
      title: '删除分类',
      message: '确定删除空分类“${category.name}”吗？删除后无法恢复。',
      tone: PosNoticeTone.warning,
      primaryLabel: '确认删除',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() => _deletingCategoryId = category.id);
    try {
      await widget.repository.deleteCategory(category.id);
      final categories = await widget.repository.loadCategories();
      if (!mounted) return;
      final merged = mergeCashierCategoriesWithDishes(
        categories: categories,
        dishes: _dishes,
      );
      setState(() {
        _categories = merged;
        if (_selectedCategoryKey == category.key) {
          _selectedCategoryKey = null;
        }
        _deletingCategoryId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletingCategoryId = null);
      await _showError('删除分类失败', error);
    } finally {
      if (mounted) setState(() => _deletingCategoryId = null);
    }
  }

  Future<void> _reorderCategory(
    int sourceId,
    CashierDishCategory target,
  ) async {
    final repository = widget.repository;
    final targetIndex = _categories.indexOf(target) + 1;
    if (_reordering ||
        sourceId == target.id ||
        targetIndex < 1 ||
        repository is! CashierCatalogSortingRepository) {
      return;
    }
    setState(() => _reordering = true);
    try {
      // v1.2.283 契约：targetIndex 为分类列表中的 1-based 目标显示位置，
      // 后端在当前门店分类列表内写连续 1..n。
      await (repository as CashierCatalogSortingRepository).reorderCategory(
        id: sourceId,
        targetIndex: targetIndex,
      );
      // 排序只改变分类顺序、不改变分类集合：重拉一次菜品接口
      // （服务端已按新排序返回）聚合即可，无需再读分类接口。
      final dishes = await widget.repository.loadAllDishes(query: '');
      if (!mounted) return;
      final merged = mergeCashierCategoriesWithDishes(
        categories: _categories,
        dishes: dishes,
      );
      setState(() {
        _categories = merged;
        _dishes = dishes;
      });
      _showSaved('已保存分类排序');
    } catch (error) {
      if (mounted) await _showError('调整分类排序失败', error);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _reorderDish(int sourceId, CashierDish target) async {
    final repository = widget.repository;
    final targetIndex = _visibleDishes.indexOf(target) + 1;
    // 菜品排序仅在选中具体分类时可用（v1.2.283：按菜品生效分类内重排，
    // 全部菜品视图跨分类拖拽会被后端拒绝或错乱）。
    if (_reordering ||
        sourceId == target.id ||
        _selectedCategory == null ||
        targetIndex < 1 ||
        repository is! CashierCatalogSortingRepository) {
      return;
    }
    setState(() => _reordering = true);
    try {
      await (repository as CashierCatalogSortingRepository).reorderDish(
        id: sourceId,
        targetIndex: targetIndex,
      );
      await _load();
      if (mounted) _showSaved('已保存菜品排序');
    } catch (error) {
      if (mounted) await _showError('调整菜品排序失败', error);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  void _showSaved(String message) {
    if (!mounted) return;
    _savedTipTimer?.cancel();
    setState(() => _savedTip = message);
    _savedTipTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _savedTip = null);
    });
  }

  @override
  void dispose() {
    _savedTipTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showError(String title, Object error) => showPosNotice(
    context,
    title: title,
    message: '${_message(error)}\n请检查后重试。',
    tone: PosNoticeTone.error,
  );

  bool _importingHq = false;

  Future<void> _importFromHq() async {
    final currentIds = _dishes.map((d) => d.id).toSet();
    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _HqDishImportDialog(
        repository: widget.repository,
        currentDishIds: currentIds,
      ),
    );
    if (imported == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedTip = _savedTip;
    final inCategoryDishes = _dishesInCategory;
    final totalCount = inCategoryDishes.length;
    final sufficientCount = inCategoryDishes
        .where((d) => d.availability == CashierDishAvailability.sufficient)
        .length;
    final lowCount = inCategoryDishes
        .where((d) => d.availability == CashierDishAvailability.lowStock)
        .length;
    final soldOutCount = inCategoryDishes
        .where((d) => d.availability == CashierDishAvailability.soldOut)
        .length;

    return Material(
      color: context.cashier.canvas,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧：菜品分类导轨 (200px 宽度)
              SizedBox(
                key: const Key('cashier-dish-category-rail'),
                width: 200,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.cashier.surface,
                    border: Border(
                      right: BorderSide(color: context.cashier.border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.cashier.border),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '菜品分类',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: context.cashier.ink,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.cashier.subtle,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: context.cashier.border),
                              ),
                              child: Text(
                                '${_categories.length} 个分类',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.cashier.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            _CategoryItem(
                              label: '全部菜品',
                              count: _dishes.length,
                              selected: _selectedCategoryKey == null,
                              onTap: () =>
                                  setState(() => _selectedCategoryKey = null),
                            ),
                            const SizedBox(height: 4),
                            for (final category in _categories)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _CategoryDropTarget(
                                  key: Key(
                                    'cashier-dish-category-${category.key}',
                                  ),
                                  category: category,
                                  enabled:
                                    widget.canManage &&
                                    category.id > 0 &&
                                    !_reordering,
                                  onAccept: (sourceId) =>
                                      _reorderCategory(sourceId, category),
                                  child: _CategoryItem(
                                    categoryId: category.id,
                                    label: category.name,
                                    count: _dishes
                                        .where(category.matches)
                                        .length,
                                    selected:
                                        _selectedCategoryKey == category.key,
                                    deleting: _deletingCategoryId == category.id,
                                    reorderEnabled: widget.canManage,
                                    onTap: () => setState(
                                      () => _selectedCategoryKey = category.key,
                                    ),
                                    onDelete: widget.canManage && category.id > 0
                                        ? () => _deleteCategory(
                                            category,
                                            _dishes
                                                .where(category.matches)
                                                .length,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.canManage)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: context.cashier.border),
                            ),
                          ),
                          child: SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              key: const Key('cashier-dish-category-add'),
                              onPressed: _busy ? null : _createCategory,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF18181B),
                                foregroundColor:
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF18181B)
                                        : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text(
                                '+ 新建分类',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 右侧主工作区
              Expanded(
                child: Container(
                  color: context.cashier.canvas,
                  child: Column(
                    children: [
                      _Toolbar(
                        categoryName: _selectedCategory?.name ?? '全部菜品',
                        dishCount: _visibleDishes.length,
                        searchController: _searchController,
                        onSearchChanged: (val) =>
                            setState(() => _searchQuery = val),
                        loading: _loading || _busy,
                        canManage: widget.canManage,
                        creating: _creating,
                        creatingCombo: _creatingCombo,
                        importingHq: _importingHq,
                        onAdd: () => _editDish(),
                        onAddCombo: _createCombo,
                        onImportHq: _importFromHq,
                      ),
                      _CatalogKpiBar(
                        totalCount: totalCount,
                        sufficientCount: sufficientCount,
                        lowCount: lowCount,
                        soldOutCount: soldOutCount,
                        selectedFilter: _selectedStatusFilter,
                        onFilterChanged: (filter) =>
                            setState(() => _selectedStatusFilter = filter),
                      ),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (savedTip != null)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const Key('cashier-catalog-saved-tip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: context.cashier.success,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          savedTip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _dishes.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.loading,
        title: '正在加载菜品',
        message: '正在同步当前门店菜单和库存',
      );
    }
    if (_error != null && _dishes.isEmpty) {
      return CashierStateView(
        state: CashierViewState.error,
        title: '菜品加载失败',
        message: _error!,
        actionLabel: '重试',
        onAction: () => _load(initial: _categories.isEmpty),
      );
    }
    if (_visibleDishes.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.empty,
        title: '暂无菜品',
        message: '当前筛选条件下没有菜品，可调整筛选或增加菜品。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 300).floor().clamp(2, 5);
        return GridView.builder(
          key: const Key('cashier-dish-grid'),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: widget.canManage ? 190 : 140,
          ),
          itemCount: _visibleDishes.length,
          itemBuilder: (context, index) {
            final dish = _visibleDishes[index];
            final card = _DishCard(
              dish: dish,
              canManage: widget.canManage,
              busy: _submittingId == dish.id || _reordering,
              showDragHandle:
                  widget.canManage && _selectedCategory != null,
              onEdit: () => _editDish(dish),
              onToggleSoldOut: () => _toggleSoldOut(dish),
              onConfigCombo: () => _configCombo(dish),
              onAddStock: (count) => _quickAddStock(dish, count),
            );
            if (!widget.canManage ||
                dish.id <= 0 ||
                _selectedCategory == null) {
              return card;
            }
            return DragTarget<int>(
              onWillAcceptWithDetails: (details) =>
                  !_reordering && details.data != dish.id,
              onAcceptWithDetails: (details) =>
                  _reorderDish(details.data, dish),
              builder: (context, candidates, rejected) =>
                  LongPressDraggable<int>(
                    data: dish.id,
                    maxSimultaneousDrags: _reordering ? 0 : 1,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(width: 280, height: 190, child: card),
                    ),
                    childWhenDragging: Opacity(opacity: .35, child: card),
                    child: AnimatedScale(
                      scale: candidates.isEmpty ? 1 : .96,
                      duration: const Duration(milliseconds: 120),
                      child: card,
                    ),
                  ),
            );
          },
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.categoryName,
    required this.dishCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.loading,
    required this.canManage,
    required this.creating,
    required this.importingHq,
    required this.onAdd,
    required this.onImportHq,
    this.creatingCombo = false,
    this.onAddCombo,
  });

  final String categoryName;
  final int dishCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool loading;
  final bool canManage;
  final bool creating;
  final bool creatingCombo;
  final bool importingHq;
  final VoidCallback onAdd;
  final VoidCallback? onAddCombo;
  final VoidCallback onImportHq;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: context.cashier.surface,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.cashier.border),
          ),
        ),
        child: Row(
          children: [
            // 左侧：分类标题与商品总数提示
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      categoryName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.cashier.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.cashier.subtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.cashier.border),
                      ),
                      child: Text(
                        '$dishCount 种商品',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '点击卡片可快速设为估清、补库存或调整售价规格',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // 中间：即时搜索框
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.cashier.subtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.cashier.border),
                    ),
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.ink,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      hintText: '输入菜品名称/拼音助记码快速检索...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: context.cashier.inkMuted,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              color: context.cashier.inkMuted,
                              onPressed: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
            // 右侧：三大操作按键
            if (canManage) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  key: const Key('cashier-dish-import-hq-button'),
                  onPressed: loading ? null : onImportHq,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.ink,
                    side: BorderSide(color: context.cashier.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: importingHq
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 16),
                  label: const Text(
                    '从总部导入',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  key: const Key('cashier-dish-add-combo-button'),
                  onPressed: loading ? null : onAddCombo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.ink,
                    side: BorderSide(color: context.cashier.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: creatingCombo
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_mosaic_outlined, size: 16),
                  label: const Text(
                    '新增套餐',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: FilledButton.icon(
                  onPressed: loading ? null : onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.white : const Color(0xFF18181B),
                    foregroundColor:
                        isDark ? const Color(0xFF18181B) : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: creating
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    '增加菜品',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogKpiBar extends StatelessWidget {
  const _CatalogKpiBar({
    required this.totalCount,
    required this.sufficientCount,
    required this.lowCount,
    required this.soldOutCount,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final int totalCount;
  final int sufficientCount;
  final int lowCount;
  final int soldOutCount;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cashier.surface,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.cashier.border),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _KpiFilterChip(
                label: '全部菜品',
              value: totalCount,
              dotColor: const Color(0xFF71717A),
              valueColor: context.cashier.ink,
              selected: selectedFilter == 'all',
              onTap: () => onFilterChanged('all'),
            ),
            const SizedBox(width: 8),
            _KpiFilterChip(
              label: '正常在售',
              value: sufficientCount,
              dotColor: context.cashier.success,
              valueColor: context.cashier.success,
              selected: selectedFilter == 'sufficient',
              onTap: () => onFilterChanged('sufficient'),
            ),
            const SizedBox(width: 8),
            _KpiFilterChip(
              label: '低库存预警',
              value: lowCount,
              dotColor: context.cashier.warning,
              valueColor: context.cashier.warning,
              selected: selectedFilter == 'low',
              onTap: () => onFilterChanged('low'),
            ),
            const SizedBox(width: 8),
            _KpiFilterChip(
              label: '已估清/售罄',
              value: soldOutCount,
              dotColor: context.cashier.danger,
              valueColor: context.cashier.danger,
              selected: selectedFilter == 'soldout',
              onTap: () => onFilterChanged('soldout'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _KpiFilterChip extends StatelessWidget {
  const _KpiFilterChip({
    required this.label,
    required this.value,
    required this.dotColor,
    required this.valueColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color dotColor;
  final Color valueColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7))
          : context.cashier.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8))
                  : context.cashier.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? context.cashier.ink : context.cashier.inkSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    this.categoryId,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
    this.reorderEnabled = false,
  });

  final int? categoryId;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool deleting;
  final bool reorderEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label，$count 个菜品',
      child: Material(
        color: selected
            ? (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8))
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? context.cashier.ink : context.cashier.inkSecondary,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? context.cashier.surface : context.cashier.subtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? context.cashier.border : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? context.cashier.ink : context.cashier.inkMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 36,
                    child: IconButton(
                      key: categoryId == null
                          ? null
                          : Key('cashier-dish-category-delete-$categoryId'),
                      tooltip: '删除分类',
                      padding: EdgeInsets.zero,
                      onPressed: deleting ? null : onDelete,
                      color: context.cashier.danger,
                      icon: deleting
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.cashier.danger,
                              ),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ),
                ],
                if (reorderEnabled)
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: selected ? context.cashier.ink : context.cashier.inkMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryDropTarget extends StatelessWidget {
  const _CategoryDropTarget({
    super.key,
    required this.category,
    required this.enabled,
    required this.onAccept,
    required this.child,
  });

  final CashierDishCategory category;
  final bool enabled;
  final ValueChanged<int> onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<int>(
    onWillAcceptWithDetails: (details) =>
        enabled && details.data != category.id,
    onAcceptWithDetails: (details) => onAccept(details.data),
    builder: (context, candidates, rejected) => LongPressDraggable<int>(
      data: category.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 204, child: child),
      ),
      childWhenDragging: Opacity(opacity: .35, child: child),
      child: ColoredBox(
        color: candidates.isEmpty ? Colors.transparent : context.cashier.subtle,
        child: child,
      ),
    ),
  );
}

String _getDishEmoji(CashierDish dish) {
  final name = dish.name;
  final cat = dish.categoryName;
  final combined = '$cat $name';
  if (combined.contains('套餐')) return '🍱';
  if (combined.contains('酒') ||
      combined.contains('啤') ||
      combined.contains('水') ||
      combined.contains('茶') ||
      combined.contains('饮')) {
    return '🍺';
  }
  if (combined.contains('凉') ||
      combined.contains('黄瓜') ||
      combined.contains('拍') ||
      combined.contains('拌') ||
      combined.contains('沙拉')) {
    return '🥗';
  }
  if (combined.contains('肠') || combined.contains('培根')) return '🥓';
  if (combined.contains('串') || combined.contains('烤')) return '🍢';
  if (combined.contains('炒') ||
      combined.contains('热') ||
      combined.contains('煲') ||
      combined.contains('锅') ||
      combined.contains('汤') ||
      combined.contains('鸡') ||
      combined.contains('鸭') ||
      combined.contains('鱼')) {
    return '🍲';
  }
  if (combined.contains('油边') ||
      combined.contains('肉') ||
      combined.contains('牛') ||
      combined.contains('羊') ||
      combined.contains('排') ||
      combined.contains('骨')) {
    return '🥩';
  }
  return '🍽️';
}

class _DishCard extends StatelessWidget {
  const _DishCard({
    required this.dish,
    required this.canManage,
    required this.busy,
    required this.onEdit,
    required this.onToggleSoldOut,
    this.onConfigCombo,
    this.onAddStock,
    this.showDragHandle = false,
  });

  final CashierDish dish;
  final bool canManage;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggleSoldOut;
  final VoidCallback? onConfigCombo;
  final ValueChanged<int>? onAddStock;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCombo = dish.categoryName.contains('套餐') || dish.name.contains('套餐');

    final (Color badgeBg, Color badgeFg, String badgeText) = switch (
      dish.availability
    ) {
      CashierDishAvailability.sufficient => (
        context.cashier.successBackground,
        context.cashier.success,
        '库存充足',
      ),
      CashierDishAvailability.lowStock => (
        context.cashier.warningBackground,
        context.cashier.warning,
        '快售罄',
      ),
      CashierDishAvailability.soldOut => (
        const Color(0xff202020),
        Colors.white,
        '已售罄',
      ),
    };

    return Semantics(
      container: true,
      label: '${dish.name}，${dish.availabilityLabel}，${dish.stockLabel}',
      hint: canManage ? '点击编辑菜品' : null,
      child: Material(
        key: Key('cashier-dish-card-${dish.id}'),
        color: dish.soldOut
            ? (isDark ? context.cashier.subtle : const Color(0xfff3f1f0))
            : context.cashier.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canManage && !busy ? onEdit : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.cashier.subtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.cashier.border),
                      ),
                      alignment: Alignment.center,
                      child: dish.image.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                dish.image,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Text(_getDishEmoji(dish), style: const TextStyle(fontSize: 20)),
                              ),
                            )
                          : Text(
                              _getDishEmoji(dish),
                              style: const TextStyle(fontSize: 20),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (showDragHandle) ...[
                                Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 16,
                                  color: context.cashier.inkMuted,
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (isCombo) ...[
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x338B5CF6),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0x668B5CF6)),
                                  ),
                                  child: const Text(
                                    '套餐',
                                    style: TextStyle(
                                      color: Color(0xFFC4B5FD),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  dish.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.cashier.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${dish.categoryName.isNotEmpty ? dish.categoryName : "精选"} · ${dish.unit}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.cashier.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeFg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '¥ ${dish.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: context.cashier.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '/ ${dish.unit}',
                              style: TextStyle(
                                color: context.cashier.inkMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '会员 ¥ ${(dish.price * 0.88).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '库存 ',
                          style: TextStyle(
                            color: context.cashier.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          dish.stockLabel,
                          style: TextStyle(
                            color: context.cashier.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (canManage) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (isCombo && onConfigCombo != null) ...[
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              key: Key('cashier-dish-combo-${dish.id}'),
                              onPressed: busy ? null : onConfigCombo,
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                foregroundColor: const Color(0xFF8B5CF6),
                                side: const BorderSide(color: Color(0xFF8B5CF6)),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.tune_rounded, size: 14),
                              label: const Text(
                                '配置套餐',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (!dish.soldOut && onAddStock != null) ...[
                        SizedBox(
                          height: 42,
                          child: OutlinedButton(
                            key: Key('cashier-dish-add-5-${dish.id}'),
                            onPressed: busy ? null : () => onAddStock!(5),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size.zero,
                              foregroundColor: context.cashier.ink,
                              side: BorderSide(color: context.cashier.border),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '+5',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 42,
                          child: OutlinedButton(
                            key: Key('cashier-dish-add-10-${dish.id}'),
                            onPressed: busy ? null : () => onAddStock!(10),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size.zero,
                              foregroundColor: context.cashier.ink,
                              side: BorderSide(color: context.cashier.border),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '+10',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            key: Key('cashier-dish-toggle-${dish.id}'),
                            onPressed: busy ? null : onToggleSoldOut,
                            style: FilledButton.styleFrom(
                              minimumSize: Size.zero,
                              backgroundColor: dish.soldOut
                                  ? context.cashier.success
                                  : Colors.white,
                              foregroundColor: dish.soldOut
                                  ? Colors.white
                                  : context.cashier.danger,
                              side: dish.soldOut
                                  ? BorderSide.none
                                  : const BorderSide(color: Color(0xfff2b8b8)),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    dish.soldOut
                                        ? Icons.refresh_rounded
                                        : Icons.block_outlined,
                                    size: 15,
                                  ),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                busy
                                    ? '提交中'
                                    : dish.soldOut
                                        ? '恢复可售'
                                        : '设为售罄',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.cashier.inkMuted,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 10),
      const Divider(height: 1),
      const SizedBox(height: 12),
    ],
  );
}

class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.name});

  final String name;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stockController = TextEditingController();

  @override
  void dispose() {
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    width: 460,
    height: 340,
    title: '恢复可售',
    onClose: () => Navigator.pop(context),
    body: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '「${widget.name}」恢复为可售前，请先设置库存数量，确定后按此数量恢复销售。',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const Key('cashier-dish-restock-input'),
            controller: _stockController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '库存数量',
              suffixText: '份',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
            ),
            validator: (value) {
              final stock = int.tryParse(value ?? '');
              return stock == null || stock < 1 ? '库存数量必须至少为 1 份' : null;
            },
          ),
        ],
      ),
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
      CashierActionButton(
        key: const Key('cashier-dish-restock-confirm'),
        label: '确定恢复',
        onPressed: _submit,
      ),
    ],
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, int.parse(_stockController.text));
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog();

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    width: 620,
    height: 360,
    title: '新建分类',
    onClose: () => Navigator.pop(context),
    body: Form(
      key: _formKey,
      child: TextFormField(
        key: const Key('cashier-category-name-input'),
        controller: _nameController,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: '分类名称',
          hintText: '例如：招牌菜、烧烤、饮品',
          border: OutlineInputBorder(),
        ),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '请输入分类名称' : null,
      ),
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
      CashierActionButton(
        key: const Key('cashier-category-save-confirm'),
        label: '确认创建',
        onPressed: _submit,
      ),
    ],
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _nameController.text.trim());
  }
}

class _DishEditorDialog extends StatefulWidget {
  const _DishEditorDialog({
    required this.dish,
    required this.categories,
    required this.repository,
    this.isCombo = false,
  });

  final CashierDish? dish;
  final List<CashierDishCategory> categories;
  final CashierCatalogRepository repository;
  final bool isCombo;

  @override
  State<_DishEditorDialog> createState() => _DishEditorDialogState();
}

/// 编辑弹窗结果：保存或删除（删除仅编辑既有菜品时可用）。
sealed class _DishEditorResult {
  const _DishEditorResult();
}

class _DishEditorSave extends _DishEditorResult {
  const _DishEditorSave(this.input);

  final CashierDishInput input;
}

class _DishEditorDelete extends _DishEditorResult {
  const _DishEditorDelete();
}

class _DishEditorDialogState extends State<_DishEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _unitController;
  late final TextEditingController _stockController;
  late final TextEditingController _servingDurationController;
  late final DishSpecificationEditorController _specificationController;
  int? _typeId;
  late bool _onSale;
  late bool _limitedStock;
  late String _image;
  bool _uploadingImage = false;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    final dish = widget.dish;
    _nameController = TextEditingController(text: dish?.name ?? '');
    _priceController = TextEditingController(
      text: dish == null ? '' : dish.price.toStringAsFixed(2),
    );
    _unitController = TextEditingController(
      text: dish?.unit ?? (widget.isCombo ? '套' : '份'),
    );
    _specificationController = DishSpecificationEditorController.fromRaw(
      dish?.specification ?? '',
    );
    _limitedStock = dish?.stock != null && dish!.stock! > 0;
    _stockController = TextEditingController(
      text: _limitedStock ? '${dish!.stock}' : '',
    );
    _servingDurationController = TextEditingController(
      text: '${dish?.servingDurationMinutes ?? 10}',
    );
    _typeId = _initialCategoryId(dish);
    _onSale = dish?.onSale ?? true;
    _image = dish?.image ?? '';
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > 5 * 1024 * 1024) {
        setState(() => _imageError = '图片大小不能超过 5MB');
        return;
      }
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _imageError = '读取图片数据失败');
        return;
      }
      setState(() {
        _uploadingImage = true;
        _imageError = null;
      });
      final src = await widget.repository.uploadDishImage(
        bytes: bytes,
        filename: file.name,
      );
      if (mounted) {
        setState(() {
          _image = src;
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageError = '上传失败：$e';
          _uploadingImage = false;
        });
      }
    }
  }

  Widget _buildImageCard(BuildContext context) {
    final cashier = context.cashier;
    if (_uploadingImage) {
      return Container(
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cashier.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cashier.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: cashier.selected),
            ),
            const SizedBox(width: 12),
            Text('正在上传图片...', style: TextStyle(color: cashier.selected, fontSize: 13)),
          ],
        ),
      );
    }

    if (_image.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cashier.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cashier.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 70,
                height: 52,
                color: cashier.surface,
                child: _image.startsWith('http')
                    ? Image.network(
                        _image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.image, color: cashier.inkSecondary),
                      )
                    : Icon(Icons.image_outlined, color: cashier.selected, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _image,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cashier.ink, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 2),
                  Text('已成功绑定菜品图片', style: TextStyle(fontSize: 11, color: cashier.success)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('更换', style: TextStyle(fontSize: 12)),
              onPressed: _pickAndUploadImage,
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
              label: const Text('清除', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              onPressed: () => setState(() => _image = ''),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickAndUploadImage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: cashier.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cashier.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 18, color: cashier.selected),
                  const SizedBox(width: 8),
                  Text(
                    '点击选取本地图片上传',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cashier.selected),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '支持 PNG、JPG、WEBP 格式，大小不超过 5MB',
                style: TextStyle(fontSize: 11, color: cashier.inkSecondary),
              ),
              if (_imageError != null) ...[
                const SizedBox(height: 2),
                Text(_imageError!, style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int? _initialCategoryId(CashierDish? dish) {
    if (dish == null) {
      if (widget.isCombo) {
        for (final category in widget.categories) {
          if (category.id > 0 && category.name.contains('套餐')) {
            return category.id;
          }
        }
      }
      return null;
    }
    for (final category in widget.categories) {
      if (category.matches(dish) && category.id > 0) return category.id;
    }
    return dish.typeId > 0 ? dish.typeId : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _specificationController.dispose();
    _stockController.dispose();
    _servingDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    width: 720,
    height: 700,
    title: widget.isCombo
        ? '新增套餐'
        : (widget.dish == null ? '增加菜品' : '编辑菜品'),
    onClose: () => Navigator.pop(context),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _GroupTitle('基本信息'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('cashier-dish-name-input'),
                  controller: _nameController,
                  autofocus: widget.dish == null,
                  decoration: const InputDecoration(
                    labelText: '菜品名称',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入菜品名称' : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('cashier-dish-category-input'),
                  initialValue: _typeId,
                  decoration: const InputDecoration(
                    labelText: '菜品分类',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  items: [
                    for (final category in widget.categories)
                      if (category.id > 0)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    if (_typeId != null &&
                        _typeId! > 0 &&
                        !widget.categories.any((c) => c.id == _typeId))
                      DropdownMenuItem(
                        value: _typeId,
                        child: Text(
                          widget.dish?.categoryName.isNotEmpty == true
                              ? widget.dish!.categoryName
                              : '分类 $_typeId',
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _typeId = value),
                  validator: (value) => value == null ? '请选择菜品分类' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('cashier-dish-price-input'),
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,6}(\.\d{0,2})?'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: '单价',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  validator: (value) {
                    final price = double.tryParse(value ?? '');
                    return price == null || price <= 0 ? '请输入有效单价' : null;
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextFormField(
                  key: const Key('cashier-dish-unit-input'),
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: '销售单位',
                    hintText: '例如：份、串、瓶',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入销售单位' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _GroupTitle('菜品展示图'),
          _buildImageCard(context),
          const SizedBox(height: 18),
          const _GroupTitle('菜品规格'),
          DishSpecificationEditor(controller: _specificationController),
          const SizedBox(height: 18),
          const _GroupTitle('库存与销售'),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '上架销售',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '关闭后点餐页不可选择',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _onSale,
                  onChanged: (value) => setState(() => _onSale = value),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '启用有限库存',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '关闭后按不限量销售',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _limitedStock,
                  onChanged: (value) => setState(() => _limitedStock = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('cashier-dish-editor-stock-input'),
                  controller: _stockController,
                  enabled: _limitedStock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '初始库存',
                    suffixText: '份',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  validator: (value) {
                    if (!_limitedStock) return null;
                    final stock = int.tryParse(value ?? '');
                    return stock == null || stock < 1
                        ? '有限库存必须至少为 1 份'
                        : null;
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextFormField(
                  key: const Key('cashier-dish-serving-duration-input'),
                  controller: _servingDurationController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '预计出餐时长',
                    helperText: '用于 KDS 单品超时提醒',
                    suffixText: '分钟',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  validator: (value) {
                    final minutes = int.tryParse(value ?? '');
                    return minutes == null || minutes <= 0
                        ? '出餐时长必须大于 0 分钟'
                        : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _GroupTitle('AI 配餐画像'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 智能配餐风味与健康画像',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '包含免辣制作能力、辣度选项、过敏原标记及卡路里营养素',
                        style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const Key('btn-dish-ai-profile-quick'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请前往「商品菜单 - AI配餐画像」模块进行全量深度配置'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('画像维护'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ),
    actions: [
      if (widget.dish != null)
        CashierActionButton(
          key: const Key('cashier-dish-delete'),
          label: '删除菜品',
          variant: CashierActionButtonVariant.danger,
          onPressed: () => Navigator.pop(context, const _DishEditorDelete()),
        ),
      CashierActionButton(
        label: '取消',
        variant: CashierActionButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
      CashierActionButton(
        key: const Key('cashier-dish-save-confirm'),
        label: widget.dish == null
            ? (widget.isCombo ? '确认增加套餐' : '确认增加')
            : '保存修改',
        onPressed: _submit,
      ),
    ],
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final dish = widget.dish;
    Navigator.pop(
      context,
      _DishEditorSave(
        CashierDishInput(
          id: dish?.id,
          name: _nameController.text,
          specification: _specificationController.encodedValue,
          price: double.parse(_priceController.text),
          unit: _unitController.text,
          stock: _limitedStock ? int.parse(_stockController.text) : -1,
          onSale: _onSale,
          soldOut: dish?.soldOut ?? false,
          typeId: _typeId!,
          image: _image,
          sorting: dish?.sorting ?? 0,
          quantity: dish?.quantity ?? 0,
          servingDurationMinutes: int.parse(_servingDurationController.text),
        ),
      ),
    );
  }
}

String _message(Object error) =>
    error is ApiException ? error.message : error.toString();

class _HqDishImportDialog extends StatefulWidget {
  const _HqDishImportDialog({
    required this.repository,
    required this.currentDishIds,
  });

  final CashierCatalogRepository repository;
  final Set<int> currentDishIds;

  @override
  State<_HqDishImportDialog> createState() => _HqDishImportDialogState();
}

class _HqDishImportDialogState extends State<_HqDishImportDialog> {
  final _searchController = TextEditingController();
  List<CashierDish> _hqDishes = const [];
  final Set<int> _selectedIds = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHqDishes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchHqDishes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.loadHqTemplateDishes(
        pageNum: 1,
        pageSize: 100,
        query: _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _hqDishes = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _hqDishes.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_hqDishes.map((d) => d.id));
      }
    });
  }

  Future<void> _submitImport() async {
    if (_selectedIds.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.repository.importDishesFromHq(_selectedIds.toList());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      await showPosNotice(
        context,
        title: '导入失败',
        message: _message(e),
        tone: PosNoticeTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _hqDishes.isNotEmpty && _selectedIds.length == _hqDishes.length;
    return CashierDialogFrame(
      width: 760,
      height: 600,
      title: '从总部导入菜品',
      onClose: _submitting ? () {} : () => Navigator.pop(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    key: const Key('cashier-hq-import-search-input'),
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索总部菜品名称...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _fetchHqDishes(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              CashierActionButton(
                key: const Key('cashier-hq-import-search-button'),
                label: '搜索',
                icon: Icons.search,
                minimumWidth: 90,
                height: 42,
                variant: CashierActionButtonVariant.secondary,
                onPressed: _loading ? null : _fetchHqDishes,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('cashier-hq-import-select-all-button'),
                onPressed: _hqDishes.isEmpty ? null : _toggleSelectAll,
                icon: Icon(
                  allSelected ? Icons.deselect : Icons.select_all,
                  size: 18,
                ),
                label: Text(allSelected ? '取消全选' : '全选'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(100, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '共找到 ${_hqDishes.length} 个总部模板菜品，已选择 ${_selectedIds.length} 个',
            style: TextStyle(
              fontSize: 13,
              color: context.cashier.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          SizedBox(
            height: 340,
            child: _buildList(),
          ),
        ],
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: _submitting ? null : () => Navigator.pop(context),
        ),
        CashierActionButton(
          key: const Key('cashier-hq-import-confirm-button'),
          label: '确认导入 (${_selectedIds.length})',
          busy: _submitting,
          onPressed: _selectedIds.isEmpty || _submitting ? null : _submitImport,
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载总部菜品失败：$_error',
                style: TextStyle(color: context.cashier.danger)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _fetchHqDishes, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_hqDishes.isEmpty) {
      return const Center(child: Text('暂无符合条件的总部标准菜品'));
    }
    return ListView.separated(
      key: const Key('cashier-hq-import-list'),
      itemCount: _hqDishes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final dish = _hqDishes[index];
        final selected = _selectedIds.contains(dish.id);
        final inShop = widget.currentDishIds.contains(dish.id);
        return CheckboxListTile(
          key: Key('cashier-hq-dish-item-${dish.id}'),
          value: selected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedIds.add(dish.id);
              } else {
                _selectedIds.remove(dish.id);
              }
            });
          },
          title: Row(
            children: [
              Text(
                dish.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(width: 8),
              if (inShop)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.cashier.border),
                  ),
                  child: Text(
                    '本店已导入',
                    style: TextStyle(
                        fontSize: 11, color: context.cashier.inkMuted),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.cashier.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '可导入',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.cashier.success,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            '售价: ¥${dish.price.toStringAsFixed(2)} / ${dish.unit.isNotEmpty ? dish.unit : "份"}' +
                (dish.servingDurationMinutes > 0
                    ? ' · 制作约 ${dish.servingDurationMinutes} 分钟'
                    : ''),
            style: TextStyle(color: context.cashier.inkMuted, fontSize: 13),
          ),
        );
      },
    );
  }
}

