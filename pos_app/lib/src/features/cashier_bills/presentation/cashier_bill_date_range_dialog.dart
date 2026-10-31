import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../domain/cashier_bill.dart';

class CashierBillDateRangeResult {
  const CashierBillDateRangeResult({
    this.startTime,
    this.endTime,
    required this.preset,
  });

  final DateTime? startTime;
  final DateTime? endTime;
  final CashierDatePreset preset;

  bool get isDefault => startTime == null && endTime == null;
}

class CashierBillDateRangeDialog extends StatefulWidget {
  const CashierBillDateRangeDialog({
    super.key,
    required this.initialQuery,
    this.hasSuperPermission = false,
  });

  final CashierBillQuery initialQuery;
  final bool hasSuperPermission;

  @override
  State<CashierBillDateRangeDialog> createState() =>
      _CashierBillDateRangeDialogState();
}

class _CashierBillDateRangeDialogState
    extends State<CashierBillDateRangeDialog> {
  late CashierDatePreset _preset;
  DateTime? _start;
  DateTime? _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preset = widget.initialQuery.datePreset;
    _start = widget.initialQuery.startTime;
    _end = widget.initialQuery.endTime;
  }

  void _applyPreset(CashierDatePreset preset) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    setState(() {
      _preset = preset;
      _error = null;
      switch (preset) {
        case CashierDatePreset.today:
          _start = todayStart;
          _end = todayEnd;
          break;
        case CashierDatePreset.yesterday:
          final yesterday = todayStart.subtract(const Duration(days: 1));
          _start = DateTime(yesterday.year, yesterday.month, yesterday.day, 0, 0, 0);
          _end = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          break;
        case CashierDatePreset.last7Days:
          final startDay = todayStart.subtract(const Duration(days: 6));
          _start = DateTime(startDay.year, startDay.month, startDay.day, 0, 0, 0);
          _end = todayEnd;
          break;
        case CashierDatePreset.custom:
          break;
      }
    });
  }

  void _resetToDefault() {
    setState(() {
      _preset = CashierDatePreset.today;
      _start = null;
      _end = null;
      _error = null;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? (_start ?? DateTime.now()) : (_end ?? DateTime.now());
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: isStart ? '选择开始日期' : '选择结束日期',
    );
    if (pickedDate == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      isStart ? 0 : 23,
      isStart ? 0 : 59,
      isStart ? 0 : 59,
    );

    setState(() {
      _preset = CashierDatePreset.custom;
      _error = null;
      if (isStart) {
        _start = combined;
      } else {
        _end = combined;
      }
    });
  }

  void _confirm() {
    if (_start == null && _end == null) {
      // 默认最近3小时/未结账
      Navigator.of(context).pop(
        const CashierBillDateRangeResult(
          startTime: null,
          endTime: null,
          preset: CashierDatePreset.today,
        ),
      );
      return;
    }

    if (_start == null || _end == null) {
      setState(() => _error = '开始时间与结束时间必须成对设置');
      return;
    }

    if (_end!.isBefore(_start!)) {
      setState(() => _error = '结束时间不能早于开始时间');
      return;
    }

    if (_end!.difference(_start!).inDays > 31) {
      setState(() => _error = '自定义时间范围不能超过31天');
      return;
    }

    Navigator.of(context).pop(
      CashierBillDateRangeResult(
        startTime: _start,
        endTime: _end,
        preset: _preset,
      ),
    );
  }

  String _formatDisplayDate(DateTime? dt, String placeholder) {
    if (dt == null) return placeholder;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final isDefault = _start == null && _end == null;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                children: [
                  Icon(Icons.calendar_month, color: tokens.selected, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    '选择账单查询时间范围',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('btn-close-date-dialog'),
                    icon: Icon(Icons.close, color: tokens.inkSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 权限提示条（无超管权限时给出醒目提醒）
              if (!widget.hasSuperPermission) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.warningBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.warning, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: tokens.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '提示：按服务端规范，自定义时间跨度与历史账单查询需要超级管理员权限 (admin:super)。',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 快捷预设按钮组
              Text(
                '快捷时间预设',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.inkSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _PresetChip(
                    key: const Key('preset-default'),
                    label: '默认 (最近3小时/未结)',
                    selected: isDefault,
                    onTap: _resetToDefault,
                  ),
                  _PresetChip(
                    key: const Key('preset-today-full'),
                    label: '今日全天',
                    selected: !isDefault && _preset == CashierDatePreset.today,
                    onTap: () => _applyPreset(CashierDatePreset.today),
                  ),
                  _PresetChip(
                    key: const Key('preset-yesterday'),
                    label: '昨日全天',
                    selected: !isDefault && _preset == CashierDatePreset.yesterday,
                    onTap: () => _applyPreset(CashierDatePreset.yesterday),
                  ),
                  _PresetChip(
                    key: const Key('preset-last-7-days'),
                    label: '近 7 天',
                    selected: !isDefault && _preset == CashierDatePreset.last7Days,
                    onTap: () => _applyPreset(CashierDatePreset.last7Days),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 自定义起止日期选择
              Text(
                '自定义日期范围（最多 31 天）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.inkSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 开始日期
                  Expanded(
                    child: _DateTimePickerBox(
                      key: const Key('picker-start-time'),
                      label: '开始日期',
                      value: _formatDisplayDate(_start, '请选择开始日期'),
                      isSet: _start != null,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('至', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  // 结束日期
                  Expanded(
                    child: _DateTimePickerBox(
                      key: const Key('picker-end-time'),
                      label: '结束日期',
                      value: _formatDisplayDate(_end, '请选择结束日期'),
                      isSet: _end != null,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 错误消息展示
              if (_error != null) ...[
                Container(
                  key: const Key('date-range-error-banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: tokens.dangerBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.danger),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: tokens.danger, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.danger,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              // 底部操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('btn-reset-default'),
                    onPressed: _resetToDefault,
                    child: Text(
                      '恢复默认时间',
                      style: TextStyle(color: tokens.inkSecondary),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    key: const Key('btn-cancel-date-dialog'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: tokens.border),
                    ),
                    child: Text('取消', style: TextStyle(color: tokens.ink)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    key: const Key('btn-confirm-date-dialog'),
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.focus,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('确定查询', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.selectedBackground : tokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? tokens.selected : tokens.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? tokens.selected : tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _DateTimePickerBox extends StatelessWidget {
  const _DateTimePickerBox({
    super.key,
    required this.label,
    required this.value,
    required this.isSet,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSet ? tokens.selected : tokens.border,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                      color: isSet ? tokens.ink : tokens.inkMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: isSet ? tokens.selected : tokens.inkSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
