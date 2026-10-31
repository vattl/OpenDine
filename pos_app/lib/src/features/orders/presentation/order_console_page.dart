import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/formatters.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../../cashier_settings/presentation/cashier_receipt_preview_dialog.dart';
import '../../cashier_shell/presentation/cashier_approval_dialog.dart';
import '../data/order_repository.dart';
import '../domain/admin_order.dart';
import '../domain/order_query.dart';

class OrderConsolePage extends StatefulWidget {
  const OrderConsolePage({
    super.key,
    required this.appState,
    required this.repository,
    required this.approvalRepository,
  });

  final AppState appState;
  final OrderRepository repository;

  /// 权限中心审批仓库：删除订单等敏感操作统一走店长现场授权。
  final AccessApprovalRepository approvalRepository;

  @override
  State<OrderConsolePage> createState() => _OrderConsolePageState();
}

class _OrderConsolePageState extends State<OrderConsolePage> {
  final keywordController = TextEditingController();
  OrderQuery query = const OrderQuery();
  PagedOrders? page;
  String? error;
  bool loading = false;
  int? busyOrderId;

  static const statusOptions = <_StatusFilter>[
    _StatusFilter(label: '全部订单', value: null),
    _StatusFilter(label: '未结账', value: 'unsettled'),
    _StatusFilter(label: '已结账', value: 'success'),
    _StatusFilter(label: '已取消', value: 'cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrderConsolePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      query = const OrderQuery();
      keywordController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    keywordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null) {
      setState(() {
        error = '当前账号没有可访问门店，无法查询订单';
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.repository.listOrders(query, shopId: shopId);
      if (mounted) {
        setState(() {
          page = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _search() {
    query = query.copyWith(pageNum: 1, keyword: keywordController.text);
    _load();
  }

  void _setStatus(String? status) {
    query = query.copyWith(pageNum: 1, status: status);
    _load();
  }

  void _turnPage(int delta) {
    final next = query.pageNum + delta;
    if (next < 1) return;
    query = query.copyWith(pageNum: next);
    _load();
  }

  Future<void> _openDetail(AdminOrder order) async {
    setState(() => busyOrderId = order.id);
    AdminOrder detail;
    try {
      detail = await widget.repository.loadOrderDetails(order);
    } catch (e) {
      if (!mounted) return;
      setState(() => busyOrderId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('订单详情加载失败：$e')));
      return;
    }
    if (!mounted) return;
    setState(() => busyOrderId = null);
    final changed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭订单详情',
      barrierColor: Colors.black.withValues(alpha: .28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: _OrderDetailDrawer(
            initialOrder: detail,
            repository: widget.repository,
            appState: widget.appState,
            approvalRepository: widget.approvalRepository,
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = page;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Header(
            todayCount: data?.todayCount ?? 0,
            total: data?.total ?? 0,
            pageNum: query.pageNum,
            shopName: widget.appState.currentShop?.name ?? '未选择门店',
            loading: loading,
          ),
          const SizedBox(height: 12),
          _FilterBar(
            keywordController: keywordController,
            status: query.status,
            statusOptions: statusOptions,
            onSearch: _search,
            onStatusChanged: _setStatus,
            onRefresh: _load,
          ),
          const SizedBox(height: 12),
          if (error != null) _ErrorPanel(message: error!, onRetry: _load),
          if (error == null && data == null)
            const _LoadingPanel()
          else if (error == null && data != null && data.orders.isEmpty)
            const _EmptyPanel()
          else if (error == null && data != null) ...[
            _OrderTable(
              orders: data.orders,
              busyOrderId: busyOrderId,
              onDetail: _openDetail,
            ),
            const SizedBox(height: 12),
            _Pager(
              pageNum: query.pageNum,
              pageSize: query.pageSize,
              total: data.total,
              onPrevious: loading ? null : () => _turnPage(-1),
              onNext: loading ? null : () => _turnPage(1),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.todayCount,
    required this.total,
    required this.pageNum,
    required this.shopName,
    required this.loading,
  });

  final int todayCount;
  final int total;
  final int pageNum;
  final String shopName;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffd92121), Color(0xffffbf2f)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '订单管理工作台',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$shopName · 点击订单行查看费用、用户、菜品与售后操作',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          _MetricPill(label: '今日订单', value: '$todayCount'),
          _MetricPill(label: '筛选结果', value: '$total'),
          _MetricPill(label: '当前页', value: '$pageNum'),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff7c2d12))),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xff9a1414),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.keywordController,
    required this.status,
    required this.statusOptions,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onRefresh,
  });

  final TextEditingController keywordController;
  final String? status;
  final List<_StatusFilter> statusOptions;
  final VoidCallback onSearch;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: keywordController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: const InputDecoration(
                  labelText: '订单号 / 桌台 / 手机号',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            for (final option in statusOptions)
              ChoiceChip(
                label: Text(option.label),
                selected: status == option.value,
                onSelected: (_) => onStatusChanged(option.value),
              ),
            FilledButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.manage_search),
              label: const Text('查询'),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTable extends StatelessWidget {
  const _OrderTable({
    required this.orders,
    required this.busyOrderId,
    required this.onDetail,
  });

  final List<AdminOrder> orders;
  final int? busyOrderId;
  final ValueChanged<AdminOrder> onDetail;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xfffff3d0)),
          columns: const [
            DataColumn(label: Text('订单')),
            DataColumn(label: Text('就餐类型')),
            DataColumn(label: Text('取餐码')),
            DataColumn(label: Text('桌台')),
            DataColumn(label: Text('金额')),
            DataColumn(label: Text('接单')),
            DataColumn(label: Text('厨显')),
            DataColumn(label: Text('找零')),
            DataColumn(label: Text('时间')),
            DataColumn(label: Text('操作')),
          ],
          rows: [
            for (final order in orders)
              DataRow(
                onSelectChanged: (_) => onDetail(order),
                cells: [
                  DataCell(_SizedText(dash(order.orderNo), width: 168)),
                  DataCell(_OrderTypeBadge(order: order)),
                  DataCell(_PickupCodeBadge(order: order)),
                  DataCell(Text(dash(order.tableNumber))),
                  DataCell(
                    _SizedText(money(order.totalAmount), width: 86, bold: true),
                  ),
                  DataCell(
                    _StatusBadge(
                      text: _receivingLabel(order.receivingStatus),
                      raw: order.receivingStatus,
                    ),
                  ),
                  DataCell(
                    _StatusBadge(
                      text: _kdsLabel(order.kdsOrderStatus),
                      raw: order.kdsOrderStatus,
                    ),
                  ),
                  DataCell(
                    _SizedText(money(order.checkoutChangeAmount), width: 82),
                  ),
                  DataCell(_SizedText(dash(order.createdAt), width: 142)),
                  DataCell(
                    busyOrderId == order.id
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => onDetail(order),
                            child: const Text('明细'),
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

class _OrderDetailDrawer extends StatefulWidget {
  const _OrderDetailDrawer({
    required this.initialOrder,
    required this.repository,
    required this.appState,
    required this.approvalRepository,
  });

  final AdminOrder initialOrder;
  final OrderRepository repository;
  final AppState appState;
  final AccessApprovalRepository approvalRepository;

  @override
  State<_OrderDetailDrawer> createState() => _OrderDetailDrawerState();
}

class _OrderDetailDrawerState extends State<_OrderDetailDrawer> {
  late AdminOrder order = widget.initialOrder;
  bool loading = false;
  bool changed = false;

  bool get canOperate => widget.appState.hasPermission('order:operate');
  bool get canKds => widget.appState.hasPermission('kds:config');
  bool get canDelete => widget.appState.hasPermission('order:delete');
  bool get canRefund => widget.appState.hasPermission('order:operate');
  int get shopId => widget.appState.currentShopId ?? 0;

  Future<void> _reload() async {
    setState(() => loading = true);
    try {
      final next = await widget.repository.loadOrderDetails(order);
      if (mounted) setState(() => order = next);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    setState(() => loading = true);
    try {
      await action();
      changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _printReceipt() async {
    await _run('打印小票请求已发送', () async {
      await widget.repository.printReceipt(order);
    });
  }

  Future<void> _previewReceipt() async {
    await showCashierReceiptPreviewDialog(
      context: context,
      orderId: order.id > 0 ? order.id : null,
      orderNo: order.orderNo,
      initialScenario: ReceiptTemplateScenario.standardReceipt,
      onFetchPreview: (scenario, paperSize, customContent) async {
        return await widget.repository.fetchPrintPreview(
          scenario: scenario.code,
          orderId: order.id > 0 ? order.id : null,
          orderNo: order.orderNo,
          paperSize: paperSize,
        );
      },
      onExecutePrint: () async {
        await _printReceipt();
      },
    );
  }

  Future<void> _reprintKitchen() async {
    await _run('厨房小票补打请求已发送', () async {
      await widget.repository.reprintKitchenTicket(order);
    });
  }

  Future<void> _repushKds() async {
    await _run('KDS 重推已提交', () async {
      await widget.repository.repushKdsTicket(order);
    });
  }

  Future<void> _refundLine(OrderLine line) async {
    final yes = await _confirm('退菜', '确定将「${line.name}」标记为已退菜并回退库存吗？');
    if (yes != true) return;
    await _run('退菜已提交', () => widget.repository.refundLine(line));
  }

  Future<void> _changeQuantity(OrderLine line) async {
    final controller = TextEditingController(text: '${line.quantity}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改数量：${line.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '新数量'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 1 || value == line.quantity) return;
    await _run(
      '菜品数量已更新',
      () => widget.repository.updateLineQuantity(line, value),
    );
  }

  Future<void> _wechatRefund() async {
    final amount = order.paidAmount <= 0 ? order.totalAmount : order.paidAmount;
    final amountController = TextEditingController(
      text: amount.toStringAsFixed(2),
    );
    final reasonController = TextEditingController(text: '后台手动退款');
    final payload = await showDialog<({double amount, String reason})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('微信退款'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '退款金额'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: '退款原因'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(amountController.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(context, (
                amount: parsed,
                reason: reasonController.text,
              ));
            },
            child: const Text('提交退款'),
          ),
        ],
      ),
    );
    amountController.dispose();
    reasonController.dispose();
    if (payload == null) return;
    await _run(
      '退款请求已提交',
      () => widget.repository.refundWechat(
        order,
        amount: payload.amount,
        reason: payload.reason,
      ),
    );
  }

  Future<void> _showTakeout() async {
    try {
      final data = await widget.repository.loadTakeoutDelivery(order);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('外卖配送详情'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(data),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('配送详情加载失败：$e')));
    }
  }

  Future<void> _deleteOrder() async {
    final yes = await _confirm('删除订单', '删除后不可恢复。确定删除订单 ${order.orderNo} 吗？');
    if (yes != true) return;
    // 统一审批授权：删除订单仅允许超级管理员，首次执行返回"缺少现场授权"，
    // 自动唤起店长授权弹窗，获取一次性审批令牌后携带 approvalToken 重试。
    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '删除订单审批',
        permission: 'order:delete',
        permissionLabel: '删除订单',
        bizType: 'ORDER',
        bizId: order.orderNo,
        amount: order.totalAmount,
        reason: '删除订单记录（删除后不可恢复）',
        requiredRoles: '仅超级管理员可授权删除订单',
      ),
      execute: (approvalToken) => widget.repository.deleteOrder(
        order,
        approvalToken: approvalToken,
      ),
    );
    if (!executed || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('订单已删除')));
    await _reload();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showPhoneHistory() async {
    final phone = order.user?.phone ?? '';
    if (phone.isEmpty || shopId <= 0) return;
    try {
      final page = await widget.repository.loadPhoneHistory(
        phone,
        shopId: shopId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$phone 的历史订单'),
          content: SizedBox(
            width: 720,
            child: page.orders.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('暂无历史订单')),
                  )
                : SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('订单号')),
                        DataColumn(label: Text('金额')),
                        DataColumn(label: Text('状态')),
                        DataColumn(label: Text('时间')),
                      ],
                      rows: [
                        for (final item in page.orders)
                          DataRow(
                            cells: [
                              DataCell(Text(item.orderNo)),
                              DataCell(Text(money(item.totalAmount))),
                              DataCell(Text(_payStatusLabel(item.payStatus))),
                              DataCell(Text(item.createdAt)),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('历史订单加载失败：$e')));
    }
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = order.user;
    final userPhone = user?.phone ?? '';
    return Material(
      color: Colors.white,
      elevation: 18,
      child: SizedBox(
        width: 820,
        height: double.infinity,
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '订单详情 ${order.orderNo}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, changed),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: '费用明细',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MoneyTile(label: '实付金额', value: order.paidAmount),
                        _MoneyTile(label: '商品金额', value: order.goodsAmount),
                        _MoneyTile(label: '优惠金额', value: order.discountAmount),
                        _MoneyTile(label: '配送费', value: order.deliveryFee),
                        _MoneyTile(label: '服务费', value: order.serviceFee),
                        _MoneyTile(label: '已退金额', value: order.refundAmount),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: '订单详情',
                    child: _InfoGrid(
                      items: {
                        '订单号': order.orderNo,
                        '取餐码': '${order.id}',
                        '台号': dash(order.tableNumber),
                        '就餐类型': dash(order.orderType),
                        '下单次数': order.orderNumber <= 0
                            ? '-'
                            : '${order.orderNumber}',
                        '结账状态': _payStatusLabel(order.payStatus),
                        '接单状态': _receivingLabel(order.receivingStatus),
                        '下单时间': dash(order.createdAt),
                        '结账时间': dash(order.payTime),
                        '支付方式': dash(order.paymentMethod),
                        '备注': dash(order.remark),
                      },
                    ),
                  ),
                  _SectionCard(
                    title: '用户信息',
                    child: _InfoGrid(
                      items: {
                        '昵称': dash(user?.nickname),
                        '手机号': userPhone.isNotEmpty ? userPhone : '-',
                        '余额': money(user?.balance ?? 0),
                        '本金余额': money(user?.principalBalance ?? 0),
                        '赠送余额': money(user?.giftBalance ?? 0),
                        '积分': '${user?.points ?? 0}',
                        '累计消费': money(user?.consumeAmount ?? 0),
                        'openid': dash(order.openid),
                      },
                      actionLabel: userPhone.isNotEmpty ? '查历史订单' : null,
                      onAction: userPhone.isNotEmpty ? _showPhoneHistory : null,
                    ),
                  ),
                  _SectionCard(
                    title: '菜品明细',
                    child: _LineTable(
                      lines: order.lines,
                      canOperate: canOperate && order.isUnsettled,
                      onRefund: _refundLine,
                      onQuantity: _changeQuantity,
                    ),
                  ),
                  _SectionCard(
                    title: '其他操作',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _printReceipt,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('打印小票'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _previewReceipt,
                          icon: const Icon(Icons.preview_outlined),
                          label: const Text('预览小票'),
                        ),
                        OutlinedButton.icon(
                          onPressed: canOperate ? _reprintKitchen : null,
                          icon: const Icon(Icons.kitchen_outlined),
                          label: Text(
                            canOperate ? '补打厨房小票' : '补打厨房小票（需 order:operate）',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: canKds ? _repushKds : null,
                          icon: const Icon(Icons.monitor_outlined),
                          label: Text(
                            canKds ? '重推 KDS' : '重推 KDS（需 kds:config）',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: canRefund && order.canWechatRefund
                              ? _wechatRefund
                              : null,
                          icon: const Icon(Icons.currency_yen_outlined),
                          label: Text(
                            canRefund ? '微信退款' : '微信退款（需 order:operate）',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: order.isTakeout ? _showTakeout : null,
                          icon: const Icon(Icons.delivery_dining_outlined),
                          label: const Text('外卖配送'),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xffdc2626),
                          ),
                          onPressed: canDelete ? _deleteOrder : null,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            canDelete ? '删除订单' : '删除订单（需 order:delete）',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (loading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: .45),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineTable extends StatelessWidget {
  const _LineTable({
    required this.lines,
    required this.canOperate,
    required this.onRefund,
    required this.onQuantity,
  });

  final List<OrderLine> lines;
  final bool canOperate;
  final ValueChanged<OrderLine> onRefund;
  final ValueChanged<OrderLine> onQuantity;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const Text('暂无菜品明细');
    return Column(
      children: [
        for (final line in lines) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF8),
              border: Border.all(color: const Color(0xFFF3E0D4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFE2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      line.orderRound <= 0 ? '-' : '第${line.orderRound}次',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8A3E22),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(_lineStatusLabel(line.lineStatus)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _MetaText('规格', _formatSpec(line.specification)),
                            _MetaText('数量', '${line.quantity}${line.unit}'),
                            _MetaText('小计', money(line.totalPrice)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 142,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton(
                          onPressed: canOperate && line.refundable
                              ? () => onQuantity(line)
                              : null,
                          child: const Text('改数量'),
                        ),
                        FilledButton.tonal(
                          onPressed: canOperate && line.refundable
                              ? () => onRefund(line)
                              : null,
                          child: const Text('退菜'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF17803D),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label：',
        style: TextStyle(color: Colors.grey.shade600),
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFF2F261F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  const _MoneyTile({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfffff7ed),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff9a3412))),
          const SizedBox(height: 6),
          Text(
            money(value),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items, this.actionLabel, this.onAction});

  final Map<String, String> items;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final item in items.entries)
              SizedBox(
                width: 230,
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: '${item.key}：',
                        style: const TextStyle(color: Color(0xff64748b)),
                      ),
                      TextSpan(text: item.value),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.history_outlined),
            label: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _SizedText extends StatelessWidget {
  const _SizedText(this.text, {required this.width, this.bold = false});

  final String text;
  final double width;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null,
      ),
    );
  }
}

class _OrderTypeBadge extends StatelessWidget {
  const _OrderTypeBadge({required this.order});

  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final type = dash(order.orderType);
    final highlighted = order.needsPickupCodeHighlight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFE7D6) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFFB923C)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: highlighted
              ? const Color(0xFFC2410C)
              : const Color(0xFF475569),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PickupCodeBadge extends StatelessWidget {
  const _PickupCodeBadge({required this.order});

  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final highlighted = order.needsPickupCodeHighlight;
    return Container(
      width: highlighted ? 96 : 76,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFB91C1C) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF7F1D1D)
              : const Color(0xFFFED7AA),
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x22991B1B),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          if (highlighted) ...[
            const Icon(
              Icons.confirmation_number,
              size: 15,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '${order.id}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlighted ? Colors.white : const Color(0xFF7C2D12),
              fontSize: highlighted ? 18 : 15,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.raw});

  final String text;
  final String raw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _statusColor(raw).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: _statusColor(raw), fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String status) {
    if (status.contains('cancel') ||
        status.contains('refund') ||
        status == '90') {
      return const Color(0xff64748b);
    }
    if (status.contains('complete') ||
        status.contains('done') ||
        status == '40' ||
        status == 'off_order') {
      return const Color(0xff16a34a);
    }
    if (status.contains('cook') ||
        status.contains('accept') ||
        status == '20' ||
        status == 'rec_order') {
      return const Color(0xfff97316);
    }
    return const Color(0xffdc2626);
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.pageNum,
    required this.pageSize,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageNum;
  final int pageSize;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final hasNext = total == 0 ? false : pageNum * pageSize < total;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('第 $pageNum 页 · 每页 $pageSize 条 · 共 $total 条'),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: pageNum <= 1 ? null : onPrevious,
          child: const Text('上一页'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: hasNext ? onNext : null,
          child: const Text('下一页'),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('订单加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('没有匹配订单，换个状态或关键词再试。')),
      ),
    );
  }
}

class _StatusFilter {
  const _StatusFilter({required this.label, required this.value});

  final String label;
  final String? value;
}

String _receivingLabel(String status) {
  return switch (status) {
    'mis_order' => '待接单',
    'rec_order' => '已接单',
    'off_order' => '已完成',
    'cancelled' => '已取消',
    _ => dash(status),
  };
}

String _payStatusLabel(String status) {
  return switch (status) {
    'unsettled' => '未结账',
    'success' => '已结账',
    'cancelled' => '已取消',
    _ => dash(status),
  };
}

String _kdsLabel(String status) {
  return switch (status) {
    '10' => '待下发',
    '20' => '制作中',
    '30' => '部分完成',
    '40' => '已完成',
    '90' => '已取消',
    'cooking' => '制作中',
    'completed' => '已完成',
    'cancelled' => '已取消',
    _ => dash(status),
  };
}

String _lineStatusLabel(String status) {
  return switch (status) {
    '' => '正常',
    'normal' => '正常',
    'refunded' => '已退菜',
    'void' => '已作废',
    _ => dash(status),
  };
}

String _formatSpec(String raw) {
  if (raw.trim().isEmpty) return '-';
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(' / ');
    }
  } catch (_) {}
  return raw;
}
