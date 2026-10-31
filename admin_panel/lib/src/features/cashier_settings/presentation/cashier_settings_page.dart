import 'package:flutter/material.dart';
import '../../../core/admin_api_client.dart';
import '../../kds_local/runtime/cashier_kds_runtime.dart';
import '../../cashier_payment/data/cashier_payment_repository.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_detail_pages.dart';
import 'cashier_settings_shared.dart';
import 'cashier_settings_catalogue.dart';
import 'package:flutter/foundation.dart';
import '../../api_debug/presentation/api_debug_console_page.dart';
import '../../cashier_shell/presentation/cashier_change_password_dialog.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../../core/app_config.dart';
import '../../version_upgrade/data/app_version_service.dart';
import '../../version_upgrade/presentation/version_upgrade_dialog.dart';

class CashierSettingsPage extends StatefulWidget {
  const CashierSettingsPage({
    super.key,
    required this.repository,
    required this.paymentRepository,
    required this.storeName,
    required this.kdsAvailable,
    this.client,
    this.permissions = const {},
    this.currentShopId,
    this.onPasswordChanged,
    this.onOpenKdsDiagnostics,
    this.kdsRuntime,
  });

  final CashierSettingsRepository repository;
  final CashierPaymentRepository paymentRepository;
  final String storeName;
  final bool kdsAvailable;

  /// 接口调试目的地所需的客户端与权限（更多页迁移而来）。
  final AdminApiClient? client;
  final Set<String> permissions;
  final int? currentShopId;
  final VoidCallback? onPasswordChanged;
  final VoidCallback? onOpenKdsDiagnostics;
  final CashierKdsRuntime? kdsRuntime;

  @override
  State<CashierSettingsPage> createState() => _CashierSettingsPageState();
}

class _CashierSettingsPageState extends State<CashierSettingsPage> {
  SettingsDestination? _destination;
  var _detailKey = GlobalKey<SettingsDetailPageState>();

  @override
  void didUpdateWidget(CashierSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.client != widget.client ||
        oldWidget.currentShopId != widget.currentShopId ||
        !setEquals(oldWidget.permissions, widget.permissions)) {
      _destination = null;
      _detailKey = GlobalKey<SettingsDetailPageState>();
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: context.cashier.canvas,
      child: _destination == null
          ? _SettingsHub(
              repository: widget.repository,
              paymentRepository: widget.paymentRepository,
              kdsAvailable: widget.kdsAvailable,
              client: widget.client,
              permissions: widget.permissions,
              currentShopId: widget.currentShopId,
              onPasswordChanged: widget.onPasswordChanged,
              onOpenKdsDiagnostics: widget.onOpenKdsDiagnostics,
              onOpen: (value) => setState(() => _destination = value),
            )
          : SettingsDetailPage(
            key: _detailKey,
            repository: widget.repository,
              paymentRepository: widget.paymentRepository,
              destination: _destination!,
              storeName: widget.storeName,
              client: widget.client,
              permissions: widget.permissions,
              currentShopId: widget.currentShopId,
              onPasswordChanged: widget.onPasswordChanged,
              kdsRuntime: widget.kdsRuntime,
              onBack: () => setState(() => _destination = null),
    ),
  );
}

class _SettingsHub extends StatefulWidget {
  const _SettingsHub({
    required this.repository,
    required this.paymentRepository,
    required this.kdsAvailable,
    required this.onOpen,
    this.client,
    this.permissions = const {},
    this.currentShopId,
    this.onPasswordChanged,
    this.onOpenKdsDiagnostics,
  });

  final CashierSettingsRepository repository;
  final CashierPaymentRepository paymentRepository;
  final bool kdsAvailable;
  final ValueChanged<SettingsDestination> onOpen;
  final AdminApiClient? client;
  final Set<String> permissions;
  final int? currentShopId;
  final VoidCallback? onPasswordChanged;
  final VoidCallback? onOpenKdsDiagnostics;

  @override
  State<_SettingsHub> createState() => _SettingsHubState();
}

