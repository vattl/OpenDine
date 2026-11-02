import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/dish_ai_profile_repository.dart';
import '../domain/dish_ai_profile_models.dart';

const _allergenLabels = <String, String>{
  'PEANUT': '花生',
  'SEAFOOD': '海鲜甲壳',
  'GLUTEN': '麦麸面筋',
  'EGG': '蛋类',
  'SOY': '大豆',
};

const _standardSpiceOptions = ['不辣', '微辣', '中辣', '特辣'];

class DishAiProfilesPage extends StatefulWidget {
  const DishAiProfilesPage({
    super.key,
    required this.appState,
    required this.repository,
    this.initialShopId,
  });

  final AppState appState;
  final DishAiProfileRepository repository;
  final int? initialShopId;

  @override
  State<DishAiProfilesPage> createState() => _DishAiProfilesPageState();
}

class _DishAiProfilesPageState extends State<DishAiProfilesPage> {
  List<DishWithProfileVO> _dishes = [];
  bool _loading = false;
  String? _error;

  String _selectedCategory = 'ALL';
  String _configFilter = 'ALL'; // 'ALL', 'CONFIGURED', 'UNCONFIGURED'
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final Set<int> _selectedDishIds = {};

  int get _shopId =>
      widget.initialShopId ?? widget.appState.currentShopId ?? 1;

  String get _shopName =>
      widget.appState.currentShop?.name ?? '深圳宝安店';

  @override
  void initState() {
    super.initState();
    _loadDishes();
  }

