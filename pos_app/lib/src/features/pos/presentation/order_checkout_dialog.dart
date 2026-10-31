import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../domain/pos_models.dart';

const _checkoutInk = Color(0xff2d2d2d);
const _checkoutBlue = Color(0xff238af2);
const _checkoutRed = Color(0xffe65353);

enum OfflineCollectionDialogResult {
  manualConfirm,
  autoSettled,
}

class OfflineCollectionCheckoutDialog extends StatefulWidget {
  const OfflineCollectionCheckoutDialog({
    super.key,
    required this.amount,
    required this.channel,
    required this.channelLabel,
    required this.loadQr,
    this.checkSettled,
  });

  final double amount;
  final String channel;
  final String channelLabel;
  final Future<PosOfflineCollectionQr> Function() loadQr;
  final Future<bool> Function()? checkSettled;

  @override
  State<OfflineCollectionCheckoutDialog> createState() =>
      _OfflineCollectionCheckoutDialogState();
}

class _OfflineCollectionCheckoutDialogState
    extends State<OfflineCollectionCheckoutDialog> {
  static const int _confirmGuardSeconds = 3;

  PosOfflineCollectionQr? qr;
  Object? error;
  bool loading = true;
  int remainingSeconds = 0;
  int guardSeconds = 0;
  Timer? timer;
  Timer? _guardTimer;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    _guardTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    timer?.cancel();
    _guardTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      loading = true;
      error = null;
      qr = null;
      remainingSeconds = 0;
      guardSeconds = 0;
    });
    try {
      final value = await widget.loadQr();
      if (!mounted) return;
      setState(() {
        qr = value;
        loading = false;
        remainingSeconds = value.expiresInSeconds;
        guardSeconds = _confirmGuardSeconds;
      });
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || remainingSeconds <= 1) {
          timer.cancel();
          _pollTimer?.cancel();
          if (mounted) setState(() => remainingSeconds = 0);
          return;
        }
        setState(() => remainingSeconds -= 1);
      });
      _guardTimer = Timer.periodic(const Duration(seconds: 1), (guardTimer) {
        if (!mounted || guardSeconds <= 1) {
          guardTimer.cancel();
          if (mounted) setState(() => guardSeconds = 0);
          return;
        }
        setState(() => guardSeconds -= 1);
      });
      if (widget.checkSettled != null) {
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          if (!mounted) {
            _pollTimer?.cancel();
            return;
          }
          if (remainingSeconds <= 0) {
            _pollTimer?.cancel();
            return;
          }
          if (_polling) return;
          _polling = true;
          try {
            final isSettled = await widget.checkSettled!();
            if (!mounted) return;
            if (isSettled) {
              timer?.cancel();
              _guardTimer?.cancel();
              _pollTimer?.cancel();
              Navigator.of(context).pop(OfflineCollectionDialogResult.autoSettled);
            }
          } catch (_) {
          } finally {
            _polling = false;
          }
        });
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = qr != null && remainingSeconds > 0;
    return _CheckoutFrame(
      dialogKey: const Key('offline-collection-checkout-dialog'),
      title: '${widget.channelLabel}收款',
      width: 760,
      height: 790,
      body: Column(
        children: [
          const Text(
            '本单应收',
            style: TextStyle(color: Color(0xff777777), fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            '¥${widget.amount.toStringAsFixed(2)}',
            key: const Key('offline-collection-amount'),
            style: const TextStyle(
              color: _checkoutRed,
              fontSize: 52,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildQrState()),
          const SizedBox(height: 14),
          Text(
            ready
                ? '收款码 ${_timeLabel(remainingSeconds)} 后失效'
                : remainingSeconds == 0 && qr != null
                ? '收款码已失效，请刷新'
                : '正在准备收款码',
            style: TextStyle(
              color: ready ? const Color(0xff777777) : _checkoutRed,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '请顾客使用对应 App 扫码并输入应收金额，到账后再确认收款',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff555555), fontSize: 17),
          ),
        ],
      ),
      primaryKey: const Key('offline-collection-confirm'),
      primaryLabel: guardSeconds > 0
          ? '正在检测支付状态 ${guardSeconds}S'
          : '确认已收款',
      primaryChild: guardSeconds > 0
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '正在检测支付状态 ${guardSeconds}S',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            )
          : null,
      primaryEnabled: ready && guardSeconds <= 0,
      onPrimary: () => Navigator.of(context).pop(OfflineCollectionDialogResult.manualConfirm),
    );
  }

  Widget _buildQrState() {
    if (loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _checkoutBlue),
            SizedBox(height: 18),
            Text('正在生成临时收款码', style: TextStyle(fontSize: 20)),
          ],
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 82, color: _checkoutRed),
            const SizedBox(height: 14),
            const Text(
              '收款码加载失败',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff777777), fontSize: 16),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              key: const Key('offline-collection-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重新获取'),
            ),
          ],
        ),
      );
    }
    final bytes = _decodeQr(qr?.qrImageBase64 ?? '');
    return Center(
      child: Container(
        key: const Key('offline-collection-qr'),
        width: 310,
        height: 310,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffd7d7d7)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: bytes == null
            ? const Icon(Icons.broken_image_outlined, size: 90)
            : Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 90),
              ),
      ),
    );
  }
}

