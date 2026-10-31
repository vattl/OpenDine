import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../reconciliation/data/ledger_migration_repository.dart';
import '../../reconciliation/data/reconciliation_repository.dart';
import '../../reconciliation/domain/migration_models.dart';
import '../../reconciliation/domain/reconciliation_models.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 收款对账（原型文档 §四.11 / 商用方案 POS-SDC-401 & POS-SDC-402 & POS-SDC-501 & POS-SDC-502）。
///
/// 1. 接入商业级渠道对账引擎与三层差异处理单；
/// 2. 未导入微信/支付宝官方渠道对账单时，严禁标记“已对平”，系统强制标示“未导入 (内部汇总)”；
/// 3. 支持历史账本回填、双写影子验证与数据读源切读；
/// 4. 当未注入真实仓库且非演示模式时，呈现升级过渡保护视图；
/// 5. 演示模式下提供带明确水印的静态样例。
class PaymentReconcilePage extends StatefulWidget {
  const PaymentReconcilePage({
    super.key,
    this.isDemoMode,
    this.repository,
    this.migrationRepository,
  });

  final bool? isDemoMode;
  final ReconciliationRepository? repository;
  final LedgerMigrationRepository? migrationRepository;

  @override
  State<PaymentReconcilePage> createState() => _PaymentReconcilePageState();
}

class _PaymentReconcilePageState extends State<PaymentReconcilePage> {
  int _dayOffset = 0;
  bool _loading = false;
  String? _error;
  ReconciliationOverview? _overview;
  List<ReconciliationCase> _cases = [];

  bool get _isDemo => widget.isDemoMode ?? (widget.repository == null && AppConfig.debugBackendEnabled);

