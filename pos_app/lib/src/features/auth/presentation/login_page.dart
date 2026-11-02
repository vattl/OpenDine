import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/app_config.dart';
import '../../../core/app_state.dart';
import '../data/auth_repository.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.appState,
    required this.repository,
  });

  final AppState appState;
  final AuthRepository repository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await widget.repository.login(
        username: usernameController.text.trim(),
        password: passwordController.text,
      );
      if (!mounted) return;
      widget.appState.applySession(session);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '登录失败，请检查账号、密码或网络连接');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      body: Center(
        child: SizedBox(
          width: 430,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '运营收银后台',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppConfig.debugBackendEnabled
                        ? '调试环境：${AppConfig.debugApiBaseUrl}'
                        : '生产环境：${AppConfig.productionApiBaseUrl}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: '员工工号 / 管理员账号',
                      hintText: '请输入员工工号或系统用户名',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                    onSubmitted: (_) => loading ? null : _login(),
                  ),
                  const SizedBox(height: 16),
                  if (error != null) ...[
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: loading ? null : _login,
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('登录并拉取权限'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
