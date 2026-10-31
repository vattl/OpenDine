import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 库存盘点（原型文档 §四.9）。
///
/// 原型阶段：本地样例库存，输入实盘数实时计算差异徽标与盘点进度；
/// 分类切换、差异提示、提交按钮禁用态均为纯 UI 演示。
class InventoryCountPage extends StatefulWidget {
  const InventoryCountPage({super.key});

  @override
  State<InventoryCountPage> createState() => _InventoryCountPageState();
}

class _StockItem {
  _StockItem({required this.name, required this.unit, required this.system});

  final String name;
  final String unit;
  final int system;
  final controller = TextEditingController();

  int? get actual => int.tryParse(controller.text);
}

class _InventoryCountPageState extends State<InventoryCountPage> {
  String _category = '肉类';

  final Map<String, List<_StockItem>> _data = {
    '肉类': [
      _StockItem(name: '羊肉卷', unit: '份', system: 23),
      _StockItem(name: '牛肉串', unit: '串', system: 120),
      _StockItem(name: '五花肉', unit: '份', system: 40),
      _StockItem(name: '鸡翅', unit: '只', system: 88),
    ],
    '海鲜': [
      _StockItem(name: '生蚝', unit: '只', system: 60),
      _StockItem(name: '鱿鱼', unit: '串', system: 45),
    ],
    '蔬菜': [
      _StockItem(name: '韭菜', unit: '把', system: 30),
      _StockItem(name: '玉米', unit: '根', system: 25),
      _StockItem(name: '茄子', unit: '个', system: 18),
    ],
    '酒水': [
      _StockItem(name: '啤酒', unit: '瓶', system: 240),
      _StockItem(name: '可乐', unit: '听', system: 96),
    ],
    '调料': [
      _StockItem(name: '孜然', unit: '袋', system: 12),
      _StockItem(name: '辣椒面', unit: '袋', system: 8),
    ],
  };

  int get _filledCount =>
      _data.values.expand((list) => list).where((i) => i.actual != null).length;
  int get _totalCount => _data.values.fold(0, (sum, list) => sum + list.length);

  @override
  void dispose() {
    for (final item in _data.values.expand((list) => list)) {
      item.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allFilled = _filledCount == _totalCount;
    return Scaffold(
      appBar: AppBar(title: const Text('库存盘点')),
      body: Column(
        children: [
          Padding(
            padding: MobileMetrics.pagePadding.copyWith(
              top: MobileMetrics.spaceLg,
            ),
            child: Card(
              child: Padding(
                padding: MobileMetrics.cardPaddingCompact,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '6月7日晚市盘点 · 盘点人：李师傅',
                        style: MobileTypography.body,
                      ),
                    ),
                    StatusTag(
                      allFilled ? '已完成' : '未完成',
                      tone: allFilled
                          ? SemanticTone.success
                          : SemanticTone.danger,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildCategoryChips(),
          Expanded(
            child: ListView.separated(
              padding: MobileMetrics.pagePadding.copyWith(
                top: MobileMetrics.spaceSm,
                bottom: MobileMetrics.spaceLg,
              ),
              itemCount: _data[_category]!.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: MobileMetrics.cardGap),
              itemBuilder: (_, index) =>
                  _StockRow(item: _data[_category]![index], onChanged: () => setState(() {})),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已盘 $_filledCount/$_totalCount 项',
                style: context.bodySecondaryStyle,
              ),
            ),
            Expanded(
              flex: 2,
              child: allFilled
                  ? FilledButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('盘点已提交（原型演示）')),
                        );
                      },
                      child: const Text('提交盘点'),
                    )
                  : const OutlinedButton(
                      onPressed: null,
                      child: Text('提交盘点'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: MobileMetrics.pagePadding.copyWith(
        top: MobileMetrics.spaceMd,
        bottom: MobileMetrics.spaceSm,
      ),
      child: Row(
        children: [
          for (final category in _data.keys) ...[
            ChoiceChip(
              selected: _category == category,
              onSelected: (_) => setState(() => _category = category),
              label: Text(category),
            ),
            const SizedBox(width: MobileMetrics.spaceSm),
          ],
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.item, required this.onChanged});

  final _StockItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final actual = item.actual;
    final diff = actual == null ? null : actual - item.system;
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPaddingCompact,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item.name}（${item.unit}）',
                      style: MobileTypography.itemTitle),
                  const SizedBox(height: MobileMetrics.spaceXs),
                  Text('系统库存 ${item.system}',
                      style: context.captionStyle),
                ],
              ),
            ),
            SizedBox(
              width: 88,
              child: TextField(
                controller: item.controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: MobileTypography.itemTitle.copyWith(
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  hintText: '实盘',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: MobileMetrics.spaceSm,
                    vertical: MobileMetrics.spaceSm,
                  ),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: MobileMetrics.spaceMd),
            SizedBox(
              width: 64,
              child: diff == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: diff == 0
                          ? const StatusTag('平', tone: SemanticTone.success)
                          : StatusTag(
                              '${diff > 0 ? '+' : ''}$diff',
                              tone: SemanticTone.danger,
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
