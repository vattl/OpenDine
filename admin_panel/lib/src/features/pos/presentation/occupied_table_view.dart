import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../mobile/responsive/breakpoints.dart';
import '../../tables/domain/dining_table.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';
import 'pos_receipt_print_dialog.dart';

const _red = Color(0xffdd5757);

class OccupiedTableView extends StatefulWidget {
  const OccupiedTableView({
    super.key,
    required this.workspace,
    required this.busy,
    required this.onBack,
    required this.onAddDishes,
    required this.onMerge,
    required this.onTransfer,
    required this.onClear,
    required this.onRefund,
    required this.onGift,
    required this.onDiscount,
    this.onForceCheckout,
    required this.onPrintReceipt,
    required this.paymentMethods,
    required this.onCheckout,
    required this.onBalanceCheckout,
    this.onHang,
    this.pickupOrder = false,
    this.checkoutOnly = false,
    this.fulfillmentTitle,
    this.onViewMemberHistory,
    this.onUpdateDiners,
    this.isDrawerOpen = true,
  });

  final PosWorkspace workspace;
  final bool busy;
  final VoidCallback onBack;
  final void Function([PosOrder? targetOrder]) onAddDishes;
  final VoidCallback onMerge;
  final void Function([PosOrder? targetOrder]) onTransfer;
  final VoidCallback onClear;
  final ValueChanged<PosOrderLine> onRefund;
  final ValueChanged<PosOrderLine> onGift;
  final void Function([PosOrder? targetOrder]) onDiscount;
  final void Function([PosOrder? targetOrder])? onForceCheckout;
  final void Function(PosReceiptPrintType type, [PosOrder? targetOrder])
  onPrintReceipt;
  final List<PosPaymentMethod> paymentMethods;
  final ValueChanged<String> onCheckout;
  final VoidCallback onBalanceCheckout;
  final bool isDrawerOpen;

  /// 修改用餐人数回调
  final void Function([PosOrder? targetOrder])? onUpdateDiners;

  /// 挂单回调：把未结订单挂起、释放桌台；为 null 时不显示入口。
  final VoidCallback? onHang;
  final bool pickupOrder;
  final bool checkoutOnly;
  final String? fulfillmentTitle;
  final VoidCallback? onViewMemberHistory;

  @override
  State<OccupiedTableView> createState() => _OccupiedTableViewState();
}

