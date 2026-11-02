import 'dart:async';

import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_components.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_auth_dialog.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../data/table_repository.dart';
import '../domain/dining_table.dart';
import '../domain/takeout_dispatch_alert.dart';
import '../domain/takeout_delivery.dart';
import 'takeout_delivery_panel.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

Future<bool> showFulfillmentOrderDetail({
  required BuildContext context,
  required TableRepository repository,
  required FulfillmentOrder order,
  required bool canUpdate,
  String? defaultAccount,
  Future<bool> Function(FulfillmentOrderDetail detail)? onCheckout,
  Future<CashierManualRefundResult> Function(
    FulfillmentOrder order, {
    double? amount,
    String? reason,
    String? account,
    String? password,
  })? onManualRefund,
  void Function(String orderNo)? onNavigateToBillRefund,
  Stream<TakeoutDispatchAlert>? dispatchAlerts,
}) async {
  bool hasChanged = false;
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭订单详情',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final screenWidth = MediaQuery.sizeOf(dialogContext).width;
      final drawerWidth = screenWidth < 600.0
          ? screenWidth * 0.95
          : (screenWidth * 0.65).clamp(520.0, 720.0);
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: drawerWidth,
          height: double.infinity,
          child: _FulfillmentOrderDetailPage(
            repository: repository,
            order: order,
            canUpdate: canUpdate,
            defaultAccount: defaultAccount,
            onCheckout: onCheckout,
            onManualRefund: onManualRefund,
            onNavigateToBillRefund: onNavigateToBillRefund,
            dispatchAlerts: dispatchAlerts,
            onChanged: () => hasChanged = true,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      );
    },
  );
  return result ?? hasChanged;
}

class _FulfillmentOrderDetailPage extends StatefulWidget {
  const _FulfillmentOrderDetailPage({
    required this.repository,
    required this.order,
    required this.canUpdate,
    this.defaultAccount,
    this.onCheckout,
    this.onManualRefund,
    this.onNavigateToBillRefund,
    this.dispatchAlerts,
    this.onChanged,
  });

  final TableRepository repository;
  final FulfillmentOrder order;
  final bool canUpdate;
  final String? defaultAccount;
  final Future<bool> Function(FulfillmentOrderDetail detail)? onCheckout;
  final Future<CashierManualRefundResult> Function(
    FulfillmentOrder order, {
    double? amount,
    String? reason,
    String? account,
    String? password,
  })? onManualRefund;
  final void Function(String orderNo)? onNavigateToBillRefund;
  final Stream<TakeoutDispatchAlert>? dispatchAlerts;
  final VoidCallback? onChanged;

  @override
  State<_FulfillmentOrderDetailPage> createState() =>
      _FulfillmentOrderDetailPageState();
}