  String get _currentDateStr {
    final date = DateTime(2026, 10, 3).add(Duration(days: _dayOffset));
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  String get _dateLabel {
    final date = DateTime(2026, 10, 3).add(Duration(days: _dayOffset));
    return '${date.month}月${date.day}日';
  }

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _loadRealData();
    }
  }

  Future<void> _loadRealData() async {
    if (widget.repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await widget.repository!.loadOverview(statDate: _currentDateStr);
      final cases = await widget.repository!.loadCases(statDate: _currentDateStr);
      if (mounted) {
        setState(() {
          _overview = overview;
          _cases = cases;
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

  @override
  Widget build(BuildContext context) {
    // 1. 若注入了真实仓库，则展示商用三层对账真实页面
    if (widget.repository != null) {
      return _buildCommercialReconciliationScaffold();
    }

    // 2. 生产模式且无真实仓库保护视图
    if (!_isDemo) {
      return Scaffold(
        appBar: AppBar(title: const Text('收款对账')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.construction_outlined,
                  size: 64,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 16),
                const Text(
                  '收款对账商用化升级中',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '当前正在接入不可变支付账本与渠道对账引擎，生产环境暂不展示模拟财务数据。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. 演示/原型模式视图
    return Scaffold(
      appBar: AppBar(
        title: const Text('收款对账'),
        actions: [
          TextButton(
            onPressed: () => _snack('日报导出为原型演示'),
            child: const Text('导出'),
          ),
        ],
      ),
      body: ListView(
        padding: MobileMetrics.pagePadding.copyWith(
          top: MobileMetrics.spaceLg,
          bottom: MobileMetrics.spaceLg,
        ),
        children: [
          Container(
            key: const Key('reconcile-demo-banner'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: MobileMetrics.cardGap),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '【演示环境】当前为静态样例数据，未接入生产真实对账源，不可作为财务依据。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: MobileMetrics.cardPaddingCompact,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '前一天',
                    onPressed: () => setState(() => _dayOffset--),
                  ),
                  Text(_dateLabel, style: MobileTypography.sectionTitle),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '后一天',
                    onPressed: _dayOffset < 0
                        ? () => setState(() => _dayOffset++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          const Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Row(
                children: [
                  _SummaryCell(label: '应收', value: '¥8,642.00'),
                  _SummaryCell(label: '实收', value: '¥8,618.00'),
                  _SummaryCell(label: '差额', value: '-¥24.00', danger: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          const Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('渠道对账', style: MobileTypography.sectionTitle),
                  SizedBox(height: MobileMetrics.spaceSm),
                  _ChannelRow(
                    icon: Icons.qr_code_2,
                    label: '微信支付',
                    amount: '¥5,320',
                    tag: StatusTag('内部试算', tone: SemanticTone.neutral),
                  ),
                  _ChannelRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '支付宝',
                    amount: '¥1,860',
                    tag: StatusTag('内部试算', tone: SemanticTone.neutral),
                  ),
                  _ChannelRow(
                    icon: Icons.payments_outlined,
                    label: '现金',
                    amount: '¥1,438',
                    tag: StatusTag('差 ¥24', tone: SemanticTone.danger),
                    last: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('异常订单', style: MobileTypography.sectionTitle),
                  const SizedBox(height: MobileMetrics.spaceSm),
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: context.palette.danger,
                          size: MobileMetrics.iconSize),
                      const SizedBox(width: MobileMetrics.spaceSm),
                      const Expanded(
                        child: Text(
                          '#0607-052 · 现金 · 应收 ¥128 实收 ¥104',
                          style: MobileTypography.body,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _snack('异常订单处理为原型演示'),
                        child: const Text('去处理'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton(
          onPressed: () => _snack('已重新拉取渠道账单（原型演示）'),
          child: const Text('重新对账'),
        ),
      ),
    );
  }

  /// 商业级真实三层对账视图
  Widget _buildCommercialReconciliationScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('三层渠道与到账对账'),
        actions: [
          if (widget.migrationRepository != null)
            IconButton(
              key: const Key('reconcile-migration-button'),
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: '历史回填与切读',
              onPressed: _openMigrationCutoverDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新对账数据',
            onPressed: _loading ? null : _loadRealData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: context.palette.danger),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: context.palette.danger), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadRealData, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : _overview == null
                  ? const Center(child: Text('无对账数据'))
                  : ListView(
                      padding: MobileMetrics.pagePadding.copyWith(
                        top: MobileMetrics.spaceLg,
                        bottom: MobileMetrics.spaceLg,
                      ),
                      children: [
                        // 1. 状态与守则警示条
                        _buildStatusBanner(_overview!),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 2. 日期切换卡片
                        Card(
                          child: Padding(
                            padding: MobileMetrics.cardPaddingCompact,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  tooltip: '前一天',
                                  onPressed: () {
                                    setState(() => _dayOffset--);
                                    _loadRealData();
                                  },
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      '$_dateLabel ($_currentDateStr)',
                                      style: MobileTypography.sectionTitle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  tooltip: '后一天',
                                  onPressed: _dayOffset < 0
                                      ? () {
                                          setState(() => _dayOffset++);
                                          _loadRealData();
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 3. 汇总核心三指标
                        Card(
                          child: Padding(
                            padding: MobileMetrics.cardPadding,
                            child: Row(
                              children: [
                                _SummaryCell(
                                  label: '订单应收',
                                  value: '¥${_overview!.layer1.orderNetSalesYuan.toStringAsFixed(2)}',
                                ),
                                _SummaryCell(
                                  label: '台账实收',
                                  value: '¥${_overview!.layer1.ledgerNetAmountYuan.toStringAsFixed(2)}',
                                ),
                                _SummaryCell(
                                  label: '核对差额',
                                  value: '¥${_overview!.layer1.differenceYuan.toStringAsFixed(2)}',
                                  danger: !_overview!.layer1.balanced,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 4. 第一层：订单 vs 内部支付台账
                        _buildLayer1Card(_overview!.layer1),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 5. 第二层：内部支付台账 vs 渠道对账单
                        _buildLayer2Card(_overview!.layer2),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 6. 第三层：渠道账单 vs 扣费到账净额
                        _buildLayer3Card(_overview!.layer3),
                        const SizedBox(height: MobileMetrics.cardGap),

                        // 7. 差异处理单卡片
                        _buildDiscrepancyCasesCard(_cases),
                      ],
                    ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('导入渠道对账单'),
                onPressed: () => _openImportDialog(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重新对账'),
                onPressed: _loadRealData,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(ReconciliationOverview overview) {
    if (!overview.hasChannelStatement) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade400),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('未导入外部渠道对账单', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      const SizedBox(width: 8),
                      const StatusTag('未导入 (内部汇总)', tone: SemanticTone.neutral),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前仅汇总内部交易流水，严禁标记“已对平”。请点击下方“导入渠道对账单”上传微信/支付宝官方账单。',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (overview.summaryStatus == 'RECONCILED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade400),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade800, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Text('三层对账已对平', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                  const SizedBox(width: 8),
                  const StatusTag('三层已对平', tone: SemanticTone.success),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade400),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade800, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('对账存在差异', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                    const SizedBox(width: 8),
                    StatusTag('存在差异 (${overview.openCasesCount})', tone: SemanticTone.danger),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '系统检测到 ${overview.openCasesCount} 笔待处理差异单，请在下方列表核查处置并平账。',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayer1Card(ReconciliationLayer1 layer1) {
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text('第 1 层：订单 vs 内部支付台账', style: MobileTypography.sectionTitle),
                ),
                const SizedBox(width: 8),
                layer1.balanced
                    ? const StatusTag('订单对平', tone: SemanticTone.success)
                    : const StatusTag('差额不符', tone: SemanticTone.danger),
              ],
            ),
            const SizedBox(height: MobileMetrics.spaceSm),
            _MetricRow('订单总笔数', '${layer1.orderCount} 单'),
            _MetricRow('订单应付净额', '¥${layer1.orderNetSalesYuan.toStringAsFixed(2)}'),
            _MetricRow('台账成功笔数', '${layer1.ledgerCount} 笔'),
            _MetricRow('台账实收净额', '¥${layer1.ledgerNetAmountYuan.toStringAsFixed(2)}'),
            const Divider(height: 16),
            _MetricRow(
              '第一层差异',
              '¥${layer1.differenceYuan.toStringAsFixed(2)}',
              danger: !layer1.balanced,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayer2Card(ReconciliationLayer2 layer2) {
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text('第 2 层：内部台账 vs 渠道对账单', style: MobileTypography.sectionTitle),
                ),
                const SizedBox(width: 8),
                if (!layer2.hasStatement)
                  const StatusTag('未导入对账单', tone: SemanticTone.neutral)
                else if (layer2.status == 'BALANCED')
                  const StatusTag('渠道对平', tone: SemanticTone.success)
                else
                  const StatusTag('渠道存在差异', tone: SemanticTone.danger),
              ],
            ),
            const SizedBox(height: MobileMetrics.spaceSm),
            if (!layer2.hasStatement) ...[
              Text(
                layer2.message ?? '未导入微信/支付宝官方渠道对账单',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ] else ...[
              _MetricRow('渠道交易总笔数', '${layer2.channelTradeCount} 笔'),
              _MetricRow('渠道交易总金额', '¥${layer2.channelTotalAmountYuan.toStringAsFixed(2)}'),
              _MetricRow('双向成功匹配', '${layer2.matchedCount} 笔'),
              if (layer2.unmatchedInternalCount > 0)
                _MetricRow('内部有账渠道缺失', '${layer2.unmatchedInternalCount} 笔', danger: true),
              if (layer2.unmatchedChannelCount > 0)
                _MetricRow('渠道有账内部缺失', '${layer2.unmatchedChannelCount} 笔', danger: true),
              if (layer2.amountMismatchCount > 0)
                _MetricRow('单据金额不符', '${layer2.amountMismatchCount} 笔', danger: true),
              const Divider(height: 16),
              _MetricRow(
                '第二层差异',
                '¥${layer2.differenceYuan.toStringAsFixed(2)}',
                danger: layer2.differenceFen != 0,
                bold: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLayer3Card(ReconciliationLayer3 layer3) {
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('第 3 层：渠道账单 vs 扣费到账净额', style: MobileTypography.sectionTitle),
                ),
                SizedBox(width: 8),
                StatusTag('结算到账核算', tone: SemanticTone.neutral),
              ],
            ),
            const SizedBox(height: MobileMetrics.spaceSm),
            _MetricRow('渠道交易毛额', '¥${layer3.channelGrossYuan.toStringAsFixed(2)}'),
            _MetricRow('平台扣除手续费', '-¥${layer3.feeYuan.toStringAsFixed(2)}', danger: false),
            const Divider(height: 16),
            _MetricRow('预计到账净额', '¥${layer3.netSettlementYuan.toStringAsFixed(2)}', bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscrepancyCasesCard(List<ReconciliationCase> cases) {
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('差异处理单 (${cases.length})', style: MobileTypography.sectionTitle),
                if (cases.isEmpty)
                  const StatusTag('无差异单', tone: SemanticTone.success)
                else
                  StatusTag('${cases.where((c) => c.isOpen).length} 笔待处理', tone: SemanticTone.danger),
              ],
            ),
            const SizedBox(height: MobileMetrics.spaceSm),
            if (cases.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('当前营业日无对账差异处理单', style: TextStyle(color: Colors.grey)),
              ),
            ] else ...[
              for (final c in cases) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        c.isOpen ? Icons.error_outline : Icons.check_circle_outline,
                        color: c.isOpen ? context.palette.danger : context.palette.success,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.caseNo} · ${_formatDiscrepancyType(c.discrepancyType)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.reason ?? '内部金额: ¥${c.internalAmountYuan.toStringAsFixed(2)}, 渠道: ¥${c.channelAmountYuan.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      if (c.isOpen)
                        TextButton(
                          onPressed: () => _openResolveCaseDialog(c),
                          child: const Text('去处理'),
                        )
                      else
                        const Text('已平账', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDiscrepancyType(String type) {
    switch (type) {
      case 'INTERNAL_MISSING':
        return '渠道有账·内部漏单';
      case 'CHANNEL_MISSING':
        return '内部有账·渠道缺失';
      case 'AMOUNT_MISMATCH':
        return '单据金额不一致';
      case 'TIMING_DIFFERENCE':
        return '跨日延迟时间差';
      case 'ORDER_LEDGER_MISMATCH':
        return '订单与台账差额';
      default:
        return type;
    }
  }

  void _openImportDialog() {
    final controller = TextEditingController();
    String selectedChannel = 'WECHAT';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('导入渠道对账单 (CSV/JSON)'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择账单渠道：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: selectedChannel,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'WECHAT', child: Text('微信支付商户账单 (WECHAT)')),
                      DropdownMenuItem(value: 'ALIPAY', child: Text('支付宝商户账单 (ALIPAY)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedChannel = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('粘贴对账单内容（CSV 或 JSON）：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: '支持微信官方 CSV、支付宝官方 CSV 或通用标准 JSON/CSV 格式...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text('填充微信对账测试样例'),
                    onPressed: () {
                      controller.text = 'trade_time,channel,channel_trade_no,merchant_order_no,entry_type,amount,fee\n'
                          '${_currentDateStr} 12:00:00,$selectedChannel,TX-${DateTime.now().millisecondsSinceEpoch},ORD-${DateTime.now().millisecondsSinceEpoch},PAYMENT,50.00,0.30\n';
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  _snack('请输入对账单内容');
                  return;
                }
                Navigator.of(ctx).pop();
                setState(() => _loading = true);
                try {
                  await widget.repository!.importStatement(
                    channel: selectedChannel,
                    fileName: '${selectedChannel.toLowerCase()}_statement.csv',
                    content: text,
                  );
                  _snack('对账单导入成功，已自动执行三层对账');
                  await _loadRealData();
                } catch (e) {
                  setState(() => _loading = false);
                  _snack('导入失败: $e');
                }
              },
              child: const Text('确认导入'),
            ),
          ],
        ),
      ),
    );
  }

  void _openResolveCaseDialog(ReconciliationCase c) {
    final noteCtrl = TextEditingController();
    final personCtrl = TextEditingController(text: '财务管理员');
    String selectedStatus = 'CLOSED';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('处置差异单: ${c.caseNo}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('差异类型: ${_formatDiscrepancyType(c.discrepancyType)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('差额: ¥${c.differenceYuan.toStringAsFixed(2)}', style: TextStyle(color: context.palette.danger)),
                const SizedBox(height: 12),
                const Text('处置结果状态：'),
                DropdownButton<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'CLOSED', child: Text('核实无误·平账关闭 (CLOSED)')),
                    DropdownMenuItem(value: 'ADJUSTED', child: Text('财务已补调账 (ADJUSTED)')),
                    DropdownMenuItem(value: 'WRITTEN_OFF', child: Text('无法追回·核销坏账 (WRITTEN_OFF)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedStatus = v);
                  },
                ),
                const SizedBox(height: 10),
                const Text('责任人 / 经办人：'),
                TextField(
                  controller: personCtrl,
                  decoration: const InputDecoration(hintText: '输入核实责任人姓名或工号'),
                ),
                const SizedBox(height: 10),
                const Text('处置说明 / 核实原因：'),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '如：已核对第三方商户后台，为跨日延迟到账，确认无资金风险'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                setState(() => _loading = true);
                try {
                  await widget.repository!.resolveCase(
                    caseId: c.id,
                    status: selectedStatus,
                    resolutionNote: noteCtrl.text.trim().isEmpty ? '核实确认平账' : noteCtrl.text.trim(),
                    responsiblePerson: personCtrl.text.trim(),
                  );
                  _snack('差异单已处置');
                  await _loadRealData();
                } catch (e) {
                  setState(() => _loading = false);
                  _snack('处置失败: $e');
                }
              },
              child: const Text('确认平账'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMigrationCutoverDialog() async {
    if (widget.migrationRepository == null) return;
    try {
      final status = await widget.migrationRepository!.getStatus();
      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.swap_horiz, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(child: Text('历史账本回填与切读 (Phase 5)')),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前数据读源: ${status.isCutoverToLedger ? "商业支付台账 (PAYMENT_LEDGER)" : "历史订单口径 (LEGACY_ORDER)"}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: status.isCutoverToLedger ? Colors.green.shade800 : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('流水统计：总计 ${status.totalLedgerRows} 行（原生: ${status.nativeRows} 行，回填: ${status.backfilledRows} 行）',
                    style: const TextStyle(fontSize: 13)),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.history, color: Colors.white, size: 20),
                  ),
                  title: const Text('执行历史订单回填 (POS-SDC-501)'),
                  subtitle: const Text('幂等补齐历史订单支付流水，生成防篡改审计哈希'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openBackfillDialog();
                  },
                ),
                const Divider(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.compare_arrows, color: Colors.white, size: 20),
                  ),
                  title: const Text('双写影子验证 (POS-SDC-502)'),
                  subtitle: const Text('对比旧订单口径与新台账口径逐笔及渠道汇总'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openShadowVerifyDialog();
                  },
                ),
                const Divider(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: status.isCutoverToLedger ? Colors.orange : Colors.green,
                    child: const Icon(Icons.alt_route, color: Colors.white, size: 20),
                  ),
                  title: Text(status.isCutoverToLedger ? '回退至历史订单读源' : '正式切换至新台账读源'),
                  subtitle: Text(status.isCutoverToLedger ? '只切读源，不删除新台账数据' : '完成影子核对后切换生产流量'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openCutoverConfirmDialog(status);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('获取切读状态失败: $e');
    }
  }

  void _openBackfillDialog() {
    bool dryRun = true;
    final dateCtrl = TextEditingController(text: _currentDateStr);
    BackfillReport? report;
    bool backfilling = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('执行历史订单回填 (POS-SDC-501)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(
                      labelText: '回填指定日期 (yyyy-MM-dd，留空则全量历史)',
                      hintText: '留空表示回填所有历史已结订单',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('仅演练试算 (Dry-Run 模式)'),
                    subtitle: const Text('仅扫描统计、复算恒等式并生成防篡改报告，不落库修改'),
                    value: dryRun,
                    onChanged: (v) {
                      setDialogState(() => dryRun = v ?? true);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (backfilling)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (report != null) ...[
                    const Divider(),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report!.dryRun ? '【演练预览结果】' : '【正式回填完成】',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900),
                          ),
                          const SizedBox(height: 6),
                          Text('扫描订单: ${report!.totalOrdersScanned} 笔'),
                          Text('成功回填: ${report!.backfilledOrders} 笔 (插入流水 ${report!.totalRowsInserted} 行)'),
                          Text('跳过已有: ${report!.skippedOrders} 笔'),
                          Text('回填金额: ¥${(report!.totalAmountFen / 100.0).toStringAsFixed(2)}'),
                          Text('异常单数: ${report!.anomaliesCount} 笔'),
                          Text('签名摘要: ${report!.integrityHash.length >= 16 ? report!.integrityHash.substring(0, 16) : report!.integrityHash}...'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            ElevatedButton(
              key: const Key('reconcile-run-backfill-button'),
              onPressed: backfilling
                  ? null
                  : () async {
                      setDialogState(() => backfilling = true);
                      try {
                        final res = await widget.migrationRepository!.backfill(
                          statDate: dateCtrl.text.trim().isEmpty ? null : dateCtrl.text.trim(),
                          dryRun: dryRun,
                        );
                        setDialogState(() {
                          report = res;
                          backfilling = false;
                        });
                        _snack(dryRun ? '演练试算完成' : '历史账本已回填落库');
                        _loadRealData();
                      } catch (e) {
                        setDialogState(() => backfilling = false);
                        _snack('回填失败: $e');
                      }
                    },
              child: Text(dryRun ? '开始演练试算' : '确认正式回填'),
            ),
          ],
        ),
      ),
    );
  }

  void _openShadowVerifyDialog() {
    final dateCtrl = TextEditingController(text: _currentDateStr);
    ShadowVerifyResult? result;
    bool verifying = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('双写影子验证 (POS-SDC-502)'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(
                      labelText: '核对营业日 (yyyy-MM-dd)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (verifying)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (result != null) ...[
                    const Divider(),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: result!.readyForCutover ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: result!.readyForCutover ? Colors.green.shade300 : Colors.red.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                result!.readyForCutover ? Icons.check_circle : Icons.warning,
                                color: result!.readyForCutover ? Colors.green : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  result!.readyForCutover ? '验证通过·账实零差异·可安全切读' : '存在差异·暂不可切读',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: result!.readyForCutover ? Colors.green.shade900 : Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('旧订单净收: ¥${((result!.legacyOrderSummary['net_revenue_fen'] as num? ?? 0) / 100.0).toStringAsFixed(2)}'),
                          Text('新台账实收: ¥${((result!.ledgerSummary['net_revenue_fen'] as num? ?? 0) / 100.0).toStringAsFixed(2)}'),
                          Text('综合净差额: ¥${(result!.netVarianceFen / 100.0).toStringAsFixed(2)}'),
                          Text('单据差异数: ${result!.discrepancyCount} 笔'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            ElevatedButton(
              key: const Key('reconcile-run-shadow-button'),
              onPressed: verifying
                  ? null
                  : () async {
                      setDialogState(() => verifying = true);
                      try {
                        final res = await widget.migrationRepository!.shadowVerify(
                          statDate: dateCtrl.text.trim(),
                        );
                        setDialogState(() {
                          result = res;
                          verifying = false;
                        });
                      } catch (e) {
                        setDialogState(() => verifying = false);
                        _snack('影子验证失败: $e');
                      }
                    },
              child: const Text('开始核对'),
            ),
          ],
        ),
      ),
    );
  }

  void _openCutoverConfirmDialog(CutoverStatus status) {
    final target = status.isCutoverToLedger ? 'LEGACY_ORDER' : 'PAYMENT_LEDGER';
    final targetLabel = status.isCutoverToLedger ? '历史订单口径 (LEGACY_ORDER)' : '商业支付台账 (PAYMENT_LEDGER)';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认切换数据读源 (POS-SDC-502)'),
        content: Text('即将切换数据读源至: $targetLabel。\n\n切换后日结对账、收银交班及渠道统计将实时采用该读源。数据安全机制保证回退时只切读源，不删除新台账数据。确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            key: const Key('reconcile-confirm-cutover-button'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await widget.migrationRepository!.cutover(targetSource: target);
                _snack('读源已成功切换至 $targetLabel');
                await _loadRealData();
              } catch (e) {
                _snack('切换读源失败: $e');
              }
            },
            child: const Text('确认切换'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value, {this.danger = false, this.bold = false});

  final String label;
  final String value;
  final bool danger;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: danger ? context.palette.danger : context.palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (danger) ...[
                Icon(Icons.error_outline,
                    size: 14, color: context.palette.danger),
                const SizedBox(width: 2),
              ],
              Text(label, style: context.captionStyle),
            ],
          ),
          const SizedBox(height: MobileMetrics.spaceXs),
          Text(
            value,
            style: MobileTypography.sectionTitle.copyWith(
              fontSize: 18,
              color: danger ? context.palette.danger : context.palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.label,
    required this.amount,
    required this.tag,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String amount;
  final StatusTag tag;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(vertical: MobileMetrics.spaceMd),
          child: Row(
            children: [
              Icon(icon,
                  size: MobileMetrics.iconSize, color: context.palette.brandInk),
              const SizedBox(width: MobileMetrics.spaceMd),
              Expanded(child: Text(label, style: MobileTypography.body)),
              Text(
                amount,
                style: MobileTypography.itemTitle.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: MobileMetrics.spaceMd),
              tag,
            ],
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }
}
