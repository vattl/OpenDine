import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../mobile/responsive/breakpoints.dart';
import '../domain/pos_models.dart';
import 'pos_notice_dialog.dart';


class PosOrderingView extends StatefulWidget {
  const PosOrderingView({
    super.key,
    required this.workspace,
    required this.tableNumber,
    required this.submitting,
    required this.addingDishes,
    required this.onBack,
    required this.onSubmit,
    this.onEmptyBack,
    this.packingOrder = false,
  });

  final PosWorkspace workspace;
  final String tableNumber;
  final bool submitting;
  final bool addingDishes;
  final bool packingOrder;
  final VoidCallback onBack;
  final Future<void> Function()? onEmptyBack;
  final Future<void> Function({
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
  })
  onSubmit;

  @override
  State<PosOrderingView> createState() => _PosOrderingViewState();
}

class _PosOrderingViewState extends State<PosOrderingView> {
  PosCart cart = const PosCart();
  int? selectedCategoryId;
  String searchQuery = '';
  String quickFilter = 'all'; // 'all', 'sign', 'instock'
  bool showKeyboard = true;
  late int _diners = widget.workspace.table.people > 0 ? widget.workspace.table.people : 2;
  String _remark = '';

  List<PosDish> get visibleDishes {
    var list = widget.workspace.dishes;
    final categoryId = selectedCategoryId;
    if (categoryId != null) {
      PosCategory? selectedCategory;
      for (final category in widget.workspace.categories) {
        if (category.id == categoryId) {
          selectedCategory = category;
          break;
        }
      }
      if (selectedCategory == null) return const [];
      final currentCategory = selectedCategory;
      final currentCategoryId = currentCategory.id;
      final categoryCode = currentCategory.code.trim();
      list = list
          .where(
            (dish) =>
                dish.categoryId == currentCategoryId ||
                (categoryCode.isNotEmpty &&
                    dish.categoryCode == categoryCode) ||
                dish.categoryCode == currentCategoryId.toString() ||
                (categoryCode.isNotEmpty &&
                    dish.categoryId.toString() == categoryCode),
          )
          .toList(growable: false);
    }
    if (quickFilter == 'sign') {
      list = list
          .where((dish) => dish.isCombo || dish.specGroups.isNotEmpty)
          .toList(growable: false);
    } else if (quickFilter == 'instock') {
      list = list.where((dish) => dish.available).toList(growable: false);
    }
    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where(
            (dish) =>
                _dishMatchesSearch(dish.name, query) ||
                _dishCode(dish).toLowerCase().contains(query),
          )
          .toList(growable: false);
    }
    return list;
  }

  int _existingComboQuantity(PosDish dish) {
    if (!widget.addingDishes) return 0;
    final comboId = dish.comboDefinition?.comboId;
    if (comboId == null || comboId <= 0) return 0;
    return widget.workspace.allLines
        .where(
          (line) =>
              line.isComboHeader && !line.isRefunded && line.comboId == comboId,
        )
        .fold(0, (sum, line) => sum + line.quantity);
  }

  int _comboQuantityInOrder(PosDish dish) =>
      _existingComboQuantity(dish) + cart.quantityForDish(dish.id);

  Future<void> _selectDish(PosDish dish) async {
    if (!dish.available) return;
    final combo = dish.comboDefinition;
    final commercialReason = combo?.unavailableReason(
      now: DateTime.now(),
      packingOrder: widget.packingOrder,
    );
    if (commercialReason != null) {
      await showPosNotice(
        context,
        title: '当前不可售',
        message: widget.packingOrder && commercialReason == '仅限堂食'
            ? '当前为打包订单，${dish.name}仅限堂食。'
            : '${dish.name}$commercialReason。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final quantityInOrder = _comboQuantityInOrder(dish);
    if (combo?.orderLimitReached(quantityInOrder) == true) {
      await showPosNotice(
        context,
        title: '已达限购上限',
        message: '${dish.name}单单限购 ${combo!.limitPerOrder} 份。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final remaining = cart.remainingStock(dish);
    if (remaining != null && remaining <= 0) {
      await _showStockLimit(dish);
      return;
    }
    if (dish.isCombo) {
      final selection = await showDialog<_ComboSelection>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x4d000000),
        builder: (context) => _ComboSelectionDialog(
          dish: dish,
          menuDishes: widget.workspace.dishes,
          maxQuantity: _comboMaximumQuantity(dish, remaining),
        ),
      );
      if (selection != null && mounted) {
        setState(
          () => cart = cart.add(
            dish,
            selections: selection.specifications,
            comboSelections: selection.comboSelections,
            quantity: selection.quantity,
          ),
        );
      }
      return;
    }
    if (dish.specGroups.isEmpty) {
      setState(() => cart = cart.add(dish));
      return;
    }
    final selection = await showDialog<_SpecificationSelection>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x4d000000),
      builder: (context) =>
          _SpecificationDialog(dish: dish, maxQuantity: remaining),
    );
    if (selection != null && mounted) {
      setState(
        () => cart = cart.add(
          dish,
          selections: selection.values,
          quantity: selection.quantity,
        ),
      );
    }
  }

  int? _comboMaximumQuantity(PosDish dish, int? stockRemaining) {
    final limit = dish.comboDefinition?.limitPerOrder;
    if (limit == null || limit <= 0) return stockRemaining;
    final commercialRemaining = limit - _comboQuantityInOrder(dish);
    if (stockRemaining == null) return commercialRemaining.clamp(0, 99);
    return stockRemaining < commercialRemaining
        ? stockRemaining
        : commercialRemaining.clamp(0, 99);
  }

  Future<void> _promptEditDiners() async {
    final result = await showDialog<int>(
      context: context,
      builder: (dialogCtx) {
        int selected = _diners;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('修改就餐人数', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 360,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(12, (index) {
                    final num = index + 1;
                    final active = selected == num;
                    return InkWell(
                      onTap: () => setDialogState(() => selected = num),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 50,
                        height: 44,
                        decoration: BoxDecoration(
                          color: active ? context.cashier.selected : context.cashier.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? context.cashier.selected : context.cashier.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$num人',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: active ? Colors.white : context.cashier.ink,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(selected),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _diners = result);
    }
  }

  Future<void> _promptEditRemark() async {
    final controller = TextEditingController(text: _remark);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('整单备注', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '请输入整单备注 (如：少盐、不要香菜、加急等)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['少辣', '微辣', '免葱姜蒜', '少盐少油', '打包带走', '加急']
                      .map((tag) => ActionChip(
                            label: Text(tag),
                            onPressed: () {
                              if (controller.text.isEmpty) {
                                controller.text = tag;
                              } else {
                                controller.text = '${controller.text} $tag';
                              }
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _remark = result);
    }
  }

  Future<void> _submit() async {
    if (cart.lines.isEmpty) {
      await showPosNotice(
        context,
        title: '请选择菜品',
        message: '购物车为空，请选择菜品后再下单。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    await widget.onSubmit(diners: _diners, remark: _remark, lines: cart.lines);
  }

  Future<void> _back() async {
    final emptyBack = widget.onEmptyBack;
    if (cart.lines.isEmpty && emptyBack != null) {
      await emptyBack();
      return;
    }
    widget.onBack();
  }

  Future<void> _showStockLimit(PosDish dish) {
    final stock = dish.stock ?? 0;
    return showPosNotice(
      context,
      title: '库存不足',
      message: '${dish.name}库存仅剩 $stock 份，不能继续增加数量。',
      tone: PosNoticeTone.warning,
    );
  }

  Future<void> _changeQuantity(PosCartLine line, int value) async {
    if (value <= 0) {
      setState(() => cart = cart.remove(line.key));
      return;
    }
    final combo = line.dish.comboDefinition;
    final limit = combo?.limitPerOrder;
    if (limit != null && limit > 0) {
      final otherQuantity = cart.quantityForDish(line.dish.id) - line.quantity;
      final existingQuantity = _existingComboQuantity(line.dish);
      if (value + otherQuantity + existingQuantity > limit) {
        await showPosNotice(
          context,
          title: '已达限购上限',
          message: '${line.dish.name}单单限购 $limit 份。',
          tone: PosNoticeTone.warning,
        );
        return;
      }
    }
    final stock = line.dish.stock;
    if (stock != null && stock > 0) {
      final otherQuantity = cart.quantityForDish(line.dish.id) - line.quantity;
      final maximumForLine = (stock - otherQuantity).clamp(0, 99);
      if (value > maximumForLine) {
        await _showStockLimit(line.dish);
        return;
      }
    }
    setState(() => cart = cart.updateQuantity(line.key, value));
  }

  void _showMobileCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: _CartPanel(
            cart: cart,
            tableNumber: widget.tableNumber,
            title: widget.packingOrder ? '打包点餐' : null,
            submitting: widget.submitting,
            actionLabel: widget.addingDishes
                ? '确认加菜'
                : widget.packingOrder
                ? '确认打包'
                : (widget.tableNumber.isEmpty ? '立即下单' : '确认下单'),
            packingOrder: widget.packingOrder,
            diners: widget.packingOrder ? null : _diners,
            remark: _remark,
            onEditDiners: widget.packingOrder ? null : _promptEditDiners,
            onEditRemark: _promptEditRemark,
            onBack: () => Navigator.of(sheetContext).pop(),
            onClear: () {
              setState(() => cart = const PosCart());
              Navigator.of(sheetContext).pop();
            },
            quantityInOrder: _comboQuantityInOrder,
            onQuantityChanged: _changeQuantity,
            onRemove: (line) =>
                setState(() => cart = cart.remove(line.key)),
            onSubmit: () {
              Navigator.of(sheetContext).pop();
              _submit();
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact || context.isPhoneLandscape;
    final isMedium = context.isMedium;

    if (isCompact) {
      return Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 左栏：紧凑分类导航 (76dp)
              SizedBox(
                key: const Key('pos-left-column'),
                width: 76,
                child: _CategoryRail(
                  key: const Key('pos-category-rail'),
                  categories: widget.workspace.categories,
                  dishes: widget.workspace.dishes,
                  selectedId: selectedCategoryId,
                  onSelected: (value) => setState(() => selectedCategoryId = value),
                ),
              ),
              const SizedBox(width: 8),
              // 2. 中栏：菜品点选区 (Expanded)
              Expanded(
                child: Column(
                  key: const Key('pos-dish-main-col'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DishToolbar(
                      searchQuery: searchQuery,
                      showKeyboard: showKeyboard,
                      onToggleKeyboard: () => setState(() => showKeyboard = !showKeyboard),
                      onSearchChanged: (val) => setState(() => searchQuery = val),
                      onClearSearch: () => setState(() => searchQuery = ''),
                      quickFilter: quickFilter,
                      onQuickFilterChanged: (val) => setState(() => quickFilter = val),
                    ),
                    if (showKeyboard) ...[
                      const SizedBox(height: 8),
                      _PinyinKeyboardDrawer(
                        onTapKey: (key) => setState(() => searchQuery = '$searchQuery$key'),
                        onQuickKey: (val) => setState(() => searchQuery = val),
                        onBackspace: () {
                          if (searchQuery.isNotEmpty) {
                            setState(() => searchQuery = searchQuery.substring(0, searchQuery.length - 1));
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('pos-dish-grid'),
                        child: _DishGrid(
                          dishes: visibleDishes,
                          packingOrder: widget.packingOrder,
                          onSelected: _selectDish,
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MobileFloatingCartBar(
              cart: cart,
              actionLabel: widget.addingDishes
                  ? '确认加菜'
                  : widget.packingOrder
                  ? '确认打包'
                  : '确认下单',
              submitting: widget.submitting,
              onOpenCart: () => _showMobileCartSheet(context),
              onSubmit: _submit,
            ),
          ),
        ],
      );
    }

    final leftWidth = isMedium ? 110.0 : 140.0;
    final cartWidth = isMedium ? 320.0 : 380.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 左栏：分类导航
        SizedBox(
          key: const Key('pos-left-column'),
          width: leftWidth,
          child: _CategoryRail(
            key: const Key('pos-category-rail'),
            categories: widget.workspace.categories,
            dishes: widget.workspace.dishes,
            selectedId: selectedCategoryId,
            onSelected: (value) => setState(() => selectedCategoryId = value),
          ),
        ),
        const SizedBox(width: 10),
        // 2. 中栏：菜品点选区 (Expanded, 带顶部搜索工具条与触控拼音键盘抽屉)
        Expanded(
          child: Column(
            key: const Key('pos-dish-main-col'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DishToolbar(
                searchQuery: searchQuery,
                showKeyboard: showKeyboard,
                onToggleKeyboard: () => setState(() => showKeyboard = !showKeyboard),
                onSearchChanged: (val) => setState(() => searchQuery = val),
                onClearSearch: () => setState(() => searchQuery = ''),
                quickFilter: quickFilter,
                onQuickFilterChanged: (val) => setState(() => quickFilter = val),
              ),
              if (showKeyboard) ...[
                const SizedBox(height: 8),
                _PinyinKeyboardDrawer(
                  onTapKey: (key) => setState(() => searchQuery = '$searchQuery$key'),
                  onQuickKey: (val) => setState(() => searchQuery = val),
                  onBackspace: () {
                    if (searchQuery.isNotEmpty) {
                      setState(() => searchQuery = searchQuery.substring(0, searchQuery.length - 1));
                    }
                  },
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: KeyedSubtree(
                  key: const Key('pos-dish-grid'),
                  child: _DishGrid(
                    dishes: visibleDishes,
                    packingOrder: widget.packingOrder,
                    onSelected: _selectDish,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // 3. 右栏：购物车与结算面板
        SizedBox(
          key: const Key('pos-cart-panel'),
          width: cartWidth,
          child: _CartPanel(
            cart: cart,
            tableNumber: widget.tableNumber,
            title: widget.packingOrder ? '打包点餐' : null,
            submitting: widget.submitting,
            actionLabel: widget.addingDishes
                ? '确认加菜'
                : widget.packingOrder
                ? '确认打包'
                : (widget.tableNumber.isEmpty ? '立即下单' : '确认下单'),
            packingOrder: widget.packingOrder,
            diners: widget.packingOrder ? null : _diners,
            remark: _remark,
            onEditDiners: widget.packingOrder ? null : _promptEditDiners,
            onEditRemark: _promptEditRemark,
            onBack: _back,
            onClear: () => setState(() => cart = const PosCart()),
            quantityInOrder: _comboQuantityInOrder,
            onQuantityChanged: _changeQuantity,
            onRemove: (line) =>
                setState(() => cart = cart.remove(line.key)),
            onSubmit: _submit,
          ),
        ),
      ],
    );
  }
}

class _MobileFloatingCartBar extends StatelessWidget {
  const _MobileFloatingCartBar({
    required this.cart,
    required this.actionLabel,
    required this.submitting,
    required this.onOpenCart,
    required this.onSubmit,
  });

  final PosCart cart;
  final String actionLabel;
  final bool submitting;
  final VoidCallback onOpenCart;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final totalCount = cart.itemCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1f2937) : const Color(0xff111827),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpenCart,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(28)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Badge(
                        label: Text('$totalCount'),
                        isLabelVisible: totalCount > 0,
                        backgroundColor: const Color(0xffef4444),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            totalCount > 0
                                ? '¥${cart.total.toStringAsFixed(2)}'
                                : '购物车是空的',
                            style: TextStyle(
                              fontSize: totalCount > 0 ? 17 : 14,
                              fontWeight: FontWeight.w800,
                              color: totalCount > 0
                                  ? Colors.white
                                  : Colors.white60,
                            ),
                          ),
                          if (totalCount > 0)
                            const Text(
                              '点击展开明细',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.white60),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton(
                key: const Key('pos-mobile-submit-button'),
                onPressed: submitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff2563eb),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        actionLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DishToolbar extends StatelessWidget {
  const _DishToolbar({
    required this.searchQuery,
    required this.showKeyboard,
    required this.onToggleKeyboard,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.quickFilter,
    required this.onQuickFilterChanged,
  });

  final String searchQuery;
  final bool showKeyboard;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final String quickFilter;
  final ValueChanged<String> onQuickFilterChanged;

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;
    final searchInput = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: context.cashier.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('pos-dish-search-input'),
              controller: TextEditingController(text: searchQuery)
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: searchQuery.length),
                ),
              onChanged: onSearchChanged,
              style: TextStyle(
                fontSize: 13,
                color: context.cashier.ink,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: isCompact
                    ? '搜索菜品/编号...'
                    : '输入拼音首字母/菜品编号 (如: YB, 01)...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: context.cashier.inkMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: isCompact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(width: 130, child: searchInput),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const Key('pos-dish-search-clear'),
                    onPressed: onClearSearch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.cashier.inkSecondary,
                      side: BorderSide(color: context.cashier.border),
                      backgroundColor: context.cashier.subtle,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      '清空',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _QuickFilterChip(
                    label: '全部',
                    active: quickFilter == 'all',
                    onTap: () => onQuickFilterChanged('all'),
                  ),
                  const SizedBox(width: 6),
                  _QuickFilterChip(
                    label: '招牌',
                    active: quickFilter == 'sign',
                    onTap: () => onQuickFilterChanged('sign'),
                  ),
                  const SizedBox(width: 6),
                  _QuickFilterChip(
                    label: '仅可售',
                    active: quickFilter == 'instock',
                    onTap: () => onQuickFilterChanged('instock'),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: searchInput),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('pos-dish-search-clear'),
                  onPressed: onClearSearch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.inkSecondary,
                    side: BorderSide(color: context.cashier.border),
                    backgroundColor: context.cashier.subtle,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    '清空',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('pos-keyboard-toggle'),
                  onPressed: onToggleKeyboard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: showKeyboard
                        ? context.cashier.ink
                        : context.cashier.inkMuted,
                    side: BorderSide(color: context.cashier.border),
                    backgroundColor: showKeyboard
                        ? context.cashier.subtle
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    showKeyboard ? '⌨️ 收起拼音键盘' : '⌨️ 展开拼音键盘',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                _QuickFilterChip(
                  label: '全部',
                  active: quickFilter == 'all',
                  onTap: () => onQuickFilterChanged('all'),
                ),
                const SizedBox(width: 6),
                _QuickFilterChip(
                  label: '招牌',
                  active: quickFilter == 'sign',
                  onTap: () => onQuickFilterChanged('sign'),
                ),
                const SizedBox(width: 6),
                _QuickFilterChip(
                  label: '仅可售',
                  active: quickFilter == 'instock',
                  onTap: () => onQuickFilterChanged('instock'),
                ),
              ],
            ),
    );
  }
}

class _PinyinKeyboardDrawer extends StatelessWidget {
  const _PinyinKeyboardDrawer({
    required this.onTapKey,
    required this.onQuickKey,
    required this.onBackspace,
  });

  final ValueChanged<String> onTapKey;
  final ValueChanged<String> onQuickKey;
  final VoidCallback onBackspace;

  static const _row1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const _row2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  static const _row3 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pos-pinyin-keyboard-drawer'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final key in _row1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _KbKey(label: key, onTap: () => onTapKey(key)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(flex: 1),
              for (final key in _row2)
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _KbKey(label: key, onTap: () => onTapKey(key)),
                  ),
                ),
              const Spacer(flex: 1),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _KbKey(
                label: 'YB(油边)',
                isAction: true,
                onTap: () => onQuickKey('YB'),
              ),
              const SizedBox(width: 4),
              for (final key in _row3)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _KbKey(label: key, onTap: () => onTapKey(key)),
                  ),
                ),
              const SizedBox(width: 4),
              _KbKey(
                label: '⌫ 退格',
                isAction: true,
                onTap: onBackspace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KbKey extends StatelessWidget {
  const _KbKey({
    required this.label,
    this.isAction = false,
    required this.onTap,
  });

  final String label;
  final bool isAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isAction ? context.cashier.subtle : context.cashier.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: context.cashier.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: isAction ? 10 : 4),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isAction ? context.cashier.ink : context.cashier.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickFilterChip extends StatelessWidget {
  const _QuickFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: active ? context.cashier.ink : context.cashier.subtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: active ? context.cashier.ink : context.cashier.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active
                  ? (isDark ? Colors.black : Colors.white)
                  : context.cashier.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DishGrid extends StatelessWidget {
  const _DishGrid({
    required this.dishes,
    required this.packingOrder,
    required this.onSelected,
  });

  final List<PosDish> dishes;
  final bool packingOrder;
  final ValueChanged<PosDish> onSelected;

  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: context.cashier.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '当前分类暂无菜品',
              style: TextStyle(
                color: context.cashier.ink,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '请尝试更换分类或清除搜索关键词',
              style: TextStyle(color: context.cashier.inkMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1200
            ? 6
            : (constraints.maxWidth >= 950
                ? 5
                : (constraints.maxWidth >= 700
                    ? 4
                    : (constraints.maxWidth >= 450 ? 3 : 2)));
        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: dishes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 140 / 114,
          ),
          itemBuilder: (context, index) {
            final dish = dishes[index];
            return _DishCard(
              key: Key('pos-dish-card-${dish.id}'),
              dish: dish,
              commercialUnavailableReason: dish.comboDefinition?.unavailableReason(
                now: DateTime.now(),
                packingOrder: packingOrder,
              ),
              onTap: () => onSelected(dish),
            );
          },
        );
      },
    );
  }
}

class _DishCard extends StatelessWidget {
  const _DishCard({
    super.key,
    required this.dish,
    required this.commercialUnavailableReason,
    required this.onTap,
  });

  final PosDish dish;
  final String? commercialUnavailableReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = dish.available && commercialUnavailableReason == null;
    final code = _dishCode(dish);
    final subtitle = _dishSubtitle(dish);
    final commercialLabels = <String>[];
    final combo = dish.comboDefinition;
    if (available && combo != null) {
      final start = combo.timeRangeStart;
      final end = combo.timeRangeEnd;
      if (start != null && end != null) {
        commercialLabels.add('${_compactTime(start)}–${_compactTime(end)}');
      }
      final orderLimit = combo.limitPerOrder;
      if (orderLimit != null && orderLimit > 0) {
        commercialLabels.add('单单限$orderLimit份');
      }
      if (!combo.allowCoupon && commercialLabels.length < 2) {
        commercialLabels.add('不参与用券');
      }
    }

    return Semantics(
      button: true,
      label: '${dish.name}，${commercialUnavailableReason ?? dish.stockLabel}',
      child: Material(
        color: available ? context.cashier.surface : context.cashier.subtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: available
                ? context.cashier.border
                : context.cashier.border.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: dish.available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dish.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: available
                                  ? context.cashier.ink
                                  : context.cashier.inkMuted,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (!available)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: context.cashier.danger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              commercialUnavailableReason ?? '售罄',
                              style: TextStyle(
                                color: context.cashier.danger,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else ...[
                          if (commercialLabels.isNotEmpty)
                            for (final label in commercialLabels.take(2))
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: context.cashier.warningBackground,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: context.cashier.warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          if (dish.isCombo)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: context.cashier.subtle,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: context.cashier.border),
                              ),
                              child: Text(
                                '套餐',
                                style: TextStyle(
                                  color: context.cashier.inkSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else if (dish.specGroups.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: context.cashier.subtle,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: context.cashier.border),
                              ),
                              child: Text(
                                '多规格',
                                style: TextStyle(
                                  color: context.cashier.inkSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '[$code] $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '¥${dish.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: available ? context.cashier.ink : context.cashier.inkMuted,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: context.cashier.subtle,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.cashier.border),
                      ),
                      child: Text(
                        dish.unit.isNotEmpty ? dish.unit : '份',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dishCode(PosDish dish) {
  final initials = _toPinyinInitials(dish.name).toUpperCase();
  final prefix = initials.length >= 2 ? initials.substring(0, 2) : initials.padRight(2, 'X');
  final numStr = dish.id.toString().padLeft(2, '0');
  return '$prefix$numStr';
}

String _dishSubtitle(PosDish dish) {
  if (dish.comboDefinition?.unavailableReason(now: DateTime.now(), packingOrder: false) case final reason?) {
    return reason;
  }
  if (dish.isCombo) return '组合套餐 / 优惠畅享';
  if (dish.specGroups.isNotEmpty) return '现穿现烤 / 人气必选';
  return '现做现上 / 经典风味';
}

String _compactTime(String value) {
  final trimmed = value.trim();
  return trimmed.length >= 5 ? trimmed.substring(0, 5) : trimmed;
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    super.key,
    required this.categories,
    required this.dishes,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PosCategory> categories;
  final List<PosDish> dishes;
  final int? selectedId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _CategoryButton(
            key: const Key('pos-category-all'),
            label: '全部商品',
            count: dishes.length,
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          for (final category in categories)
            _CategoryButton(
              key: Key('pos-category-${category.id}'),
              label: category.name,
              count: dishes
                  .where(
                    (d) =>
                        d.categoryId == category.id ||
                        (category.code.isNotEmpty &&
                            d.categoryCode == category.code),
                  )
                  .length,
              selected: selectedId == category.id,
              onTap: () => onSelected(category.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected ? context.cashier.subtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.cashier.border),
              left: BorderSide(
                color: selected ? context.cashier.ink : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? context.cashier.ink : context.cashier.inkSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: selected
                      ? (isDark ? context.cashier.ink : Colors.black)
                      : context.cashier.subtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? Colors.transparent : context.cashier.border,
                  ),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? (isDark ? Colors.black : Colors.white)
                        : context.cashier.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.tableNumber,
    this.title,
    required this.submitting,
    required this.actionLabel,
    required this.packingOrder,
    this.diners,
    required this.remark,
    this.onEditDiners,
    required this.onEditRemark,
    required this.onBack,
    required this.onClear,
    required this.quantityInOrder,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onSubmit,
  });

  final PosCart cart;
  final String tableNumber;
  final String? title;
  final bool submitting;
  final String actionLabel;
  final bool packingOrder;
  final int? diners;
  final String remark;
  final VoidCallback? onEditDiners;
  final VoidCallback onEditRemark;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final int Function(PosDish dish) quantityInOrder;
  final void Function(PosCartLine line, int value) onQuantityChanged;
  final ValueChanged<PosCartLine> onRemove;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _CartHeader(
            tableNumber: tableNumber,
            title: title,
            showClear: cart.lines.isNotEmpty,
            onBack: onBack,
            onClear: onClear,
            diners: diners,
            onEditDiners: onEditDiners,
          ),
          Expanded(
            child: cart.lines.isEmpty
                ? const _EmptyCartState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final line = cart.lines[index];
                      return _CartRow(
                        key: Key('cart-row-${index + 1}'),
                        index: index + 1,
                        line: line,
                        quantityInOrder: quantityInOrder(line.dish),
                        onQuantityChanged: (value) =>
                            onQuantityChanged(line, value),
                        onRemove: () => onRemove(line),
                      );
                    },
                  ),
          ),
          _CartFooter(
            cart: cart,
            packingOrder: packingOrder,
            remark: remark,
            submitting: submitting,
            actionLabel: actionLabel,
            onEditRemark: onEditRemark,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.tableNumber,
    this.title,
    required this.showClear,
    required this.onBack,
    required this.onClear,
    this.diners,
    this.onEditDiners,
  });

  final String tableNumber;
  final String? title;
  final bool showClear;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final int? diners;
  final VoidCallback? onEditDiners;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  title ?? (tableNumber.isEmpty ? '待选桌台' : '$tableNumber号'),
                  style: TextStyle(
                    fontSize: 15,
                    color: context.cashier.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (title == null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '· 点单小票',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (diners != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onEditDiners,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        '$diners人就餐',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showClear) ...[
            OutlinedButton(
              key: const Key('clear-cart'),
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cashier.danger,
                side: BorderSide(color: context.cashier.border),
                backgroundColor: context.cashier.surface,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                '清空',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: '返回桌台',
            child: FilledButton.icon(
              key: const Key('pos-cart-back-button'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text(
                '返回桌台',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff2563eb),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: context.cashier.border,
            ),
            const SizedBox(height: 12),
            Text(
              '请从左侧点选菜品',
              style: TextStyle(
                color: context.cashier.inkSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '购物车空空如也，可输入拼音简码加菜',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cashier.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    super.key,
    required this.index,
    required this.line,
    required this.quantityInOrder,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final int index;
  final PosCartLine line;
  final int quantityInOrder;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.cashier.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.dish.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          color: context.cashier.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (line.specification.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xff1e293b)
                              : const Color(0xffeff6ff),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xff334155)
                                : const Color(0xffbfdbfe),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          line.specification,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xff93c5fd)
                                : const Color(0xff1d4ed8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (line.dish.comboDefinition?.limitPerOrder case final limit?)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      quantityInOrder >= limit
                          ? '已达本单限购上限 $limit 份'
                          : '本单还可购买 ${limit - quantityInOrder} 份',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: quantityInOrder >= limit
                            ? context.cashier.warning
                            : context.cashier.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '¥${line.dish.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xffdc2626),
                        fontFamily: 'monospace',
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xff27272a) : const Color(0xffe2e8f0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '× ${line.quantity}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: context.cashier.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _QuantityControl(
            key: Key('cart-quantity-$index'),
            value: line.quantity,
            increaseKey: Key('cart-quantity-increase-$index'),
            onChanged: onQuantityChanged,
          ),
        ],
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.cart,
    required this.packingOrder,
    required this.remark,
    required this.submitting,
    required this.actionLabel,
    required this.onEditRemark,
    required this.onSubmit,
  });

  final PosCart cart;
  final bool packingOrder;
  final String remark;
  final bool submitting;
  final String actionLabel;
  final VoidCallback onEditRemark;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final total = packingOrder ? cart.totalWithPackaging : cart.total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        border: Border(top: BorderSide(color: context.cashier.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '待下单总计 (${cart.itemCount}件)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.cashier.inkSecondary,
                ),
              ),
              Text(
                '¥${total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: context.cashier.ink,
                ),
              ),
            ],
          ),
          if (packingOrder) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '打包费',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkSecondary,
                  ),
                ),
                Text(
                  '含打包费 ¥${cart.packagingFee.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    showPosNotice(
                      context,
                      title: '整单优惠',
                      message: '整单优惠可在结账台结算时直接应用。',
                      tone: PosNoticeTone.info,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.ink,
                    side: BorderSide(color: context.cashier.border),
                    backgroundColor: context.cashier.subtle,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    '整单优惠',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onEditRemark,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.ink,
                    side: BorderSide(color: context.cashier.border),
                    backgroundColor: context.cashier.subtle,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    remark.isEmpty ? '整单备注' : '备注: $remark',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (cart.lines.isNotEmpty)
            SizedBox(
              height: 52,
              width: double.infinity,
              child: _SubmitButton(
                key: const Key('pos-submit-populated'),
                label: actionLabel,
                submitting: submitting,
                onPressed: onSubmit,
              ),
            ),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    super.key,
    required this.label,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton(
      onPressed: submitting ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? Colors.white : const Color(0xff09090b),
        foregroundColor: isDark ? const Color(0xff09090b) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Center(
        child: submitting
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  color: isDark ? Colors.black : Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 20,
                    color: isDark ? const Color(0xff09090b) : Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: isDark ? const Color(0xff09090b) : Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.large = false,
    this.increaseKey,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool large;
  final Key? increaseKey;

  @override
  Widget build(BuildContext context) {
    final height = large ? 52.0 : 42.0;
    final buttonWidth = large ? 52.0 : 38.0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border.all(color: context.cashier.border, width: 1.2),
        borderRadius: BorderRadius.circular(large ? 8 : 7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(
            key: large ? const Key('spec-quantity-decrease') : null,
            icon: Icons.remove,
            width: buttonWidth,
            height: height,
            large: large,
            onTap: () => onChanged(value - 1),
          ),
          Container(
            constraints: BoxConstraints(minWidth: large ? 52 : 36),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: TextStyle(
                color: context.cashier.ink,
                fontSize: large ? 24 : 17,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
          _QuantityButton(
            key:
                increaseKey ??
                (large ? const Key('spec-quantity-increase') : null),
            icon: Icons.add,
            width: buttonWidth,
            height: height,
            large: large,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    super.key,
    required this.icon,
    required this.width,
    required this.height,
    required this.large,
    required this.onTap,
  });

  final IconData icon;
  final double width;
  final double height;
  final bool large;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final action = icon == Icons.add ? '增加数量' : '减少数量';
    return Semantics(
      button: true,
      label: action,
      child: Material(
        color: large
            ? (isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9))
            : context.cashier.surface,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Icon(
              icon,
              size: large ? 24 : 20,
              color: large
                  ? const Color(0xff2563eb)
                  : context.cashier.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecificationSelection {
  const _SpecificationSelection({required this.values, required this.quantity});

  final Map<String, String> values;
  final int quantity;
}

class _ComboSelection {
  const _ComboSelection({
    required this.specifications,
    required this.comboSelections,
    required this.quantity,
  });

  final Map<String, String> specifications;
  final Map<String, List<int>> comboSelections;
  final int quantity;
}

class _ComboSelectionDialog extends StatefulWidget {
  const _ComboSelectionDialog({
    required this.dish,
    required this.menuDishes,
    required this.maxQuantity,
  });

  final PosDish dish;
  final List<PosDish> menuDishes;
  final int? maxQuantity;

  @override
  State<_ComboSelectionDialog> createState() => _ComboSelectionDialogState();
}

class _ComboSelectionDialogState extends State<_ComboSelectionDialog> {
  late final Map<int, PosDish> dishesById = {
    for (final dish in widget.menuDishes) dish.id: dish,
  };
  late final Map<String, String> specifications = {
    for (final group in widget.dish.specGroups)
      if (group.options.isNotEmpty) group.label: group.options.first,
  };
  late final Map<String, List<int>> comboSelections = {
    for (final group
        in widget.dish.comboDefinition?.groups ?? const <PosComboGroup>[])
      group.key: group.options
          .where((option) => dishesById[option.dishId]?.available ?? false)
          .take(group.minPick)
          .map((option) => option.dishId)
          .toList(growable: true),
  };
  int quantity = 1;

  PosComboDefinition get combo => widget.dish.comboDefinition!;

  bool get selectionValid => combo.groups.every((group) {
    final count = comboSelections[group.key]?.length ?? 0;
    return count >= group.minPick && count <= group.maxPick;
  });

  String _dishName(int dishId) => dishesById[dishId]?.name ?? '菜品#$dishId';

  void _toggleOption(PosComboGroup group, PosComboOption option) {
    final component = dishesById[option.dishId];
    if (component == null || !component.available) return;
    final selected = comboSelections[group.key] ?? <int>[];
    final next = List<int>.from(selected);
    if (group.maxPick <= 1) {
      next.clear();
      if (!selected.contains(option.dishId) || group.minPick > 0) {
        next.add(option.dishId);
      }
    } else if (next.contains(option.dishId)) {
      if (next.length > group.minPick) next.remove(option.dishId);
    } else if (next.length < group.maxPick) {
      next.add(option.dishId);
    }
    setState(() => comboSelections[group.key] = next);
  }

  @override
  Widget build(BuildContext context) {
    final fixedSummary = combo.fixedItems
        .map((item) => '${_dishName(item.dishId)}×${item.quantity}')
        .join('、');
    final unitPrice = widget.dish.price + combo.extraPriceFor(comboSelections);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: context.cashier.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        key: const Key('combo-dialog'),
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.dish.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.cashier.ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '¥${unitPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xffdc2626),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (fixedSummary.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '套餐包含：$fixedSummary',
                    style: TextStyle(fontSize: 18, color: context.cashier.ink),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in widget.dish.specGroups) ...[
                        _ComboSectionTitle(
                          title: '选择${group.label}',
                          helper: '请选择 1 项',
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final option in group.options)
                              ChoiceChip(
                                label: Text(option),
                                selected: specifications[group.label] == option,
                                selectedColor: isDark
                                    ? context.cashier.selectedBackground
                                    : const Color(0xffead4d5),
                                onSelected: (_) => setState(
                                  () => specifications[group.label] = option,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      for (final group in combo.groups) ...[
                        _ComboSectionTitle(
                          title: group.title.isEmpty ? group.key : group.title,
                          helper: group.minPick == group.maxPick
                              ? '请选择 ${group.minPick} 项'
                              : '请选择 ${group.minPick}～${group.maxPick} 项',
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final option in group.options)
                              Builder(
                                builder: (context) {
                                  final component = dishesById[option.dishId];
                                  final available =
                                      component?.available ?? false;
                                  final selected =
                                      comboSelections[group.key]?.contains(
                                        option.dishId,
                                      ) ??
                                      false;
                                  final extra = option.extraPrice == 0
                                      ? ''
                                      : ' +¥${option.extraPrice.toStringAsFixed(2)}';
                                  return FilterChip(
                                    key: Key(
                                      'combo-option-${group.key}-${option.dishId}',
                                    ),
                                    label: Text(
                                      '${_dishName(option.dishId)}$extra${available ? '' : '（已售罄）'}',
                                    ),
                                    selected: selected,
                                    selectedColor: isDark
                                        ? context.cashier.selectedBackground
                                        : const Color(0xffead4d5),
                                    onSelected: available
                                        ? (_) => _toggleOption(group, option)
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '数量',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: context.cashier.ink,
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 180,
                    height: 52,
                    child: _QuantityControl(
                      value: quantity,
                      onChanged: (value) {
                        final maximum = widget.maxQuantity ?? 99;
                        setState(() => quantity = value.clamp(1, maximum));
                      },
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('combo-confirm'),
                    onPressed: selectionValid
                        ? () => Navigator.pop(
                            context,
                            _ComboSelection(
                              specifications: Map.of(specifications),
                              comboSelections: {
                                for (final entry in comboSelections.entries)
                                  entry.key: List<int>.from(entry.value),
                              },
                              quantity: quantity,
                            ),
                          )
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.cashier.ink,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                    ),
                    child: const Text('确认加入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComboSectionTitle extends StatelessWidget {
  const _ComboSectionTitle({required this.title, required this.helper});

  final String title;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xff2563eb),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.cashier.ink,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            helper,
            style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _SpecificationDialog extends StatefulWidget {
  const _SpecificationDialog({required this.dish, this.maxQuantity});

  final PosDish dish;
  final int? maxQuantity;

  @override
  State<_SpecificationDialog> createState() => _SpecificationDialogState();
}

class _SpecificationDialogState extends State<_SpecificationDialog> {
  late final Map<String, String> selections = {
    for (final group in widget.dish.specGroups)
      if (group.options.isNotEmpty) group.label: group.options.first,
  };
  int quantity = 1;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      backgroundColor: context.cashier.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.cashier.border, width: 1.2),
      ),
      child: Container(
        key: const Key('spec-dialog'),
        width: 752,
        constraints: const BoxConstraints(maxHeight: 575),
        padding: const EdgeInsets.fromLTRB(40, 26, 40, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.dish.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.cashier.ink,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff2563eb).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xff2563eb).withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 13,
                                  color: Color(0xff2563eb),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '规格定制',
                                  style: TextStyle(
                                    color: Color(0xff2563eb),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '按需定制口味与偏好 · 支持调整下单份数',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.cashier.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '¥${widget.dish.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xffdc2626),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      '单位: ${widget.dish.unit.isEmpty ? "份" : widget.dish.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: context.cashier.border),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in widget.dish.specGroups) ...[
                      _SpecificationGroupPicker(
                        group: group,
                        selected:
                            selections[group.label] ??
                            (group.options.isNotEmpty
                                ? group.options.first
                                : ''),
                        onSelected: (option) =>
                            setState(() => selections[group.label] = option),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff18181b) : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cashier.border, width: 1.0),
              ),
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '数量',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.cashier.ink,
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        key: const Key('spec-quantity-control'),
                        height: 52,
                        child: _QuantityControl(
                          value: quantity,
                          large: true,
                          onChanged: (value) async {
                            final maximum = widget.maxQuantity ?? 99;
                            if (value > maximum) {
                              await showPosNotice(
                                context,
                                title: '库存不足',
                                message:
                                    '${widget.dish.name}库存仅剩 $maximum 份，不能继续增加数量。',
                                tone: PosNoticeTone.warning,
                              );
                              return;
                            }
                            if (mounted) {
                              setState(() => quantity = value.clamp(1, maximum));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '小计金额',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '¥${(widget.dish.price * quantity).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xffdc2626),
                          fontFamily: 'monospace',
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: OutlinedButton(
                      key: const Key('spec-cancel'),
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.cashier.ink,
                        backgroundColor: context.cashier.surface,
                        side: BorderSide(
                          color: context.cashier.border,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: FilledButton(
                      key: const Key('spec-confirm'),
                      onPressed: () => Navigator.pop(
                        context,
                        _SpecificationSelection(
                          values: Map.of(selections),
                          quantity: quantity,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff2563eb),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '确认',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecificationGroupPicker extends StatelessWidget {
  const _SpecificationGroupPicker({
    required this.group,
    required this.selected,
    required this.onSelected,
  });

  final PosSpecGroup group;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xff2563eb), width: 4)),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                '选择${group.label}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff1e293b) : const Color(0xffeff6ff),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? const Color(0xff334155) : const Color(0xffbfdbfe),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '单选',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xff93c5fd) : const Color(0xff1d4ed8),
                  ),
                ),
              ),
              const Spacer(),
              if (selected.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '已选：$selected',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff2563eb),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final option in group.options)
              SizedBox(
                key: Key('spec-option-${group.label}-$option'),
                width: 170,
                height: 60,
                child: _SpecOptionTile(
                  option: option,
                  isSelected: selected == option,
                  onTap: () => onSelected(option),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpecOptionTile extends StatelessWidget {
  const _SpecOptionTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final String option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isSelected
          ? const Color(0xff2563eb)
          : (isDark ? context.cashier.subtle : const Color(0xfff8fafc)),
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 2 : 0,
      shadowColor: const Color(0xff2563eb).withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xff3b82f6)
                  : context.cashier.border,
              width: isSelected ? 1.6 : 1.1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    option,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : context.cashier.ink,
                      fontSize: 20,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              if (isSelected)
                const Positioned(
                  top: 5,
                  right: 6,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _dishMatchesSearch(String name, String query) {
  final cleanName = name.toLowerCase();
  if (cleanName.contains(query)) return true;
  final initials = _toPinyinInitials(cleanName);
  return initials.contains(query);
}

String _toPinyinInitials(String text) {
  final sb = StringBuffer();
  for (final char in text.runes) {
    if (char >= 0x4e00 && char <= 0x9fa5) {
      sb.write(_charToPinyinInitial(char));
    } else {
      sb.write(String.fromCharCode(char).toLowerCase());
    }
  }
  return sb.toString();
}

String _charToPinyinInitial(int codePoint) {
  const pinyinCharMap = <int, String>{
    0x8001: 'l', // 老
    0x80a5: 'f', // 肥
    0x6cb9: 'y', // 油
    0x8fb9: 'b', // 边
    0x738b: 'w', // 王
    0x70e4: 'k', // 烤
    0x8089: 'r', // 肉
    0x4e32: 'c', // 串
    0x7f8a: 'y', // 羊
    0x725b: 'n', // 牛
    0x732a: 'z', // 猪
    0x9e21: 'j', // 鸡
    0x9e2d: 'y', // 鸭
    0x9c7c: 'y', // 鱼
    0x867e: 'x', // 虾
    0x87f9: 'x', // 蟹
    0x7172: 'b', // 煲
    0x6c64: 't', // 汤
    0x996d: 'f', // 饭
    0x9762: 'm', // 面
    0x83dc: 'c', // 菜
    0x7279: 't', // 特
    0x8272: 's', // 色
    0x62db: 'z', // 招
    0x724c: 'p', // 牌
    0x79d8: 'm', // 秘
    0x5236: 'z', // 制
    0x9152: 'j', // 酒
    0x6c34: 's', // 水
    0x5564: 'p', // 啤
    0x9ec4: 'h', // 黄
    0x74dc: 'g', // 瓜
    0x62cd: 'p', // 拍
    0x8fa3: 'l', // 辣
    0x9ebb: 'm', // 麻
    0x9999: 'x', // 香
    0x80a0: 'c', // 肠
    0x51c9: 'l', // 凉
    0x62cc: 'b', // 拌
    0x751f: 's', // 生
    0x869d: 'h', // 蚝
    0x8106: 'c', // 脆
    0x9aa8: 'g', // 骨
    0x5fc3: 'x', // 心
    0x8170: 'y', // 腰
    0x5b50: 'z', // 子
  };
  return pinyinCharMap[codePoint] ?? '';
}
