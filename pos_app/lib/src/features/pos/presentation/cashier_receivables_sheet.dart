import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

/// 收银端应收单与还款管理抽屉/对话框 (WI-047 / UI047 / v1.2.298)
class CashierReceivablesSheet extends StatefulWidget {
  const CashierReceivablesSheet({
    super.key,
    required this.repository,
    this.drawerSessionId,
    this.operatorName = '',
  });

  final PosReceivableRepository repository;
  final int? drawerSessionId;
  final String operatorName;

  @override
  State<CashierReceivablesSheet> createState() => _CashierReceivablesSheetState();
}

class _CashierReceivablesSheetState extends State<CashierReceivablesSheet> {
  bool _loading = true;
  String? _error;
  List<PosReceivableClaim> _claims = [];
  String _selectedStatus = 'OPEN'; // OPEN, PARTIAL, ALL

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusParam = _selectedStatus == 'ALL' ? null : _selectedStatus;
      final list = await widget.repository.loadReceivableClaims(status: statusParam);
      if (!mounted) return;
      setState(() {
        _claims = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is CashierReceivableException ? e.message : e.toString();
      });
    }
  }

  void _openCollectDialog(PosReceivableClaim claim) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReceivableCollectModal(
        claim: claim,
        drawerSessionId: widget.drawerSessionId,
        collectReceivable: widget.repository.collectReceivable,
      ),
    ).then((collected) {
      if (collected == true) {
        _loadClaims();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? context.cashier.surface : Colors.white;
    final border = isDark ? context.cashier.border : const Color(0xffe2e8f0);
    final textInk = isDark ? context.cashier.ink : const Color(0xff0f172a);
    final textMuted = isDark ? context.cashier.inkMuted : const Color(0xff64748b);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 860,
          constraints: const BoxConstraints(maxHeight: 720),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '门店客户应收账款与回款',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: textInk,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xffdcfce7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xffbbf7d0)),
                        ),
                        child: Text(
                          widget.drawerSessionId != null
                              ? '钱箱会话 #${widget.drawerSessionId} (${widget.operatorName})'
                              : '无活跃钱箱',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff15803d),
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Filter Tabs
              Row(
                children: [
                  _buildTab('待收款 (OPEN)', 'OPEN'),
                  const SizedBox(width: 8),
                  _buildTab('部分还款 (PARTIAL)', 'PARTIAL'),
                  const SizedBox(width: 8),
                  _buildTab('全部应收', 'ALL'),
                  const Spacer(),
                  IconButton(
                    onPressed: _loadClaims,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: '刷新',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Claims list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: const TextStyle(color: Color(0xffef4444))),
                                const SizedBox(height: 8),
                                OutlinedButton(onPressed: _loadClaims, child: const Text('重试')),
                              ],
                            ),
                          )
                        : _claims.isEmpty
                            ? Center(
                                child: Text('当前状态下暂无应收单据', style: TextStyle(color: textMuted)),
                              )
                            : ListView.separated(
                                itemCount: _claims.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: border.withValues(alpha: 0.5)),
                                itemBuilder: (context, index) {
                                  final claim = _claims[index];
                                  final isUnsettled = claim.isUnsettled;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    claim.customerName.isNotEmpty
                                                        ? claim.customerName
                                                        : '授信账户 #${claim.accountId}',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w700,
                                                      color: textInk,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _buildStatusBadge(claim.status),
                                                  if (claim.isOverdue) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xfffee2e2),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '逾期 ${claim.overdueDays} 天',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(0xffb91c1c),
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '单号: ${claim.claimNo} · 订单号: ${claim.orderNo} · 到期日: ${claim.dueDate.isNotEmpty ? claim.dueDate : '无'}',
                                                style: TextStyle(fontSize: 12, color: textMuted),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '未清: ¥ ${claim.outstandingYuan.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xff0284c7),
                                                ),
                                              ),
                                              Text(
                                                '挂账 ¥${claim.originalAmountYuan.toStringAsFixed(2)} · 已回 ¥${claim.collectedAmountYuan.toStringAsFixed(2)}',
                                                style: TextStyle(fontSize: 11, color: textMuted),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        ElevatedButton(
                                          onPressed: isUnsettled ? () => _openCollectDialog(claim) : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xff0284c7),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text('登记还款'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, String value) {
    final active = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        setState(() => _selectedStatus = value);
        _loadClaims();
      },
      selectedColor: const Color(0xff0284c7),
      labelStyle: TextStyle(
        color: active ? Colors.white : null,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final (bg, fg, label) = switch (status.toUpperCase()) {
      'OPEN' => (const Color(0xfffef3c7), const Color(0xffb45309), '待还款'),
      'PARTIAL' => (const Color(0xffe0f2fe), const Color(0xff0369a1), '部分还款'),
      'COLLECTED' => (const Color(0xffdcfce7), const Color(0xff15803d), '已结清'),
      'WRITTEN_OFF' => (const Color(0xfff1f5f9), const Color(0xff64748b), '坏账核销'),
      'CANCELLED' => (const Color(0xfffee2e2), const Color(0xffb91c1c), '已撤销'),
      _ => (const Color(0xfff1f5f9), const Color(0xff64748b), status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// 还款模态对话框
class _ReceivableCollectModal extends StatefulWidget {
  const _ReceivableCollectModal({
    required this.claim,
    this.drawerSessionId,
    required this.collectReceivable,
  });

  final PosReceivableClaim claim;
  final int? drawerSessionId;
  final Future<PosReceivableLedger> Function({
    required int claimId,
    required int amountFen,
    required String channel,
    required String requestId,
    String? note,
    int? drawerSessionId,
  }) collectReceivable;

  @override
  State<_ReceivableCollectModal> createState() => _ReceivableCollectModalState();
}

class _ReceivableCollectModalState extends State<_ReceivableCollectModal> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  String _selectedChannel = 'CASH';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.claim.outstandingYuan.toStringAsFixed(2));
    _noteController = TextEditingController();
    // 无钱箱时默认选择非现金
    if (widget.drawerSessionId == null) {
      _selectedChannel = 'BANK_TRANSFER';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    final amountYuan = double.tryParse(amountText);
    if (amountYuan == null || amountYuan <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合法的回款金额')),
      );
      return;
    }

    if (amountYuan > (widget.claim.outstandingYuan + 0.0001)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回款金额不能超过未清余额 ¥${widget.claim.outstandingYuan.toStringAsFixed(2)}')),
      );
      return;
    }

    if (_selectedChannel == 'CASH' && widget.drawerSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前无开启中的钱箱会话，禁止收取现金回款！请开班或选择银行转账/线上渠道。')),
      );
      return;
    }

    setState(() => _submitting = true);
    final amountFen = (amountYuan * 100).round();
    final requestId = 'POS-COLLECT-${DateTime.now().millisecondsSinceEpoch}-${widget.claim.id}';

    try {
      await widget.collectReceivable(
        claimId: widget.claim.id,
        amountFen: amountFen,
        channel: _selectedChannel,
        requestId: requestId,
        note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
        drawerSessionId: _selectedChannel == 'CASH' ? widget.drawerSessionId : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('登记回款成功！已记录资金流水。'),
          backgroundColor: Color(0xff15803d),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e is CashierReceivableException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登记回款失败：$msg'), backgroundColor: const Color(0xffef4444)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '登记客户还款',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff0f172a)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xffe2e8f0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('客户：${widget.claim.customerName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('应收单：${widget.claim.claimNo} · 未清余额：¥ ${widget.claim.outstandingYuan.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xff0284c7), fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '本次还款金额 (元)',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedChannel,
                decoration: InputDecoration(
                  labelText: '回款支付渠道',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('现金收款 (入账钱箱)')),
                  DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('银行公对公转账')),
                  DropdownMenuItem(value: 'WECHAT', child: Text('微信商业收款')),
                  DropdownMenuItem(value: 'ALIPAY', child: Text('支付宝商业收款')),
                  DropdownMenuItem(value: 'OTHER', child: Text('其他方式')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedChannel = val);
                },
              ),
              const SizedBox(height: 12),
              if (_selectedChannel == 'CASH')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.drawerSessionId != null ? const Color(0xffdcfce7) : const Color(0xfffee2e2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.drawerSessionId != null
                        ? '✓ 现金回款将实时增加本班钱箱现金结余，自动纳入交班对账。'
                        : '⚠ 警告：当前未绑定活跃钱箱会话，禁止收取现金！',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.drawerSessionId != null ? const Color(0xff15803d) : const Color(0xffb91c1c),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '还款备注（可选）',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0284c7),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_submitting ? '提交中...' : '确认还款'),
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
