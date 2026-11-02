import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/app_config.dart';
import '../../cashier_shell/presentation/cashier_app_theme.dart';
import '../data/auth_repository.dart';
import '../data/cashier_account_storage.dart';
import '../domain/auth_models.dart';

const _brandPrimary = Color(0xffed3d08);
const _textDark = Color(0xff2d2d2f);
const _textMuted = Color(0xff848484);
const _bgLight = Color(0xfff5f6f7);

class CashierLoginPage extends StatefulWidget {
  const CashierLoginPage({
    super.key,
    required this.repository,
    required this.onLoggedIn,
    this.accountStorage,
    this.initialUsername,
    this.themeMode = ThemeMode.light,
    this.onThemeModeChanged,
  });

  final AuthRepository repository;
  final FutureOr<void> Function(LoginSession session) onLoggedIn;
  final CashierAccountStorage? accountStorage;

  /// 快速切换账号预填的员工工号（切换入口选中后带入），密码仍需手动输入。
  final String? initialUsername;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<CashierLoginPage> createState() => _CashierLoginPageState();
}

class _CashierLoginPageState extends State<CashierLoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordFocusNode = FocusNode();
  late final CashierAccountStorage _storage;

  List<String> savedAccounts = const [];
  bool showAccountDropdown = false;
  bool obscurePassword = true;
  bool rememberAccount = true;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _storage = widget.accountStorage ?? CashierAccountStorage();
    final initialUsername = widget.initialUsername?.trim() ?? '';
    if (initialUsername.isNotEmpty) {
      usernameController.text = initialUsername;
      // 切换账号场景：工号已预填，自动聚焦密码框减少一步操作。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) passwordFocusNode.requestFocus();
      });
    }
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await _storage.getSavedAccounts();
    final remember = await _storage.getRememberMe();
    if (!mounted) return;
    setState(() {
      savedAccounts = accounts;
      rememberAccount = remember;
      if (accounts.isNotEmpty && usernameController.text.isEmpty) {
        usernameController.text = accounts.first;
      }
    });
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => error = '请输入账号和密码');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      showAccountDropdown = false;
    });

    try {
      final session = await widget.repository.login(
        username: username,
        password: password,
      );
      final accountToSave = session.workNo.isNotEmpty ? session.workNo : username;
      await _storage.saveAccount(accountToSave, remember: rememberAccount);
      if (!mounted) return;

      final greeting = session.jobTitle.isNotEmpty
          ? '欢迎回来，${session.jobTitle} ${session.displayName.isNotEmpty ? session.displayName : (session.realName.isNotEmpty ? session.realName : username)}！'
          : '欢迎回来，${session.displayName.isNotEmpty ? session.displayName : (session.realName.isNotEmpty ? session.realName : username)}！';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(greeting),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await Future.sync(() => widget.onLoggedIn(session));
    } on ApiException catch (e) {
      if (mounted) {
        // 登录防暴力破解锁定（连续 5 次密码错误自动锁定 15 分钟，locked_until）。
        setState(() => error = e.isAccountLocked
            ? '账号已锁定：连续多次密码错误触发保护，约 15 分钟后自动解锁，期间请联系管理员'
            : _cleanErrorMessage(e.message));
      }
    } catch (e) {
      if (mounted) setState(() => error = '登录失败，请检查账号、密码或网络连接');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _cleanErrorMessage(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    if (lower.contains('<html') ||
        lower.contains('<!doctype') ||
        lower.contains('<body') ||
        lower.contains('<head') ||
        lower.contains('<center>') ||
        trimmed.contains(RegExp(r'<[a-zA-Z\/][^>]*>'))) {
      return '服务器网关连接异常（502 Bad Gateway），请稍后重试';
    }
    return trimmed.isEmpty ? '登录失败，请稍后重试' : trimmed;
  }

  Future<void> _removeSavedAccount(String account) async {
    await _storage.removeAccount(account);
    final updated = await _storage.getSavedAccounts();
    if (!mounted) return;
    setState(() {
      savedAccounts = updated;
      if (usernameController.text == account) {
        usernameController.text = updated.isNotEmpty ? updated.first : '';
      }
      if (updated.isEmpty) {
        showAccountDropdown = false;
      }
    });
  }

  void _forgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请联系系统管理员或店长重置密码'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final primaryColor = dark ? scheme.primary : _brandPrimary;

    return Scaffold(
      backgroundColor: dark ? theme.scaffoldBackgroundColor : _bgLight,
      body: Stack(
        children: [
          // 顶部或右上角主题切换
          if (widget.onThemeModeChanged != null)
            Positioned(
              top: 24,
              right: 28,
              child: CashierThemeToggle(
                themeMode: widget.themeMode,
                onChanged: widget.onThemeModeChanged!,
              ),
            ),

          // 核心登录卡片 (居中且自适应大屏)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360, maxWidth: 440),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: dark
                          ? const Color(0xff444444)
                          : const Color(0xffe7e7e7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: dark
                            ? Colors.black.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 卡片标题
                      Text(
                        '欢迎登录',
                        style: TextStyle(
                          color: dark ? scheme.onSurface : _textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 卡片副标题
                      Text(
                        '使用员工工号或系统账号登录收银系统',
                        style: TextStyle(
                          color: dark ? scheme.onSurfaceVariant : _textMuted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 账号输入栏与下拉切换列表
                      _LoginInputField(
                        label: '员工工号',
                        hintText: '请输入员工工号或系统用户名 (如 EMP1001)',
                        controller: usernameController,
                        enabled: !loading,
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.person_outline_rounded,
                        isDark: dark,
                        suffixIcon: savedAccounts.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  showAccountDropdown
                                      ? Icons.arrow_drop_up_rounded
                                      : Icons.arrow_drop_down_rounded,
                                  size: 28,
                                  color: dark
                                      ? scheme.onSurfaceVariant
                                      : _textMuted,
                                ),
                                tooltip: '已记住的历史账号',
                                onPressed: () {
                                  setState(() {
                                    showAccountDropdown = !showAccountDropdown;
                                  });
                                },
                              )
                            : null,
                      ),

                      // 已保存账号的下拉选择面板 (对应 Figma AccountDropdown 2212:1587)
                      if (showAccountDropdown && savedAccounts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xff242426)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: dark
                                  ? const Color(0xff555555)
                                  : const Color(0xffe5e6eb),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: dark
                                    ? Colors.black.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: savedAccounts
                                .map((account) {
                                  final isSelected =
                                      usernameController.text.trim() == account;
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setState(() {
                                          usernameController.text = account;
                                          showAccountDropdown = false;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? (dark
                                                    ? scheme.primary.withValues(
                                                        alpha: 0.15,
                                                      )
                                                    : _brandPrimary.withValues(
                                                        alpha: 0.08,
                                                      ))
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.account_circle_outlined,
                                              size: 20,
                                              color: isSelected
                                                  ? primaryColor
                                                  : (dark
                                                        ? scheme
                                                              .onSurfaceVariant
                                                        : _textMuted),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                account,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                  color: isSelected
                                                      ? primaryColor
                                                      : (dark
                                                            ? scheme.onSurface
                                                            : _textDark),
                                                ),
                                              ),
                                            ),
                                            if (isSelected)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: Icon(
                                                  Icons.check_rounded,
                                                  size: 16,
                                                  color: primaryColor,
                                                ),
                                              ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              tooltip: '删除此账号记录',
                                              color: dark
                                                  ? scheme.onSurfaceVariant
                                                  : _textMuted,
                                              onPressed: () =>
                                                  _removeSavedAccount(account),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // 密码输入栏
                      _LoginInputField(
                        label: '密码',
                        hintText: '请输入登录密码',
                        controller: passwordController,
                        focusNode: passwordFocusNode,
                        enabled: !loading,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        prefixIcon: Icons.lock_outline_rounded,
                        isDark: dark,
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: dark ? scheme.onSurfaceVariant : _textMuted,
                          ),
                          onPressed: () {
                            setState(() => obscurePassword = !obscurePassword);
                          },
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 16),

                      // 错误提示信息
                      if (error != null) ...[
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
                                color: Color(0xffef4444),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: const TextStyle(
                                    color: Color(0xffb91c1c),
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 记住账号与忘记密码
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: loading
                                ? null
                                : () => setState(
                                    () => rememberAccount = !rememberAccount,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Checkbox(
                                      value: rememberAccount,
                                      activeColor: primaryColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      onChanged: loading
                                          ? null
                                          : (val) => setState(
                                              () =>
                                                  rememberAccount = val ?? true,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '记住工号',
                                    style: TextStyle(
                                      color: dark
                                          ? scheme.onSurface
                                          : _textDark,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: loading ? null : _forgotPassword,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '忘记密码?',
                                style: TextStyle(
                                  color: dark
                                      ? scheme.onSurfaceVariant
                                      : _textMuted,
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // 登录大按钮 (56px 触控大按钮)
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: primaryColor.withValues(
                              alpha: 0.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: loading ? null : _login,
                          child: loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '登 录',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '提示：如遇工号未分配，请联系门店管理员创建',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: dark ? scheme.onSurfaceVariant : _textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 底部品牌与版本信息
          Align(
            alignment: const Alignment(0, 0.94),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (AppConfig.debugBackendEnabled) ...[
                  const Text(
                    '调试环境 · ${AppConfig.debugApiBaseUrl}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xffef4444),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '老肥家收银系统 · V${AppConfig.version}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dark ? scheme.onSurfaceVariant : _textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginInputField extends StatelessWidget {
  const _LoginInputField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.isDark,
    this.obscureText = false,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final bool isDark;
  final bool obscureText;
  final bool enabled;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = isDark
        ? const Color(0xff555555)
        : const Color(0xffe5e6eb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? scheme.onSurface : _textDark,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            obscureText: obscureText,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? scheme.onSurface : _textDark,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xff777777)
                    : const Color(0xffb0b0b0),
                fontSize: 15,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xff242426) : Colors.white,
              prefixIcon: prefixIcon != null
                  ? Icon(
                      prefixIcon,
                      size: 20,
                      color: isDark ? scheme.onSurfaceVariant : _textMuted,
                    )
                  : null,
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? scheme.primary : _brandPrimary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
