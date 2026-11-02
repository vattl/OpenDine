import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/data/access_approval_repository.dart';
import '../../cashier_shell/presentation/cashier_approval_dialog.dart';
import '../../cashier_shell/presentation/cashier_design_tokens.dart';
import '../data/cashier_member_repository.dart';
import '../domain/cashier_member.dart';
import 'member_consumption_order_detail_dialog.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class MemberConsumptionDialog extends StatefulWidget {
  const MemberConsumptionDialog({
    super.key,
    required this.phone,
    required this.repository,
    this.approvalRepository,
    this.permissions = const {},
    this.currentAccount,
    this.isSuperAdmin = false,
  });

  final String phone;
  final CashierMemberRepository repository;
  final AccessApprovalRepository? approvalRepository;
  final Set<String> permissions;
  final String? currentAccount;
  final bool isSuperAdmin;

  @override
  State<MemberConsumptionDialog> createState() =>
      _MemberConsumptionDialogState();
}

class _MemberConsumptionDialogState extends State<MemberConsumptionDialog> {
  late Future<List<MemberConsumptionRecord>> records;
  bool _isPhoneUnmasked = false;

  @override
  void initState() {
    super.initState();
    records = widget.repository.loadConsumption(widget.phone);
  }

  void _retry() {
    setState(() {
      records = widget.repository.loadConsumption(widget.phone);
    });
  }

