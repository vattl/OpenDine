import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../app/mobile_router.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';

class MobileLoginPage extends ConsumerStatefulWidget {
  const MobileLoginPage({super.key});

  @override
  ConsumerState<MobileLoginPage> createState() => _MobileLoginPageState();
}

class _MobileLoginPageState extends ConsumerState<MobileLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = await AuthRepository(
        client,
      ).login(username: _username.text.trim(), password: _password.text);
      if (!mounted) return;
      await ref.read(authProvider.notifier).applySession(session);
      // 深链挂起的扫码审批：登录完成后直接跳转审批页。
      final pendingCode = pendingApprovalCode;
      if (pendingCode != null && pendingCode.isNotEmpty) {
        pendingApprovalCode = null;
        if (mounted) context.go('/approval?code=$pendingCode');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '老肥家门店助手',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: '账号',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入账号'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        decoration:
                            const InputDecoration(
                              labelText: '密码',
                              prefixIcon: Icon(Icons.lock_outline),
                            ).copyWith(
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                onPressed: _busy
                                    ? null
                                    : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) =>
                            value == null || value.isEmpty ? '请输入密码' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
