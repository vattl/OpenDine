import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

typedef PosAuthCredentials = ({String account, String password});

/// 唤起 POS / 收银端敏感高危操作（如整单打折、退菜、赠菜、退款、删除）店长/管理账号二次授权弹窗。
Future<PosAuthCredentials?> showPosAuthDialog(
  BuildContext context, {
  required String title,
  required String reason,
  String? currentAccount,
  String warningMessage = '此操作涉及金额变动或高危数据修改，请由店长或管理员输入账号密码进行二次授权。',
  Future<void> Function(String account, String password)? onVerify,
  bool barrierDismissible = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<PosAuthCredentials>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: const Color(0x66000000),
    builder: (_) => PosAuthDialog(
      title: title,
      reason: reason,
      currentAccount: currentAccount,
      warningMessage: warningMessage,
      onVerify: onVerify,
    ),
  );
  final result = await navigator.push<PosAuthCredentials>(route);
  await route.completed;
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
  return result;
}

/// 敏感操作管理员授权弹窗组件
class PosAuthDialog extends StatefulWidget {
  const PosAuthDialog({
    super.key,
    required this.title,
    required this.reason,
    this.currentAccount,
    this.warningMessage = '此操作涉及金额变动或高危数据修改，请由店长或管理员输入账号密码进行二次授权。',
    this.onVerify,
  });

  final String title;
  final String reason;
  final String? currentAccount;
  final String warningMessage;
  final Future<void> Function(String account, String password)? onVerify;

  @override
  State<PosAuthDialog> createState() => _PosAuthDialogState();
}

class _PosAuthDialogState extends State<PosAuthDialog> {
  late final TextEditingController _accountController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _verifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController(
      text: widget.currentAccount?.isNotEmpty == true
          ? widget.currentAccount
          : 'admin',
    );
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty) {
      setState(() => _errorMessage = '请输入员工工号或管理员账号');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = '请输入管理密码');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      if (widget.onVerify != null) {
        await widget.onVerify!(account, password);
      }
      if (!mounted) return;
      Navigator.of(context).pop((account: account, password: password));
    } catch (e) {
      if (!mounted) return;
      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      } else if (message.startsWith('Bad state: ')) {
        message = message.substring('Bad state: '.length);
      }
      setState(() {
        _verifying = false;
        _errorMessage =
            message.contains('密码') ||
                message.contains('账号') ||
                message.contains('工号') ||
                message.contains('权限') ||
                message.contains('超级管理员')
            ? message
            : '授权失败，请检查账号权限后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      key: const Key('pos-auth-dialog'),
      compact: true,
      width: 480,
      height: 480,
      title: widget.title,
      subtitle: widget.reason,
      onClose: _verifying ? null : () => Navigator.pop(context, null),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.cashier.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: context.cashier.danger,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.warningMessage,
                    style: TextStyle(
                      color: context.cashier.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pos-auth-account'),
            controller: _accountController,
            enabled: !_verifying,
            decoration: const InputDecoration(
              labelText: '员工工号 / 管理员账号 *',
              hintText: '请输入员工工号或管理员账号 (如 EMP1001)',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pos-auth-password'),
            controller: _passwordController,
            enabled: !_verifying,
            obscureText: _obscurePassword,
            autofocus: true,
            onSubmitted: (_) => _handleConfirm(),
            decoration: InputDecoration(
              labelText: '管理员密码 *',
              hintText: '请输入密码进行授权',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xfffef2f2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xffef4444).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.cashier.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: context.cashier.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('pos-auth-cancel'),
                  onPressed: _verifying
                      ? null
                      : () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FilledButton(
                  key: const Key('pos-auth-confirm'),
                  onPressed: _verifying ? null : _handleConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.cashier.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '确认授权',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
