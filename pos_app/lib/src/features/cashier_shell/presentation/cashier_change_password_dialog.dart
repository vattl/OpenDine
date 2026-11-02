import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import 'cashier_tokens.dart';

/// 弹出收银端修改密码对话框
Future<bool?> showCashierChangePasswordDialog({
  required BuildContext context,
  required AdminApiClient client,
  int? currentShopId,
  String? accountName,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CashierChangePasswordDialog(
        client: client,
        currentShopId: currentShopId,
        accountName: accountName,
      ),
    );

/// 收银端修改密码对话框。
///
/// 要求操作员输入当前密码（原始密码）进行身份鉴权验证，
/// 修改成功后服务端将递增 tokenVersion 吊销全部既有登录凭证。
class CashierChangePasswordDialog extends StatefulWidget {
  const CashierChangePasswordDialog({
    super.key,
    required this.client,
    this.currentShopId,
    this.accountName,
  });

  final AdminApiClient client;
  final int? currentShopId;
  final String? accountName;

  @override
  State<CashierChangePasswordDialog> createState() =>
      _CashierChangePasswordDialogState();
}

class _CashierChangePasswordDialogState
    extends State<CashierChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _clearPasswords() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final targetClient = widget.currentShopId != null
          ? widget.client.copyWith(shopId: widget.currentShopId)
          : widget.client;

      await targetClient.post(
        adminModifyPasswordEndpoint,
        body: {
          'password': _currentPasswordController.text,
          'newPassword': _newPasswordController.text,
        },
      );

      _clearPasswords();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _clearPasswords();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : '密码修改失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cashier = context.cashier;

    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: dark ? theme.colorScheme.surface : Colors.white,
        surfaceTintColor: dark ? theme.colorScheme.surface : Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xfffff1ed),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: Color(0xffed3d08),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '修改登录密码',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  if (widget.accountName?.isNotEmpty == true)
                    Text(
                      '账号：${widget.accountName}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cashier.inkMuted,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.amber.shade900.withValues(alpha: 0.15)
                            : const Color(0xfffffbeb),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: dark
                              ? Colors.amber.shade700
                              : const Color(0xfffde68a),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: dark
                                ? Colors.amber.shade200
                                : const Color(0xffb45309),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '需要验证原始密码。修改成功后所有已登录会话将失效，需重新登录。',
                              style: TextStyle(
                                fontSize: 12,
                                color: dark
                                    ? Colors.amber.shade100
                                    : const Color(0xff92400e),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextFormField(
                      key: const Key('change-password-current'),
                      controller: _currentPasswordController,
                      autofocus: true,
                      enabled: !_submitting,
                      obscureText: _obscureCurrent,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: '当前密码',
                        hintText: '请输入原登录密码（原始密码）进行身份验证',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _obscureCurrent ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscureCurrent
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscureCurrent = !_obscureCurrent,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '请输入当前密码（原始密码）';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('change-password-new'),
                      controller: _newPasswordController,
                      enabled: !_submitting,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: '新密码',
                        hintText: '至少 6 位，不可与原密码相同',
                        prefixIcon: const Icon(Icons.key_rounded, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _obscureNew ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '请输入新密码';
                        }
                        if (v.trim().length < 6) {
                          return '新密码长度不能少于 6 位';
                        }
                        if (v.trim() == _currentPasswordController.text.trim() &&
                            _currentPasswordController.text.isNotEmpty) {
                          return '新密码不能与当前密码相同';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('change-password-confirm'),
                      controller: _confirmPasswordController,
                      enabled: !_submitting,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '确认新密码',
                        hintText: '请再次输入新密码',
                        prefixIcon: const Icon(
                          Icons.verified_user_outlined,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          tooltip: _obscureConfirm ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '请确认新密码';
                        }
                        if (v.trim() != _newPasswordController.text.trim()) {
                          return '两次输入的新密码不一致';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfffef2f2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xfffecaca)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: Color(0xffdc2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xffdc2626),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('change-password-cancel'),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('取 消'),
          ),
          FilledButton.icon(
            key: const Key('change-password-submit'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffed3d08),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_submitting ? '提交中...' : '确认修改'),
          ),
        ],
      ),
    );
  }
}
