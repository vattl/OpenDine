import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

enum WechatNativeDialogResult {
  success,
  cancelled,
}

class WechatNativeCheckoutDialog extends StatefulWidget {
  const WechatNativeCheckoutDialog({
    super.key,
    required this.order,
    required this.createOrder,
    required this.queryOrder,
    required this.closeOrder,
  });

  final PosOrder order;
  final Future<PosWechatNativeOrder> Function() createOrder;
  final Future<PosWechatNativeStatus> Function() queryOrder;
  final Future<PosWechatNativeCloseResult> Function() closeOrder;

  @override
  State<WechatNativeCheckoutDialog> createState() =>
      _WechatNativeCheckoutDialogState();
}

class _WechatNativeCheckoutDialogState
    extends State<WechatNativeCheckoutDialog> {
  static const int _defaultTtlSeconds = 300;

  bool _loading = true;
  bool _querying = false;
  bool _closing = false;
  Object? _error;
  int? _errorCode;

  PosWechatNativeOrder? _nativeOrder;
  PosWechatNativeStatus? _status;
  bool _paymentSuccess = false;

  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startCheckout();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
      _nativeOrder = null;
      _status = null;
      _paymentSuccess = false;
      _remainingSeconds = 0;
    });

    try {
      final order = await widget.createOrder();
      if (!mounted) return;

      int ttl = _defaultTtlSeconds;
      if (order.expiresAt != null) {
        final diff = order.expiresAt!.difference(DateTime.now()).inSeconds;
        ttl = diff > 0 ? diff : 0;
      }

      setState(() {
        _nativeOrder = order;
        _loading = false;
        _remainingSeconds = ttl;
      });

      _startTimers();
    } catch (e) {
      if (!mounted) return;
      int? code;
      String message = e.toString();
      if (e is CashierWechatNativeException) {
        code = e.code;
        message = e.message;
      }
      setState(() {
        _loading = false;
        _error = message;
        _errorCode = code;
      });
    }
  }

  void _startTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remainingSeconds <= 1) {
        timer.cancel();
        _pollTimer?.cancel();
        if (mounted) setState(() => _remainingSeconds = 0);
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _silentPoll();
    });
  }

  Future<void> _silentPoll() async {
    if (!mounted || _querying || _closing || _paymentSuccess) return;
    try {
      final status = await widget.queryOrder();
      if (!mounted) return;
      _status = status;
      if (status.isSuccess) {
        _handlePaymentSuccess(status);
      }
    } catch (_) {
      // 轮询静默失败，不打断界面
    }
  }

  Future<void> _manualQuery() async {
    if (_querying || _closing || _paymentSuccess) return;
    setState(() => _querying = true);
    try {
      final status = await widget.queryOrder();
      if (!mounted) return;
      setState(() {
        _querying = false;
        _status = status;
        _error = null;
        _errorCode = null;
      });
      if (status.isSuccess) {
        _handlePaymentSuccess(status);
      } else {
        final stateLabel = switch (status.tradeState.toUpperCase()) {
          'NOTPAY' => '未支付',
          'USERPAYING' => '用户支付中',
          'CLOSED' => '已关闭',
          'REVOKED' => '已撤销',
          'PAYERROR' => '支付失败',
          _ => status.tradeState,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('微信当前状态：$stateLabel (暂未到账)'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xff0284c7),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _querying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('查单异常：$e'),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xffef4444),
        ),
      );
    }
  }

  void _handlePaymentSuccess(PosWechatNativeStatus status) {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _paymentSuccess = true;
      _status = status;
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.of(context).pop(WechatNativeDialogResult.success);
      }
    });
  }

  Future<void> _handleClose() async {
    if (_closing || _paymentSuccess) return;
    setState(() => _closing = true);

    try {
      await widget.closeOrder();
      if (!mounted) return;
      Navigator.of(context).pop(WechatNativeDialogResult.cancelled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      if (e is CashierWechatNativeException && e.isPaidCannotClose) {
        // 订单已支付，不能关单 -> 直接走成功流
        _handlePaymentSuccess(
          PosWechatNativeStatus(
            paymentId: _nativeOrder?.paymentId ?? 0,
            orderNo: widget.order.orderNo,
            outTradeNo: _nativeOrder?.outTradeNo ?? '',
            amountFen: _nativeOrder?.amountFen ?? (widget.order.total * 100).round(),
            tradeState: 'SUCCESS',
            status: 'SUCCESS',
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('关单失败：$e。建议先查单确认'),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xffef4444),
        ),
      );
      // 关单失败后主动唤起强制退出确认弹窗，绝不卡死
      await _showForceExitDialog();
    }
  }

  Future<void> _showForceExitDialog() async {
    if (!mounted || _paymentSuccess) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('wechat-native-force-exit-dialog'),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xffdc2626), size: 22),
            SizedBox(width: 8),
            Text('强制退出微信支付确认', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: const Text(
          '关单请求未能在微信端完成确认（可能网络离线或订单未在微信生成）。\n\n'
          '处理指引：请向顾客核实是否已扣款。\n'
          '• 若确认未付款，强制退出后可改用现金、顾客付款码反扫或其他渠道结算；\n'
          '• 若顾客已付款，请点击“取消”并使用【立即查询微信状态】同步入账。\n\n'
          '是否确认强制退出？',
          style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xff475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消 (返回查单)'),
          ),
          FilledButton(
            key: const Key('wechat-native-confirm-force-exit-btn'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认强制退出'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).pop(WechatNativeDialogResult.cancelled);
    }
  }

  void _handleCloseOrDismiss() {
    if (_paymentSuccess || _closing) return;
    if (_nativeOrder != null || _errorCode == 40931 || _errorCode == 50331) {
      _handleClose();
    } else {
      Navigator.of(context).pop(WechatNativeDialogResult.cancelled);
    }
  }

  String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? context.cashier.surface : Colors.white;
    final border = isDark ? context.cashier.border : const Color(0xffe2e8f0);
    final textInk = isDark ? context.cashier.ink : const Color(0xff0f172a);
    final textMuted = isDark ? context.cashier.inkMuted : const Color(0xff64748b);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _handleCloseOrDismiss,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: Container(
              width: 520,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(24),
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
                children: [
                  _buildHeader(textInk, textMuted),
                  const SizedBox(height: 16),
                  if (_paymentSuccess)
                    _buildSuccessView(textInk, textMuted)
                  else if (_errorCode == 40931 || _errorCode == 50331)
                    _buildAnomalyView(textInk, textMuted)
                  else if (_errorCode == 40231)
                    _buildWechatRejectionView(textInk, textMuted)
                  else if (_error != null)
                    _buildErrorView(textInk, textMuted)
                  else if (_loading)
                    _buildLoadingView(textMuted)
                  else
                    _buildActiveQrView(textInk, textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color textInk, Color textMuted) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            key: const Key('wechat-native-header-close-btn'),
            icon: const Icon(Icons.close, size: 20),
            tooltip: '关闭',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            color: textMuted,
            onPressed: _closing ? null : _handleCloseOrDismiss,
          ),
        ),
        Center(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xff07c160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '微信支付',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: textInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '桌台：${widget.order.tableNumber}号桌 · 订单号：${widget.order.orderNo}',
                style: TextStyle(fontSize: 13, color: textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView(Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xff07c160)),
          const SizedBox(height: 20),
          Text(
            '正在生成微信支付动态二维码...',
            style: TextStyle(fontSize: 16, color: textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQrView(Color textInk, Color textMuted) {
    final codeUrl = _nativeOrder?.codeUrl ?? '';
    final amount = _nativeOrder?.amountYuan ?? widget.order.total;

    return Column(
      children: [
        Text(
          '¥${amount.toStringAsFixed(2)}',
          key: const Key('wechat-native-amount'),
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            color: Color(0xffef4444),
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('wechat-native-qr-container'),
          width: 240,
          height: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xff07c160), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1a07c160),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: codeUrl.isNotEmpty
              ? QrImageView(
                  key: const Key('wechat-native-qr-image'),
                  data: codeUrl,
                  version: QrVersions.auto,
                  size: 216,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                )
              : const Center(
                  child: Text('二维码暂不可用', style: TextStyle(color: Colors.red)),
                ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xff07c160),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _remainingSeconds > 0
                  ? '等待扫码支付 (${_formatSeconds(_remainingSeconds)}后失效)'
                  : '二维码已失效，请重新出码',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _remainingSeconds > 0 ? textMuted : const Color(0xffef4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '* 金额由系统锁定，顾客扫码直接扣款，无需手动输入',
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('wechat-native-close-btn'),
                onPressed: _closing ? null : _handleClose,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_closing ? '关单中...' : '关闭支付'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('wechat-native-query-btn'),
                onPressed: _querying ? null : _manualQuery,
                icon: _querying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_querying ? '查单中...' : '立即主动查单'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff07c160),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessView(Color textInk, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xffdcfce7),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xff86efac), width: 2),
            ),
            child: const Icon(Icons.check, color: Color(0xff16a34a), size: 44),
          ),
          const SizedBox(height: 16),
          const Text(
            '微信支付成功！',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xff15803d),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '实收金额：¥${((_status?.amountFen ?? (widget.order.total * 100).round()) / 100.0).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 16, color: Color(0xffef4444), fontWeight: FontWeight.bold),
          ),
          if (_status?.transactionId != null && _status!.transactionId!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '微信单号：${_status!.transactionId}',
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '正在自动记账并清台...',
            style: TextStyle(fontSize: 13, color: textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyView(Color textInk, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xfffffbeb),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Color(0xffb45309), size: 36),
          ),
          const SizedBox(height: 12),
          const Text(
            '下单状态待确认 (防重收款拦截)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xffb45309),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfffef3c7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _error?.toString() ?? '上一笔下单结果暂未确认，可能顾客已扫码支付。为防止重复扣款，系统已拦截重新出码。请先主动查单。',
              style: const TextStyle(color: Color(0xff92400e), fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('wechat-native-anomaly-close-btn'),
                  onPressed: _closing ? null : _handleClose,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_closing ? '关单中...' : '关闭尝试'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('wechat-native-anomaly-query-btn'),
                  onPressed: _querying ? null : _manualQuery,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_querying ? '查询中...' : '立即查询微信状态'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff0284c7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('wechat-native-force-exit-btn'),
              onPressed: _showForceExitDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffdc2626),
                side: const BorderSide(color: Color(0xfffca5a5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                '关单失败？确认未付款后【强制退出并改用其他方式】',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWechatRejectionView(Color textInk, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xfffee2e2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, color: Color(0xffdc2626), size: 36),
          ),
          const SizedBox(height: 12),
          const Text(
            '微信下单明确拒绝 (code: 40231)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xffdc2626),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '微信官方接口已明确拒绝，本地已安全释放活动键',
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffe2e8f0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '拒绝原因：${_error?.toString() ?? '微信参数或商户权限错误'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xff334155)),
                ),
                const SizedBox(height: 6),
                const Text(
                  '处理建议：请勿反复重试出码，建议使用现金、顾客付款码反扫或其他渠道结算。',
                  style: TextStyle(fontSize: 12, color: Color(0xff0369a1), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(WechatNativeDialogResult.cancelled),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('返回并改用其他渠道', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(Color textInk, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xffef4444), size: 52),
          const SizedBox(height: 12),
          const Text(
            '微信下单失败',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xffef4444)),
          ),
          const SizedBox(height: 8),
          Text(
            _error?.toString() ?? '未知错误',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: textMuted),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(WechatNativeDialogResult.cancelled),
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _startCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff07c160),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('重试出码'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
