import 'package:flutter/material.dart';

const _brandPrimary = Color(0xffed3d08);
const _textDark = Color(0xff2d2d2f);
const _textMuted = Color(0xff848484);

/// 打开「切换账号 - 密码验证」对话框。
///
/// 快速切换账号在收银台当前界面之上进行：选中目标工号后弹出本对话框
/// 验证密码，不退出当前界面、不经过登录页。密码仅用于本次登录请求，
/// 系统不保存任何密码/令牌凭据。
///
/// 返回用户输入的密码；取消返回 null。
Future<String?> showCashierAccountPasswordDialog(
  BuildContext context, {
  required String workNo,
  NavigatorState? navigator,
}) {
  final targetNavigator = navigator ??
      Navigator.maybeOf(context, rootNavigator: true) ??
      Navigator.of(context);
  final route = DialogRoute<String>(
    context: context,
    builder: (dialogCtx) => _CashierAccountPasswordDialog(workNo: workNo),
    barrierDismissible: true,
    useSafeArea: true,
  );
  return targetNavigator.push<String>(route);
}

class _CashierAccountPasswordDialog extends StatefulWidget {
  const _CashierAccountPasswordDialog({required this.workNo});

  final String workNo;

  @override
  State<_CashierAccountPasswordDialog> createState() =>
      _CashierAccountPasswordDialogState();
}

class _CashierAccountPasswordDialogState
    extends State<_CashierAccountPasswordDialog> {
  final passwordController = TextEditingController();
  final passwordFocusNode = FocusNode();
  bool obscurePassword = true;

  @override
  void dispose() {
    passwordController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  void _confirm() {
    final password = passwordController.text;
    if (password.isEmpty) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final primaryColor = dark ? scheme.primary : _brandPrimary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xfffff1ed),
            child: Icon(Icons.lock_person_rounded, color: Color(0xffed3d08)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '切换到工号 ${widget.workNo}',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            Text(
              '请输入该工号的登录密码验证身份；切换后当前界面保留，'
              '账号信息与操作权限将原地更新。系统不保存密码。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: dark ? scheme.onSurfaceVariant : _textMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('switch-password-input'),
              controller: passwordController,
              focusNode: passwordFocusNode,
              autofocus: true,
              obscureText: obscurePassword,
              onSubmitted: (_) => _confirm(),
              style: TextStyle(
                fontSize: 15,
                color: dark ? scheme.onSurface : _textDark,
              ),
              decoration: InputDecoration(
                hintText: '请输入登录密码',
                hintStyle: TextStyle(
                  color: dark
                      ? const Color(0xff777777)
                      : const Color(0xffb0b0b0),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: dark ? const Color(0xff242426) : Colors.white,
                prefixIcon: Icon(
                  Icons.password_rounded,
                  size: 20,
                  color: dark ? scheme.onSurfaceVariant : _textMuted,
                ),
                suffixIcon: IconButton(
                  key: const Key('switch-password-visibility'),
                  tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                    color: dark ? scheme.onSurfaceVariant : _textMuted,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: dark
                        ? const Color(0xff555555)
                        : const Color(0xffe5e6eb),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: dark
                        ? const Color(0xff555555)
                        : const Color(0xffe5e6eb),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('switch-password-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取 消'),
        ),
        FilledButton.icon(
          key: const Key('switch-password-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _confirm,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('验证并切换'),
        ),
      ],
    );
  }
}
