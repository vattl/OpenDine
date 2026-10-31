import 'package:flutter/material.dart';

import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 员工排班（原型文档 §四.10）。
///
/// 原型阶段：本地样例排班表；单字班次胶囊（早/晚/休）保证 7 列在手机上不拥挤，
/// 图例行解释含义；周切换与新建排班为占位交互。
class StaffSchedulePage extends StatelessWidget {
  const StaffSchedulePage({super.key});

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 今天列（周四）。
  static const _todayIndex = 3;

  static const _employees = <(String, List<String>)>[
    ('王姐', ['早', '早', '休', '早', '早', '休', '早']),
    ('李师傅', ['晚', '晚', '晚', '休', '晚', '晚', '晚']),
    ('小张', ['早', '休', '晚', '晚', '休', '早', '晚']),
    ('赵阿姨', ['晚', '晚', '休', '早', '早', '晚', '休']),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('员工排班'),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('本周'),
          ),
        ],
      ),
      body: ListView(
        padding: MobileMetrics.pagePadding.copyWith(
          top: MobileMetrics.spaceLg,
          bottom: MobileMetrics.spaceLg,
        ),
        children: [
          Card(
            child: Padding(
              padding: MobileMetrics.cardPaddingCompact,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一周',
                    onPressed: () => _todo(context),
                  ),
                  const Text('6月2日 – 6月8日',
                      style: MobileTypography.sectionTitle),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一周',
                    onPressed: () => _todo(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          Card(
            child: Padding(
              padding: MobileMetrics.cardPaddingCompact,
              child: Column(
                children: [
                  _buildHeaderRow(context),
                  const Divider(height: MobileMetrics.spaceMd),
                  for (final (name, shifts) in _employees) ...[
                    _EmployeeRow(name: name, shifts: shifts),
                    if ((name, shifts) != _employees.last)
                      const Divider(height: MobileMetrics.spaceSm),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          const Card(
            child: Padding(
              padding: MobileMetrics.cardPaddingCompact,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LegendItem(text: '早', label: '早班 9:00–17:00'),
                  _LegendItem(text: '晚', label: '晚班 16:00–24:00'),
                  _LegendItem(text: '休', label: '休息'),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: () => _todo(context),
          child: const Text('新建排班'),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 64),
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.spaceXs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: i == _todayIndex
                      ? context.palette.brandSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(MobileMetrics.radiusPill),
                ),
                child: Text(
                  _weekdays[i],
                  style: context.captionStyle.copyWith(
                    color: i == _todayIndex
                        ? context.palette.brandInk
                        : context.palette.textMuted,
                    fontWeight:
                        i == _todayIndex ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _todo(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('原型演示：排班编辑待后端接口定稿')));
  }
}

/// 晚班胶囊：品牌橙浅底 + 加深橙文字（复用品牌色而非语义色）。
/// 与状态徽标一致，自包含浅底深字小标签在暗色卡片上同样清晰，不做暗色变体。
const _eveningTone = SemanticTone(MobileColors.brandInk, MobileColors.brandSoft);

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.name, required this.shifts});

  final String name;
  final List<String> shifts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MobileMetrics.spaceXs),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: context.palette.brandSoft,
                  child: Text(
                    name.characters.first,
                    style: context.captionStyle.copyWith(
                      color: context.palette.brandInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  name,
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          for (final shift in shifts)
            Expanded(
              child: Center(child: _ShiftCapsule(shift: shift)),
            ),
        ],
      ),
    );
  }
}

class _ShiftCapsule extends StatelessWidget {
  const _ShiftCapsule({required this.shift});

  final String shift;

  @override
  Widget build(BuildContext context) {
    final tone = switch (shift) {
      '早' => SemanticTone.success,
      '晚' => _eveningTone,
      _ => SemanticTone.neutral,
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(MobileMetrics.radiusControl),
      ),
      child: Center(
        child: Text(
          shift,
          style: context.captionStyle.copyWith(
            color: tone.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShiftCapsule(shift: text),
        const SizedBox(width: MobileMetrics.spaceXs),
        Text(label, style: context.captionStyle),
      ],
    );
  }
}
