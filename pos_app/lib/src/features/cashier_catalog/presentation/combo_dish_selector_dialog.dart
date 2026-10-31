import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../domain/cashier_dish.dart';

class ComboDishSelectorDialog extends StatefulWidget {
  const ComboDishSelectorDialog({
    super.key,
    required this.allDishes,
    required this.categories,
    this.excludedDishIds = const {},
    this.title = '选择菜品',
  });

  final List<CashierDish> allDishes;
  final List<CashierDishCategory> categories;
  final Set<int> excludedDishIds;
  final String title;

  static Future<List<CashierDish>?> show({
    required BuildContext context,
    required List<CashierDish> allDishes,
    required List<CashierDishCategory> categories,
    Set<int> excludedDishIds = const {},
    String title = '选择菜品',
  }) {
    return showDialog<List<CashierDish>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ComboDishSelectorDialog(
        allDishes: allDishes,
        categories: categories,
        excludedDishIds: excludedDishIds,
        title: title,
      ),
    );
  }

  @override
  State<ComboDishSelectorDialog> createState() => _ComboDishSelectorDialogState();
}

class _ComboDishSelectorDialogState extends State<ComboDishSelectorDialog> {
  final _searchController = TextEditingController();
  int? _selectedCategoryId;
  final _selectedDishes = <int, CashierDish>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CashierDish> get _filteredDishes {
    final query = _searchController.text.trim().toLowerCase();
    return widget.allDishes.where((dish) {
      if (widget.excludedDishIds.contains(dish.id)) {
        return false;
      }
      if (_selectedCategoryId != null && _selectedCategoryId! > 0) {
        if (dish.typeId != _selectedCategoryId) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final nameMatch = dish.name.toLowerCase().contains(query);
        final catMatch = dish.categoryName.toLowerCase().contains(query);
        if (!nameMatch && !catMatch) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.cashier;
    final filtered = _filteredDishes;

    return Dialog(
      backgroundColor: cashier.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cashier.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶栏
              Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cashier.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: cashier.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 搜索与分类筛选
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: cashier.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索菜品名称或分类...',
                        hintStyle: TextStyle(color: cashier.inkSecondary, fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 18, color: cashier.inkSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: cashier.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: cashier.border),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 分类下拉选择
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: cashier.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedCategoryId,
                        hint: Text('全部分类', style: TextStyle(color: cashier.ink, fontSize: 13)),
                        dropdownColor: cashier.surface,
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('全部分类', style: TextStyle(color: cashier.ink, fontSize: 13)),
                          ),
                          ...widget.categories.map(
                            (c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name, style: TextStyle(color: cashier.ink, fontSize: 13)),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedCategoryId = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 菜品选择表格/列表
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cashier.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            '未找到匹配菜品',
                            style: TextStyle(color: cashier.inkSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: cashier.border),
                          itemBuilder: (ctx, index) {
                            final dish = filtered[index];
                            final isSelected = _selectedDishes.containsKey(dish.id);
                            return CheckboxListTile(
                              value: isSelected,
                              activeColor: cashier.selected,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedDishes[dish.id] = dish;
                                  } else {
                                    _selectedDishes.remove(dish.id);
                                  }
                                });
                              },
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dish.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cashier.ink,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: cashier.subtle,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      dish.categoryName.isNotEmpty ? dish.categoryName : '未分类',
                                      style: TextStyle(fontSize: 11, color: cashier.inkSecondary),
                                    ),
                                  ),
                                  Text(
                                    '¥',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: cashier.selected,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // 底部确认栏
              Row(
                children: [
                  Text(
                    '已选  项',
                    style: TextStyle(
                      color: cashier.inkSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cashier.ink,
                      side: BorderSide(color: cashier.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedDishes.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop(_selectedDishes.values.toList());
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cashier.selected,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('加入配置'),
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
