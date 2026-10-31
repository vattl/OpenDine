import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

/// 客户挂账结算弹窗 (WI-047 / UI047 / v1.2.298)
class ReceivableChargeDialog extends StatefulWidget {
  const ReceivableChargeDialog({
    super.key,
    required this.order,
    required this.loadAccounts,
    required this.chargeReceivable,
    this.tableNumber = '',
  });

  final PosOrder order;
  final String tableNumber;
  final Future<List<PosReceivableEligibleAccount>> Function() loadAccounts;
  final Future<PosReceivableClaim> Function({
    required int accountId,
    required String requestId,
    String? note,
  }) chargeReceivable;

  @override
  State<ReceivableChargeDialog> createState() => _ReceivableChargeDialogState();
}

class _ReceivableChargeDialogState extends State<ReceivableChargeDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<PosReceivableEligibleAccount> _accounts = [];
  PosReceivableEligibleAccount? _selectedAccount;
  String _searchQuery = '';
  late final TextEditingController _searchController;
  late final TextEditingController _operatorController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _operatorController = TextEditingController();
    _noteController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _operatorController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _loading = false;
        // 默认选中第一个额度充足的账户
        _selectedAccount = list.where((a) => a.canCover(widget.order.total)).firstOrNull;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is CashierReceivableException ? e.message : e.toString();
      });
    }
  }

  List<PosReceivableEligibleAccount> get _filteredAccounts {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _accounts;
    return _accounts.where((a) {
      return a.customerName.toLowerCase().contains(q) ||
          a.contactPhone.toLowerCase().contains(q) ||
          a.contactName.toLowerCase().contains(q) ||
          a.taxNo.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _submit() async {
    final account = _selectedAccount;
    if (account == null || _submitting) return;

    if (!account.canCover(widget.order.total)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('客户【${account.customerName}】可用额度不足，无法挂账！'),
          backgroundColor: const Color(0xffef4444),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    // 生成稳定 requestId 防重
    final requestId = 'POS-AR-${DateTime.now().millisecondsSinceEpoch}-${widget.order.orderNo}';
    final operatorName = _operatorController.text.trim();
    final noteText = _noteController.text.trim();
    final combinedNote = [
      if (operatorName.isNotEmpty) '经手人: $operatorName',
      if (noteText.isNotEmpty) noteText,
    ].join(' | ');

    try {
      final claim = await widget.chargeReceivable(
        accountId: account.id,
        requestId: requestId,
        note: combinedNote.isNotEmpty ? combinedNote : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(claim);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e is CashierReceivableException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('挂账结账失败：$msg'),
          backgroundColor: const Color(0xffef4444),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? context.cashier.surface : Colors.white;
    final border = isDark ? context.cashier.border : const Color(0xffe2e8f0);
    final textInk = isDark ? context.cashier.ink : const Color(0xff0f172a);
    final textMuted = isDark ? context.cashier.inkMuted : const Color(0xff64748b);
    final cardBg = isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc);

    final requiredTotal = widget.order.total;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 640,
          constraints: const BoxConstraints(maxHeight: 740),
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '客户挂账结算',
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
                          color: const Color(0xffe0f2fe),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xffbae6fd)),
                        ),
                        child: const Text(
                          '商业化应收',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff0369a1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '桌台：${widget.tableNumber.isNotEmpty ? widget.tableNumber : widget.order.tableNumber} · 单号：${widget.order.orderNo}',
                    style: TextStyle(fontSize: 13, color: textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Amount highlight box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '订单净应付金额（不可修改）',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMuted),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '服务端将严格按此金额记入应收单据',
                          style: TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
                        ),
                      ],
                    ),
                    Text(
                      '¥ ${requiredTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xff0284c7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search Input
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '输入客户名称、联系电话或统一税号快速搜索...',
                  hintStyle: TextStyle(fontSize: 13, color: textMuted),
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xff0284c7)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xff0284c7), width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 12),

              // Accounts list
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
                                OutlinedButton(onPressed: _load, child: const Text('重试加载授信账户')),
                              ],
                            ),
                          )
                        : _filteredAccounts.isEmpty
                            ? Center(
                                child: Text(
                                  _accounts.isEmpty ? '当前门店暂无可用授信挂账账户' : '未找到匹配的授信客户',
                                  style: TextStyle(fontSize: 14, color: textMuted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _filteredAccounts.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: border.withValues(alpha: 0.5)),
                                itemBuilder: (context, index) {
                                  final account = _filteredAccounts[index];
                                  final isCoverable = account.canCover(requiredTotal);
                                  final isSelected = _selectedAccount?.id == account.id;

                                  return InkWell(
                                    onTap: isCoverable
                                        ? () => setState(() => _selectedAccount = account)
                                        : () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '客户【${account.customerName}】可用额度 ¥${account.availableLimitYuan.toStringAsFixed(2)} 不足支付 ¥${requiredTotal.toStringAsFixed(2)}，禁止挂账',
                                                ),
                                                duration: const Duration(seconds: 2),
                                                backgroundColor: const Color(0xffb45309),
                                              ),
                                            );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? (isDark ? const Color(0xff0369a1).withValues(alpha: 0.2) : const Color(0xfff0f9ff))
                                            : null,
                                        border: isSelected
                                            ? const Border(left: BorderSide(color: Color(0xff0284c7), width: 4))
                                            : null,
                                      ),
                                      child: Opacity(
                                        opacity: isCoverable ? 1.0 : 0.5,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        account.customerName,
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w700,
                                                          color: textInk,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: account.isCompany
                                                              ? const Color(0xffe0f2fe)
                                                              : const Color(0xffdcfce7),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          account.isCompany ? '企业' : '个人',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: account.isCompany
                                                                ? const Color(0xff0369a1)
                                                                : const Color(0xff15803d),
                                                          ),
                                                        ),
                                                      ),
                                                      if (!isCoverable) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xfffee2e2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text(
                                                            '额度不足',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w700,
                                                              color: Color(0xffb91c1c),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [
                                                      if (account.contactName.isNotEmpty) '联系人: ${account.contactName}',
                                                      if (account.contactPhone.isNotEmpty) account.contactPhone,
                                                      '账期: ${account.paymentTermsDays} 天',
                                                    ].join(' · '),
                                                    style: TextStyle(fontSize: 12, color: textMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '¥ ${account.availableLimitYuan.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: isCoverable
                                                        ? const Color(0xff15803d)
                                                        : const Color(0xffb91c1c),
                                                  ),
                                                ),
                                                Text(
                                                  '可用额度 (总 ¥${account.creditLimitYuan.toStringAsFixed(2)})',
                                                  style: TextStyle(fontSize: 11, color: textMuted),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 12),

              // Inputs for operator & notes
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _operatorController,
                      decoration: InputDecoration(
                        labelText: '经办/签单人姓名',
                        labelStyle: TextStyle(fontSize: 13, color: textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        labelText: '挂账备注 / 商务凭据说明',
                        labelStyle: TextStyle(fontSize: 13, color: textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: (_selectedAccount == null || !_selectedAccount!.canCover(requiredTotal) || _submitting)
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0284c7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_submitting ? '正在挂账结账...' : '确认挂账结账 (清台出票)'),
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
