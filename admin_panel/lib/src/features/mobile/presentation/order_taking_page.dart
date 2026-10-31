import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/domain/pos_models.dart';
import '../../tables/domain/dining_table.dart';
import '../data/cart_state.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';
import 'checkout_page.dart';

class OrderTakingPage extends ConsumerStatefulWidget {
  const OrderTakingPage({super.key, required this.table});

  final DiningTable table;

  @override
  ConsumerState<OrderTakingPage> createState() => _OrderTakingPageState();
}

class _OrderTakingPageState extends ConsumerState<OrderTakingPage> {
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(posWorkspaceProvider(widget.table));
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('点菜 · ${widget.table.number}'),
        actions: [
          if (cart.totalQuantity > 0)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('清空'),
            ),
        ],
      ),
      body: workspace.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (data) {
          final categories = data.categories;
          if (categories.isEmpty) {
            return const Center(child: Text('暂无菜品'));
          }
          final selected = categories[_selectedCategory.clamp(0, categories.length - 1)];
          final dishes = data.dishes
              .where((d) => d.categoryId == selected.id || d.requestCategoryCode == selected.code)
              .toList();
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final selected = index == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat.name),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = index),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: dishes.isEmpty
                    ? const Center(child: Text('该分类暂无菜品'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: dishes.length,
                        itemBuilder: (context, index) =>
                            _DishCard(dish: dishes[index]),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: cart.totalQuantity == 0
          ? null
          : _CartBar(
              total: cart.total,
              quantity: cart.totalQuantity,
              onCheckout: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CheckoutPage(table: widget.table),
                ),
              ),
            ),
    );
  }
}

class _DishCard extends ConsumerWidget {
  const _DishCard({required this.dish});

  final PosDish dish;

  /// 含规格的菜品先弹规格选择，无规格直接加入购物车。
  void _addDish(BuildContext context, WidgetRef ref, PosDish dish) {
    if (dish.specGroups.isEmpty) {
      ref.read(cartProvider.notifier).add(dish);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (_) => _SpecSheet(dish: dish),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final lineIndex = cart.lines.indexWhere((l) => l.dish.id == dish.id);
    final quantity = lineIndex >= 0 ? cart.lines[lineIndex].quantity : 0;
    final available = dish.available;
    return Opacity(
      opacity: available ? 1 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: MobileMetrics.cardGap),
        child: Padding(
          padding: MobileMetrics.cardPaddingCompact,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            dish.name,
                            style: MobileTypography.itemTitle,
                          ),
                        ),
                        if (!available) ...[
                          const SizedBox(width: MobileMetrics.spaceXs),
                          const StatusTag('已估清', tone: SemanticTone.danger),
                        ],
                      ],
                    ),
                    const SizedBox(height: MobileMetrics.spaceXs),
                    Text(
                      '¥${dish.price.toStringAsFixed(2)} /${dish.unit}',
                      style: context.bodySecondaryStyle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (quantity > 0) ...[
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      color: context.palette.brand,
                      tooltip: '减少一份',
                      onPressed: () => ref
                          .read(cartProvider.notifier)
                          .decrement(cart.lines[lineIndex]),
                    ),
                    Text(
                      '$quantity',
                      style: MobileTypography.itemTitle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    color: available
                        ? context.palette.brand
                        : context.palette.textDisabled,
                    tooltip: available ? '加入购物车' : '已估清',
                    onPressed: available
                        ? () => _addDish(context, ref, dish)
                        : null,
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

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.total,
    required this.quantity,
    required this.onCheckout,
  });

  final double total;
  final int quantity;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.cartBar,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MobileMetrics.spaceLg,
            vertical: MobileMetrics.spaceSm,
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_outlined, color: Colors.white),
              const SizedBox(width: MobileMetrics.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.spaceXs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.palette.danger,
                  borderRadius: BorderRadius.circular(
                    MobileMetrics.radiusPill,
                  ),
                ),
                child: Text(
                  '$quantity',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(width: MobileMetrics.cardGap),
              Text(
                '¥ ${total.toStringAsFixed(2)}',
                style: MobileTypography.sectionTitle.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, MobileMetrics.buttonHeight),
                ),
                onPressed: onCheckout,
                child: const Text('下单'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 规格选择弹层：每个规格组单选，确认后加入购物车（携带 selections）。
class _SpecSheet extends ConsumerStatefulWidget {
  const _SpecSheet({required this.dish});

  final PosDish dish;

  @override
  ConsumerState<_SpecSheet> createState() => _SpecSheetState();
}

class _SpecSheetState extends ConsumerState<_SpecSheet> {
  late final Map<String, String> _selections = {
    for (final group in widget.dish.specGroups)
      if (group.options.isNotEmpty) group.label: group.options.first,
  };
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(MobileMetrics.spaceLg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dish.name, style: MobileTypography.sectionTitle),
                      const SizedBox(height: MobileMetrics.spaceXs),
                      Text(
                        '¥${dish.price.toStringAsFixed(2)}/${dish.unit}',
                        style: context.bodySecondaryStyle.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                MobileMetrics.spaceLg,
                MobileMetrics.spaceMd,
                MobileMetrics.spaceLg,
                MobileMetrics.spaceLg,
              ),
              children: [
                for (final group in dish.specGroups) ...[
                  Text(group.label, style: MobileTypography.label),
                  const SizedBox(height: MobileMetrics.spaceSm),
                  Wrap(
                    spacing: MobileMetrics.spaceSm,
                    runSpacing: MobileMetrics.spaceSm,
                    children: [
                      for (final option in group.options)
                        ChoiceChip(
                          label: Text(option),
                          selected: _selections[group.label] == option,
                          onSelected: (_) => setState(
                            () => _selections[group.label] = option,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: MobileMetrics.spaceLg),
                ],
                Row(
                  children: [
                    const Text('数量', style: MobileTypography.label),
                    const Spacer(),
                    IconButton(
                      tooltip: '减少一份',
                      onPressed: _quantity <= 1
                          ? null
                          : () => setState(() => _quantity--),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$_quantity',
                      style: MobileTypography.itemTitle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      tooltip: '增加一份',
                      onPressed: _quantity >= 99
                          ? null
                          : () => setState(() => _quantity++),
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(MobileMetrics.spaceLg),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                ),
                onPressed: () {
                  ref
                      .read(cartProvider.notifier)
                      .add(dish, selections: _selections, quantity: _quantity);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已加入购物车：${dish.name}')),
                  );
                },
                child: const Text('加入购物车'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