  Future<void> _togglePhoneMask() async {
    final cleanPhone = widget.phone.trim();
    if (cleanPhone.isEmpty) return;

    if (_isPhoneUnmasked) {
      setState(() {
        _isPhoneUnmasked = false;
      });
      return;
    }

    final canViewPrivacy = widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (canViewPrivacy || widget.approvalRepository == null) {
      setState(() {
        _isPhoneUnmasked = true;
      });
      return;
    }

    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '查看会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '查看会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: cleanPhone,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository!,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _isPhoneUnmasked = true;
      });
    }
  }

  Future<void> _copyPhone() async {
    final cleanPhone = widget.phone.trim();
    if (cleanPhone.isEmpty) return;

    final canViewPrivacy = _isPhoneUnmasked ||
        widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (canViewPrivacy || widget.approvalRepository == null) {
      await Clipboard.setData(ClipboardData(text: cleanPhone));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('手机号已复制到剪贴板')),
      );
      return;
    }

    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '复制会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '复制会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: cleanPhone,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository!,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _isPhoneUnmasked = true;
      });
      await Clipboard.setData(ClipboardData(text: cleanPhone));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('授权通过，手机号已复制到剪贴板')),
      );
    }
  }

  Future<void> _openDetail(MemberConsumptionRecord record) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x66000000),
      builder: (_) => MemberConsumptionOrderDetailDialog(
        record: record,
        repository: widget.repository,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(980.0, viewport.width - 48);
    final height = math.min(640.0, viewport.height - 48);
    return Dialog(
      key: const Key('member-consumption-dialog'),
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _DialogHeader(onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: FutureBuilder<List<MemberConsumptionRecord>>(
                future: records,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingState();
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(onRetry: _retry);
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const _EmptyState();
                  }
                  return _ConsumptionBody(
                    phone: widget.phone,
                    records: items,
                    isPhoneUnmasked: _isPhoneUnmasked,
                    onTogglePhoneMask: _togglePhoneMask,
                    onCopyPhone: _copyPhone,
                    onSelect: _openDetail,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: context.cashier.ink,
      padding: const EdgeInsets.only(left: 24, right: 8),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '会员消费记录',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            key: const Key('member-consumption-close'),
            tooltip: '关闭消费记录',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }
}

class _ConsumptionBody extends StatelessWidget {
  const _ConsumptionBody({
    required this.phone,
    required this.records,
    this.isPhoneUnmasked = false,
    this.onTogglePhoneMask,
    this.onCopyPhone,
    required this.onSelect,
  });

  final String phone;
  final List<MemberConsumptionRecord> records;
  final bool isPhoneUnmasked;
  final VoidCallback? onTogglePhoneMask;
  final VoidCallback? onCopyPhone;
  final ValueChanged<MemberConsumptionRecord> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = records.fold<double>(0, (sum, item) => sum + item.amount);
    final latest = records.first.paidAt.isEmpty ? '--' : records.first.paidAt;
    final cleanPhone = phone.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        children: [
          _SummaryBar(
            cells: [
              _SummaryCell(
                label: '累计消费',
                value: _money(total),
                emphasize: true,
              ),
              _SummaryCell(label: '消费次数', value: '${records.length} 次'),
              _SummaryCell(label: '最近消费', value: latest),
              _SummaryCell(
                label: '会员手机号',
                valueWidget: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isPhoneUnmasked ? cleanPhone : _maskedPhone(cleanPhone),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isPhoneUnmasked ? FontWeight.w700 : FontWeight.w600,
                          color: isPhoneUnmasked
                              ? const Color(0xFF38BDF8)
                              : context.cashier.ink,
                        ),
                      ),
                      if (cleanPhone.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: isPhoneUnmasked
                              ? '隐藏完整手机号'
                              : '查看完整手机号 (需权限)',
                          child: InkWell(
                            key: const Key('consumption-toggle-phone-mask-btn'),
                            borderRadius: BorderRadius.circular(4),
                            onTap: onTogglePhoneMask,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                isPhoneUnmasked
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 16,
                                color: isPhoneUnmasked
                                    ? const Color(0xFF38BDF8)
                                    : context.cashier.inkMuted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Tooltip(
                          message: '复制手机号',
                          child: InkWell(
                            key: const Key('consumption-copy-phone-btn'),
                            borderRadius: BorderRadius.circular(4),
                            onTap: onCopyPhone,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 16,
                                color: isPhoneUnmasked
                                    ? const Color(0xFF38BDF8)
                                    : context.cashier.inkMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _HistoryHeader(),
          Expanded(
            child: ListView.builder(
              key: const Key('member-consumption-list'),
              itemCount: records.length,
              itemBuilder: (context, index) => _HistoryRow(
                record: records[index],
                shaded: index.isOdd,
                onTap: () => onSelect(records[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 会员摘要条：4 指标等宽网格（可复算指标，不依赖画像接口）。
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.cells});

  final List<_SummaryCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.cashier.canvas,
        borderRadius: BorderRadius.circular(CashierMetrics.controlRadius),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    this.value = '',
    this.valueWidget,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.cashier.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          valueWidget ??
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color:
                      emphasize ? context.cashier.danger : context.cashier.ink,
                ),
              ),
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.cashier.inkMuted,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: 48,
      color: context.cashier.row,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _HistoryCell(flex: 5, child: Text('消费时间', style: style)),
          _HistoryCell(flex: 6, child: Text('订单编号', style: style)),
          _HistoryCell(flex: 2, child: Text('桌号', style: style)),
          _HistoryCell(flex: 3, child: Text('支付方式', style: style)),
          _HistoryCell(flex: 3, child: Text('实付金额', style: style)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.record,
    required this.shaded,
    required this.onTap,
  });

  final MemberConsumptionRecord record;
  final bool shaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.cashier.ink, fontSize: 14);
    return Material(
      color: shaded ? context.cashier.row : Colors.white,
      child: InkWell(
        key: Key('member-consumption-row-${record.id}'),
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: const Color(0x14075985),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              _HistoryCell(
                flex: 5,
                child: Text(
                  record.paidAt.isEmpty ? '--' : record.paidAt,
                  style: style,
                ),
              ),
              _HistoryCell(
                flex: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        record.orderNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style.copyWith(
                          color: context.cashier.selected,
                          decoration: TextDecoration.underline,
                          decorationColor: context.cashier.selected,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: context.cashier.selected,
                    ),
                  ],
                ),
              ),
              _HistoryCell(
                flex: 2,
                child: Text(
                  record.tableNumber.isEmpty ? '--' : record.tableNumber,
                  style: style,
                ),
              ),
              _HistoryCell(
                flex: 3,
                child: Text(_paymentLabel(record.paymentMethod), style: style),
              ),
              _HistoryCell(
                flex: 3,
                child: Text(
                  '¥${record.amount.toStringAsFixed(2)}',
                  style: style.copyWith(
                    color: context.cashier.danger,
                    fontWeight: FontWeight.w700,
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

class _HistoryCell extends StatelessWidget {
  const _HistoryCell({required this.flex, required this.child});

  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Center(child: child),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: context.cashier.selected),
          const SizedBox(height: 16),
          const Text('正在加载消费记录…', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: context.cashier.inkMuted,
          ),
          const SizedBox(height: 14),
          Text(
            '暂无消费记录',
            style: TextStyle(fontSize: 16, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: context.cashier.danger,
          ),
          const SizedBox(height: 14),
          const Text('消费记录加载失败', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 18),
          SizedBox(
            width: 150,
            height: 48,
            child: FilledButton(
              key: const Key('member-consumption-retry'),
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: context.cashier.ink),
              child: const Text('重新加载', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(double amount) => '¥${amount.toStringAsFixed(2)}';

String _maskedPhone(String phone) {
  final normalized = phone.trim();
  if (normalized.length < 7) return normalized;
  return '${normalized.substring(0, 3)}****'
      '${normalized.substring(normalized.length - 4)}';
}

String _paymentLabel(String value) {
  return switch (value.trim().toLowerCase()) {
    'wechat' => '微信支付',
    'alipay' => '支付宝',
    'cash' => '现金支付',
    'balance' => '会员余额',
    '' => '--',
    _ => value,
  };
}