class _FulfillmentOrderDetailPageState
    extends State<_FulfillmentOrderDetailPage> {
  late Future<_FulfillmentDialogData> detailFuture;
  bool updating = false;
  bool changed = false;
  bool refreshingTracking = false;
  Timer? trackingTimer;
  StreamSubscription<TakeoutDispatchAlert>? dispatchAlertSubscription;
  TakeoutDeliverySnapshot? liveDelivery;
  Object? liveDeliveryError;

  @override
  void initState() {
    super.initState();
    detailFuture = _loadData(widget.order);
    dispatchAlertSubscription = widget.dispatchAlerts?.listen((alert) {
      if (alert.orderId != widget.order.id ||
          (!alert.isOrderMissing && !alert.isDispatchChanged)) {
        return;
      }
      unawaited(_refreshTrackingSilently(widget.order));
    });
  }

  @override
  void dispose() {
    trackingTimer?.cancel();
    dispatchAlertSubscription?.cancel();
    super.dispose();
  }

  Future<_FulfillmentDialogData> _loadData(FulfillmentOrder order) async {
    final detail = await widget.repository.loadFulfillmentOrderDetail(order);
    TakeoutDeliverySnapshot? delivery;
    Object? deliveryError;
    final deliveryRepository = widget.repository;
    if (order.type == FulfillmentType.takeout &&
        deliveryRepository is TakeoutDeliveryRepository) {
      try {
        delivery = await (deliveryRepository as TakeoutDeliveryRepository)
            .loadTakeoutDelivery(order);
      } catch (error) {
        // Order details remain usable when the third-party tracking call fails.
        deliveryError = error;
      }
    }
    liveDelivery = delivery;
    liveDeliveryError = deliveryError;
    if (mounted) _scheduleTrackingRefresh(order, delivery);
    return _FulfillmentDialogData(
      detail: detail,
      delivery: delivery,
      deliveryError: deliveryError,
    );
  }

  void _scheduleTrackingRefresh(
    FulfillmentOrder order,
    TakeoutDeliverySnapshot? delivery,
  ) {
    trackingTimer?.cancel();
    final interval = delivery?.trackingRefreshInterval;
    if (interval == null) return;
    trackingTimer = Timer(interval, () {
      if (!mounted) return;
      if (updating) {
        _scheduleTrackingRefresh(order, liveDelivery);
        return;
      }
      unawaited(_refreshTrackingSilently(order));
    });
  }

  Future<void> _refreshTrackingSilently(FulfillmentOrder order) async {
    final repository = widget.repository;
    if (refreshingTracking || repository is! TakeoutDeliveryRepository) return;
    refreshingTracking = true;
    try {
      final next = await (repository as TakeoutDeliveryRepository)
          .loadTakeoutDelivery(order);
      if (!mounted) return;
      if (next != null) {
        setState(() {
          liveDelivery = next;
          liveDeliveryError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => liveDeliveryError = error);
    } finally {
      refreshingTracking = false;
      if (mounted) _scheduleTrackingRefresh(order, liveDelivery);
    }
  }

  Future<void> _update(FulfillmentOrder order, FulfillmentStatus status) async {
    if (updating) return;
    setState(() => updating = true);
    try {
      await widget.repository.updateFulfillmentStatus(order, status);
      changed = true;
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        detailFuture = _loadData(order);
      });
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '订单状态更新失败',
        message: '$error'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> _dispatchRider(
    FulfillmentOrder order, {
    required bool redispatch,
    bool repeatCompleted = false,
  }) async {
    final repository = widget.repository;
    if (updating || repository is! TakeoutDeliveryRepository) return;
    setState(() => updating = true);
    try {
      final delivery = await (repository as TakeoutDeliveryRepository)
          .dispatchTakeoutRider(order, redispatch: redispatch);
      changed = true;
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        liveDelivery = delivery;
        liveDeliveryError = null;
      });
      _scheduleTrackingRefresh(order, delivery);
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: repeatCompleted
            ? '再次配送失败'
            : redispatch
            ? '重新叫骑手失败'
            : '叫骑手失败',
        message: '$error'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> _cancelDelivery(FulfillmentOrder order) async {
    final repository = widget.repository;
    if (updating || repository is! TakeoutDeliveryRepository) return;
    final confirmed = await showPosNotice(
      context,
      title: '取消配送订单',
      message: '取消后骑手将停止配送，平台可能收取责任费用。确定取消当前配送订单吗？',
      tone: PosNoticeTone.warning,
      primaryLabel: '确认取消',
      secondaryLabel: '暂不取消',
    );
    if (!mounted || !confirmed || updating) return;
    setState(() => updating = true);
    try {
      final delivery = await (repository as TakeoutDeliveryRepository)
          .cancelTakeoutDelivery(order);
      changed = true;
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        liveDelivery = delivery;
        liveDeliveryError = null;
      });
      _scheduleTrackingRefresh(order, delivery);
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '取消配送失败',
        message: '$error'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> _checkout(FulfillmentOrderDetail detail) async {
    final checkout = widget.onCheckout;
    if (updating || checkout == null) return;
    setState(() => updating = true);
    try {
      final success = await checkout(detail);
      if (!mounted || !success) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '订单结账失败',
        message: '$error'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> _manualRefund(FulfillmentOrderDetail detail) async {
    final handler = widget.onManualRefund;
    if (updating || handler == null) return;
    final order = detail.order;
    final requested = await showDialog<_ManualRefundRequest>(
      context: context,
      builder: (context) => _ManualRefundDialog(
        orderNo: order.orderNo,
        orderAmount: order.amount,
      ),
    );
    if (!mounted || requested == null) return;

    final auth = await showPosAuthDialog(
      context,
      title: '退款主管授权',
      reason:
          '外卖/自提订单人工退款：金额 ${requested.amount != null ? '¥${requested.amount!.toStringAsFixed(2)}' : '全额'}${requested.reason.isNotEmpty ? '（原因：${requested.reason}）' : ''}',
      warningMessage: '订单退款涉及金额冲减，请由店长或管理员输入账号密码进行二次授权。',
      currentAccount: widget.defaultAccount,
      onVerify: (account, password) => widget.repository.verifyPassword(
        username: account,
        password: password,
      ),
    );
    if (!mounted || auth == null) return;

    setState(() => updating = true);
    try {
      final outcome = await handler(
        order,
        amount: requested.amount,
        reason: requested.reason,
        account: auth.account,
        password: auth.password,
      );
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '人工退款成功',
        message:
            '已退款 ¥${outcome.refundAmount.toStringAsFixed(2)}，累计退款 ¥${outcome.refundTotal.toStringAsFixed(2)}，订单现金剩余 ¥${outcome.cashRemaining.toStringAsFixed(2)}。',
        tone: PosNoticeTone.success,
        primaryLabel: '好的',
      );
      changed = true;
      widget.onChanged?.call();
      if (mounted) {
        setState(() {
          detailFuture = _loadData(order);
        });
      }
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '人工退款失败',
        message: '$error'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  void _jumpToBillRefund(FulfillmentOrderDetail detail) {
    final orderNo = detail.order.orderNo.trim();
    if (orderNo.isEmpty) {
      showPosNotice(
        context,
        title: '无法跳转账单',
        message: '该订单暂无有效订单编号，无法在账单中查找并操作退款。',
        tone: PosNoticeTone.warning,
      );
      return;
    }

    if (widget.onNavigateToBillRefund != null) {
      Navigator.of(context).pop();
      widget.onNavigateToBillRefund!(orderNo);
    } else if (widget.onManualRefund != null) {
      _manualRefund(detail);
    } else {
      showPosNotice(
        context,
        title: '账单退款',
        message: '请前往收银端「账单」页面，搜索订单号 $orderNo 办理退款。',
        tone: PosNoticeTone.info,
      );
    }
  }

  void _close() => Navigator.of(context).pop(changed);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FulfillmentDialogData>(
      future: detailFuture,
      builder: (context, snapshot) {
        final tokens = context.cashier;
        final isLight = Theme.of(context).brightness == Brightness.light;
        final pageColor = isLight ? Colors.white : tokens.surface;
        final data = snapshot.data;
        final detail = data?.detail;
        final delivery = liveDelivery;
        final deliveryError = liveDeliveryError;
        final actions = <Widget>[
          CashierActionButton(
            label: '关闭',
            variant: CashierActionButtonVariant.secondary,
            onPressed: updating ? null : _close,
          ),
          if (detail != null && widget.canUpdate)
            if (detail.order.status == FulfillmentStatus.pendingPayment &&
                widget.onCheckout != null)
              CashierActionButton(
                key: const Key('fulfillment-checkout-button'),
                label: updating ? '结账中' : '结账',
                onPressed: updating ? null : () => _checkout(detail),
              )
            else
              ..._statusActions(
                detail.order,
                delivery,
                deliveryUnavailable: deliveryError != null,
              ),
          if (detail != null &&
              widget.canUpdate &&
              detail.order.status != FulfillmentStatus.pendingPayment)
            CashierActionButton(
              key: const Key('fulfillment-manual-refund-button'),
              label: '去账单退款',
              variant: CashierActionButtonVariant.danger,
              icon: Icons.receipt_long_outlined,
              onPressed: updating ? null : () => _jumpToBillRefund(detail),
            ),
        ];
        return PopScope(
          canPop: !updating,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !updating) _close();
          },
          child: Material(
            elevation: 16,
            color: pageColor,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Scaffold(
              key: const Key('fulfillment-order-detail-page'),
              backgroundColor: pageColor,
              appBar: AppBar(
                backgroundColor: tokens.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(color: tokens.border, height: 1),
                ),
                leading: IconButton(
                  tooltip: '关闭',
                  onPressed: updating ? null : _close,
                  icon: Icon(Icons.close, color: tokens.ink),
                ),
                title: Text(
                  widget.order.type == FulfillmentType.takeout
                      ? '外卖订单明细'
                      : '自提订单明细',
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: switch (snapshot.connectionState) {
                  ConnectionState.waiting => const CashierStateView(
                    state: CashierViewState.loading,
                    title: '正在加载订单',
                    message: '正在读取订单与菜品明细',
                  ),
                  _ when snapshot.hasError => CashierStateView(
                    state: CashierViewState.error,
                    title: '订单加载失败',
                    message: '${snapshot.error}',
                  ),
                  _ => _FulfillmentDetailBody(
                    detail: detail!,
                    delivery: delivery,
                    deliveryError: deliveryError,
                  ),
                },
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: context.cashier.surface,
                  border: Border(
                    top: BorderSide(color: context.cashier.border),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: actions
                            .expand((action) => [const SizedBox(width: 12), action])
                            .skip(1)
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _statusActions(
    FulfillmentOrder order,
    TakeoutDeliverySnapshot? delivery, {
    required bool deliveryUnavailable,
  }) {
    if (order.status == FulfillmentStatus.pendingPayment ||
        (order.status == FulfillmentStatus.completed &&
            order.type != FulfillmentType.takeout)) {
      return const [];
    }
    final receiving = order.receivingStatus.toLowerCase();
    if (receiving.isEmpty ||
        receiving == 'mis_order' ||
        receiving == 'pending') {
      return [
        CashierActionButton(
          label: updating ? '处理中' : '接单',
          onPressed: updating
              ? null
              : () => _update(order, FulfillmentStatus.waiting),
        ),
      ];
    }
    if (order.type == FulfillmentType.takeout) {
      final repository = widget.repository;
      if (repository is TakeoutDeliveryRepository) {
        if (deliveryUnavailable) return const [];
        final retryInitialDispatch = delivery?.canRetryDispatch == true;
        final shouldRedispatch =
            !retryInitialDispatch && delivery?.canRedispatch == true;
        final repeatCompleted = delivery?.isCompleted == true;
        final localStatus = order.dispatchStatus.toLowerCase();
        final canFirstDispatch =
            retryInitialDispatch ||
            (delivery == null
                ? const {'', 'submitted', 'paid'}.contains(localStatus)
                : delivery.delivery.zsqOpenOrderId <= 0 && !shouldRedispatch);
        if (delivery?.canCancel == true) {
          return [
            CashierActionButton(
              key: const Key('takeout-cancel-delivery-button'),
              label: updating ? '取消中' : '取消配送订单',
              variant: CashierActionButtonVariant.danger,
              icon: Icons.cancel_outlined,
              onPressed: updating ? null : () => _cancelDelivery(order),
            ),
          ];
        }
        if (canFirstDispatch || shouldRedispatch) {
          return [
            CashierActionButton(
              key: const Key('takeout-dispatch-rider-button'),
              label: updating
                  ? '叫骑手中'
                  : repeatCompleted
                  ? '再次配送'
                  : shouldRedispatch || retryInitialDispatch
                  ? '重新叫骑手'
                  : '一键叫骑手',
              onPressed: updating
                  ? null
                  : () => _dispatchRider(
                      order,
                      redispatch: shouldRedispatch,
                      repeatCompleted: repeatCompleted,
                    ),
            ),
          ];
        }
      }
      return const [];
    }
    return [
      CashierActionButton(
        label: updating
            ? '处理中'
            : order.type == FulfillmentType.takeout
            ? '完成配送'
            : '完成取餐',
        onPressed: updating
            ? null
            : () => _update(order, FulfillmentStatus.completed),
      ),
    ];
  }
}

class _FulfillmentDetailBody extends StatelessWidget {
  const _FulfillmentDetailBody({
    required this.detail,
    this.delivery,
    this.deliveryError,
  });

  final FulfillmentOrderDetail detail;
  final TakeoutDeliverySnapshot? delivery;
  final Object? deliveryError;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final effectiveRemark = detail.effectiveRemark;
    final detailTableHeight = (58 + detail.lines.length.clamp(1, 5) * 54)
        .toDouble();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoTile(label: '取餐码', value: order.displayCode),
              _InfoTile(
                label: '订单编号',
                value: order.orderNo.isEmpty ? '未返回' : order.orderNo,
                width: 260,
              ),
              _InfoTile(
                label: '订单状态',
                value: order.type == FulfillmentType.takeout && delivery != null
                    ? _deliveryOrderStatusLabel(delivery!)
                    : _statusLabel(order.status),
              ),
              _InfoTile(
                label: '接单状态',
                value: order.type == FulfillmentType.takeout && delivery != null
                    ? delivery!.receivingStatusLabel
                    : _receivingStatusLabel(order.receivingStatus),
              ),
              _InfoTile(
                label: '制作状态',
                value: _kdsOrderStatusLabel(order.kdsOrderStatus),
              ),
              _InfoTile(
                label: '应收金额',
                value: '¥${order.amount.toStringAsFixed(2)}',
                emphasis: true,
              ),
              if (detail.paymentMethod.isNotEmpty)
                _InfoTile(label: '支付方式', value: detail.paymentMethod),
              _InfoTile(
                label: '订单备注',
                value: effectiveRemark.isNotEmpty ? effectiveRemark : '无备注',
                width: 260,
              ),
            ],
          ),
          if (effectiveRemark.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('fulfillment-order-remark-box'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xfffffbeb),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xfffde68a)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: Color(0xffd97706),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '备注说明：',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff92400e),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      effectiveRemark,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff78350f),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '菜品明细',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: detailTableHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: context.cashier.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const _DetailHeader(),
                  Expanded(
                    child: detail.lines.isEmpty
                        ? Center(
                            child: Text(
                              '暂无菜品明细',
                              style: TextStyle(
                                color: context.cashier.inkMuted,
                                fontSize: 18,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: detail.lines.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) => _DetailRow(
                              index: index + 1,
                              line: detail.lines[index],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (order.type == FulfillmentType.takeout) ...[
            const SizedBox(height: 18),
            TakeoutDeliveryPanel(
              snapshot: delivery,
              errorMessage: deliveryError == null
                  ? ''
                  : '$deliveryError'.replaceFirst('Exception: ', ''),
            ),
          ],
        ],
      ),
    );
  }
}

class _FulfillmentDialogData {
  const _FulfillmentDialogData({
    required this.detail,
    this.delivery,
    this.deliveryError,
  });

  final FulfillmentOrderDetail detail;
  final TakeoutDeliverySnapshot? delivery;
  final Object? deliveryError;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    this.width = 180,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final double width;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.subtle,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.inkMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasis ? tokens.danger : tokens.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.cashier.ink,
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: const Row(
        children: [
          const _Cell('序号', flex: 1, light: true),
          const _Cell('菜品', flex: 4, light: true),
          const _Cell('规格', flex: 3, light: true),
          const _Cell('出品状态', flex: 2, light: true),
          const _Cell('单价', flex: 2, light: true),
          const _Cell('数量', flex: 2, light: true),
          const _Cell('小计', flex: 2, light: true),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.index, required this.line});

  final int index;
  final FulfillmentOrderLine line;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRefunded = line.isRefunded;
    final statusColor = switch (line.productionStatusLabel) {
      '已出餐' => const Color(0xff389e0d),
      '制作中' => const Color(0xff1677ff),
      '待制作' => const Color(0xffd46b08),
      '已退菜' => const Color(0xffcf1322),
      _ => line.productionStatusLabel.startsWith('已出')
          ? const Color(0xff0958d9)
          : (isDark ? context.cashier.inkMuted : const Color(0xff999999)),
    };
    final defaultColor = isRefunded
        ? (isDark ? context.cashier.inkMuted : const Color(0xff999999))
        : null;
    final decoration = isRefunded ? TextDecoration.lineThrough : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          _Cell('$index', flex: 1, color: defaultColor, decoration: decoration),
          _Cell(line.name, flex: 4, bold: true, color: defaultColor, decoration: decoration),
          _Cell(line.specification.isEmpty ? '-' : line.specification, flex: 3, color: defaultColor, decoration: decoration),
          _Cell(line.productionStatusLabel, flex: 2, bold: true, color: statusColor, decoration: decoration),
          _Cell('¥${line.unitPrice.toStringAsFixed(2)}', flex: 2, color: defaultColor, decoration: decoration),
          _Cell('${line.quantity}', flex: 2, color: defaultColor, decoration: decoration),
          _Cell('¥${line.totalPrice.toStringAsFixed(2)}', flex: 2, bold: true, color: defaultColor, decoration: decoration),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.flex,
    this.bold = false,
    this.light = false,
    this.color,
    this.decoration,
  });

  final String text;
  final int flex;
  final bool bold;
  final bool light;
  final Color? color;
  final TextDecoration? decoration;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: light ? Colors.white : (color ?? context.cashier.ink),
        fontSize: 16,
        fontWeight: bold || light ? FontWeight.w800 : FontWeight.w500,
        decoration: decoration,
      ),
    ),
  );
}

String _statusLabel(FulfillmentStatus status) => switch (status) {
  FulfillmentStatus.pendingPayment => '待结账',
  FulfillmentStatus.waiting => '待取餐',
  FulfillmentStatus.delivering => '配送中',
  FulfillmentStatus.completed => '已完成',
};

String _deliveryOrderStatusLabel(TakeoutDeliverySnapshot snapshot) {
  final phase = snapshot.effectivePhase;
  if (phase == 'DELIVERED' ||
      (!snapshot.hasAuthoritativeTrackingState &&
          snapshot.delivery.dispatchStatus == 'completed')) {
    return '已完成';
  }
  if (phase == 'TO_SHOP' ||
      phase == 'TO_USER' ||
      (!snapshot.hasAuthoritativeTrackingState &&
          snapshot.delivery.dispatchStatus == 'delivering')) {
    return '配送中';
  }
  if (phase == 'CANCELLED' ||
      (!snapshot.hasAuthoritativeTrackingState &&
          snapshot.delivery.dispatchStatus == 'cancelled')) {
    return '已取消';
  }
  if (snapshot.canRedispatch) return '配送异常';
  return '待配送';
}

String _receivingStatusLabel(String status) {
  final trimmed = status.trim().toLowerCase();
  return switch (trimmed) {
    'mis_order' || 'pending' || '1' => '待接单',
    'rec_order' || 'accepted' || '2' => '已接单',
    'off_order' || 'completed' || '3' => '已完成',
    'cancelled' || '4' => '已取消',
    _ => status.isEmpty ? '待接单' : status,
  };
}

String _kdsOrderStatusLabel(String status) {
  final trimmed = status.trim().toLowerCase();
  return switch (trimmed) {
    '10' || 'pending' || 'waiting' => '待制作',
    '20' || 'cooking' || 'in_progress' => '制作中',
    '30' || 'partially_completed' || 'partial' => '部分完成',
    '40' || 'completed' || 'done' || 'ready' => '已完成',
    '90' || 'cancelled' => '已取消',
    _ => trimmed.isEmpty ? '—' : status.trim(),
  };
}

String _refundYuan(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

class _ManualRefundRequest {
  const _ManualRefundRequest({this.amount, required this.reason});

  final double? amount;
  final String reason;
}

class _ManualRefundDialog extends StatefulWidget {
  const _ManualRefundDialog({
    required this.orderNo,
    required this.orderAmount,
  });

  final String orderNo;
  final num orderAmount;

  @override
  State<_ManualRefundDialog> createState() => _ManualRefundDialogState();
}

class _ManualRefundDialogState extends State<_ManualRefundDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _amountController.text.trim();
    double? amount;
    if (raw.isNotEmpty) {
      final parsed = double.tryParse(raw);
      if (parsed == null || parsed <= 0) {
        setState(() => _amountError = '请输入大于 0 的金额');
        return;
      }
      amount = parsed;
    }
    Navigator.of(context).pop(_ManualRefundRequest(
      amount: amount,
      reason: _reasonController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('人工退款（现金）'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '订单号：${widget.orderNo}'
              '\n订单金额：¥${_refundYuan(widget.orderAmount.toDouble())}',
              style: const TextStyle(fontSize: 14, color: Color(0xff6b6b6b)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '退款金额（元）',
                hintText: '留空 = 退现金剩余全部',
                errorText: _amountError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: '退款备注（可选）',
                hintText: '例如：现金退款、收银员xxx',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '仅退回现金渠道剩余金额；纯微信/纯余额订单请勿在此操作。',
              style: TextStyle(fontSize: 12, color: Color(0xff8d8d8d)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确认退款'),
        ),
      ],
    );
  }
}

/// 外卖与自提履约调度抽屉弹窗 (UI061 Prototype Modal 10: Fulfillment Takeout Drawer)
Future<void> showFulfillmentDispatchDialog({
  required BuildContext context,
  required TableRepository repository,
  required bool canUpdate,
  String? defaultAccount,
  Future<bool> Function(FulfillmentOrderDetail detail)? onCheckout,
  Future<CashierManualRefundResult> Function(
    FulfillmentOrder order, {
    double? amount,
    String? reason,
    String? account,
    String? password,
  })? onManualRefund,
  void Function(String orderNo)? onNavigateToBillRefund,
  Stream<TakeoutDispatchAlert>? dispatchAlerts,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _FulfillmentDispatchDialog(
      repository: repository,
      canUpdate: canUpdate,
      defaultAccount: defaultAccount,
      onCheckout: onCheckout,
      onManualRefund: onManualRefund,
      onNavigateToBillRefund: onNavigateToBillRefund,
      dispatchAlerts: dispatchAlerts,
    ),
  );
}

class _FulfillmentDispatchDialog extends StatefulWidget {
  const _FulfillmentDispatchDialog({
    required this.repository,
    required this.canUpdate,
    this.defaultAccount,
    this.onCheckout,
    this.onManualRefund,
    this.onNavigateToBillRefund,
    this.dispatchAlerts,
  });

  final TableRepository repository;
  final bool canUpdate;
  final String? defaultAccount;
  final Future<bool> Function(FulfillmentOrderDetail detail)? onCheckout;
  final Future<CashierManualRefundResult> Function(
    FulfillmentOrder order, {
    double? amount,
    String? reason,
    String? account,
    String? password,
  })? onManualRefund;
  final void Function(String orderNo)? onNavigateToBillRefund;
  final Stream<TakeoutDispatchAlert>? dispatchAlerts;

  @override
  State<_FulfillmentDispatchDialog> createState() =>
      _FulfillmentDispatchDialogState();
}

enum _TypeFilter {
  all('全部'),
  takeout('外卖'),
  pickup('自提');

  const _TypeFilter(this.label);
  final String label;
}

enum _StatusFilter {
  all('全部状态'),
  active('待处理'),
  completed('已完成');

  const _StatusFilter(this.label);
  final String label;
}

class _FulfillmentDispatchDialogState
    extends State<_FulfillmentDispatchDialog> {
  bool _loading = true;
  String? _error;
  List<FulfillmentOrder> _allOrders = const [];
  int _operatingOrderId = -1;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final overview = await widget.repository.loadTableOverview();
      if (!mounted) return;
      final combined = [
        ...overview.takeoutOrders,
        ...overview.pickupOrders,
      ];
      // 活跃订单在前，其次按创建时间倒序排列
      combined.sort((a, b) {
        if (a.status.isActive != b.status.isActive) {
          return a.status.isActive ? -1 : 1;
        }
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime != null && bTime != null) {
          return bTime.compareTo(aTime);
        }
        return b.id.compareTo(a.id);
      });
      setState(() {
        _allOrders = combined;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<FulfillmentOrder> get _filteredOrders {
    return _allOrders.where((order) {
      if (_typeFilter == _TypeFilter.takeout &&
          order.type != FulfillmentType.takeout) {
        return false;
      }
      if (_typeFilter == _TypeFilter.pickup &&
          order.type != FulfillmentType.pickup) {
        return false;
      }
      if (_statusFilter == _StatusFilter.active && !order.status.isActive) {
        return false;
      }
      if (_statusFilter == _StatusFilter.completed &&
          order.status != FulfillmentStatus.completed) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _takeoutCount =>
      _allOrders.where((o) => o.type == FulfillmentType.takeout).length;

  int get _pickupCount =>
      _allOrders.where((o) => o.type == FulfillmentType.pickup).length;

  int get _activeCount => _allOrders.where((o) => o.status.isActive).length;

  int get _completedCount =>
      _allOrders.where((o) => o.status == FulfillmentStatus.completed).length;

  int get _pendingTakeoutRiderCount => _allOrders
      .where((o) =>
          o.type == FulfillmentType.takeout &&
          o.status.isActive &&
          o.status != FulfillmentStatus.delivering)
      .length;

  void _updateOrderInMemory(FulfillmentOrder updated) {
    final index = _allOrders.indexWhere((o) => o.id == updated.id);
    if (index >= 0) {
      _allOrders[index] = updated;
    }
  }

  /// 一键叫骑手
  Future<void> _handleDispatchRider(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    setState(() => _operatingOrderId = order.id);
    try {
      final repo = widget.repository;
      final isDelivering = order.status == FulfillmentStatus.delivering;
        if (repo is TakeoutDeliveryRepository) {
        await (repo as TakeoutDeliveryRepository).dispatchTakeoutRider(
          order,
          redispatch: isDelivering,
        );
      } else {
        await widget.repository.updateFulfillmentStatus(
          order,
          FulfillmentStatus.delivering,
        );
      }
      _updateOrderInMemory(FulfillmentOrder(
        id: order.id,
        type: order.type,
        status: FulfillmentStatus.delivering,
        pickupCode: order.pickupCode,
        orderNo: order.orderNo,
        tableNumber: order.tableNumber,
        amount: order.amount,
        receivingStatus: order.receivingStatus,
        kdsOrderStatus: order.kdsOrderStatus,
        dispatchStatus: 'delivering',
        createdAt: order.createdAt,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已一键呼叫聚合配送骑手！[#${order.displayCode}]'),
            backgroundColor: const Color(0xFF0284C7),
          ),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '叫骑手失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 取消骑手配送
  Future<void> _handleCancelDelivery(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    final confirmed = await showPosNotice(
      context,
      title: '取消配送确认',
      message: '确定要取消外卖单 [#${order.displayCode}] 的骑手配送吗？\n取消后可重新呼叫骑手。',
      primaryLabel: '确认取消配送',
      secondaryLabel: '暂不取消',
      tone: PosNoticeTone.warning,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _operatingOrderId = order.id);
    try {
      final repo = widget.repository;
      if (repo is TakeoutDeliveryRepository) {
        await (repo as TakeoutDeliveryRepository).cancelTakeoutDelivery(order);
      } else {
        await widget.repository.updateFulfillmentStatus(
          order,
          FulfillmentStatus.waiting,
        );
      }
      _updateOrderInMemory(FulfillmentOrder(
        id: order.id,
        type: order.type,
        status: FulfillmentStatus.waiting,
        pickupCode: order.pickupCode,
        orderNo: order.orderNo,
        tableNumber: order.tableNumber,
        amount: order.amount,
        receivingStatus: order.receivingStatus,
        kdsOrderStatus: order.kdsOrderStatus,
        dispatchStatus: 'cancelled',
        createdAt: order.createdAt,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消外卖配送订单！[#${order.displayCode}]'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '取消配送失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 快捷完成外卖配送
  Future<void> _handleCompleteTakeout(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    final confirmed = await showPosNotice(
      context,
      title: '完成配送确认',
      message: '确定外卖单 [#${order.displayCode}] 已送达并完成吗？',
      primaryLabel: '确认完成',
      secondaryLabel: '取消',
      tone: PosNoticeTone.info,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _operatingOrderId = order.id);
    try {
      await widget.repository.updateFulfillmentStatus(
        order,
        FulfillmentStatus.completed,
      );
      _updateOrderInMemory(FulfillmentOrder(
        id: order.id,
        type: order.type,
        status: FulfillmentStatus.completed,
        pickupCode: order.pickupCode,
        orderNo: order.orderNo,
        tableNumber: order.tableNumber,
        amount: order.amount,
        receivingStatus: order.receivingStatus,
        kdsOrderStatus: order.kdsOrderStatus,
        dispatchStatus: 'completed',
        createdAt: order.createdAt,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('外卖订单已完成配送！[#${order.displayCode}]'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '更新状态失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 一键呼叫所有待配骑手
  Future<void> _handleBatchDispatchRiders() async {
    final pendingOrders = _allOrders
        .where((o) =>
            o.type == FulfillmentType.takeout &&
            o.status.isActive &&
            o.status != FulfillmentStatus.delivering)
        .toList();
    if (pendingOrders.isEmpty) return;
    if (_operatingOrderId >= 0) return;
    setState(() => _operatingOrderId = 999999);
    int successCount = 0;
    try {
      final repo = widget.repository;
      for (final order in pendingOrders) {
        try {
          if (repo is TakeoutDeliveryRepository) {
            await (repo as TakeoutDeliveryRepository).dispatchTakeoutRider(order);
          } else {
            await widget.repository.updateFulfillmentStatus(
              order,
              FulfillmentStatus.delivering,
            );
          }
          successCount++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已为 $successCount 笔外卖订单成功一键呼叫骑手！'),
            backgroundColor: const Color(0xFF0284C7),
          ),
        );
      }
      await _loadOrders();
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 自提提醒
  Future<void> _handlePickupRemind(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    setState(() => _operatingOrderId = order.id);
    try {
      final receiving = order.receivingStatus.toLowerCase();
      if (order.status == FulfillmentStatus.pendingPayment ||
          receiving == 'pending' ||
          receiving == 'mis_order') {
        await widget.repository.updateFulfillmentStatus(
          order,
          FulfillmentStatus.waiting,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已向顾客发送到店自提提醒通知！（取餐码：#${order.displayCode}）'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '提醒发送失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 完成自提取餐
  Future<void> _handlePickupComplete(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    setState(() => _operatingOrderId = order.id);
    try {
      await widget.repository.updateFulfillmentStatus(
        order,
        FulfillmentStatus.completed,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自提订单已完成核销交付！[#${order.displayCode}]')),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '核销失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 接单出票
  Future<void> _handleAcceptOrder(FulfillmentOrder order) async {
    if (_operatingOrderId >= 0) return;
    setState(() => _operatingOrderId = order.id);
    try {
      await widget.repository.updateFulfillmentStatus(
        order,
        FulfillmentStatus.waiting,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已接单并自动出票送往后厨！[#${order.displayCode}]')),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '接单失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _operatingOrderId = -1);
      }
    }
  }

  /// 打开订单详情
  Future<void> _openOrderDetail(FulfillmentOrder order) async {
    final changed = await showFulfillmentOrderDetail(
      context: context,
      repository: widget.repository,
      order: order,
      canUpdate: widget.canUpdate,
      defaultAccount: widget.defaultAccount,
      onCheckout: widget.onCheckout,
      onManualRefund: widget.onManualRefund,
      onNavigateToBillRefund: (orderNo) {
        Navigator.of(context).pop();
        widget.onNavigateToBillRefund?.call(orderNo);
      },
      dispatchAlerts: widget.dispatchAlerts,
    );
    if (changed && mounted) {
      _loadOrders();
    }
  }

  Widget _buildChannelBadge(FulfillmentOrder order, CashierTokens tokens) {
    final isTakeout = order.type == FulfillmentType.takeout;
    final color = isTakeout ? const Color(0xFF0284C7) : const Color(0xFF059669);
    final icon = isTakeout ? Icons.moped_rounded : Icons.shopping_bag_outlined;
    final label = isTakeout ? '外卖' : '自提';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(FulfillmentOrder order, CashierTokens tokens) {
    final isTakeout = order.type == FulfillmentType.takeout;
    final receiving = order.receivingStatus.toLowerCase();
    final isPendingReceipt = receiving.isEmpty ||
        receiving == 'mis_order' ||
        receiving == 'pending';

    String label;
    Color bg;
    Color text;
    IconData icon;

    final dispatchLower = order.dispatchStatus.toLowerCase();
    final isFailed = dispatchLower == 'failed' || dispatchLower == 'dispatch_failed';
    final isCancelled = dispatchLower == 'cancelled' || dispatchLower == 'rider_cancelled';
    final isDeliveryActive = !isFailed &&
        !isCancelled &&
        (order.status == FulfillmentStatus.delivering ||
            const {
              'dispatched',
              'delivering',
              'waiting_rider',
              'to_shop',
              'to_user',
            }.contains(dispatchLower));

    if (order.status == FulfillmentStatus.completed) {
      label = isTakeout ? '已完成' : '已取餐';
      bg = tokens.inkMuted.withValues(alpha: 0.12);
      text = tokens.inkMuted;
      icon = Icons.check_circle_outline_rounded;
    } else if (isTakeout && isFailed) {
      label = '叫骑手失败';
      bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      text = const Color(0xFFDC2626);
      icon = Icons.error_outline_rounded;
    } else if (isTakeout && isCancelled) {
      label = '配送已取消';
      bg = tokens.inkMuted.withValues(alpha: 0.15);
      text = tokens.inkMuted;
      icon = Icons.cancel_outlined;
    } else if (isTakeout && isDeliveryActive) {
      label = switch (dispatchLower) {
        'waiting_rider' => '等待骑手接单',
        'to_shop' => '骑手已到店',
        _ => '骑手配送中',
      };
      bg = const Color(0xFFF97316).withValues(alpha: 0.15);
      text = const Color(0xFFEA580C);
      icon = Icons.moped_rounded;
    } else if (order.status == FulfillmentStatus.waiting) {
      if (isTakeout) {
        label = '制作中/待叫骑手';
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
        text = const Color(0xFF2563EB);
        icon = Icons.soup_kitchen_rounded;
      } else {
        label = '待到店取餐';
        bg = const Color(0xFF10B981).withValues(alpha: 0.15);
        text = const Color(0xFF059669);
        icon = Icons.storefront_rounded;
      }
    } else if (isPendingReceipt) {
      label = '新单待确认';
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      text = const Color(0xFFD97706);
      icon = Icons.fiber_new_rounded;
    } else {
      label = _statusLabel(order.status);
      bg = tokens.subtle;
      text = tokens.ink;
      icon = Icons.receipt_long_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    FulfillmentOrder order,
    CashierTokens tokens,
    bool isBusy,
  ) {
    final isTakeout = order.type == FulfillmentType.takeout;
    final receiving = order.receivingStatus.toLowerCase();
    final isPendingReceipt = receiving.isEmpty ||
        receiving == 'mis_order' ||
        receiving == 'pending';
    final isCompleted = order.status == FulfillmentStatus.completed;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 详情按钮
        OutlinedButton(
          key: Key('btn-order-detail-${order.id}'),
          onPressed: isBusy ? null : () => _openOrderDetail(order),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            side: BorderSide(color: tokens.border),
            foregroundColor: tokens.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('详情', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),

        if (isTakeout) ...[
          // 新单可接单出票
          if (isPendingReceipt && !isCompleted) ...[
            OutlinedButton(
              key: Key('btn-accept-order-${order.id}'),
              onPressed: isBusy ? null : () => _handleAcceptOrder(order),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                side: BorderSide(color: tokens.border),
                foregroundColor: tokens.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                '接单出票',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // 根据外卖状态动态展示不同操作按钮
          if (isCompleted)
            Text(
              '已结单',
              style: TextStyle(color: tokens.inkMuted, fontSize: 12),
            )
          else ...[
            () {
              final dispatchLower = order.dispatchStatus.toLowerCase();
              final isFailed = dispatchLower == 'failed' || dispatchLower == 'dispatch_failed';
              final isCancelled = dispatchLower == 'cancelled' || dispatchLower == 'rider_cancelled';
              final isDeliveryActive = !isFailed &&
                  !isCancelled &&
                  (order.status == FulfillmentStatus.delivering ||
                      const {
                        'dispatched',
                        'delivering',
                        'waiting_rider',
                        'to_shop',
                        'to_user',
                      }.contains(dispatchLower));

              if (isDeliveryActive) {
                // 已叫骑手/配送中 -> 变成【取消配送】按钮，并辅以【完成配送】
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      key: Key('btn-cancel-delivery-${order.id}'),
                      onPressed: isBusy ? null : () => _handleCancelDelivery(order),
                      icon: isBusy && _operatingOrderId == order.id
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cancel_outlined, size: 15),
                      label: const Text(
                        '取消配送',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: Key('btn-complete-delivery-${order.id}'),
                      onPressed: isBusy ? null : () => _handleCompleteTakeout(order),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        side: const BorderSide(color: Color(0xFF059669)),
                        foregroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        '完成配送',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                );
              }

              // 未叫骑手 / 配送取消 / 配送失败 -> 呼叫骑手
              final shouldRedispatch = isFailed || isCancelled;
              return FilledButton.icon(
                key: Key('btn-dispatch-rider-${order.id}'),
                onPressed: isBusy ? null : () => _handleDispatchRider(order),
                icon: isBusy && _operatingOrderId == order.id
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.moped_rounded, size: 15),
                label: Text(
                  shouldRedispatch ? '重新叫骑手' : '一键叫骑手',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.btnPrimaryBg,
                  foregroundColor: tokens.btnPrimaryInk,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }(),
          ],
        ] else ...[
          // 自提订单
          if (!isCompleted) ...[
            // 自提提醒按钮
            FilledButton.icon(
              key: Key('btn-pickup-remind-${order.id}'),
              onPressed: isBusy ? null : () => _handlePickupRemind(order),
              icon: isBusy && _operatingOrderId == order.id
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.notifications_active_rounded, size: 15),
              label: const Text(
                '自提提醒',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 完成取餐按钮
            OutlinedButton(
              key: Key('btn-pickup-complete-${order.id}'),
              onPressed: isBusy ? null : () => _handlePickupComplete(order),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                side: BorderSide(color: tokens.border),
                foregroundColor: tokens.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                '完成取餐',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ] else
            Text(
              '已取餐',
              style: TextStyle(color: tokens.inkMuted, fontSize: 12),
            ),
        ],
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final filtered = _filteredOrders;
    final totalCount = _allOrders.length;
    final pendingCount = _activeCount;

    return CashierDialogFrame(
      width: 760,
      height: 650,
      compact: true,
      title: '🛵 履约外卖 ($pendingCount)',
      subtitle: '共 $totalCount 笔订单 · $pendingCount 笔未完成',
      onClose: () => Navigator.of(context).pop(),
      actions: [
        CashierActionButton(
          label: '关闭',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // Type Filter Segment
                Wrap(
                  spacing: 6,
                  children: _TypeFilter.values.map((f) {
                    final selected = _typeFilter == f;
                    final count = switch (f) {
                      _TypeFilter.all => _allOrders.length,
                      _TypeFilter.takeout => _takeoutCount,
                      _TypeFilter.pickup => _pickupCount,
                    };
                    return ChoiceChip(
                      label: Text('${f.label} ($count)'),
                      selected: selected,
                      onSelected: (_) => setState(() => _typeFilter = f),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? tokens.btnPrimaryInk : tokens.ink,
                      ),
                      selectedColor: tokens.btnPrimaryBg,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: selected ? Colors.transparent : tokens.border,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                // Status Filter Segment
                Wrap(
                  spacing: 6,
                  children: _StatusFilter.values.map((f) {
                    final selected = _statusFilter == f;
                    final count = switch (f) {
                      _StatusFilter.all => _allOrders.length,
                      _StatusFilter.active => _activeCount,
                      _StatusFilter.completed => _completedCount,
                    };
                    return ChoiceChip(
                      label: Text('${f.label} ($count)'),
                      selected: selected,
                      onSelected: (_) => setState(() => _statusFilter = f),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? tokens.btnPrimaryInk : tokens.ink,
                      ),
                      selectedColor: tokens.btnPrimaryBg,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: selected ? Colors.transparent : tokens.border,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                // Batch call & Refresh
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pendingTakeoutRiderCount > 0) ...[
                      FilledButton.icon(
                        onPressed: _operatingOrderId >= 0
                            ? null
                            : _handleBatchDispatchRiders,
                        icon: const Icon(Icons.rocket_launch_rounded, size: 14),
                        label: Text(
                          '一键呼叫待配骑手 ($_pendingTakeoutRiderCount)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    IconButton(
                      tooltip: '刷新订单',
                      onPressed: _loading ? null : _loadOrders,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Order List Content
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: TextStyle(color: tokens.danger)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadOrders,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: tokens.inkMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '暂无符合条件的外卖或自提订单',
                      style: TextStyle(
                        color: tokens.inkMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (int i = 0; i < filtered.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _buildOrderCard(
                filtered[i],
                tokens,
                _operatingOrderId == filtered[i].id,
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildOrderCard(
    FulfillmentOrder order,
    CashierTokens tokens,
    bool isBusy,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: tokens.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildChannelBadge(order, tokens),
                    const SizedBox(width: 8),
                    Text(
                      '#${order.displayCode}',
                      style: TextStyle(
                        color: tokens.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(order, tokens),
                    const Spacer(),
                    Text(
                      '¥${order.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: tokens.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '单号: ${order.orderNo.isEmpty ? "未生成" : order.orderNo}',
                      style: TextStyle(
                        color: tokens.inkMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    if (order.createdAt != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: tokens.inkMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _formatTime(order.createdAt!),
                        style: TextStyle(
                          color: tokens.inkMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (order.tableNumber.isNotEmpty &&
                        order.tableNumber != '0') ...[
                      const SizedBox(width: 12),
                      Text(
                        '桌号: ${order.tableNumber}',
                        style: TextStyle(
                          color: tokens.inkMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
                if (order.remark.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.edit_note_rounded,
                        size: 13,
                        color: Color(0xffd97706),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '备注: ${order.remark}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xffd97706),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Right Action Buttons
          _buildActionButtons(order, tokens, isBusy),
        ],
      ),
    );
  }
}

