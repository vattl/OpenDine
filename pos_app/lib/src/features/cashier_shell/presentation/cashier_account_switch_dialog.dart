import 'package:flutter/material.dart';

const _brandPrimary = Color(0xffed3d08);
const _textDark = Color(0xff2d2d2f);
const _textMuted = Color(0xff848484);

/// 打开「切换账号」弹窗。
///
/// 收银台个人档案入口：列出已保存的历史工号与手动输入其他工号，
/// 选中后返回目标工号（由调用方退出当前会话并跳转登录页预填，
/// 密码仍需手动输入，不保存任何密码/令牌凭据）。
///
/// 返回选中的工号；用户取消返回 null。
Future<String?> showCashierAccountSwitchDialog(
  BuildContext context, {
  required List<String> savedAccounts,
  required String currentWorkNo,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => _CashierAccountSwitchDialog(
      savedAccounts: savedAccounts,
      currentWorkNo: currentWorkNo,
    ),
  );
}

class _CashierAccountSwitchDialog extends StatefulWidget {
  const _CashierAccountSwitchDialog({
    required this.savedAccounts,
    required this.currentWorkNo,
  });

  final List<String> savedAccounts;
  final String currentWorkNo;

  @override
  State<_CashierAccountSwitchDialog> createState() =>
      _CashierAccountSwitchDialogState();
}

class _CashierAccountSwitchDialogState
    extends State<_CashierAccountSwitchDialog> {
  final otherWorkNoController = TextEditingController();
  String? otherError;

  @override
  void dispose() {
    otherWorkNoController.dispose();
    super.dispose();
  }

  void _confirmOtherWorkNo() {
    final value = otherWorkNoController.text.trim();
    if (value.isEmpty) {
      setState(() => otherError = '请输入要切换的员工工号');
      return;
    }
    Navigator.of(context).pop(value);
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
      title: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xfffff1ed),
            child: Icon(Icons.swap_horiz_rounded, color: Color(0xffed3d08)),
          ),
          SizedBox(width: 12),
          Text('切换账号', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            Text(
              '选择目标账号后将在当前界面验证密码，账号信息与操作权限'
              '原地更新，不退出收银界面；密码仅由本人输入，系统不保存任何密码。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: dark ? scheme.onSurfaceVariant : _textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '已保存的历史工号',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: dark ? scheme.onSurface : _textDark,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.savedAccounts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xff242426)
                      : const Color(0xfff5f6f7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '暂无历史工号，可在下方输入其他工号',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: dark ? scheme.onSurfaceVariant : _textMuted,
                  ),
                ),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.savedAccounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final account = widget.savedAccounts[index];
                      final isCurrent = account == widget.currentWorkNo;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('switch-account-$account'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: isCurrent
                              ? null
                              : () => Navigator.of(context).pop(account),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? primaryColor.withValues(alpha: 0.06)
                                  : (dark
                                        ? const Color(0xff242426)
                                        : const Color(0xfff5f6f7)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: dark
                                    ? const Color(0xff444444)
                                    : const Color(0xffe7e7e7),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_circle_outlined,
                                  size: 20,
                                  color: isCurrent
                                      ? primaryColor
                                      : (dark
                                            ? scheme.onSurfaceVariant
                                            : _textMuted),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    account,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isCurrent
                                          ? primaryColor
                                          : (dark
                                                ? scheme.onSurface
                                                : _textDark),
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '当前',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              '其他工号',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: dark ? scheme.onSurface : _textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('switch-other-workno'),
              controller: otherWorkNoController,
              autofocus: widget.savedAccounts.isEmpty,
              enabled: true,
              onSubmitted: (_) => _confirmOtherWorkNo(),
              style: TextStyle(
                fontSize: 15,
                color: dark ? scheme.onSurface : _textDark,
              ),
              decoration: InputDecoration(
                hintText: '输入员工工号后确认',
                hintStyle: TextStyle(
                  color: dark
                      ? const Color(0xff777777)
                      : const Color(0xffb0b0b0),
                  fontSize: 14,
                ),
                errorText: otherError,
                errorMaxLines: 1,
                filled: true,
                fillColor: dark ? const Color(0xff242426) : Colors.white,
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: dark ? scheme.onSurfaceVariant : _textMuted,
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
          key: const Key('switch-account-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取 消'),
        ),
        FilledButton.icon(
          key: const Key('switch-account-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: primaryColor.withValues(alpha: 0.5),
          ),
          onPressed: _confirmOtherWorkNo,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('切换到此工号'),
        ),
      ],
    );
  }
}
