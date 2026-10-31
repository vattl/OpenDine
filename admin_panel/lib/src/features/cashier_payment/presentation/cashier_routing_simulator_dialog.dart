import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_components.dart';
import '../data/cashier_payment_repository.dart';
import '../domain/cashier_payment_config.dart';

/// 商户分流路由现场试算模拟器弹窗
class CashierRoutingSimulatorDialog extends StatefulWidget {
  const CashierRoutingSimulatorDialog({
    super.key,
    required this.repository,
    required this.channel,
    this.availableMerchants = const [],
  });

  final CashierPaymentRepository repository;
  final PaymentChannel channel;
  final List<PaymentMerchant> availableMerchants;

  @override
  State<CashierRoutingSimulatorDialog> createState() =>
      _CashierRoutingSimulatorDialogState();
}

class _CashierRoutingSimulatorDialogState
    extends State<CashierRoutingSimulatorDialog> {
  final _amountController = TextEditingController(text: '88.00');
  final _goodsController = TextEditingController(text: '挪威三文鱼刺身, 芥末生抽');
  String _diningType = '打包';
  bool _busy = false;
  String? _error;
  PaymentRoutingSimulationResult? _result;

  @override
  void dispose() {
    _amountController.dispose();
    _goodsController.dispose();
    super.dispose();
  }

  Future<void> _simulate() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 0) {
      setState(() => _error = '请输入合法的测试实付金额');
      return;
    }

    final goodsText = _goodsController.text.trim();
    final goodsItems = <Map<String, Object?>>[];
    if (goodsText.isNotEmpty) {
      final names = goodsText
          .split(RegExp(r'[,，\s]+'))
          .where((s) => s.isNotEmpty)
          .toList();
      for (var i = 0; i < names.length; i++) {
        goodsItems.add({
          'goodsId': 1000 + i,
          'goodsName': names[i],
          'price': amount,
          'quantity': 1,
        });
      }
    }

    final payload = <String, Object?>{
      'channel': widget.channel.code,
      'paidYuan': amount,
      'diningType': _diningType,
      'goodsItems': goodsItems,
    };

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await widget.repository.simulateRouting(payload);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      title: '商户分流路由规则现场试算模拟器',
      subtitle: '${widget.channel.label} · 输入模拟订单上下文，现场验证规则链判定与最终收款商户',
      width: 860,
      height: 620,
      busy: _busy,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        CashierActionButton(
          label: '关闭',
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 100,
          height: 48,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：模拟参数输入
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '📥 模拟测试输入参数',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('cashier-sim-amount-input'),
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '测试订单实付金额 (元) *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('cashier-sim-dining-dropdown'),
                    initialValue: _diningType,
                    decoration: const InputDecoration(
                      labelText: '测试就餐方式 *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '打包', child: Text('打包')),
                      DropdownMenuItem(value: '堂食', child: Text('堂食')),
                      DropdownMenuItem(value: '外卖自提', child: Text('外卖自提')),
                      DropdownMenuItem(value: '外卖配送', child: Text('外卖配送')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _diningType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('cashier-sim-goods-input'),
                    controller: _goodsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '测试菜品名称明细',
                      hintText: '输入菜品名称，多个以逗号分隔',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  CashierActionButton(
                    key: const Key('cashier-sim-run-btn'),
                    label: '开始模拟试算',
                    height: 48,
                    busy: _busy,
                    onPressed: _simulate,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 分隔竖线
          const VerticalDivider(width: 32),

          // 右侧：推导结果反馈
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🎯 决策推导与最终收款商户',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_result == null)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Text(
                          '点击左侧【开始模拟试算】按钮\n实时查看当前多维度规则链判定结果',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), height: 1.6),
                        ),
                      ),
                    )
                  else ...[
                    // 结果卡片
                    Container(
                      key: const Key('cashier-sim-result-card'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _result!.matched
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _result!.matched
                              ? const Color(0xFFBBF7D0)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _result!.matched
                                    ? Icons.check_circle
                                    : Icons.info_outline,
                                color: _result!.matched
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFD97706),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _result!.matched
                                    ? '成功命中分流规则'
                                    : '未命中分流规则（走默认）',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: _result!.matched
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          if (_result!.matched) ...[
                            _buildResultRow(
                              '命中规则',
                              _result!.matchedRuleName.isNotEmpty
                                  ? _result!.matchedRuleName
                                  : '规则 ID #${_result!.matchedRuleId}',
                            ),
                            _buildResultRow('目标商户', _result!.targetMerchantKey),
                            _buildResultRow(
                              '商户凭据就绪性',
                              _result!.targetMerchantPayReady ? '🟢 凭据已就绪' : '🔴 凭据未就绪',
                            ),
                          ] else
                            _buildResultRow('未命中原因', _result!.reason),

                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _result!.fallbackOccurred
                                    ? const Color(0xFFFECACA)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '最终实际收款商户：',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _result!.effectiveMerchantKey,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _result!.fallbackOccurred
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF0284C7),
                                  ),
                                ),
                                if (_result!.fallbackOccurred)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Text(
                                      '(自动降级主商户保护)',
                                      style: TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 安全机制解释
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Text(
                        '💡 资金安全机制说明：\n系统在每次收银出码/付款时，前置校验目标商户密钥证书的完整就绪状态。若目标商户由于凭据过期或未上传导致无法收款，路由引擎将自动兜底降级至主商户 (default)，确保店内营业与点餐结账永不中断。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E40AF),
                          height: 1.5,
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
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label：',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