class _SettingsHubState extends State<_SettingsHub> {
  late Future<CashierSettingsOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.repository.loadSettingsOverview();
  }

  @override
  void didUpdateWidget(_SettingsHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentShopId != widget.currentShopId ||
        !setEquals(oldWidget.permissions, widget.permissions)) {
      _overview = widget.repository.loadSettingsOverview();
    }
  }

  bool _checkingUpdate = false;

  void _reload() => setState(() {
    _overview = widget.repository.loadSettingsOverview();
  });

  Future<void> _checkUpdate(BuildContext context) async {
    if (widget.client == null) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('客户端未连接网络，无法检查版本更新')));
      return;
    }
    setState(() => _checkingUpdate = true);
    try {
      final service = AppVersionService(client: widget.client!);
      final info = await service.checkUpdate(shopId: widget.currentShopId);
      if (!mounted) return;
      if (info.hasUpdate) {
        await showVersionUpgradeDialog(
          context,
          info: info,
          service: service);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本 (v${AppConfig.version})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CashierSettingsOverview>(
    future: _overview,
    builder: (context, snapshot) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1300
            ? 5
            : constraints.maxWidth >= 820
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final overview = snapshot.data;
        final destinations =
            snapshot.connectionState == ConnectionState.done && snapshot.hasData
            ? _visibleDestinations(overview)
            : const <SettingsDestination>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    '系统设置',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  if (widget.client != null)
                    Positioned(
                      right: 0,
                      child: OutlinedButton.icon(
                        key: const Key('settings-modify-password-button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xffed3d08),
                          side: const BorderSide(color: Color(0xffffd0c2)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          final changed =
                              await showCashierChangePasswordDialog(
                                context: context,
                                client: widget.client!,
                                currentShopId: widget.currentShopId,
                              );
                          if (changed == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('密码修改成功，请使用新密码重新登录'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 3),
                              ),
                            );
                            widget.onPasswordChanged?.call();
                          }
                        },
                        icon: const Icon(Icons.lock_reset_rounded, size: 20),
                        label: const Text('修改密码'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 48),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (snapshot.hasError)
                _SettingsOverviewError(error: snapshot.error, onRetry: _reload),
              if (snapshot.hasError) const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                mainAxisSpacing: 30,
                crossAxisSpacing: 24,
                childAspectRatio: 1.45,
                children: [
                  for (final destination in destinations)
                    _SettingsTile(
                      label: destination.label,
                      icon: destination == SettingsDestination.kds
                          ? Icons.developer_board_outlined
                          : destination.icon,
                      summary: destination == SettingsDestination.kds
                          ? (widget.kdsAvailable ? '局域网运行正常' : '需要检查设备')
                          : _summaryFor(destination, overview),
                      semanticLabel: destination == SettingsDestination.kds
                          ? '厨房KDS，${widget.kdsAvailable ? '运行正常' : '需要检查'}'
                          : null,
                      onTap:
                          destination == SettingsDestination.apiConsole
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ApiDebugConsolePage(),
                              ),
                            )
                          : () => widget.onOpen(destination),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '老肥家收银系统 · v${AppConfig.version}',
                    style: TextStyle(color: context.cashier.inkMuted, fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.client != null)
                    InkWell(
                      key: const Key('cashier-settings-check-update-button'),
                      onTap: _checkingUpdate ? null : () => _checkUpdate(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_checkingUpdate)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2,
                                ),
                              )
                            else
                              Icon(
                                Icons.refresh_rounded,
                                size: 14,
                                color: context.cashier.selected,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              _checkingUpdate ? '正在检查...' : '检查更新',
                              style: TextStyle(
                                color: context.cashier.selected,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  List<SettingsDestination> _visibleDestinations(
    CashierSettingsOverview? overview,
  ) {
    return overview == null
        ? const []
        : visibleSettingsDestinations(overview, widget.permissions);
  }

  String _summaryFor(
    SettingsDestination destination,
    CashierSettingsOverview? overview,
  ) {
    final module = overview?.module(destination.backendModule);
    if (module == null || module.summary.isEmpty) return destination.summary;
    return module.alerts > 0
        ? '${module.summary} · ${module.alerts} 项告警'
        : module.summary;
  }
}

class _SettingsOverviewError extends StatelessWidget {
  const _SettingsOverviewError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xfffff7ed),
        border: Border.all(color: const Color(0xfffed7aa)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xffc2410c)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '设置概览加载失败：$error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.label,
    required this.icon,
    required this.summary,
    required this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final String summary;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? context.cashier.surface : context.cashier.ink;
    final iconColor = isDark ? context.cashier.ink : Colors.white;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      child: Material(
        key: Key('settings-tile-$label'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(16),
                  border: isDark
                      ? Border.all(color: context.cashier.border)
                      : null,
                ),
                child: Icon(icon, color: iconColor, size: 40),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                summary,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.cashier.inkMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
