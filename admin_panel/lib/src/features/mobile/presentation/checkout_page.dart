import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cashier_member/data/real_cashier_member_repository.dart';
import '../../cashier_member/domain/cashier_member.dart';
import '../../pos/domain/pos_models.dart';
import '../../tables/domain/dining_table.dart';
import '../data/api_providers.dart';
import '../data/cart_state.dart';
import '../data/cart_storage.dart';
import '../data/idempotency.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key, required this.table});

  final DiningTable table;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  String _paymentMethod = '现金';
  bool _busy = false;
  String? _error;
  bool _queued = false;
  String? _createdOrderNo;
  CashierMember? _member;

  static const _methods = ['现金', '扫码', '会员余额', '线下收款'];

  Future<void> _submit() async {
    if (_busy) return;
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty) return;
    if (_paymentMethod == '会员余额') {
      final member = _member;
      if (member == null || !member.hasOpenid) {
        setState(() => _error = '请先识别会员（需绑定微信）');
        return;
      }
      if (member.balance < cart.total) {
        setState(
          () => _error = '会员余额不足（¥${member.balance.toStringAsFixed(2)}）',
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _queued = false;
      _createdOrderNo = null;
    });
    final repo = ref.read(posRepositoryProvider);
    // X-Client-Request-Id：弱网重试沿用同键，后端 24h 幂等回放（v1.2.172）。
    final requestId = IdempotencyKey.next('quickOrder');
    PosSubmissionResult? submittedOrder;
    try {
      submittedOrder = await repo.submitOrder(
        tableNumber: widget.table.number,
        diners: widget.table.people,
        remark: '',
        lines: cart.lines,
        clientRequestId: requestId,
      );
      if (_paymentMethod == '会员余额') {
        final member = _member!;
        await ref
            .read(posBalanceCheckoutProvider)
            .checkoutByBalance(
              orderNo: submittedOrder.orderNo,
              openid: member.openid!,
              memberPhone: member.phone,
            );
      } else {
        await repo.checkout(
          orderNo: submittedOrder.orderNo,
          paymentMethod: _paymentMethod,
          cashAmount: _paymentMethod == '现金' ? cart.total : null,
        );
      }
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已结账 ¥${cart.total.toStringAsFixed(2)}')),
      );
    } catch (error) {
      // 409 = 幂等键误用/业务冲突：直接展示后端 msg，不换键重试（指南 §8）。
      final isConflict = '$error'.contains('409');
      final offline = !isConflict && _isNetworkError(error);
      final createdOrder = submittedOrder;
      if (createdOrder != null) {
        ref.read(cartProvider.notifier).clear();
        if (mounted) {
          setState(() {
            _createdOrderNo = createdOrder.orderNo;
            _error = offline
                ? '订单 ${createdOrder.orderNo} 已创建，但支付结果未知。请到订单列表核对，勿重复收款。'
                : '订单 ${createdOrder.orderNo} 已创建，但结账未完成：$error。请到订单列表处理。';
          });
        }
      } else if (offline) {
        await _queuePending(cart, requestId);
        if (mounted) {
          setState(() => _queued = true);
          ref.read(cartProvider.notifier).clear();
        }
      } else {
        if (mounted) setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isNetworkError(Object error) {
    final text = '$error';
    return error is SocketException ||
        text.contains('SocketException') ||
        text.contains('TimeoutException') ||
        text.contains('请求超时') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection');
  }

  Future<void> _queuePending(cart, String clientRequestId) async {
    final storage = ref.read(cartStorageProvider);
    final pending = await storage.readPending();
    await storage.savePending([
      ...pending,
      PendingOrder.forCheckout(
        clientRequestId: clientRequestId,
        tableNumber: widget.table.number,
        diners: widget.table.people,
        remark: '',
        lines: cart.lines,
        paymentMethod: _paymentMethod,
        createdAt: DateTime.now(),
      ),
    ]);
  }

  Future<void> _rechargeMember() async {
    final member = _member;
    if (member == null) return;
    final amountController = TextEditingController();
    final giftController = TextEditingController(text: '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('会员充值 · ${member.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: '充值本金（≥50）',
                prefixText: '¥',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: giftController,
              decoration: const InputDecoration(
                labelText: '赠送金额',
                prefixText: '¥',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认充值'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final gift = double.tryParse(giftController.text.trim()) ?? 0;
    if (amount < 50) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('充值本金不得低于 50 元')));
      return;
    }
    try {
      await RealCashierMemberRepository(
        ref.read(apiClientProvider),
      ).recharge(phone: member.phone, amount: amount, giftAmount: gift);
      // 刷新余额。
      final profile = await RealCashierMemberRepository(
        ref.read(apiClientProvider),
      ).loadProfile(member.phone);
      if (mounted) setState(() => _member = profile.member);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('充值成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('充值失败：$error')));
      }
    }
  }

  Future<void> _lookupMember() async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('识别会员'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '手机号'),
          keyboardType: TextInputType.phone,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('查询'),
          ),
        ],
      ),
    );
    if (phone == null || phone.isEmpty || !mounted) return;
    try {
      final profile = await RealCashierMemberRepository(
        ref.read(apiClientProvider),
      ).loadProfile(phone);
      setState(() => _member = profile.member);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到该手机号的会员')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: Text('下单并结账 · ${widget.table.number}')),
      body: ListView(
        padding: MobileMetrics.pagePadding.copyWith(
          top: MobileMetrics.spaceLg,
          bottom: MobileMetrics.spaceLg,
        ),
        children: [
          if (_queued)
            Container(
              margin: const EdgeInsets.only(bottom: MobileMetrics.cardGap),
              padding: MobileMetrics.cardPaddingCompact,
              decoration: BoxDecoration(
                color: context.palette.warningBg,
                borderRadius: MobileMetrics.controlRadius,
              ),
              child: Text(
                '网络异常，订单已暂存；恢复网络后只会创建待支付订单，支付需人工核对后完成',
                style: TextStyle(color: context.palette.warning, fontSize: 13),
              ),
            ),
          Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('订单金额', style: context.bodySecondaryStyle),
                      AmountText(cart.total),
                    ],
                  ),
                  const Divider(height: MobileMetrics.space2xl),
                  ...cart.lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: MobileMetrics.spaceXs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.dish.name,
                              style: MobileTypography.body,
                            ),
                          ),
                          Text(
                            '×${line.quantity}',
                            style: context.bodySecondaryStyle,
                          ),
                          const SizedBox(width: MobileMetrics.spaceLg),
                          AmountText(line.total, style: MobileTypography.body),
                        ],
                      ),
                    ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '会员（可选）',
                        style: context.bodySecondaryStyle,
                      ),
                      TextButton(
                        onPressed: _lookupMember,
                        child: Text(_member == null ? '识别会员' : '重新识别'),
                      ),
                    ],
                  ),
                  if (_member != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: MobileMetrics.spaceXs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${_member!.name} · ${_member!.phone}',
                              style: MobileTypography.body,
                            ),
                          ),
                          Text(
                            '余额 ¥${_member!.balance.toStringAsFixed(2)}',
                            style: MobileTypography.label.copyWith(
                              color: context.palette.success,
                            ),
                          ),
                          TextButton(
                            onPressed: _rechargeMember,
                            child: const Text('充值'),
                          ),
                        ],
                      ),
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
                  Text('支付方式', style: context.bodySecondaryStyle),
                  const SizedBox(height: MobileMetrics.cardGap),
                  Wrap(
                    spacing: MobileMetrics.spaceMd,
                    children: _methods.map((method) {
                      final selected = _paymentMethod == method;
                      return ChoiceChip(
                        label: Text(method),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _paymentMethod = method),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: MobileMetrics.cardGap),
            Container(
              padding: MobileMetrics.cardPaddingCompact,
              decoration: BoxDecoration(
                color: context.palette.dangerBg,
                borderRadius: MobileMetrics.controlRadius,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: context.palette.danger,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
          ),
          onPressed: _busy || cart.lines.isEmpty || _createdOrderNo != null
              ? null
              : _submit,
          child: _busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.textPrimary,
                  ),
                )
              : Text(
                  _createdOrderNo == null
                      ? '确认收款 ¥${cart.total.toStringAsFixed(2)}'
                      : '请先核对订单 $_createdOrderNo',
                ),
        ),
      ),
    );
  }
}