class _OccupiedTableViewState extends State<OccupiedTableView> {
  int? selectedOrderIndex;
  int _mobileTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final order = workspace.currentOrder;
    if (order == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无当前账单信息', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            FilledButton(onPressed: widget.onBack, child: const Text('返回桌台')),
          ],
        ),
      );
    }
    final settled = workspace.table.status == TableStatus.settled;
    final hasMultipleOrders = workspace.tableOrders.length > 1;
    final activeOrder =
        (selectedOrderIndex != null &&
            selectedOrderIndex! >= 0 &&
            selectedOrderIndex! < workspace.tableOrders.length)
        ? workspace.tableOrders[selectedOrderIndex!]
        : order;
    final displayLines = (hasMultipleOrders && selectedOrderIndex == null)
        ? workspace.allLines
        : activeOrder.lines;

    final isCompact = context.isCompact || context.isPhoneLandscape;
    final isMedium = context.isMedium;

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LeftHeader(createdAt: order.createdAt, onBack: widget.onBack),
          const SizedBox(height: 8),
          Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Row(
              children: [
                _MobileTabButton(
                  title: '菜品明细 (${displayLines.length})',
                  selected: _mobileTabIndex == 0,
                  onTap: () => setState(() => _mobileTabIndex = 0),
                ),
                _MobileTabButton(
                  title: '桌台操作',
                  selected: _mobileTabIndex == 1,
                  onTap: () => setState(() => _mobileTabIndex = 1),
                ),
                _MobileTabButton(
                  title: '收银结算',
                  selected: _mobileTabIndex == 2,
                  onTap: () => setState(() => _mobileTabIndex = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _mobileTabIndex,
              children: [
                // Tab 0: 菜品明细
                Column(
                  children: [
                    _OrderToolbar(
                      tableNumber: workspace.table.number,
                      diners: activeOrder.diners,
                      createdAt: activeOrder.createdAt,
                      orderNo: activeOrder.orderNo,
                      masterOrderNo: activeOrder.masterOrderNo,
                      isMergedSlaveOrder: activeOrder.isMergedSlaveOrder,
                      tableOrders: workspace.tableOrders,
                      selectedOrderIndex: selectedOrderIndex,
                      onSelectOrder: (idx) =>
                          setState(() => selectedOrderIndex = idx),
                      receivingStatus: activeOrder.receivingStatus,
                      kdsOrderStatus: activeOrder.kdsOrderStatus,
                      busy:
                          widget.busy ||
                          settled ||
                          widget.pickupOrder ||
                          widget.checkoutOnly,
                      onAddDishes: () => widget.onAddDishes(activeOrder),
                      onUpdateDiners: widget.onUpdateDiners != null
                          ? () => widget.onUpdateDiners!(activeOrder)
                          : null,
                      onHang: widget.onHang,
                      onTransfer: () => widget.onTransfer(activeOrder),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('occupied-order-lines'),
                        child: _OrderLines(
                          order: activeOrder,
                          lines: displayLines,
                          busy: widget.busy || settled || widget.checkoutOnly,
                          onRefund: widget.onRefund,
                          onGift: widget.onGift,
                          onDiscount: () => widget.onDiscount(activeOrder),
                          onPrintReceipt: (type) =>
                              widget.onPrintReceipt(type, activeOrder),
                        ),
                      ),
                    ),
                  ],
                ),
                // Tab 1: 桌台操作
                SizedBox(
                  key: const Key('occupied-left-column'),
                  child: _TableSummary(
                    workspace: workspace,
                    activeOrder: activeOrder,
                    pickupOrder: widget.pickupOrder,
                    checkoutOnly: widget.checkoutOnly,
                    fulfillmentTitle: widget.fulfillmentTitle,
                    busy: widget.busy,
                    onMerge: widget.onMerge,
                    onTransfer: widget.onTransfer,
                    onClear: widget.onClear,
                    onDiscount: widget.onDiscount,
                    onForceCheckout: widget.onForceCheckout,
                    onPrintReceipt: widget.onPrintReceipt,
                    onHang: widget.onHang,
                    onViewMemberHistory: widget.onViewMemberHistory,
                    onUpdateDiners: widget.onUpdateDiners,
                  ),
                ),
                // Tab 2: 收银结算
                SizedBox(
                  key: const Key('occupied-right-column'),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _AmountBar(
                          order: activeOrder,
                          isMergedTable: workspace.isMergedTable,
                          totalPayable: workspace.isMergedTable
                              ? workspace.tableTotalPayable
                              : activeOrder.total,
                          totalDiscount: workspace.isMergedTable
                              ? workspace.tableTotalDiscount
                              : (activeOrder.discountAmount +
                                  activeOrder.wipeZeroAmount),
                        ),
                        const SizedBox(height: 10),
                        _PaymentBar(
                          settled: settled,
                          busy: widget.busy,
                          order: activeOrder,
                          isMergedTable: workspace.isMergedTable,
                          paymentMethods: widget.paymentMethods,
                          paymentConfigurationAvailable:
                              workspace.paymentConfigurationAvailable,
                          onCheckout: widget.onCheckout,
                          onBalanceCheckout: widget.onBalanceCheckout,
                          isDrawerOpen: widget.isDrawerOpen,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final leftWidth = isMedium ? 320.0 : 420.0;
    final rightWidth = isMedium ? 300.0 : 360.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 左栏 (左侧不变：桌台概览与快捷操作)
        SizedBox(
          key: const Key('occupied-left-column'),
          width: leftWidth,
          child: Column(
            children: [
              _LeftHeader(createdAt: order.createdAt, onBack: widget.onBack),
              const SizedBox(height: 13),
              Expanded(
                child: _TableSummary(
                  workspace: workspace,
                  activeOrder: activeOrder,
                  pickupOrder: widget.pickupOrder,
                  checkoutOnly: widget.checkoutOnly,
                  fulfillmentTitle: widget.fulfillmentTitle,
                  busy: widget.busy,
                  onMerge: widget.onMerge,
                  onTransfer: widget.onTransfer,
                  onClear: widget.onClear,
                  onDiscount: widget.onDiscount,
                  onForceCheckout: widget.onForceCheckout,
                  onPrintReceipt: widget.onPrintReceipt,
                  onHang: widget.onHang,
                  onViewMemberHistory: widget.onViewMemberHistory,
                  onUpdateDiners: widget.onUpdateDiners,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // 2. 中栏 (菜品明细：享受全高纵向展示空间)
        Expanded(
          child: Column(
            children: [
              _OrderToolbar(
                tableNumber: workspace.table.number,
                diners: activeOrder.diners,
                createdAt: activeOrder.createdAt,
                orderNo: activeOrder.orderNo,
                masterOrderNo: activeOrder.masterOrderNo,
                isMergedSlaveOrder: activeOrder.isMergedSlaveOrder,
                tableOrders: workspace.tableOrders,
                selectedOrderIndex: selectedOrderIndex,
                onSelectOrder: (idx) =>
                    setState(() => selectedOrderIndex = idx),
                receivingStatus: activeOrder.receivingStatus,
                kdsOrderStatus: activeOrder.kdsOrderStatus,
                busy:
                    widget.busy ||
                    settled ||
                    widget.pickupOrder ||
                    widget.checkoutOnly,
                onAddDishes: () => widget.onAddDishes(activeOrder),
                onUpdateDiners: widget.onUpdateDiners != null
                    ? () => widget.onUpdateDiners!(activeOrder)
                    : null,
                onHang: widget.onHang,
                onTransfer: () => widget.onTransfer(activeOrder),
              ),
              const SizedBox(height: 13),
              Expanded(
                child: KeyedSubtree(
                  key: const Key('occupied-order-lines'),
                  child: _OrderLines(
                    order: activeOrder,
                    lines: displayLines,
                    busy: widget.busy || settled || widget.checkoutOnly,
                    onRefund: widget.onRefund,
                    onGift: widget.onGift,
                    onDiscount: () => widget.onDiscount(activeOrder),
                    onPrintReceipt: (type) =>
                        widget.onPrintReceipt(type, activeOrder),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // 3. 右栏 (独立支付模块与应付金额、优惠金额等结算信息)
        SizedBox(
          key: const Key('occupied-right-column'),
          width: rightWidth,
          child: Column(
            children: [
              _AmountBar(
                order: activeOrder,
                isMergedTable: workspace.isMergedTable,
                totalPayable: workspace.isMergedTable
                    ? workspace.tableTotalPayable
                    : activeOrder.total,
                totalDiscount: workspace.isMergedTable
                    ? workspace.tableTotalDiscount
                    : (activeOrder.discountAmount + activeOrder.wipeZeroAmount),
              ),
              const SizedBox(height: 13),
              Expanded(
                child: _PaymentBar(
                  settled: settled,
                  busy: widget.busy,
                  order: activeOrder,
                  isMergedTable: workspace.isMergedTable,
                  paymentMethods: widget.paymentMethods,
                  paymentConfigurationAvailable:
                      workspace.paymentConfigurationAvailable,
                  onCheckout: widget.onCheckout,
                  onBalanceCheckout: widget.onBalanceCheckout,
                  isDrawerOpen: widget.isDrawerOpen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileTabButton extends StatelessWidget {
  const _MobileTabButton({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? context.cashier.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color:
                    selected ? context.cashier.ink : context.cashier.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftHeader extends StatelessWidget {
  const _LeftHeader({required this.createdAt, required this.onBack});

  final DateTime? createdAt;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 73,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              key: const Key('occupied-left-back-button'),
              tooltip: '返回',
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back,
                size: 28,
                color: context.cashier.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '返回大盘',
            style: TextStyle(
              color: context.cashier.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time,
                  size: 18,
                  color: context.cashier.inkMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '下单时间：${_dateLabel(createdAt)}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: context.cashier.inkMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableSummary extends StatelessWidget {
  const _TableSummary({
    required this.workspace,
    this.activeOrder,
    required this.pickupOrder,
    required this.checkoutOnly,
    required this.fulfillmentTitle,
    required this.busy,
    required this.onMerge,
    required this.onTransfer,
    required this.onClear,
    required this.onDiscount,
    this.onForceCheckout,
    required this.onPrintReceipt,
    this.onHang,
    this.onViewMemberHistory,
    this.onUpdateDiners,
  });

  final PosWorkspace workspace;
  final PosOrder? activeOrder;
  final bool pickupOrder;
  final bool checkoutOnly;
  final String? fulfillmentTitle;
  final bool busy;
  final VoidCallback onMerge;
  final void Function([PosOrder? targetOrder]) onTransfer;
  final VoidCallback onClear;
  final void Function([PosOrder? targetOrder]) onDiscount;
  final void Function([PosOrder? targetOrder])? onForceCheckout;
  final void Function(PosReceiptPrintType type, [PosOrder? targetOrder])
  onPrintReceipt;
  final VoidCallback? onHang;
  final VoidCallback? onViewMemberHistory;
  final void Function([PosOrder? targetOrder])? onUpdateDiners;

  @override
  Widget build(BuildContext context) {
    final order = workspace.currentOrder!;
    final settled = workspace.table.status == TableStatus.settled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tableTitle =
        fulfillmentTitle ??
        (pickupOrder ? '自提打包' : '${workspace.table.number}号');

    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Table Number & Title
                Row(
                  children: [
                    Text(
                      tableTitle,
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: context.cashier.ink,
                      ),
                    ),
                    if (workspace.isMergedTable) ...[
                      const SizedBox(width: 12),
                      Container(
                        key: const Key('occupied-merged-table-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfffef3c7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xfff59e0b)),
                        ),
                        child: Text(
                          '并台 (${workspace.tableOrders.length}单)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xffb45309),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),

                // 2. Member / Customer Info Summary
                Align(
                  alignment: Alignment.centerLeft,
                  child: pickupOrder
                      ? _MemberSummaryText(
                          prefix: fulfillmentTitle ?? '前台打包',
                          isMember: order.hasRegisteredMember,
                        )
                      : _MemberSummaryText(
                          prefix: '${order.diners}人就餐',
                          isMember: order.hasRegisteredMember,
                          onTap: onViewMemberHistory,
                        ),
                ),
                const SizedBox(height: 18),

                // 3. 2x2 Meta Grid (Opening time, Diners, Elapsed, Operator)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? context.cashier.row
                        : const Color(0xfff8fafc),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? context.cashier.border
                          : const Color(0xffe2e8f0),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MetaItem(
                              label: '开台时间',
                              value: _dateLabel(
                                order.createdAt,
                              ).split(' ').last,
                            ),
                          ),
                          Expanded(
                            child: _MetaItem(
                              label: '就餐人数',
                              value: '${order.diners} 人',
                              onTap: busy || onUpdateDiners == null
                                  ? null
                                  : () => onUpdateDiners!(activeOrder),
                              trailing: onUpdateDiners != null
                                  ? Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: context.cashier.selected,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetaItem(
                              label: '就餐状态',
                              value: settled
                                  ? '待清台'
                                  : (workspace.isMergedTable ? '并台就餐中' : '就餐中'),
                              highlightColor: settled
                                  ? const Color(0xffb91c1c)
                                  : (workspace.isMergedTable
                                        ? const Color(0xffd97706)
                                        : const Color(0xff0284c7)),
                            ),
                          ),
                          const Expanded(
                            child: _MetaItem(label: '服务操作', value: '前台收银'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Billing Summary (精简消费总览，层级清晰，不与右侧结算台重复)
                Builder(
                  builder: (context) {
                    final displayTotal = workspace.isMergedTable
                        ? workspace.tableTotalPayable
                        : order.total;
                    final displayDiscount = workspace.isMergedTable
                        ? workspace.tableTotalDiscount
                        : (order.discountAmount + order.wipeZeroAmount);
                    final gross = order.grossAmount > 0
                        ? order.grossAmount
                        : (displayTotal + displayDiscount);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? context.cashier.row
                            : const Color(0xfff8fafc),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? context.cashier.border
                              : const Color(0xffe2e8f0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '消费总览',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: context.cashier.inkSecondary,
                                    ),
                                  ),
                                  if (workspace.isMergedTable) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfffee2e2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xfffca5a5),
                                        ),
                                      ),
                                      child: const Text(
                                        '整桌统一',
                                        style: TextStyle(
                                          color: Color(0xffb91c1c),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (displayDiscount > 0)
                                Text(
                                  '已优惠 -¥${displayDiscount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff16a34a),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  '原价 ¥${gross.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: context.cashier.inkMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    settled ? '实收 ' : '待付 ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.cashier.inkSecondary,
                                    ),
                                  ),
                                  Text(
                                    '¥${displayTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: _red,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Spacer(),

                // 5. Action Hub (结构化功能中心：桌台流转、账单服务、处置运维)
                if (!pickupOrder) ...[
                  // Cluster A: 桌台流转 (2x2 网格，清晰对称)
                  Row(
                    children: [
                      Expanded(
                        child: _TableActionButton(
                          key: const Key('occupied-merge-button'),
                          label: '并台',
                          icon: Icons.link_rounded,
                          color: isDark
                              ? const Color(0xff1e293b)
                              : const Color(0xffeff6ff),
                          textColor: const Color(0xff2563eb),
                          borderColor: isDark
                              ? const Color(0xff1d4ed8).withValues(alpha: 0.4)
                              : const Color(0xffbfdbfe),
                          onTap: busy ? null : onMerge,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TableActionButton(
                          label: '换台',
                          icon: Icons.swap_horiz_rounded,
                          color: isDark
                              ? const Color(0xff27272a)
                              : const Color(0xfffffbeb),
                          textColor: const Color(0xffd97706),
                          borderColor: isDark
                              ? const Color(0xffb45309).withValues(alpha: 0.4)
                              : const Color(0xfffde68a),
                          onTap: busy ? null : () => onTransfer(activeOrder),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _TableActionButton(
                          key: const Key('occupied-update-diners-button'),
                          label: '修改人数',
                          icon: Icons.people_outline_rounded,
                          color: isDark
                              ? const Color(0xff14532d).withValues(alpha: 0.35)
                              : const Color(0xfff0fdf4),
                          textColor: const Color(0xff16a34a),
                          borderColor: isDark
                              ? const Color(0xff15803d).withValues(alpha: 0.4)
                              : const Color(0xffbbf7d0),
                          onTap: busy || onUpdateDiners == null
                              ? null
                              : () => onUpdateDiners!(activeOrder),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TableActionButton(
                          key: const Key('occupied-hang-button'),
                          label: '挂单',
                          icon: Icons.pause_circle_outline_rounded,
                          color: isDark
                              ? const Color(0xff334155).withValues(alpha: 0.35)
                              : const Color(0xfff8fafc),
                          textColor: const Color(0xff475569),
                          borderColor: isDark
                              ? const Color(0xff475569).withValues(alpha: 0.4)
                              : const Color(0xffcbd5e1),
                          onTap: busy || settled || onHang == null
                              ? null
                              : onHang,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Cluster B: 账单与单据服务 (双按钮并排)
                Row(
                  children: [
                    Expanded(
                      child: _SummaryButton(
                        key: const Key('occupied-discount-button'),
                        label: '整单折扣',
                        icon: Icons.local_offer_outlined,
                        color: const Color(0xffea580c),
                        onTap: busy || settled || checkoutOnly
                            ? null
                            : () => onDiscount(activeOrder),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryButton(
                        key: const Key('occupied-print-button'),
                        label: '打印小票',
                        icon: Icons.print_outlined,
                        color: isDark
                            ? context.cashier.ink
                            : const Color(0xff1e293b),
                        onTap: busy || checkoutOnly
                            ? null
                            : () async {
                                final type = await showPosReceiptPrintDialog(
                                  context,
                                  order: activeOrder ?? order,
                                  settled: settled,
                                );
                                if (type != null) {
                                  onPrintReceipt(type, activeOrder ?? order);
                                }
                              },
                      ),
                    ),
                  ],
                ),

                // Cluster C: 桌面处置与运维操作 (清台 & 强制结账)
                if (!pickupOrder) ...[
                  const SizedBox(height: 10),
                  if (onForceCheckout != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _TableActionButton(
                            label: '清台',
                            icon: Icons.cleaning_services_outlined,
                            color: settled
                                ? const Color(0xffef4444)
                                : (isDark
                                      ? const Color(0xff4c0519).withValues(
                                          alpha: 0.35,
                                        )
                                      : const Color(0xfffff1f2)),
                            textColor: settled
                                ? Colors.white
                                : const Color(0xffe11d48),
                            borderColor: settled
                                ? null
                                : const Color(0xfffecdd3),
                            onTap: busy ? null : onClear,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SummaryButton(
                            key: const Key('occupied-force-checkout-button'),
                            label: '强制结账',
                            icon: Icons.gavel_outlined,
                            color: const Color(0xff991b1b),
                            onTap: busy || settled
                                ? null
                                : () => onForceCheckout!(activeOrder),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _TableActionButton(
                      label: '清台',
                      icon: Icons.cleaning_services_outlined,
                      color: settled
                          ? const Color(0xffef4444)
                          : (isDark
                                ? const Color(0xff4c0519).withValues(
                                    alpha: 0.35,
                                  )
                                : const Color(0xfffff1f2)),
                      textColor: settled
                          ? Colors.white
                          : const Color(0xffe11d48),
                      borderColor: settled ? null : const Color(0xfffecdd3),
                      onTap: busy ? null : onClear,
                    ),
                  ],
                ],
              ],
            ),
          ),

          // 7. Status Ribbon in Top-Right Corner
          Positioned(
            top: 0,
            right: 0,
            child: _StatusRibbon(
              key: const Key('occupied-status-ribbon'),
              label: settled ? '已结账' : '未结账',
              color: settled
                  ? const Color(0xffed5b5d)
                  : const Color(0xff59a0f0),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.label,
    required this.value,
    this.highlightColor,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? highlightColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.cashier.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: highlightColor ?? context.cashier.ink,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: body,
        ),
      );
    }
    return body;
  }
}

class _MemberSummaryText extends StatelessWidget {
  const _MemberSummaryText({
    required this.prefix,
    required this.isMember,
    this.onTap,
  });

  final String prefix;
  final bool isMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!isMember || onTap == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xfff1f5f9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '($prefix-${isMember ? '老肥会员' : '无绑定'})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xff64748b),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '$prefix，老肥会员，查看消费记录',
      child: InkWell(
        key: const Key('occupied-member-history'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xffe0f2fe),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xffbae6fd)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.card_membership,
                size: 18,
                color: Color(0xff0284c7),
              ),
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xff64748b),
                  ),
                  children: [
                    TextSpan(text: '($prefix-'),
                    const TextSpan(
                      text: '老肥会员',
                      style: TextStyle(
                        color: Color(0xff0284c7),
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xff0284c7),
                      ),
                    ),
                    const TextSpan(text: ')'),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '点击查看',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xff0284c7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _RibbonClipper(),
      child: Container(
        key: const Key('occupied-status-ribbon-fill'),
        width: 145,
        height: 130,
        color: color,
        alignment: const Alignment(0.35, -0.35),
        child: Transform.rotate(
          angle: .75,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TableActionButton extends StatelessWidget {
  const _TableActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.borderColor,
    this.icon,
  });

  final String label;
  final Color color;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: icon != null
            ? Icon(icon, size: 18, color: textColor)
            : const SizedBox.shrink(),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          disabledBackgroundColor: color.withValues(alpha: .45),
          disabledForegroundColor: textColor.withValues(alpha: .45),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: borderColor != null
              ? BorderSide(color: borderColor!, width: 1)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SummaryButton extends StatelessWidget {
  const _SummaryButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPrintBtn =
        color == const Color(0xff1e293b) || color == const Color(0xff2d2d2d);
    final bg = isDark && isPrintBtn ? context.cashier.ink : color;
    final fg = isDark && isPrintBtn ? Colors.black : Colors.white;
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: icon != null
            ? Icon(icon, size: 18, color: fg)
            : const SizedBox.shrink(),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: .5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _OrderToolbar extends StatelessWidget {
  const _OrderToolbar({
    required this.orderNo,
    this.tableNumber,
    this.diners,
    this.createdAt,
    this.masterOrderNo,
    this.isMergedSlaveOrder = false,
    this.tableOrders = const [],
    this.selectedOrderIndex,
    this.onSelectOrder,
    this.receivingStatus = '',
    this.kdsOrderStatus = '',
    required this.busy,
    required this.onAddDishes,
    this.onUpdateDiners,
    this.onHang,
    this.onTransfer,
  });

  final String orderNo;
  final String? tableNumber;
  final int? diners;
  final DateTime? createdAt;
  final String? masterOrderNo;
  final bool isMergedSlaveOrder;
  final List<PosOrder> tableOrders;
  final int? selectedOrderIndex;
  final ValueChanged<int?>? onSelectOrder;
  final String receivingStatus;
  final String kdsOrderStatus;
  final bool busy;
  final VoidCallback onAddDishes;
  final VoidCallback? onUpdateDiners;
  final VoidCallback? onHang;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final statusBadge = _buildReceivingBadge(receivingStatus);
    final kdsBadge = _buildKdsBadge(kdsOrderStatus);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tableTitle = (tableNumber != null && tableNumber!.isNotEmpty)
        ? (tableNumber!.endsWith('桌') || tableNumber!.endsWith('号')
            ? tableNumber!
            : '${tableNumber}号桌')
        : '';
    final timeStr = createdAt != null
        ? '${createdAt!.hour.toString().padLeft(2, '0')}:${createdAt!.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      height: 73,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (tableTitle.isNotEmpty) ...[
                    Text(
                      tableTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.cashier.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.cashier.subtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? context.cashier.border
                            : const Color(0xffe2e8f0),
                      ),
                    ),
                    child: Text(
                      '订单编号：$orderNo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: context.cashier.ink,
                      ),
                    ),
                  ),
                  if (timeStr != null || diners != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      '开台时间: ${timeStr ?? '--:--'}${diners != null ? ' · $diners人' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                  if (isMergedSlaveOrder) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfffef3c7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xfff59e0b)),
                      ),
                      child: Text(
                        '并台从单${masterOrderNo != null && masterOrderNo!.isNotEmpty ? " (主单: $masterOrderNo)" : ""}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xffb45309),
                        ),
                      ),
                    ),
                  ] else if (tableOrders.length > 1) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffe0f2fe),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xff0284c7)),
                      ),
                      child: const Text(
                        '主桌主单',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff0369a1),
                        ),
                      ),
                    ),
                  ],
                  if (statusBadge != null) ...[
                    const SizedBox(width: 10),
                    statusBadge,
                  ],
                  if (kdsBadge != null) ...[
                    const SizedBox(width: 10),
                    kdsBadge,
                  ],
                  if (tableOrders.length > 1 && onSelectOrder != null) ...[
                    const SizedBox(width: 12),
                    _OrderFilterChip(
                      label: '全部菜品',
                      selected: selectedOrderIndex == null,
                      onTap: () => onSelectOrder!(null),
                    ),
                    for (var i = 0; i < tableOrders.length; i++) ...[
                      const SizedBox(width: 6),
                      _OrderFilterChip(
                        label: tableOrders[i].isMergedSlaveOrder
                            ? '从单 ${tableOrders[i].orderNo.length > 8 ? tableOrders[i].orderNo.substring(tableOrders[i].orderNo.length - 6) : tableOrders[i].orderNo}'
                            : '主单 ${tableOrders[i].orderNo.length > 8 ? tableOrders[i].orderNo.substring(tableOrders[i].orderNo.length - 6) : tableOrders[i].orderNo}',
                        selected: selectedOrderIndex == i,
                        onTap: () => onSelectOrder!(i),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: busy ? null : onAddDishes,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                '加菜',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildReceivingBadge(String status) {
    final trimmed = status.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final (label, bg, fg) = switch (trimmed) {
      'mis_order' ||
      'pending' ||
      '1' => ('待接单', const Color(0xfffff7e6), const Color(0xffd46b08)),
      'rec_order' ||
      'accepted' ||
      '2' => ('已接单', const Color(0xffe0f2fe), const Color(0xff0284c7)),
      'off_order' ||
      'completed' ||
      '3' => ('已完成', const Color(0xffdcfce7), const Color(0xff15803d)),
      'cancelled' ||
      '4' => ('已取消', const Color(0xfff1f5f9), const Color(0xff64748b)),
      _ => (status, const Color(0xfff0f5ff), const Color(0xff2f54eb)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '接单状态：$label',
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildKdsBadge(String status) {
    final trimmed = status.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final (label, bg, fg) = switch (trimmed) {
      '10' ||
      'pending' ||
      'waiting' ||
      '待制作' ||
      '待下发' => ('待制作', const Color(0xfffff7e6), const Color(0xffd46b08)),
      '20' ||
      'cooking' ||
      'in_progress' ||
      '制作中' => ('制作中', const Color(0xffe0f2fe), const Color(0xff0284c7)),
      '30' ||
      'partially_completed' ||
      'partial' ||
      '部分完成' => ('部分完成', const Color(0xfff3e8ff), const Color(0xff7e22ce)),
      '40' ||
      'completed' ||
      'done' ||
      'ready' ||
      '已完成' ||
      '已出餐' => ('已完成', const Color(0xffdcfce7), const Color(0xff15803d)),
      '90' ||
      'cancelled' ||
      '已取消' => ('已取消', const Color(0xfff1f5f9), const Color(0xff64748b)),
      _ => (status, const Color(0xfff0f5ff), const Color(0xff2f54eb)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '制作状态：$label',
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderLines extends StatelessWidget {
  const _OrderLines({
    this.order,
    required this.lines,
    required this.busy,
    required this.onRefund,
    required this.onGift,
    this.onDiscount,
    this.onPrintReceipt,
  });

  final PosOrder? order;
  final List<PosOrderLine> lines;
  final bool busy;
  final ValueChanged<PosOrderLine> onRefund;
  final ValueChanged<PosOrderLine> onGift;
  final VoidCallback? onDiscount;
  final void Function(PosReceiptPrintType type)? onPrintReceipt;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayLines = List<PosOrderLine>.of(lines);
    if (displayLines.every((line) => line.id > 0)) {
      displayLines.sort((left, right) => left.id.compareTo(right.id));
    }
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (order != null) _BatchCard(order: order!),
          const _OrderHeader(),
          Expanded(
            child: displayLines.isEmpty
                ? Center(
                    child: Text(
                      '暂无菜品明细',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: displayLines.length,
                    itemBuilder: (context, index) {
                      final line = displayLines[index];
                      return _OrderRow(
                        index: index + 1,
                        line: line,
                        shaded: index.isOdd,
                        onRefund:
                            busy || line.isRefunded || line.isComboComponent
                            ? null
                            : () => onRefund(line),
                        onGift:
                            busy ||
                                line.isRefunded ||
                                line.total <= 0 ||
                                line.isComboComponent
                            ? null
                            : () => onGift(line),
                      );
                    },
                  ),
          ),
          _OrderBottomSummary(
            order: order,
            lines: displayLines,
            busy: busy,
            onDiscount: onDiscount,
            onPrintReceipt: onPrintReceipt,
          ),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.order});

  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = order.createdAt != null
        ? '${order.createdAt!.hour.toString().padLeft(2, '0')}:${order.createdAt!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    final (kdsLabel, kdsColor) = switch (order.kdsOrderStatus.trim().toLowerCase()) {
      '40' || 'completed' || 'done' || 'ready' || '已完成' || '已出餐' =>
        ('后厨制作完毕', const Color(0xff16a34a)),
      '20' || 'cooking' || 'in_progress' || '制作中' =>
        ('后厨制作中', const Color(0xff0284c7)),
      '30' || 'partially_completed' || 'partial' || '部分完成' =>
        ('后厨部分制作完成', const Color(0xff7e22ce)),
      '10' || 'pending' || 'waiting' || '待制作' || '待下发' =>
        ('后厨待制作', const Color(0xffd97706)),
      '90' || 'cancelled' || '已取消' =>
        ('后厨已取消', const Color(0xff64748b)),
      _ => (
        order.kdsOrderStatus.isNotEmpty ? order.kdsOrderStatus : '后厨制作完毕',
        const Color(0xff16a34a),
      ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe2e8f0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 15,
                color: context.cashier.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '第 1 批下单 ($timeStr 开台点单) · 已出单',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.cashier.inkSecondary,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: kdsColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                kdsLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kdsColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? context.cashier.row : const Color(0xfff8fafc);
    final headerFg = isDark
        ? context.cashier.inkSecondary
        : const Color(0xff64748b);
    final style = TextStyle(
      color: headerFg,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? context.cashier.border : const Color(0xffe2e8f0),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('菜品名称', style: style),
            ),
          ),
          _OrderCell(width: 80, child: Text('单价', style: style)),
          _OrderCell(width: 70, child: Text('数量', style: style)),
          _OrderCell(width: 90, child: Text('小计', style: style)),
          _OrderCell(width: 95, child: Text('制作状态', style: style)),
          _OrderCell(width: 140, child: Text('操作', style: style)),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.index,
    required this.line,
    required this.shaded,
    required this.onRefund,
    required this.onGift,
  });

  final int index;
  final PosOrderLine line;
  final bool shaded;
  final VoidCallback? onRefund;
  final VoidCallback? onGift;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRefunded = line.isRefunded;
    final rowBg = line.isComboHeader
        ? (isDark
              ? context.cashier.selectedBackground
              : const Color(0xfff8fafc))
        : shaded
        ? (isDark ? context.cashier.row : const Color(0xfffcfcfd))
        : (isDark ? context.cashier.surface : Colors.white);

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? context.cashier.border : const Color(0xfff1f5f9),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          // 1. 菜品名称 (规格备注在后)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (line.isComboComponent) ...[
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 16,
                    color: context.cashier.inkMuted,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          line.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isRefunded
                                ? context.cashier.inkMuted
                                : context.cashier.ink,
                            decoration: isRefunded
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (line.specification.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${line.specification})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isRefunded
                                ? context.cashier.inkMuted
                                : const Color(0xff0284c7),
                            decoration: isRefunded
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (line.isComboHeader) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: context.cashier.warningBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '套餐',
                      style: TextStyle(
                        color: context.cashier.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if (isRefunded) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfffee2e2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已退菜核销',
                      style: TextStyle(
                        color: Color(0xffb91c1c),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 2. 单价 (红色高亮标注)
          _OrderCell(
            width: 80,
            child: Text(
              '¥${line.unitPrice.toStringAsFixed(2)}',
              style: TextStyle(
                color: isRefunded
                    ? context.cashier.inkMuted
                    : const Color(0xffdc2626),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                decoration: isRefunded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          // 3. 数量
          _OrderCell(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xff27272a)
                    : const Color(0xfff1f5f9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark
                      ? context.cashier.border
                      : const Color(0xffe2e8f0),
                ),
              ),
              child: Text(
                '${line.quantity} 份',
                style: TextStyle(
                  color: isRefunded
                      ? context.cashier.inkMuted
                      : context.cashier.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  decoration: isRefunded ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          // 4. 小计 (高对比度粗体)
          _OrderCell(
            width: 90,
            child: Text(
              '¥${line.total.toStringAsFixed(2)}',
              style: TextStyle(
                color: isRefunded
                    ? context.cashier.inkMuted
                    : const Color(0xffb91c1c),
                fontWeight: FontWeight.w800,
                fontSize: 15,
                fontFamily: 'monospace',
                decoration: isRefunded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          // 5. 制作状态
          _OrderCell(
            width: 95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
              decoration: BoxDecoration(
                color: switch (line.productionStatusLabel) {
                  '已出餐' || '已上桌' => const Color(0xffdcfce7),
                  '制作中' => const Color(0xffe0f2fe),
                  '待制作' => const Color(0xfffef3c7),
                  '已退菜' => const Color(0xfffee2e2),
                  _ => const Color(0xfff1f5f9),
                },
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: switch (line.productionStatusLabel) {
                        '已出餐' || '已上桌' => const Color(0xff15803d),
                        '制作中' => const Color(0xff0284c7),
                        '待制作' => const Color(0xffb45309),
                        '已退菜' => const Color(0xffb91c1c),
                        _ => const Color(0xff64748b),
                      },
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      line.productionStatusLabel,
                      key: Key('order-production-${line.id}'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: switch (line.productionStatusLabel) {
                          '已出餐' || '已上桌' => const Color(0xff15803d),
                          '制作中' => const Color(0xff0284c7),
                          '待制作' => const Color(0xffb45309),
                          '已退菜' => const Color(0xffb91c1c),
                          _ => line.productionStatusLabel.startsWith('已出')
                              ? const Color(0xff0958d9)
                              : (isDark
                                    ? context.cashier.inkMuted
                                    : const Color(0xff64748b)),
                        },
                        decoration: isRefunded
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 6. 操作 (退菜 / 赠送)
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  child: TextButton(
                    key: Key('order-gift-${line.id}'),
                    onPressed: onGift,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: isRefunded || onGift == null
                              ? const Color(0xffcbd5e1)
                              : const Color(0xff0284c7),
                        ),
                      ),
                    ),
                    child: Text(
                      line.total <= 0 ? '已赠' : '赠送',
                      style: TextStyle(
                        color: isRefunded || onGift == null
                            ? const Color(0xff94a3b8)
                            : const Color(0xff0284c7),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 32,
                  child: TextButton(
                    key: Key('order-refund-${line.id}'),
                    onPressed: onRefund,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: isRefunded || onRefund == null
                              ? const Color(0xffcbd5e1)
                              : const Color(0xffb91c1c),
                        ),
                      ),
                    ),
                    child: Text(
                      isRefunded
                          ? '已退'
                          : line.isComboComponent
                          ? '随套餐退'
                          : line.isComboHeader
                          ? '退套餐'
                          : '退菜',
                      style: TextStyle(
                        color: isRefunded || onRefund == null
                            ? const Color(0xff94a3b8)
                            : const Color(0xffb91c1c),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderBottomSummary extends StatelessWidget {
  const _OrderBottomSummary({
    this.order,
    required this.lines,
    required this.busy,
    this.onDiscount,
    this.onPrintReceipt,
  });

  final PosOrder? order;
  final List<PosOrderLine> lines;
  final bool busy;
  final VoidCallback? onDiscount;
  final void Function(PosReceiptPrintType type)? onPrintReceipt;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grossAmount = order?.grossAmount ??
        lines.fold<double>(0, (sum, l) => sum + (l.unitPrice * l.quantity));
    final discountAmount = order != null
        ? (order!.discountAmount + order!.wipeZeroAmount)
        : (grossAmount -
                lines.fold<double>(0, (sum, l) => sum + l.total))
            .clamp(0, double.infinity);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        border: Border(
          top: BorderSide(
            color: isDark ? context.cashier.border : const Color(0xffe2e8f0),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '原价总计: ¥${grossAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: context.cashier.inkSecondary,
                ),
              ),
              if (discountAmount > 0) ...[
                const SizedBox(width: 14),
                Text(
                  '优惠减免: -¥${discountAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: Color(0xff16a34a),
                  ),
                ),
              ],
            ],
          ),
          Text(
            '共 ${lines.where((l) => !l.refunded).length} 项菜品',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cashier.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}


class _OrderCell extends StatelessWidget {
  const _OrderCell({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: Center(child: child));
  }
}

class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.order,
    this.isMergedTable = false,
    this.totalPayable,
    this.totalDiscount,
  });

  final PosOrder order;
  final bool isMergedTable;
  final double? totalPayable;
  final double? totalDiscount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final payable = isMergedTable ? (totalPayable ?? order.total) : order.total;
    final discount = isMergedTable
        ? (totalDiscount ?? (order.discountAmount + order.wipeZeroAmount))
        : order.discountAmount;
    final gross = order.grossAmount > 0
        ? order.grossAmount
        : (payable + discount + order.wipeZeroAmount);

    return Container(
      key: const Key('occupied-amount-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '金额明细',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.ink,
                ),
              ),
              if (isMergedTable)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xfffee2e2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xfffca5a5)),
                  ),
                  child: const Text(
                    '整桌统一',
                    style: TextStyle(
                      color: Color(0xffb91c1c),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '原价合计',
                style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
              ),
              Text(
                '¥${gross.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.cashier.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '优惠金额',
                style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
              ),
              Text(
                discount > 0 ? '-¥${discount.toStringAsFixed(2)}' : '¥0.00',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: discount > 0
                      ? const Color(0xffdc2626)
                      : context.cashier.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '抹零金额',
                style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
              ),
              Text(
                order.wipeZeroAmount > 0
                    ? '-¥${order.wipeZeroAmount.toStringAsFixed(2)}'
                    : '¥0.00',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: order.wipeZeroAmount > 0
                      ? const Color(0xffdc2626)
                      : context.cashier.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? context.cashier.border : const Color(0xffe2e8f0),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isMergedTable ? '整桌实收' : '实收金额',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.cashier.ink,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '￥${payable.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: _red,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderFilterChip extends StatelessWidget {
  const _OrderFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff0284c7) : const Color(0xfff1f5f9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xff0284c7) : const Color(0xffe2e8f0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xff475569),
          ),
        ),
      ),
    );
  }
}

class _PaymentBar extends StatefulWidget {
  const _PaymentBar({
    required this.settled,
    required this.busy,
    required this.order,
    this.isMergedTable = false,
    required this.paymentMethods,
    required this.paymentConfigurationAvailable,
    required this.onCheckout,
    required this.onBalanceCheckout,
    this.isDrawerOpen = true,
  });

  final bool settled;
  final bool busy;
  final PosOrder order;
  final bool isMergedTable;
  final List<PosPaymentMethod> paymentMethods;
  final bool paymentConfigurationAvailable;
  final ValueChanged<String> onCheckout;
  final VoidCallback onBalanceCheckout;
  final bool isDrawerOpen;

  @override
  State<_PaymentBar> createState() => _PaymentBarState();
}

class _PaymentBarState extends State<_PaymentBar> {
  String? selectedPayment;

  void _select(String code, VoidCallback callback) {
    setState(() => selectedPayment = code);
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.busy || widget.settled;
    final methods = widget.paymentMethods
        .where(
          (method) =>
              !_isBalanceCode(method.code) &&
              !_isUnsupportedPaymentCode(method.code),
        )
        .toList(growable: false);
    PosPaymentMethod? balanceMethod;
    for (final method in widget.paymentMethods) {
      if (_isBalanceCode(method.code)) {
        balanceMethod = method;
        break;
      }
    }
    final canPayFullyByBalance =
        !widget.isMergedTable &&
        widget.order.canUseStoredValue &&
        (widget.order.memberBalance ?? 0) >= widget.order.total &&
        widget.order.discountAmount <= 0 &&
        widget.order.wipeZeroAmount <= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const Key('occupied-payment-bar'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? context.cashier.border : const Color(0xffe5e5e5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: !widget.paymentConfigurationAvailable
          ? const _PaymentConfigurationError()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 20,
                      color: context.cashier.inkMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '支付方式',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cashier.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (var index = 0; index < methods.length; index++) ...[
                        if (index > 0) const SizedBox(height: 12),
                        SizedBox(
                          key: Key('pay-card-${methods[index].code}'),
                          height: 64,
                          child: _PayButton(
                            label: _paymentDisplayName(methods[index]),
                            iconAsset: _paymentIcon(methods[index].code),
                            iconKey: Key('pay-icon-${methods[index].code}'),
                            labelKey: Key('pay-label-${methods[index].code}'),
                            fillKey: Key('pay-fill-${methods[index].code}'),
                            iconSize: 32,
                            badgeText:
                                methods[index].code == 'cash' &&
                                    !widget.isDrawerOpen
                                ? '未开班'
                                : null,
                            hasWarning:
                                methods[index].code == 'cash' &&
                                !widget.isDrawerOpen,
                            highlighted: selectedPayment == methods[index].code,
                            onTap: disabled
                                ? null
                                : () => _select(
                                    methods[index].code,
                                    () =>
                                        widget.onCheckout(methods[index].code),
                                  ),
                          ),
                        ),
                      ],
                      if (balanceMethod != null && canPayFullyByBalance) ...[
                        if (methods.isNotEmpty) const SizedBox(height: 12),
                        SizedBox(
                          key: const Key('pay-card-balance'),
                          height: 64,
                          child: _PayButton(
                            label: _paymentDisplayName(balanceMethod),
                            iconAsset: null,
                            fallbackIcon: Icons.account_balance_wallet_outlined,
                            iconKey: const Key('pay-icon-balance'),
                            labelKey: const Key('pay-label-balance'),
                            fillKey: const Key('pay-fill-balance'),
                            iconSize: 32,
                            highlighted: selectedPayment == 'balance',
                            onTap: disabled
                                ? null
                                : () => _select(
                                    'balance',
                                    widget.onBalanceCheckout,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PaymentConfigurationError extends StatelessWidget {
  const _PaymentConfigurationError();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payment-configuration-error'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffffeded),
        border: Border.all(color: const Color(0xffdf4d4d)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Color(0xffc83f3f), size: 36),
          SizedBox(height: 12),
          Text(
            '支付配置加载失败，已暂停所有结算操作。请返回桌台页后重试。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xff8e2929),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.label,
    required this.iconAsset,
    required this.iconKey,
    required this.labelKey,
    required this.fillKey,
    required this.iconSize,
    required this.onTap,
    this.highlighted = false,
    this.fallbackIcon,
    this.badgeText,
    this.hasWarning = false,
  });

  final String label;
  final String? iconAsset;
  final Key iconKey;
  final Key labelKey;
  final Key fillKey;
  final double iconSize;
  final IconData? fallbackIcon;
  final VoidCallback? onTap;
  final bool highlighted;
  final String? badgeText;
  final bool hasWarning;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.expand(
      child: Opacity(
        opacity: onTap == null ? .55 : 1,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Ink(
                key: fillKey,
                decoration: BoxDecoration(
                  color: highlighted
                      ? (isDark
                            ? context.cashier.selectedBackground
                            : const Color(0x3858a6ff))
                      : (isDark ? context.cashier.surface : Colors.white),
                  border: Border.all(
                    color: highlighted
                        ? (isDark
                              ? context.cashier.selected
                              : const Color(0xff59a7ff))
                        : (isDark
                              ? context.cashier.border
                              : const Color(0xffe1e1e1)),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: iconKey,
                      width: iconSize,
                      height: iconSize,
                      child: iconAsset == null
                          ? Icon(
                              fallbackIcon ?? Icons.payments_outlined,
                              size: iconSize,
                              color: isDark
                                  ? context.cashier.selected
                                  : const Color(0xff3267d6),
                            )
                          : Image.asset(iconAsset!, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        label,
                        key: labelKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? context.cashier.ink
                              : const Color(0xff2c2c2c),
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeText != null)
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: hasWarning
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                          : const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: hasWarning
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                            : const Color(0xFF0284C7).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasWarning) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          badgeText!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: hasWarning
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ],
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

String? _paymentIcon(String code) =>
    switch (PosPaymentChannelKind.normalize(code)) {
      PosPaymentChannelKind.wechatMicropay ||
      PosPaymentChannelKind.wechatNative ||
      PosPaymentChannelKind.wechat => 'assets/icons/pos/wechat.png',
      PosPaymentChannelKind.alipay => 'assets/icons/pos/alipay.png',
      PosPaymentChannelKind.cash => 'assets/icons/pos/cash.png',
      _ => null,
    };

String _paymentDisplayName(PosPaymentMethod method) {
  if (method.name.trim().isNotEmpty) {
    return method.name;
  }
  final kind = PosPaymentChannelKind.normalize(method.code);
  return switch (kind) {
    PosPaymentChannelKind.wechatMicropay => '微信付款码',
    PosPaymentChannelKind.wechatNative => '微信支付',
    PosPaymentChannelKind.wechat => '微信收款码',
    PosPaymentChannelKind.alipay => '支付宝',
    PosPaymentChannelKind.receivable => '客户挂账',
    _ => method.name,
  };
}

bool _isBalanceCode(String code) =>
    PosPaymentChannelKind.normalize(code) == PosPaymentChannelKind.balance;

bool _isUnsupportedPaymentCode(String code) {
  final value = code.trim().toLowerCase();
  return value == 'free' || value == 'waiver';
}

String _dateLabel(DateTime? value) {
  if (value == null) return '--';
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${value.month}-${value.day} '
      '${two(value.hour)}:${two(value.minute)}';
}
