import 'dart:async';

import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/pos_repository.dart';
import '../domain/pos_device_capability.dart';
import '../domain/pos_models.dart';
import 'pos_camera_scanner_view.dart';

enum WechatMicropayDialogResult {
  success,
  cancelled,
}

class WechatMicropayCheckoutDialog extends StatefulWidget {
  const WechatMicropayCheckoutDialog({
    super.key,
    required this.order,
    required this.payMicropay,
    required this.queryOrder,
    required this.reverseOrder,
    this.initialAuthCode,
    this.isAndroidTabletWithCameraOverride,
    this.cameraScannerBuilder,
  });

  final PosOrder order;
  final Future<PosWechatMicropayOrder> Function(String authCode) payMicropay;
  final Future<PosWechatMicropayStatus> Function() queryOrder;
  final Future<PosWechatMicropayReverseResult> Function() reverseOrder;
  final String? initialAuthCode;
  final bool? isAndroidTabletWithCameraOverride;
  final Widget Function(BuildContext context, ValueChanged<String> onScanned)? cameraScannerBuilder;

  @override
  State<WechatMicropayCheckoutDialog> createState() =>
      _WechatMicropayCheckoutDialogState();
}

class _WechatMicropayCheckoutDialogState
    extends State<WechatMicropayCheckoutDialog> {
  static const int _reverseGuardSecondsTotal = 15;

  final TextEditingController _authCodeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _submitting = false;
  bool _querying = false;
  bool _reversing = false;
  bool _isUserPaying = false;
  bool _paymentSuccess = false;
  bool _useCameraScanner = false;

  Object? _error;
  int? _errorCode;

  PosWechatMicropayOrder? _micropayOrder;
  PosWechatMicropayStatus? _status;

  int _reverseCountdownSeconds = _reverseGuardSecondsTotal;
  Timer? _reverseCountdownTimer;
  Timer? _pollTimer;
  Timer? _successTimer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialAuthCode != null && widget.initialAuthCode!.isNotEmpty) {
      _authCodeController.text = widget.initialAuthCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitPayment();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _reverseCountdownTimer?.cancel();
    _pollTimer?.cancel();
    _successTimer?.cancel();
    _authCodeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startUserPayingTimers() {
    _reverseCountdownTimer?.cancel();
    _pollTimer?.cancel();

    _reverseCountdownSeconds = _reverseGuardSecondsTotal;
    _reverseCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_reverseCountdownSeconds > 0) {
        setState(() {
          _reverseCountdownSeconds--;
        });
      } else {
        timer.cancel();
      }
    });

    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _silentPoll();
    });
  }

  Future<void> _silentPoll() async {
    if (!mounted || _paymentSuccess || _reversing) return;
    _pollCount++;
    try {
      final status = await widget.queryOrder();
      if (!mounted) return;
      _status = status;
      if (status.isSuccess) {
        _handlePaymentSuccess(
          amountFen: status.amountFen,
          transactionId: status.transactionId,
        );
      } else if (status.isClosed) {
        _pollTimer?.cancel();
        _reverseCountdownTimer?.cancel();
        setState(() {
          _isUserPaying = false;
          _error = '交易已关闭或撤销，未扣款';
          _errorCode = 40241;
        });
      } else if (status.isPayError) {
        _pollTimer?.cancel();
        _reverseCountdownTimer?.cancel();
        setState(() {
          _isUserPaying = false;
          _error = '微信扣款失败：${status.status}';
          _errorCode = 40241;
        });
      }
    } catch (_) {
      // 静默轮询忽略网络波动错误，保持界面平稳
    }
  }

  Future<void> _submitPayment() async {
    final rawCode = _authCodeController.text.trim();
    if (rawCode.isEmpty) {
      setState(() {
        _error = '请使用扫码枪扫描微信付款码';
        _errorCode = null;
      });
      return;
    }

    final codePattern = RegExp(r'^1[0-5][0-9]{16}$');
    if (!codePattern.hasMatch(rawCode)) {
      setState(() {
        _error = '付款码格式错误：应为以 10-15 开头的 18 位数字';
        _errorCode = 40031;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _errorCode = null;
    });

    try {
      final order = await widget.payMicropay(rawCode);
      if (!mounted) return;
      _micropayOrder = order;

      if (order.isSuccess) {
        _handlePaymentSuccess(
          amountFen: order.amountFen,
          transactionId: order.transactionId,
        );
      } else if (order.isUserPaying) {
        setState(() {
          _submitting = false;
          _isUserPaying = true;
        });
        _startUserPayingTimers();
      } else {
        setState(() {
          _submitting = false;
          _error = '微信返回状态：${order.tradeState}';
        });
      }
    } on CashierWechatMicropayException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = e.code;
        _error = e.message;
      });
      // 若已有待确认交易或超时不确定，自动切入等待确认状态并开启轮询
      if (e.isConflictOrPending || e.isUncertainNeedQuery) {
        setState(() {
          _isUserPaying = true;
        });
        _startUserPayingTimers();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
        _errorCode = null;
      });
    }
  }

  Future<void> _manualQuery() async {
    if (_querying || !mounted) return;
    setState(() {
      _querying = true;
    });
    try {
      final status = await widget.queryOrder();
      if (!mounted) return;
      _status = status;
      if (status.isSuccess) {
        _handlePaymentSuccess(
          amountFen: status.amountFen,
          transactionId: status.transactionId,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('查单结果：${status.tradeState}（等待顾客完成支付）'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on CashierWechatMicropayException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('查单提示：${e.message}'),
          backgroundColor: Colors.amber.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查单失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _querying = false;
        });
      }
    }
  }

  Future<void> _handleReverse() async {
    if (_reversing || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('撤销付款码交易确认'),
          ],
        ),
        content: const Text(
          '撤销时，系统将先向微信核实扣款状态：\n'
          '• 若顾客已扣款成功，将自动入账结单，绝不漏单；\n'
          '• 若未扣款，将正式关闭授权并解除渠道锁定。\n\n'
          '是否确认撤销本次交易？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _reversing = true;
    });

    try {
      final result = await widget.reverseOrder();
      if (!mounted) return;

      if (result.alreadyPaid) {
        // 顾客在最后一刻完成扣款，自动进入成功逻辑
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('核单发现顾客已支付成功，自动入账结单')),
        );
        _handlePaymentSuccess(amountFen: (widget.order.total * 100).round());
        return;
      }

      _reverseCountdownTimer?.cancel();
      _pollTimer?.cancel();
      Navigator.of(context).pop(WechatMicropayDialogResult.cancelled);
    } on CashierWechatMicropayException catch (e) {
      if (!mounted) return;
      if (e.isOrderAlreadyPaidCannotReverse) {
        _handlePaymentSuccess(amountFen: (widget.order.total * 100).round());
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('撤销提示：${e.message}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撤销失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reversing = false;
        });
      }
    }
  }

  void _handlePaymentSuccess({int? amountFen, String? transactionId}) {
    _reverseCountdownTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _paymentSuccess = true;
      _isUserPaying = false;
    });
    _successTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.of(context).pop(WechatMicropayDialogResult.success);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting && !_isUserPaying && !_reversing && !_paymentSuccess,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: context.cashier.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(context),
              const SizedBox(height: 16),
              _buildOrderMetaBox(context),
              const SizedBox(height: 16),
              if (_paymentSuccess)
                _buildSuccessView(context)
              else if (_isUserPaying)
                _buildUserPayingView(context)
              else if (_errorCode != null && _errorCode != 40031)
                _buildAnomalyView(context)
              else
                _buildScanInputView(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF07C160),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: const Text(
            '微',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '微信付款码支付 (商家扫顾客)',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: context.cashier.ink,
          ),
        ),
        const Spacer(),
        if (!_isUserPaying && !_paymentSuccess && !_submitting && !_reversing)
          IconButton(
            key: const Key('wechat-micropay-close-icon'),
            icon: Icon(Icons.close, color: context.cashier.inkMuted),
            onPressed: () => Navigator.of(context).pop(WechatMicropayDialogResult.cancelled),
            tooltip: '取消',
          )
        else
          Icon(Icons.lock_outline_rounded, size: 20, color: context.cashier.inkMuted),
      ],
    );
  }

  Widget _buildOrderMetaBox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🪑 桌台：${widget.order.tableNumber}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '单号: ${widget.order.orderNo}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: context.cashier.inkMuted,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '应收金额',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
              Text(
                '¥ ${widget.order.total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: context.cashier.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanInputView(BuildContext context) {
    if (_useCameraScanner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.cameraScannerBuilder != null)
            widget.cameraScannerBuilder!(context, (code) {
              _authCodeController.text = code;
              _submitPayment();
            })
          else
            PosCameraScannerView(
              key: const Key('wechat-micropay-camera-viewfinder'),
              onBarcodeScanned: (code) {
                _authCodeController.text = code;
                _submitPayment();
              },
              onSwitchToManualOrGun: () {
                setState(() {
                  _useCameraScanner = false;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _focusNode.requestFocus();
                });
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _buildErrorMessage(context),
          ],
        ],
      );
    }

    final isTabletWithCam = widget.isAndroidTabletWithCameraOverride ??
        PosDeviceEnvironment.isAndroidTabletWithCamera(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTabletWithCam)
          Center(
            child: Container(
              key: const Key('wechat-micropay-tablet-detect-pill'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF7E22CE).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tablet_android_rounded, size: 14, color: Color(0xFFD8B4FE)),
                  SizedBox(width: 4),
                  Text(
                    '检测到安卓平板设备，支持免扫码枪直接扫码',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD8B4FE),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: context.cashier.canvas,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.cashier.selected,
              style: BorderStyle.solid,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 48,
                color: context.cashier.selected,
              ),
              const SizedBox(height: 12),
              Text(
                '请使用扫码枪扫描顾客手机微信付款码',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '顾客打开微信 →「收付款」→ 展示条形码或二维码\n扫码枪扫描后将自动极速发起扣款',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('wechat-micropay-authcode-input'),
                controller: _authCodeController,
                focusNode: _focusNode,
                autofocus: true,
                obscureText: true,
                maxLength: 18,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '扫码枪自动输入 18 位付款码',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0,
                    color: context.cashier.inkMuted,
                  ),
                  filled: true,
                  fillColor: context.cashier.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.cashier.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.cashier.selected, width: 2),
                  ),
                ),
                onSubmitted: (_) => _submitPayment(),
                onChanged: (val) {
                  // 扫码枪快速键入达到 18 位数字时自动触发提交
                  if (val.trim().length == 18) {
                    _submitPayment();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSpecGrid(context, isCameraMode: false),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _buildErrorMessage(context),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              key: const Key('wechat-micropay-cancel-button'),
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pop(WechatMicropayDialogResult.cancelled),
              child: const Text('取消'),
            ),
            if (isTabletWithCam) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('wechat-micropay-open-camera-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7E22CE),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('打开平板摄像头扫码'),
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _useCameraScanner = true;
                          _error = null;
                          _errorCode = null;
                        });
                      },
              ),
            ],
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const Key('wechat-micropay-submit-button'),
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(_submitting ? '扣款处理中...' : '确认扣款'),
              onPressed: _submitting ? null : _submitPayment,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cashier.dangerBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: context.cashier.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_error',
              style: TextStyle(fontSize: 12, color: context.cashier.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPayingView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF262015),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: Colors.amber.shade400,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '顾客正在手机上输入支付密码...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade400,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '系统正在每 2 秒向微信主动轮询扣款结果\n请提示顾客在微信手机端完成指纹或密码验证',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 15, color: Color(0xFFFCA5A5)),
                    SizedBox(width: 6),
                    Text(
                      '已锁定订单，禁止重新扫码或切换其他渠道，避免重复扣款',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFCA5A5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '轮询查单 ($_pollCount 次)...',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
            ),
            OutlinedButton(
              key: const Key('wechat-micropay-reverse-button'),
              onPressed: (_reverseCountdownSeconds > 0 || _reversing)
                  ? null
                  : _handleReverse,
              child: Text(
                _reverseCountdownSeconds > 0
                    ? '撤销 (${_reverseCountdownSeconds}s)'
                    : '撤销支付',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('wechat-micropay-query-button'),
              icon: _querying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('立即查单'),
              onPressed: _querying ? null : _manualQuery,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF132724),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981)),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                '微信付款码支付成功！',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF34D399),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '¥ ${widget.order.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
              ),
              if (_status?.transactionId != null || _micropayOrder?.transactionId != null) ...[
                const SizedBox(height: 4),
                Text(
                  '微信支付单号: ${_status?.transactionId ?? _micropayOrder?.transactionId}',
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.cashier.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.cashier.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自动化后置处理执行状态：',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF34D399)),
                  SizedBox(width: 6),
                  Text('订单已自动入账并结单', style: TextStyle(fontSize: 12, color: Color(0xFF34D399))),
                ],
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF34D399)),
                  SizedBox(width: 6),
                  Text('58mm 热敏收银小票已自动打印', style: TextStyle(fontSize: 12, color: Color(0xFF34D399))),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF34D399)),
                  const SizedBox(width: 6),
                  Text('桌台 ${widget.order.tableNumber} 已清台并解除占用', style: const TextStyle(fontSize: 12, color: Color(0xFF34D399))),
                ],
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF34D399)),
                  SizedBox(width: 6),
                  Text('支付流水已同步云端台账与 KDS 状态', style: TextStyle(fontSize: 12, color: Color(0xFF34D399))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('wechat-micropay-success-done-button'),
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.selected,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () {
            _successTimer?.cancel();
            Navigator.of(context).pop(WechatMicropayDialogResult.success);
          },
          child: const Text('完成并返回桌台看板 (1.2s 自动返回)'),
        ),
      ],
    );
  }

  Widget _buildAnomalyView(BuildContext context) {
    String title = '扣款遇到异常';
    String desc = '$_error';
    if (_errorCode == 40941) {
      title = '该订单已有待确认的支付交易';
      desc = '系统检测到此订单已发起过扣款。请勿重复扫码，建议立即查单核实是否扣款，或在确认未扣款后撤销交易。';
    } else if (_errorCode == 50341) {
      title = '扣款结果不确定 (网络超时)';
      desc = '微信未在超时时间内返回明确结果，严禁直接重新扫码！请点击下方的立即查单，系统将核实真实到账状态。';
    } else if (_errorCode == 40241) {
      title = '微信明确拒绝支付';
      desc = '顾客微信端未能成功扣款（如零钱余额不足、卡受限或风控拦截），建议提示顾客更换卡片或改用现金等支付方式。';
    } else if (_errorCode == 40031) {
      title = '付款码格式错误或已过期刷新';
      desc = '微信返回：付款码无效或已被使用（付款码每分钟自动刷新）。请让顾客在手机微信中刷新收付款条形码后重新扫描。';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.cashier.dangerBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cashier.danger),
          ),
          child: Column(
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: context.cashier.danger),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.cashier.danger,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.cashier.ink, height: 1.4),
              ),
              if (_errorCode != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.cashier.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '错误码: $_errorCode',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: context.cashier.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cashier.canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cashier.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGuidanceBullet('40941（已有待确认交易）：', '引导收银员点击【立即查单】或【安全撤销】。'),
              const SizedBox(height: 4),
              _buildGuidanceBullet('50341（扣款结果不确定）：', '严禁直接重新扫码！自动转入权威查单。'),
              const SizedBox(height: 4),
              _buildGuidanceBullet('40241（微信拒付）：', '提示顾客零钱余额不足或卡片受限，更换支付方式。'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(WechatMicropayDialogResult.cancelled),
              child: const Text('改用其他方式'),
            ),
            const SizedBox(width: 10),
            if (_errorCode == 40941 || _errorCode == 50341)
              FilledButton.icon(
                key: const Key('wechat-micropay-retry-query-button'),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('立即查单'),
                onPressed: _manualQuery,
              )
            else
              FilledButton.icon(
                key: const Key('wechat-micropay-retry-scan-button'),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: const Text('重新扫码 (已刷新)'),
                onPressed: () {
                  setState(() {
                    _error = null;
                    _errorCode = null;
                    _authCodeController.clear();
                  });
                  _focusNode.requestFocus();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuidanceBullet(String boldPrefix, String text) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: context.cashier.inkMuted, height: 1.4),
        children: [
          const TextSpan(text: '• '),
          TextSpan(
            text: boldPrefix,
            style: TextStyle(fontWeight: FontWeight.bold, color: context.cashier.ink),
          ),
          TextSpan(text: text),
        ],
      ),
    );
  }

  Widget _buildSpecGrid(BuildContext context, {required bool isCameraMode}) {
    final item1Title = isCameraMode ? '硬件友好：' : '扫码枪设备：';
    final item1Desc = isCameraMode ? '无需外购扫码枪，平板即收银机' : '即插即用，回车自动发起';
    final item2Title = isCameraMode ? '前后双摄：' : '平板专享：';
    final item2Desc = isCameraMode ? '立屏顾客自贴/手持对客扫码皆宜' : '可随时切换摄像头扫码';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.cashier.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.cashier.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
                children: [
                  TextSpan(
                    text: item1Title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.cashier.ink),
                  ),
                  TextSpan(text: item1Desc),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
                children: [
                  TextSpan(
                    text: item2Title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: context.cashier.ink),
                  ),
                  TextSpan(text: item2Desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

