import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/app_config.dart';
import '../../../core/api_contract.dart';
import '../../cashier_shift/data/real_cashier_shift_repository.dart';
import '../../cashier_shift/domain/cashier_shift.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../data/cart_storage.dart';
import 'about_page.dart';
import 'notification_preferences_page.dart';

final currentShiftProvider = FutureProvider<CashierShift?>(
  (ref) => RealCashierShiftRepository(
    ref.watch(apiClientProvider),
  ).loadCurrentShift(),
);

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final canViewShift = auth.hasPermission('cashier:operate');
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('当前门店'),
            subtitle: Text(auth.currentShop?.name ?? '未选择'),
          ),
          if (canViewShift) const _ShiftTile(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('通知偏好'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesPage(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('关于与帮助'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          if (auth.hasPermission('admin:password'))
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('修改密码'),
              subtitle: const Text('修改后需要重新登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context, ref),
            ),
          if (auth.shops.length > 1 && auth.hasPermission('shop:manage'))
            ...auth.shops.map(
              (shop) => ListTile(
                leading: Icon(
                  shop.id == auth.currentShopId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(shop.name),
                subtitle: Text(shop.code),
                onTap: () =>
                    ref.read(authProvider.notifier).selectShop(shop.id),
              ),
            ),
          const _OutboxTile(),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('当前版本'),
            subtitle: Text(AppConfig.version),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: () => _logout(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(WidgetRef ref) async {
    try {
      await ref.read(pushServiceProvider).unregister();
    } catch (error) {
      debugPrint('push unregister failed: $error');
    }
    await ref.read(authProvider.notifier).logout();
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _MobilePasswordDialog(client: ref.read(apiClientProvider)),
    );
    if (changed != true || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('密码修改成功，请使用新密码重新登录')));
    await _logout(ref);
  }
}

class _MobilePasswordDialog extends StatefulWidget {
  const _MobilePasswordDialog({required this.client});

  final AdminApiClient client;

  @override
  State<_MobilePasswordDialog> createState() => _MobilePasswordDialogState();
}

class _MobilePasswordDialogState extends State<_MobilePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.post(
        adminModifyPasswordEndpoint,
        body: {
          // 服务端安全加固后以 JWT 定位本人：password=当前密码，
          // newPassword=新密码；成功后全部旧 Token 失效，调用方负责重新登录。
          'password': _currentPassword.text,
          'newPassword': _password.text,
        },
      );
      _password.clear();
      _confirmation.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _password.clear();
      _confirmation.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException ? error.message : '密码修改失败，请检查网络后重试';
      });
    }
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '请输入$label' : null;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('修改密码'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentPassword,
                  autofocus: true,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '当前密码'),
                  validator: (value) => _required(value, '当前密码'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '新密码',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? '显示密码' : '隐藏密码',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => _required(value, '新密码'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmation,
                  enabled: !_busy,
                  obscureText: _obscure,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: '确认新密码'),
                  validator: (value) {
                    final required = _required(value, '确认新密码');
                    if (required != null) return required;
                    return value == _password.text ? null : '两次输入的密码不一致';
                  },
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
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认修改'),
        ),
      ],
    ),
  );
}

class _OutboxTile extends ConsumerStatefulWidget {
  const _OutboxTile();

  @override
  ConsumerState<_OutboxTile> createState() => _OutboxTileState();
}

class _OutboxTileState extends ConsumerState<_OutboxTile> {
  late Future<({List<PendingOrder> pending, List<PendingOrder> rejected})>
  _orders;

  @override
  void initState() {
    super.initState();
    _orders = _load();
  }

  Future<({List<PendingOrder> pending, List<PendingOrder> rejected})>
  _load() async {
    final storage = ref.read(cartStorageProvider);
    final values = await Future.wait([
      storage.readPending(),
      storage.readRejected(),
    ]);
    return (pending: values[0], rejected: values[1]);
  }

  void _refresh() => setState(() => _orders = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _orders,
    builder: (context, snapshot) {
      final value = snapshot.data;
      final pending = value?.pending.length ?? 0;
      final rejected = value?.rejected.length ?? 0;
      return ListTile(
        leading: const Icon(Icons.cloud_sync_outlined),
        title: const Text('弱网订单队列'),
        subtitle: snapshot.hasError
            ? const Text('状态读取失败，请重试')
            : Text('待补单 $pending 笔 · 需人工处理 $rejected 笔'),
        trailing: IconButton(
          tooltip: '刷新弱网订单状态',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        onTap: rejected == 0
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('需人工处理的订单'),
                  content: SizedBox(
                    width: 420,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: value!.rejected.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final order = value.rejected[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('桌台 ${order.tableNumber}'),
                          subtitle: Text(
                            '${order.rejectionReason}\n请求号 ${order.clientRequestId}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('我已知晓'),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

class _ShiftTile extends ConsumerWidget {
  const _ShiftTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(currentShiftProvider);
    return shift.when(
      loading: () => const ListTile(
        leading: Icon(Icons.schedule_outlined),
        title: Text('当前班次'),
        subtitle: Text('加载中…'),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) {
          return const ListTile(
            leading: Icon(Icons.schedule_outlined),
            title: Text('当前班次'),
            subtitle: Text('未开班'),
          );
        }
        return ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('当前班次'),
          subtitle: Text(
            '开班 ${data.startTime?.toString().substring(0, 16) ?? '-'}\n'
            '已结 ${data.orderCount} 单 · ¥${data.totalAmount.toStringAsFixed(2)}',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}
