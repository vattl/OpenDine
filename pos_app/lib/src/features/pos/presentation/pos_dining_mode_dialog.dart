import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../tables/data/table_repository.dart';
import '../../tables/domain/dining_table.dart';

enum PosDiningMode {
  takeout,
  dineIn,
}

/// 弹出就餐方式选择弹窗（打包自提 / 堂食就餐）
Future<PosDiningMode?> showPosDiningModeDialog(BuildContext context) {
  return showDialog<PosDiningMode>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final cashier = ctx.cashier;
      return Dialog(
        key: const Key('dining-mode-dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cashier.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Container(
          width: 520,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.room_service_outlined,
                      color: Color(0xFF2563EB),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择就餐方式',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cashier.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '当前订单尚未指定桌台，请选择就餐方式继续下单',
                          style: TextStyle(
                            fontSize: 13,
                            color: cashier.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('dining-mode-close-button'),
                    icon: Icon(Icons.close_rounded, color: cashier.inkMuted),
                    onPressed: () => Navigator.of(ctx).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _DiningModeOptionCard(
                      key: const Key('dining-mode-takeout'),
                      icon: Icons.takeout_dining_rounded,
                      title: '打包自提',
                      subtitle: '外带打包 · 生成取餐号',
                      badge: '外带',
                      color: const Color(0xFFD97706),
                      bgColor: const Color(0xFFFEF3C7),
                      onTap: () => Navigator.of(ctx).pop(PosDiningMode.takeout),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DiningModeOptionCard(
                      key: const Key('dining-mode-dinein'),
                      icon: Icons.restaurant_rounded,
                      title: '堂食就餐',
                      subtitle: '店内就餐 · 选桌台开台',
                      badge: '堂食',
                      color: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFDBEAFE),
                      onTap: () => Navigator.of(ctx).pop(PosDiningMode.dineIn),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('dining-mode-cancel-button'),
                  onPressed: () => Navigator.of(ctx).pop(null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    foregroundColor: cashier.inkSecondary,
                  ),
                  child: const Text('返回购物车', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DiningModeOptionCard extends StatefulWidget {
  const _DiningModeOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  State<_DiningModeOptionCard> createState() => _DiningModeOptionCardState();
}

class _DiningModeOptionCardState extends State<_DiningModeOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cashier = context.cashier;
    return InkWell(
      onTap: widget.onTap,
      onHover: (hovered) => setState(() => _hovered = hovered),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 144,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.bgColor.withValues(alpha: 0.75)
              : widget.bgColor.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? widget.color : widget.color.withValues(alpha: 0.32),
            width: _hovered ? 2 : 1.5,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 28),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cashier.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cashier.inkSecondary,
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

/// 弹出堂食桌台网格选择弹窗
Future<DiningTable?> showPosTableSelectionGridDialog(
  BuildContext context, {
  TableRepository? repository,
  List<DiningTable>? fallbackTables,
}) {
  return showDialog<DiningTable>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _TableSelectionGridDialog(
      repository: repository,
      fallbackTables: fallbackTables,
    ),
  );
}

class _TableSelectionGridDialog extends StatefulWidget {
  const _TableSelectionGridDialog({
    this.repository,
    this.fallbackTables,
  });

  final TableRepository? repository;
  final List<DiningTable>? fallbackTables;

  @override
  State<_TableSelectionGridDialog> createState() =>
      _TableSelectionGridDialogState();
}

class _TableSelectionGridDialogState extends State<_TableSelectionGridDialog> {
  List<DiningTable> _tables = const [];
  bool _loading = true;
  String? _error;
  String _selectedArea = '全部';
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    if (widget.repository == null) {
      setState(() {
        _tables = widget.fallbackTables ?? const [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await widget.repository!.loadTableOverview();
      if (!mounted) return;
      setState(() {
        _tables = overview.tables;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<String> get _areas {
    final areas = <String>{'全部'};
    for (final table in _tables) {
      final area = table.areaName.trim();
      if (area.isNotEmpty) {
        areas.add(area);
      }
    }
    return areas.toList(growable: false);
  }

  List<DiningTable> get _filteredTables {
    return _tables.where((table) {
      if (_selectedArea != '全部' && table.areaName.trim() != _selectedArea) {
        return false;
      }
      if (_searchKeyword.isNotEmpty) {
        final num = table.number.toLowerCase();
        final kw = _searchKeyword.toLowerCase();
        if (!num.contains(kw)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _onTableTapped(DiningTable table) async {
    if (table.status == TableStatus.empty) {
      Navigator.of(context).pop(table);
      return;
    }

    if (table.status == TableStatus.pending) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('桌台就餐中提示', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            '桌台 ${table.number} 当前处于就餐中状态（已开单 ¥${table.amount ?? 0}）。\n\n确认将本次菜品追加下单到该桌台吗？',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认加菜到该桌'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        Navigator.of(context).pop(table);
      }
      return;
    }

    if (table.status == TableStatus.settled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('桌台已结账', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            '桌台 ${table.number} 处于已结账待清台状态。请先在桌台大盘完成清台后再重新开单。',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.cashier;
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width * 0.9).clamp(640.0, 920.0);
    final dialogHeight = (size.height * 0.85).clamp(480.0, 680.0);

    final emptyCount = _tables.where((t) => t.status == TableStatus.empty).length;

    return Dialog(
      key: const Key('table-selection-grid-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: cashier.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏：标题、桌况统计与关闭按钮
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    color: Color(0xFF2563EB),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择堂食桌台',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cashier.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击网格中的桌台完成绑定（空闲桌台将自动开台并提交该订单）',
                        style: TextStyle(
                          fontSize: 13,
                          color: cashier.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 统计徽章
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '空闲 $emptyCount / 共 ${_tables.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('table-grid-close-button'),
                  icon: Icon(Icons.close_rounded, color: cashier.inkMuted),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 区域标签与搜索框
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _areas.map((area) {
                        final isSelected = area == _selectedArea;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: Key('table-area-chip-$area'),
                            label: Text(area),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _selectedArea = area),
                            selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFF2563EB) : cashier.inkSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : cashier.border.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  height: 36,
                  child: TextField(
                    key: const Key('table-grid-search-input'),
                    decoration: InputDecoration(
                      hintText: '搜索桌号...',
                      hintStyle: TextStyle(fontSize: 13, color: cashier.inkMuted),
                      prefixIcon: Icon(Icons.search, size: 18, color: cashier.inkMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cashier.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cashier.border),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchKeyword = val.trim()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 网格内容区
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('加载桌台列表失败：$_error', style: TextStyle(color: cashier.danger)),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _loadTables,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : _filteredTables.isEmpty
                          ? Center(
                              child: Text(
                                '未找到符合条件的桌台',
                                style: TextStyle(fontSize: 14, color: cashier.inkSecondary),
                              ),
                            )
                          : GridView.builder(
                              key: const Key('table-grid-view'),
                              padding: const EdgeInsets.only(bottom: 12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: dialogWidth > 760 ? 5 : 4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.25,
                              ),
                              itemCount: _filteredTables.length,
                              itemBuilder: (ctx, index) {
                                final table = _filteredTables[index];
                                return _TableGridCard(
                                  table: table,
                                  onTap: () => _onTableTapped(table),
                                );
                              },
                            ),
            ),

            const SizedBox(height: 10),
            // 底栏提示与取消按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildLegendDot(const Color(0xFF16A34A), '空闲 (可选)'),
                    const SizedBox(width: 16),
                    _buildLegendDot(const Color(0xFF2563EB), '就餐中'),
                    const SizedBox(width: 16),
                    _buildLegendDot(const Color(0xFF9333EA), '已结账'),
                  ],
                ),
                TextButton(
                  key: const Key('table-grid-cancel-button'),
                  onPressed: () => Navigator.of(context).pop(null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    foregroundColor: cashier.inkSecondary,
                  ),
                  child: const Text('取消返回', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.cashier.inkSecondary),
        ),
      ],
    );
  }
}

class _TableGridCard extends StatefulWidget {
  const _TableGridCard({
    required this.table,
    required this.onTap,
  });

  final DiningTable table;
  final VoidCallback onTap;

  @override
  State<_TableGridCard> createState() => _TableGridCardState();
}

class _TableGridCardState extends State<_TableGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cashier = context.cashier;
    final table = widget.table;
    final isEmpty = table.status == TableStatus.empty;
    final isPending = table.status == TableStatus.pending;

    final themeColor = isEmpty
        ? const Color(0xFF16A34A)
        : (isPending ? const Color(0xFF2563EB) : const Color(0xFF9333EA));

    final bgColor = isEmpty
        ? const Color(0xFFF0FDF4)
        : (isPending ? const Color(0xFFEFF6FF) : const Color(0xFFFAF5FF));

    final statusText = isEmpty
        ? '空闲'
        : (isPending
            ? '就餐中'
            : '已结账');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('table-grid-item-${table.number}'),
        onTap: widget.onTap,
        onHover: (hovered) => setState(() => _hovered = hovered),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _hovered ? bgColor.withValues(alpha: 0.9) : bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? themeColor : themeColor.withValues(alpha: 0.35),
              width: _hovered ? 2 : 1.2,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      table.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cashier.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    table.areaName.isNotEmpty ? table.areaName : '大厅',
                    style: TextStyle(
                      fontSize: 12,
                      color: cashier.inkSecondary,
                    ),
                  ),
                  Text(
                    '${table.people > 0 ? table.people : 4}人桌',
                    style: TextStyle(
                      fontSize: 12,
                      color: cashier.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
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
