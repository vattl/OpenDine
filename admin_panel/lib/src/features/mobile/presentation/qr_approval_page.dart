import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../auth/domain/access_approval_models.dart';
import '../data/api_providers.dart';

/// 业务类型中文标签（透传服务端 bizType，仅作展示映射；未知值原样显示）。
const Map<String, String> _bizTypeLabels = {
  'ORDER_REFUND': '订单退款',
  'REFUND': '退款',
  'DISH_REFUND': '退菜',
  'GIFT_DISH': '赠菜',
  'DISCOUNT': '整单优惠/改价',
  'PRICE_UPDATE': '改价',
  'DELETE_ORDER': '删除订单',
  'OPEN_DRAWER': '开钱箱',
  'HANDOVER': '交班长短款',
  'CASH_MOVEMENT': '钱箱现金事件',
  'ORDER': '订单',
};

/// 方案A·店长移动端扫码审批页。
///
/// 收银端出码后，店长手机扫码唤起（深链 `bbq://approval?code=...` 或
/// 手动进入 `门店助手 → /approval?code=...`），本页加载申请详情，
/// 店长核实后点击同意/驳回，服务端签发一次性审批令牌（同意时）。
class QrApprovalPage extends ConsumerStatefulWidget {
  const QrApprovalPage({super.key, required this.approvalCode});

  /// 扫码授权流水标识（QAP_...）。
  final String approvalCode;

  @override
  ConsumerState<QrApprovalPage> createState() => _QrApprovalPageState();
}

class _QrApprovalPageState extends ConsumerState<QrApprovalPage> {
  late Future<CashierQrApprovalDetails> _detailsFuture;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  /// 审批后结果状态：null=未提交；APPROVED/REJECTED=已提交。
  String? _submittedStatus;
  bool _submitting = false;

  AccessApprovalRepository get _repository =>
      AccessApprovalRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<CashierQrApprovalDetails> _loadDetails() async {
    final details = await _repository.loadQrApprovalDetails(
      widget.approvalCode,
    );
    _syncExpiry(details);
    return details;
  }

  /// 根据服务端 expiresAt 同步过期状态与倒计时。
  void _syncExpiry(CashierQrApprovalDetails details) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final deadline = details.expiresAt;
    if (deadline == null) {
      setState(() {
        _remaining = Duration.zero;
        _expired = false;
      });
      return;
    }
    void tick() {
      final left = deadline.difference(DateTime.now());
      if (!mounted) return;
      setState(() {
        _remaining = left.isNegative ? Duration.zero : left;
        _expired = left.isNegative;
      });
      if (left.isNegative) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    }

    tick();
    if (!_expired) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        tick();
        if (_expired) _countdownTimer?.cancel();
      });
    }
  }

  Future<void> _confirm(String action) async {
    if (_submitting || _expired) return;
    var rejectReason = '';
    if (action == 'REJECT') {
      rejectReason = await _promptRejectReason() ?? '';
      if (!mounted) return;
    }
    setState(() => _submitting = true);
    try {
      final result = await _repository.confirmQrApproval(
        approvalCode: widget.approvalCode,
        action: action,
        rejectReason: rejectReason,
      );
      if (!mounted) return;
      setState(() => _submittedStatus = result.status);
    } on ApiException catch (error) {
      if (!mounted) return;
      String message = error.message;
      if (error.code == 403) {
        final dataMap = error.data is Map ? (error.data as Map) : null;
        final reqPerm = dataMap?['requiredApprovalPermission']?.toString();
        if (reqPerm != null && reqPerm.isNotEmpty) {
          final label = ApprovalPermissionHelper.readableName(reqPerm);
          message = '缺少【$label】权限，无法执行审批操作';
        } else {
          message = '无权限执行此审批操作：${error.message}';
        }
      } else if (error.isRateLimited) {
        final waitSec = error.retryAfterSeconds ?? 3;
        message = '操作过于频繁，请在 $waitSec 秒后再试';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _promptRejectReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('驳回原因'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '请填写驳回原因（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确认驳回'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _submittedStatus;
    if (submitted != null) {
      return _buildResult(submitted);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('扫码审批')),
      body: SafeArea(
        child: FutureBuilder<CashierQrApprovalDetails>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildError(snapshot.error);
            }
            final details = snapshot.data;
            if (details == null) {
              return _buildError('审批申请不存在');
            }
            return _buildDetails(details);
          },
        ),
      ),
    );
  }

  Widget _buildDetails(CashierQrApprovalDetails details) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expired = _expired;

    final permCode = details.requiredApprovalPermission ?? details.permission;
    final permDisplay = permCode != null && permCode.isNotEmpty
        ? '${ApprovalPermissionHelper.readableName(permCode)} ($permCode)'
        : (details.permission ?? '-');

    final rows = <(String, String)>[
      ('门店', details.shopId == null ? '-' : '门店 #${details.shopId}'),
      ('所需审批权限', permDisplay),
      if (details.bizType != null && details.bizType!.isNotEmpty)
        ('业务类型', _bizTypeLabels[details.bizType] ?? details.bizType!),
      if (details.bizId != null && details.bizId!.isNotEmpty)
        ('业务单号', details.bizId!),
      if (details.amount != null) ('涉及金额', '¥${details.amount!.toStringAsFixed(2)}'),
      if (details.operatorName != null && details.operatorName!.isNotEmpty)
        ('操作员', details.operatorName!),
      if (details.operatorWorkNo != null && details.operatorWorkNo!.isNotEmpty)
        ('操作员工号', details.operatorWorkNo!),
      if (details.reason != null && details.reason!.trim().isNotEmpty)
        ('申请原因', details.reason!.trim()),
      if (details.expiresAt != null)
        ('失效时间', _formatTime(details.expiresAt!)),
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 状态提示条
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: expired
                      ? scheme.errorContainer
                      : scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      expired
                          ? Icons.timer_off_outlined
                          : Icons.qr_code_2,
                      color: expired ? scheme.error : scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        expired
                            ? '该审批二维码已过期，无法操作。请收银端重新出码。'
                            : _remaining.inSeconds <= 30
                                ? '二维码将在 ${_remaining.inSeconds} 秒后失效，请尽快处理'
                                : '收银端正在等待您的审批结果',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: expired ? scheme.error : scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 审批详情卡片
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            size: 20,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '审批信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final (label, value) in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 76,
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: label == '涉及金额'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: label == '涉及金额'
                                        ? scheme.error
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                '授权码：${details.approvalCode}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 底部操作
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        expired || _submitting ? null : () => _confirm('REJECT'),
                    icon: const Icon(Icons.close),
                    label: const Text('驳回'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        expired || _submitting ? null : () => _confirm('AGREE'),
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('同意'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(String status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final approved = status == 'APPROVED';
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码审批'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  approved ? Icons.check_circle : Icons.cancel,
                  size: 72,
                  color: approved
                      ? const Color(0xFF2E7D32)
                      : scheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  approved ? '已同意' : '已驳回',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  approved
                      ? '审批已通过，收银端将继续执行操作'
                      : '已驳回本次审批，收银端将收到驳回结果',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    final scheme = Theme.of(context).colorScheme;
    final message = '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              '无法加载审批申请',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _detailsFuture = _loadDetails();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