class BalanceCheckoutDialog extends StatelessWidget {
  const BalanceCheckoutDialog({
    super.key,
    required this.order,
    required this.chargeAmount,
  });

  final PosOrder order;
  final double chargeAmount;

  @override
  Widget build(BuildContext context) {
    final balance = order.memberBalance ?? 0;
    final remaining = balance - chargeAmount;
    final hasDiscount = order.discountAmount > 0 || order.wipeZeroAmount > 0;
    final enough = order.canUseStoredValue && remaining >= 0 && !hasDiscount;
    return _CheckoutFrame(
      dialogKey: const Key('balance-checkout-dialog'),
      title: '储值划扣',
      width: 720,
      height: 690,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xffe8f3ff),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _checkoutBlue,
                  size: 40,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '老肥会员',
                      style: TextStyle(
                        color: _checkoutInk,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskPhone(order.memberPhone),
                      style: const TextStyle(
                        color: Color(0xff777777),
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              _BalanceMetric(label: '当前余额', value: balance),
            ],
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xfff5f5f5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _BalanceMetric(
                    label: '本次划扣',
                    value: chargeAmount,
                    emphasized: true,
                  ),
                ),
                Container(width: 1, height: 58, color: const Color(0xffd6d6d6)),
                Expanded(
                  child: _BalanceMetric(
                    label: '划扣后余额',
                    value: remaining < 0 ? 0 : remaining,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xfffff5e8),
              border: Border.all(color: const Color(0xffffd8a6)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xffff941c),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasDiscount
                        ? '当前订单已使用优惠，请保留优惠并改用其他支付渠道。'
                        : '储值划扣将直接从该会员账户余额中扣除。',
                    style: const TextStyle(
                      color: Color(0xff75501f),
                      fontSize: 17,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!enough) ...[
            const SizedBox(height: 18),
            Text(
              hasDiscount
                  ? '当前订单已使用优惠，不能使用储值划扣'
                  : order.canUseStoredValue
                  ? '会员余额不足，还差 ¥${(-remaining).toStringAsFixed(2)}'
                  : '未获取到有效的会员储值账户',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _checkoutRed,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      primaryKey: const Key('balance-checkout-confirm'),
      primaryLabel: '确认划扣',
      primaryEnabled: enough,
      onPrimary: () => Navigator.of(context).pop(true),
    );
  }
}

class StandardCheckoutDialog extends StatelessWidget {
  const StandardCheckoutDialog({
    super.key,
    required this.methodLabel,
    required this.amount,
  });

  final String methodLabel;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return _CheckoutFrame(
      dialogKey: const Key('standard-checkout-dialog'),
      title: '确认结账',
      width: 650,
      height: 520,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.point_of_sale_rounded,
            size: 76,
            color: _checkoutBlue,
          ),
          const SizedBox(height: 18),
          Text(
            methodLabel,
            style: const TextStyle(
              color: _checkoutInk,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '本单应收',
            style: TextStyle(color: Color(0xff777777), fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            '¥${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: _checkoutRed,
              fontSize: 48,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      primaryLabel: '确认收款',
      onPrimary: () => Navigator.of(context).pop(true),
    );
  }
}

class ForceCheckoutResult {
  const ForceCheckoutResult({
    required this.paymentMethod,
    this.reason,
  });

  final String paymentMethod;
  final String? reason;
}

class CashierForceCheckoutDialog extends StatefulWidget {
  const CashierForceCheckoutDialog({
    super.key,
    required this.orderNo,
    required this.amount,
    required this.paymentMethods,
    this.title = '强制结账',
  });

  final String orderNo;
  final double amount;
  final List<PosPaymentMethod> paymentMethods;
  final String title;

  @override
  State<CashierForceCheckoutDialog> createState() =>
      _CashierForceCheckoutDialogState();
}

class _CashierForceCheckoutDialogState
    extends State<CashierForceCheckoutDialog> {
  late String _selectedMethod;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final nonBalanceMethods = widget.paymentMethods
        .where((m) => m.code != 'balance' && m.code != 'combined')
        .toList(growable: false);
    _selectedMethod =
        nonBalanceMethods.isNotEmpty ? nonBalanceMethods.first.code : 'cash';
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableMethods = widget.paymentMethods
        .where((m) => m.code != 'combined')
        .toList(growable: false);

    return _CheckoutFrame(
      dialogKey: const Key('force-checkout-dialog'),
      title: widget.title,
      width: 640,
      height: 560,
      primaryKey: const Key('force-checkout-confirm-btn'),
      primaryLabel: '确认强制结账',
      onPrimary: () {
        final reason = _reasonController.text.trim();
        Navigator.of(context).pop(
          ForceCheckoutResult(
            paymentMethod: _selectedMethod,
            reason: reason.isEmpty ? null : reason,
          ),
        );
      },
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xfffff7ed),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xfffed7aa)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xffea580c), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '强制结账将跳过常规意向校验并核销账单。若无主管权限，将自动唤起现场授权审批。',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xff9a3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xffe2e8f0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '关联单号',
                        style: TextStyle(color: Color(0xff64748b), fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.orderNo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xff1e293b),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '应收金额',
                        style: TextStyle(color: Color(0xff64748b), fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '¥${widget.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xffdc2626),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '选择入账渠道',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xff334155),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in availableMethods)
                  ChoiceChip(
                    key: Key('force-pay-chip-${method.code}'),
                    label: Text(
                      method.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _selectedMethod == method.code
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: _selectedMethod == method.code
                            ? const Color(0xff0369a1)
                            : const Color(0xff475569),
                      ),
                    ),
                    selected: _selectedMethod == method.code,
                    selectedColor: const Color(0xffe0f2fe),
                    backgroundColor: const Color(0xfff8fafc),
                    side: BorderSide(
                      color: _selectedMethod == method.code
                          ? const Color(0xff0284c7)
                          : const Color(0xffcbd5e1),
                      width: 1.5,
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedMethod = method.code);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '异常说明 / 强制备注',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xff334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('force-checkout-reason-field'),
              controller: _reasonController,
              decoration: const InputDecoration(
                hintText: '如：顾客现金结账离店、线上支付异常挂起等',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xff94a3b8)),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentSuccessDialog extends StatelessWidget {
  const PaymentSuccessDialog({
    super.key,
    required this.amount,
    required this.orderNo,
    required this.channelLabel,
  });

  final double amount;
  final String orderNo;
  final String channelLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: isDark ? BorderSide(color: context.cashier.border) : BorderSide.none,
      ),
      child: SizedBox(
        key: const Key('payment-success-dialog'),
        width: 604,
        height: 380,
        child: Column(
          children: [
            SizedBox(
              height: 79,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: _checkoutInk),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 5,
                    child: ColoredBox(
                      color: Color(0xff15803d),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '收款成功',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 13,
                    right: 14,
                    child: IconButton(
                      key: const Key('payment-success-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      iconSize: 34,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '到账金额',
                      style: TextStyle(color: Color(0xff777777), fontSize: 18),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '¥${amount.toStringAsFixed(2)}',
                      key: const Key('payment-success-amount'),
                      style: const TextStyle(
                        color: Color(0xff15803d),
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '订单号：$orderNo  |  方式：$channelLabel自动核销',
                      style: const TextStyle(
                        color: Color(0xff666666),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(38, 14, 38, 22),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? context.cashier.border : const Color(0xffe2e2e2))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton(
                  key: const Key('payment-success-confirm'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.cashier.ink,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '确认',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CombinedCheckoutDialogResult {
  const CombinedCheckoutDialogResult({
    required this.wechatMinor,
    required this.alipayMinor,
    required this.balanceMinor,
    required this.cashMinor,
    required this.cashTenderMinor,
    required this.changeAmountMinor,
    this.changeChannel,
  });

  final int wechatMinor;
  final int alipayMinor;
  final int balanceMinor;
  final int cashMinor;
  final int cashTenderMinor;
  final int changeAmountMinor;
  final PosChangeChannel? changeChannel;
}

class CombinedCheckoutDialog extends StatefulWidget {
  const CombinedCheckoutDialog({
    super.key,
    required this.order,
    required this.paymentMethods,
    required this.confirmCollection,
    this.initialSettlement,
    this.initiallyConfirmedChannels = const <String>{},
    this.onCollectionConfirmed,
  });

  final PosOrder order;
  final List<PosPaymentMethod> paymentMethods;
  final Future<bool> Function(
    String channel,
    int amountMinor,
    PosCheckoutSettlement draftSettlement,
  )
  confirmCollection;
  final PosCheckoutSettlement? initialSettlement;
  final Set<String> initiallyConfirmedChannels;
  final Future<void> Function(
    PosCheckoutSettlement settlement,
    Set<String> confirmedChannels,
  )?
  onCollectionConfirmed;

  @override
  State<CombinedCheckoutDialog> createState() => _CombinedCheckoutDialogState();
}

class _CombinedCheckoutDialogState extends State<CombinedCheckoutDialog> {
  final controllers = <_CombinedChannel, TextEditingController>{
    for (final channel in _CombinedChannel.values)
      channel: TextEditingController(),
  };
  final collectionConfirmed = <_CombinedChannel, bool>{
    _CombinedChannel.wechat: false,
    _CombinedChannel.alipay: false,
  };
  final cashTenderController = TextEditingController();
  PosChangeChannel changeChannel = PosChangeChannel.cash;
  _CombinedChannel? confirmingChannel;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettlement;
    if (initial == null) return;
    controllers[_CombinedChannel.cash]!.text = _yuanInput(initial.cashMinor);
    controllers[_CombinedChannel.wechat]!.text = _yuanInput(
      initial.wechatMinor,
    );
    controllers[_CombinedChannel.alipay]!.text = _yuanInput(
      initial.alipayMinor,
    );
    controllers[_CombinedChannel.balance]!.text = _yuanInput(
      initial.balanceMinor,
    );
    cashTenderController.text = _yuanInput(initial.cashTenderMinor);
    changeChannel = initial.changeChannel ?? PosChangeChannel.cash;
    collectionConfirmed[_CombinedChannel.wechat] =
        widget.initiallyConfirmedChannels.contains('wechat');
    collectionConfirmed[_CombinedChannel.alipay] =
        widget.initiallyConfirmedChannels.contains('alipay');
  }

  int get orderTotalMinor => (widget.order.total * 100).round();
  int get memberBalanceMinor =>
      ((widget.order.memberBalance ?? 0) * 100).round();

  Set<_CombinedChannel> get availableChannels {
    final channels = <_CombinedChannel>{};
    for (final method in widget.paymentMethods.where((item) => item.enabled)) {
      final channel = _combinedChannelForCode(method.code);
      if (channel != null) channels.add(channel);
    }
    if (!widget.order.canUseStoredValue || memberBalanceMinor <= 0) {
      channels.remove(_CombinedChannel.balance);
    }
    return channels;
  }

  int amountFor(_CombinedChannel channel) =>
      _minorUnits(controllers[channel]!.text);

  int get allocatedMinor =>
      availableChannels.fold(0, (sum, channel) => sum + amountFor(channel));

  int get remainingMinor => orderTotalMinor - allocatedMinor;

  int get positiveChannelCount =>
      availableChannels.where((channel) => amountFor(channel) > 0).length;

  int get cashTenderMinor {
    final entered = _minorUnits(cashTenderController.text);
    return entered == 0 ? amountFor(_CombinedChannel.cash) : entered;
  }

  int get changeMinor =>
      (cashTenderMinor - amountFor(_CombinedChannel.cash)).clamp(0, 1 << 62);

  bool get collectionReady {
    for (final channel in const [
      _CombinedChannel.wechat,
      _CombinedChannel.alipay,
    ]) {
      if (amountFor(channel) > 0 && collectionConfirmed[channel] != true) {
        return false;
      }
    }
    return true;
  }

  bool get valid {
    final cash = amountFor(_CombinedChannel.cash);
    final balance = amountFor(_CombinedChannel.balance);
    return positiveChannelCount >= 2 &&
        allocatedMinor == orderTotalMinor &&
        balance <= memberBalanceMinor &&
        (cash == 0 || cashTenderMinor >= cash) &&
        collectionReady;
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    cashTenderController.dispose();
    super.dispose();
  }

  void _amountChanged(_CombinedChannel channel) {
    if (channel == _CombinedChannel.wechat ||
        channel == _CombinedChannel.alipay) {
      collectionConfirmed[channel] = false;
    }
    setState(() {});
  }

  void _fillRemaining(_CombinedChannel channel) {
    final current = amountFor(channel);
    var value = current + remainingMinor;
    if (channel == _CombinedChannel.balance) {
      value = value.clamp(0, memberBalanceMinor);
    } else {
      value = value.clamp(0, orderTotalMinor);
    }
    controllers[channel]!.text = _yuanInput(value);
    _amountChanged(channel);
  }

  Future<void> _confirmCollection(_CombinedChannel channel) async {
    final amount = amountFor(channel);
    if (amount <= 0 || confirmingChannel != null) return;
    setState(() => confirmingChannel = channel);
    final confirmed = await widget.confirmCollection(
      channel.apiCode,
      amount,
      _currentSettlement(),
    );
    if (!mounted) return;
    setState(() {
      confirmingChannel = null;
      collectionConfirmed[channel] = confirmed;
    });
    if (confirmed) {
      await widget.onCollectionConfirmed?.call(
        _currentSettlement(),
        {
          for (final entry in collectionConfirmed.entries)
            if (entry.value) entry.key.apiCode,
        },
      );
    }
  }

  PosCheckoutSettlement _currentSettlement() => PosCheckoutSettlement(
    wechatMinor: amountFor(_CombinedChannel.wechat),
    alipayMinor: amountFor(_CombinedChannel.alipay),
    balanceMinor: amountFor(_CombinedChannel.balance),
    cashMinor: amountFor(_CombinedChannel.cash),
    cashTenderMinor: cashTenderMinor,
    changeAmountMinor: changeMinor,
    changeChannel: changeMinor == 0 ? null : changeChannel,
  );

  void _submit() {
    if (!valid) return;
    Navigator.of(context).pop(
      CombinedCheckoutDialogResult(
        wechatMinor: amountFor(_CombinedChannel.wechat),
        alipayMinor: amountFor(_CombinedChannel.alipay),
        balanceMinor: amountFor(_CombinedChannel.balance),
        cashMinor: amountFor(_CombinedChannel.cash),
        cashTenderMinor: cashTenderMinor,
        changeAmountMinor: changeMinor,
        changeChannel: changeMinor == 0 ? null : changeChannel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = availableChannels.toList(growable: false);
    final compact = MediaQuery.sizeOf(context).height < 850;
    return _CheckoutFrame(
      dialogKey: const Key('combined-checkout-dialog'),
      title: '组合支付',
      width: 980,
      height: 920,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _CombinedSummaryMetric(
                  label: '本单应收',
                  amountMinor: orderTotalMinor,
                ),
              ),
              Expanded(
                child: _CombinedSummaryMetric(
                  label: remainingMinor < 0 ? '超出金额' : '待分配',
                  amountMinor: remainingMinor.abs(),
                  emphasized: remainingMinor != 0,
                ),
              ),
              Expanded(
                child: _CombinedSummaryMetric(
                  label: '已选渠道',
                  text: '$positiveChannelCount 个',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xffdddddd)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (var index = 0; index < channels.length; index++) ...[
                  if (index > 0)
                    const Divider(height: 1, color: Color(0xffe5e5e5)),
                  _CombinedChannelRow(
                    channel: channels[index],
                    height: compact ? 86 : 92,
                    controller: controllers[channels[index]]!,
                    balanceMinor: memberBalanceMinor,
                    confirmed: collectionConfirmed[channels[index]] == true,
                    confirming: confirmingChannel == channels[index],
                    onChanged: () => _amountChanged(channels[index]),
                    onFillRemaining: () => _fillRemaining(channels[index]),
                    onConfirmCollection:
                        channels[index].requiresCollectionConfirmation
                        ? () => _confirmCollection(channels[index])
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (amountFor(_CombinedChannel.cash) > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('combined-cash-tender-field'),
                    controller: cashTenderController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: _combinedInputDecoration(
                      label: '客人付现',
                      hint: '默认等于现金分配金额',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '找零 ${_currency(changeMinor)}',
                  key: const Key('combined-change-amount'),
                  style: const TextStyle(
                    color: _checkoutRed,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (changeMinor > 0) ...[
                  const SizedBox(width: 16),
                  DropdownButton<PosChangeChannel>(
                    key: const Key('combined-change-channel'),
                    value: changeChannel,
                    items: [
                      for (final channel in PosChangeChannel.values)
                        DropdownMenuItem(
                          value: channel,
                          child: Text('${channel.label}找零'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => changeChannel = value);
                    },
                  ),
                ],
              ],
            ),
          ],
          const Spacer(),
          Text(
            _combinedValidationMessage(
              channelCount: positiveChannelCount,
              remainingMinor: remainingMinor,
              balanceExceeded:
                  amountFor(_CombinedChannel.balance) > memberBalanceMinor,
              cashShort:
                  amountFor(_CombinedChannel.cash) > 0 &&
                  cashTenderMinor < amountFor(_CombinedChannel.cash),
              collectionReady: collectionReady,
            ),
            key: const Key('combined-checkout-validation'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: valid ? const Color(0xff278844) : _checkoutRed,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      primaryKey: const Key('combined-checkout-confirm'),
      primaryLabel: '确认组合收款',
      primaryEnabled: valid,
      onPrimary: _submit,
    );
  }
}

enum _CombinedChannel {
  cash('cash', '现金', Icons.payments_outlined),
  wechat('wechat', '微信', Icons.chat_bubble_outline_rounded),
  alipay('alipay', '支付宝', Icons.account_balance_wallet_outlined),
  balance('balance', '会员余额', Icons.savings_outlined);

  const _CombinedChannel(this.apiCode, this.label, this.icon);

  final String apiCode;
  final String label;
  final IconData icon;

  bool get requiresCollectionConfirmation => this == wechat || this == alipay;
}

class _CombinedChannelRow extends StatelessWidget {
  const _CombinedChannelRow({
    required this.channel,
    required this.height,
    required this.controller,
    required this.balanceMinor,
    required this.confirmed,
    required this.confirming,
    required this.onChanged,
    required this.onFillRemaining,
    this.onConfirmCollection,
  });

  final _CombinedChannel channel;
  final double height;
  final TextEditingController controller;
  final int balanceMinor;
  final bool confirmed;
  final bool confirming;
  final VoidCallback onChanged;
  final VoidCallback onFillRemaining;
  final VoidCallback? onConfirmCollection;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: height < 90 ? 8 : 10,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xffedf5ff),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(channel.icon, color: _checkoutBlue, size: 30),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (channel == _CombinedChannel.balance)
                    Text(
                      '可用 ${_currency(balanceMinor)}',
                      style: const TextStyle(
                        color: Color(0xff777777),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 230,
              child: TextField(
                key: Key('combined-${channel.apiCode}-field'),
                controller: controller,
                enabled: !confirmed,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged(),
                decoration: _combinedInputDecoration(
                  label: '分配金额',
                  hint: '0.00',
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: Key('combined-${channel.apiCode}-fill'),
              onPressed: confirmed ? null : onFillRemaining,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(112, 52),
                foregroundColor: _checkoutInk,
              ),
              child: const Text('补齐剩余'),
            ),
            const Spacer(),
            if (onConfirmCollection != null)
              FilledButton.icon(
                key: Key('combined-${channel.apiCode}-confirm'),
                onPressed: confirming || confirmed
                    ? null
                    : onConfirmCollection,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(170, 52),
                  backgroundColor: confirmed
                      ? const Color(0xff3bad61)
                      : _checkoutInk,
                ),
                icon: confirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        confirmed
                            ? Icons.check_circle_outline
                            : Icons.qr_code_2_rounded,
                      ),
                label: Text(confirmed ? '已确认到账' : '扫码并确认'),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xfff3f3f3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  channel == _CombinedChannel.balance ? '提交时划扣' : '现场收款',
                  style: const TextStyle(color: Color(0xff666666)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CombinedSummaryMetric extends StatelessWidget {
  const _CombinedSummaryMetric({
    required this.label,
    this.amountMinor,
    this.text,
    this.emphasized = false,
  });

  final String label;
  final int? amountMinor;
  final String? text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xff777777), fontSize: 16),
        ),
        const SizedBox(height: 3),
        Text(
          text ?? _currency(amountMinor ?? 0),
          style: TextStyle(
            color: emphasized
                ? _checkoutRed
                : (Theme.of(context).brightness == Brightness.dark
                    ? context.cashier.ink
                    : _checkoutInk),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

InputDecoration _combinedInputDecoration({
  required String label,
  required String hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: '¥ ',
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _checkoutBlue, width: 1.8),
    ),
  );
}

_CombinedChannel? _combinedChannelForCode(String code) {
  return switch (PosPaymentChannelKind.normalize(code)) {
    PosPaymentChannelKind.cash => _CombinedChannel.cash,
    PosPaymentChannelKind.wechatNative ||
    PosPaymentChannelKind.wechat => _CombinedChannel.wechat,
    PosPaymentChannelKind.alipay => _CombinedChannel.alipay,
    PosPaymentChannelKind.balance => _CombinedChannel.balance,
    _ => null,
  };
}

int _minorUnits(String source) {
  final value = source.trim();
  if (value.isEmpty || !RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(value)) {
    return 0;
  }
  final parts = value.split('.');
  final yuan = int.tryParse(parts.first) ?? 0;
  final fraction = parts.length == 1
      ? 0
      : int.tryParse(parts[1].padRight(2, '0')) ?? 0;
  return yuan * 100 + fraction;
}

String _yuanInput(int minor) => (minor / 100).toStringAsFixed(2);

String _currency(int minor) => '¥${(minor / 100).toStringAsFixed(2)}';

String _combinedValidationMessage({
  required int channelCount,
  required int remainingMinor,
  required bool balanceExceeded,
  required bool cashShort,
  required bool collectionReady,
}) {
  if (channelCount < 2) return '请至少分配两个支付渠道';
  if (balanceExceeded) return '余额分配金额不能超过会员可用余额';
  if (cashShort) return '客人付现金额不能小于现金分配金额';
  if (remainingMinor > 0) return '还有 ${_currency(remainingMinor)} 待分配';
  if (remainingMinor < 0) return '已超出 ${_currency(-remainingMinor)}';
  if (!collectionReady) return '请完成微信或支付宝扫码，并确认到账';
  return '金额已核对，可以完成组合收款';
}

class _CheckoutFrame extends StatelessWidget {
  const _CheckoutFrame({
    required this.dialogKey,
    required this.title,
    required this.width,
    required this.height,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryKey,
    this.primaryEnabled = true,
    this.primaryChild,
  });

  final Key dialogKey;
  final String title;
  final double width;
  final double height;
  final Widget body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final Key? primaryKey;
  final bool primaryEnabled;
  final Widget? primaryChild;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.sizeOf(context);
    final compact = media.height < 850;
    return Dialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: isDark ? BorderSide(color: context.cashier.border) : BorderSide.none,
      ),
      child: SizedBox(
        key: dialogKey,
        width: width.clamp(0, media.width - 48),
        height: height.clamp(0, media.height - 48),
        child: Column(
          children: [
            SizedBox(
              height: compact ? 64 : 78,
              child: ColoredBox(
                color: _checkoutInk,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: compact ? 6 : 13,
                      child: IconButton(
                        key: const Key('checkout-dialog-close'),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 24 : 38,
                  compact ? 12 : 28,
                  compact ? 24 : 38,
                  compact ? 12 : 22,
                ),
                child: body,
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                compact ? 24 : 38,
                compact ? 8 : 14,
                compact ? 24 : 38,
                compact ? 10 : 22,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? context.cashier.border : const Color(0xffe2e2e2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: compact ? 52 : 62,
                      child: OutlinedButton(
                        key: const Key('checkout-dialog-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cashier.ink,
                          side: BorderSide(color: isDark ? context.cashier.border : const Color(0xff888888)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消', style: TextStyle(fontSize: 25)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: SizedBox(
                      height: compact ? 52 : 62,
                      child: FilledButton(
                        key: primaryKey,
                        onPressed: primaryEnabled ? onPrimary : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryEnabled
                              ? (isDark ? context.cashier.ink : _checkoutInk)
                              : (isDark ? context.cashier.subtle : const Color(0xffb5b5b5)),
                          foregroundColor: isDark && primaryEnabled ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: primaryChild ??
                            Text(
                              primaryLabel,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xff777777), fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(
          '¥${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: emphasized
                ? _checkoutRed
                : (Theme.of(context).brightness == Brightness.dark
                    ? context.cashier.ink
                    : _checkoutInk),
            fontSize: emphasized ? 32 : 27,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

Uint8List? _decodeQr(String source) {
  final value = source.contains(',') ? source.split(',').last : source;
  if (value.trim().isEmpty) return null;
  try {
    return base64Decode(value.trim());
  } catch (_) {
    return null;
  }
}

String _maskPhone(String phone) {
  final source = phone.trim();
  if (source.length < 7) return source;
  return '${source.substring(0, 3)}****${source.substring(source.length - 4)}';
}

String _timeLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