  @override
  void didUpdateWidget(covariant DishAiProfilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      _loadDishes();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDishes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dishes = await widget.repository.fetchDishProfiles(
        storeId: _shopId,
      );
      if (mounted) {
        setState(() {
          _dishes = dishes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<String> get _categories {
    final set = <String>{};
    for (final d in _dishes) {
      final name = d.categoryName;
      if (name != null && name.trim().isNotEmpty) {
        set.add(name.trim());
      }
    }
    return ['ALL', ...set];
  }

  int get _configuredCount => _dishes.where((d) => d.hasProfile).length;
  int get _unconfiguredCount => _dishes.where((d) => !d.hasProfile).length;

  List<DishWithProfileVO> get _filteredDishes {
    return _dishes.where((dish) {
      if (_selectedCategory != 'ALL' && dish.categoryName != _selectedCategory) {
        return false;
      }
      if (_configFilter == 'CONFIGURED' && !dish.hasProfile) {
        return false;
      }
      if (_configFilter == 'UNCONFIGURED' && dish.hasProfile) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = dish.dishName.toLowerCase().contains(q);
        final matchId = dish.dishId.toString().contains(q);
        if (!matchName && !matchId) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _onAutoInit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6)),
            SizedBox(width: 8),
            Text('一键智能初始化画像'),
          ],
        ),
        content: const Text(
          '系统将分析全店所有未配置画像的菜品，根据菜品名称与类别特征自动估算风味、辣度与健康营养成分。\n\n是否立即开始智能初始化？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定开始'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final count = await widget.repository.autoInitDishProfiles(storeId: _shopId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ 智能初始化成功，已处理 $count 个菜品画像'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
      await _loadDishes();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('智能初始化失败: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _onEditDish(DishWithProfileVO dish) async {
    final updated = await showDialog<DishFoodProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DishAiProfileDrawerDialog(
        storeId: _shopId,
        dish: dish,
        repository: widget.repository,
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        final index = _dishes.indexWhere((d) => d.dishId == dish.dishId);
        if (index != -1) {
          _dishes[index] = _dishes[index].copyWith(
            hasProfile: true,
            profile: updated,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('菜品【${dish.dishName}】画像已成功保存'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _onBatchEdit() async {
    final targetDishes = _selectedDishIds.isEmpty
        ? _filteredDishes
        : _dishes.where((d) => _selectedDishIds.contains(d.dishId)).toList();

    if (targetDishes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可供批量编辑的菜品')),
      );
      return;
    }

    final result = await showDialog<DishFoodProfileInput>(
      context: context,
      builder: (ctx) => _BatchEditDialog(
        targetCount: targetDishes.length,
        storeId: _shopId,
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final inputs = targetDishes.map((d) {
        return DishFoodProfileInput(
          storeId: _shopId,
          dishId: d.dishId,
          nonSpicyAvailable: result.nonSpicyAvailable,
          spiceOptions: result.spiceOptions.isNotEmpty
              ? result.spiceOptions
              : (d.profile?.spiceOptions ?? const ['不辣']),
          verifiedAllergens: result.verifiedAllergens,
          isSuitableFitness: result.isSuitableFitness,
          caloriesKcal: result.caloriesKcal ?? d.profile?.caloriesKcal,
          proteinG: result.proteinG ?? d.profile?.proteinG,
          fatG: result.fatG ?? d.profile?.fatG,
          edibleWeightG: result.edibleWeightG ?? d.profile?.edibleWeightG,
        );
      }).toList();

      final count = await widget.repository.batchSaveDishProfiles(
        storeId: _shopId,
        inputs: inputs,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功批量更新 $count 个菜品的画像配置'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        setState(() => _selectedDishIds.clear());
      }
      await _loadDishes();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批量保存失败: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _onSaveAll() async {
    final configured = _dishes.where((d) => d.profile != null).toList();
    if (configured.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无需要全量提交的画像数据')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final inputs = configured.map((d) {
        final p = d.profile!;
        return DishFoodProfileInput(
          storeId: _shopId,
          dishId: d.dishId,
          nonSpicyAvailable: p.nonSpicyAvailable,
          spiceOptions: p.spiceOptions,
          verifiedAllergens: p.verifiedAllergens,
          isSuitableFitness: p.isSuitableFitness,
          caloriesKcal: p.caloriesKcal,
          proteinG: p.proteinG,
          fatG: p.fatG,
          edibleWeightG: p.edibleWeightG,
          ingredients: p.ingredients,
          seasonings: p.seasonings,
        );
      }).toList();

      final count = await widget.repository.batchSaveDishProfiles(
        storeId: _shopId,
        inputs: inputs,
      );

      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('全量画像保存成功，共保存 $count 个菜品'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('全量保存失败: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDishes;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1380),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 6,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBreadcrumbs(),
                _buildHeader(),
                _buildFilterBar(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
                          const SizedBox(height: 8),
                          Text('加载失败: $_error', style: const TextStyle(color: Color(0xFFEF4444))),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loadDishes,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        '未检索到符合条件的菜品画像数据',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ),
                  )
                else
                  _buildTable(filtered),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: const Row(
        children: [
          const Text('后台管理端', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const Text(' / ', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          const Text('商品菜单', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const Text(' / ', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          const Text(
            'AI 配餐画像维护',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF5A1F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '菜品 AI 配餐画像管理',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0EB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33FF5A1F)),
                ),
                child: Text(
                  _shopName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFF5A1F),
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                key: const ValueKey('btn-auto-init'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _loading ? null : _onAutoInit,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('一键智能初始化'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const ValueKey('btn-batch-edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F2937),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _loading ? null : _onBatchEdit,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: Text(
                  _selectedDishIds.isEmpty
                      ? '批量编辑'
                      : '批量编辑 (${_selectedDishIds.length})',
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const ValueKey('btn-save-all'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5A1F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _loading ? null : _onSaveAll,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('保存全部'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('分类: ', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  DropdownButton<String>(
                    key: const ValueKey('dropdown-category'),
                    value: _selectedCategory,
                    underline: const SizedBox(),
                    items: _categories.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c == 'ALL' ? '全部分类' : c, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('配置状态: ', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  DropdownButton<String>(
                    key: const ValueKey('dropdown-status'),
                    value: _configFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('全部状态', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'CONFIGURED', child: Text('已配置', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'UNCONFIGURED', child: Text('未配置', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _configFilter = val);
                    },
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      '已配置 $_configuredCount',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.circle_outlined, size: 8, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 4),
                    Text(
                      '未配置 $_unconfiguredCount',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              key: const ValueKey('input-search'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索菜品...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<DishWithProfileVO> dishes) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1000),
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 68,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
          horizontalMargin: 20,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('菜品名称', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('分类', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('单价', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('免辣能力', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('辣度选项', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('健身友好', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('卡路里', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('操作', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: dishes.map((dish) {
            final profile = dish.profile;
            final isSelected = _selectedDishIds.contains(dish.dishId);

            return DataRow(
              selected: isSelected,
              onSelectChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedDishIds.add(dish.dishId);
                  } else {
                    _selectedDishIds.remove(dish.dishId);
                  }
                });
              },
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: dish.imageUrl != null && dish.imageUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  dish.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.restaurant_menu,
                                    size: 20,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.restaurant_menu,
                                size: 20,
                                color: Color(0xFF9CA3AF),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dish.dishName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            'ID: ${dish.dishId}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dish.categoryName ?? '未分类',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '¥${dish.price.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                DataCell(
                  profile == null
                      ? const Text('未配置', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: profile.nonSpicyAvailable
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: profile.nonSpicyAvailable
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFFECACA),
                            ),
                          ),
                          child: Text(
                            profile.nonSpicyAvailable ? '可免辣' : '不可免辣',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: profile.nonSpicyAvailable
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                ),
                DataCell(
                  profile == null || profile.spiceOptions.isEmpty
                      ? const Text('未配置', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
                      : Wrap(
                          spacing: 4,
                          children: profile.spiceOptions.map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                DataCell(
                  profile == null
                      ? const Text('未配置', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
                      : profile.isSuitableFitness
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Text(
                                '★ 健身友好',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '普通',
                                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ),
                ),
                DataCell(
                  profile == null
                      ? const Text('未配置', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.caloriesKcal != null
                                  ? '${profile.caloriesKcal!.toStringAsFixed(0)} kcal'
                                  : '-- kcal',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            Text(
                              '蛋: ${profile.proteinG != null ? "${profile.proteinG}g" : "--"} / ${profile.edibleWeightG != null ? "${profile.edibleWeightG}g" : "--"}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                ),
                DataCell(
                  TextButton.icon(
                    key: ValueKey('btn-edit-${dish.dishId}'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5A1F),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: () => _onEditDish(dish),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('编辑', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class DishAiProfileDrawerDialog extends StatefulWidget {
  const DishAiProfileDrawerDialog({
    super.key,
    required this.storeId,
    required this.dish,
    required this.repository,
  });

  final int storeId;
  final DishWithProfileVO dish;
  final DishAiProfileRepository repository;

  @override
  State<DishAiProfileDrawerDialog> createState() => _DishAiProfileDrawerDialogState();
}

class _DishAiProfileDrawerDialogState extends State<DishAiProfileDrawerDialog> {
  late bool _nonSpicyAvailable;
  late Set<String> _selectedSpiceOptions;
  late Set<String> _selectedAllergens;
  late bool _isSuitableFitness;

  late TextEditingController _caloriesController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;
  late TextEditingController _edibleWeightController;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.dish.profile;
    _nonSpicyAvailable = p?.nonSpicyAvailable ?? true;
    _selectedSpiceOptions = Set<String>.from(p?.spiceOptions ?? const ['不辣']);
    _selectedAllergens = Set<String>.from(p?.verifiedAllergens ?? const []);
    _isSuitableFitness = p?.isSuitableFitness ?? false;

    _caloriesController = TextEditingController(
      text: p?.caloriesKcal != null ? p!.caloriesKcal!.toString() : '',
    );
    _proteinController = TextEditingController(
      text: p?.proteinG != null ? p!.proteinG!.toString() : '',
    );
    _fatController = TextEditingController(
      text: p?.fatG != null ? p!.fatG!.toString() : '',
    );
    _edibleWeightController = TextEditingController(
      text: p?.edibleWeightG != null ? p!.edibleWeightG!.toString() : '',
    );
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _edibleWeightController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final input = DishFoodProfileInput(
      storeId: widget.storeId,
      dishId: widget.dish.dishId,
      nonSpicyAvailable: _nonSpicyAvailable,
      spiceOptions: _selectedSpiceOptions.toList(),
      verifiedAllergens: _selectedAllergens.toList(),
      isSuitableFitness: _isSuitableFitness,
      caloriesKcal: double.tryParse(_caloriesController.text.trim()),
      proteinG: double.tryParse(_proteinController.text.trim()),
      fatG: double.tryParse(_fatController.text.trim()),
      edibleWeightG: double.tryParse(_edibleWeightController.text.trim()),
    );

    try {
      final saved = await widget.repository.saveDishProfile(
        storeId: widget.storeId,
        dishId: widget.dish.dishId,
        input: input,
      );
      if (mounted) {
        Navigator.pop(context, saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 580,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          children: [
            _buildDialogHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          '保存失败: $_error',
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                        ),
                      ),
                    _buildSectionSpice(),
                    const SizedBox(height: 16),
                    _buildSectionAllergens(),
                    const SizedBox(height: 16),
                    _buildSectionFitness(),
                    const SizedBox(height: 16),
                    _buildSectionNutrition(),
                  ],
                ),
              ),
            ),
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '菜品画像编辑 — ${widget.dish.dishName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${widget.dish.dishId} | 分类: ${widget.dish.categoryName ?? "未分类"} | 单价: ¥${widget.dish.price}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSpice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.whatshot, size: 18, color: Color(0xFFFF5A1F)),
              SizedBox(width: 6),
              Text(
                '风味与制作能力',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const ValueKey('switch-non-spicy'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '后厨是否支持免辣制作',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '指该菜品在后厨加工环节是否能做到完全不放辣',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            value: _nonSpicyAvailable,
            activeTrackColor: const Color(0xFFFF5A1F),
            onChanged: (val) => setState(() => _nonSpicyAvailable = val),
          ),
          if (!_nonSpicyAvailable)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '若关闭此项，AI 求解器在遇到不吃辣顾客时，绝对不会推荐该菜品！',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            '可用辣度选项 (多选)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: _standardSpiceOptions.map((opt) {
              final isChecked = _selectedSpiceOptions.contains(opt);
              return FilterChip(
                label: Text(opt),
                selected: isChecked,
                selectedColor: const Color(0xFFFFF0EB),
                checkmarkColor: const Color(0xFFFF5A1F),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: isChecked ? const Color(0xFFFF5A1F) : const Color(0xFF4B5563),
                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedSpiceOptions.add(opt);
                    } else {
                      _selectedSpiceOptions.remove(opt);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionAllergens() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                '核验过敏原',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '勾选该菜品中明确含有的过敏原成分（AI 求解器将基于忌口绝对过滤）',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allergenLabels.entries.map((entry) {
              final isSelected = _selectedAllergens.contains(entry.key);
              return FilterChip(
                label: Text('${entry.value} (${entry.key})'),
                selected: isSelected,
                selectedColor: const Color(0xFFFEF3C7),
                checkmarkColor: const Color(0xFF92400E),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: isSelected ? const Color(0xFF92400E) : const Color(0xFF4B5563),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedAllergens.add(entry.key);
                    } else {
                      _selectedAllergens.remove(entry.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionFitness() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SwitchListTile(
        key: const ValueKey('switch-fitness'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.fitness_center, size: 20, color: Color(0xFF3B82F6)),
        title: const Text(
          '健身控重优选',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          '适合减脂控重/高蛋白低脂人群（AI 将在健身偏好场景重点加权推荐）',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        value: _isSuitableFitness,
        activeTrackColor: const Color(0xFF10B981),
        onChanged: (val) => setState(() => _isSuitableFitness = val),
      ),
    );
  }

  Widget _buildSectionNutrition() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline, size: 18, color: Color(0xFF8B5CF6)),
              SizedBox(width: 6),
              Text(
                '营养成分卡片',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNutritionInput(
                  controller: _caloriesController,
                  label: '热量 (calories_kcal)',
                  unit: 'kcal',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNutritionInput(
                  controller: _proteinController,
                  label: '蛋白质 (protein_g)',
                  unit: 'g',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNutritionInput(
                  controller: _fatController,
                  label: '脂肪 (fat_g)',
                  unit: 'g',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNutritionInput(
                  controller: _edibleWeightController,
                  label: '可食部克重 (edible_weight_g)',
                  unit: 'g',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionInput({
    required TextEditingController controller,
    required String label,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(unit, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const ValueKey('btn-save-drawer'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A1F),
              foregroundColor: Colors.white,
            ),
            onPressed: _saving ? null : _onSave,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 16),
            label: const Text('保存画像'),
          ),
        ],
      ),
    );
  }
}

class _BatchEditDialog extends StatefulWidget {
  const _BatchEditDialog({
    required this.targetCount,
    required this.storeId,
  });

  final int targetCount;
  final int storeId;

  @override
  State<_BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends State<_BatchEditDialog> {
  bool _nonSpicyAvailable = true;
  final Set<String> _selectedSpiceOptions = {'不辣'};
  final Set<String> _selectedAllergens = {};
  bool _isSuitableFitness = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.playlist_add_check, color: Color(0xFFFF5A1F)),
          const SizedBox(width: 8),
          Text('批量编辑画像 (已选 ${widget.targetCount} 个菜品)'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                title: const Text('统一设置支持免辣制作', style: TextStyle(fontSize: 13)),
                value: _nonSpicyAvailable,
                activeTrackColor: const Color(0xFFFF5A1F),
                onChanged: (val) => setState(() => _nonSpicyAvailable = val),
              ),
              const Divider(),
              const Text('统一设置辣度选项:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: _standardSpiceOptions.map((opt) {
                  final isChecked = _selectedSpiceOptions.contains(opt);
                  return FilterChip(
                    label: Text(opt),
                    selected: isChecked,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedSpiceOptions.add(opt);
                        } else {
                          _selectedSpiceOptions.remove(opt);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('统一标记为健身友好', style: TextStyle(fontSize: 13)),
                value: _isSuitableFitness,
                activeTrackColor: const Color(0xFF10B981),
                onChanged: (val) => setState(() => _isSuitableFitness = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5A1F)),
          onPressed: () {
            Navigator.pop(
              context,
              DishFoodProfileInput(
                storeId: widget.storeId,
                dishId: 0,
                nonSpicyAvailable: _nonSpicyAvailable,
                spiceOptions: _selectedSpiceOptions.toList(),
                verifiedAllergens: _selectedAllergens.toList(),
                isSuitableFitness: _isSuitableFitness,
              ),
            );
          },
          child: const Text('应用到选定菜品'),
        ),
      ],
    );
  }
}
