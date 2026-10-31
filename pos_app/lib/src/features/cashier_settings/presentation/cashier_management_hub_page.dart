import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../cashier_payment/data/cashier_payment_repository.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../kds_local/runtime/cashier_kds_runtime.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_catalogue.dart';
import 'cashier_settings_detail_pages.dart';
import 'cashier_settings_shared.dart';

class CashierManagementHubPage extends StatefulWidget {
  const CashierManagementHubPage({
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
    this.initialDestination,
  });

  final CashierSettingsRepository repository;
  final CashierPaymentRepository paymentRepository;
  final String storeName;
  final bool kdsAvailable;
  final AdminApiClient? client;
  final Set<String> permissions;
  final int? currentShopId;
  final VoidCallback? onPasswordChanged;
  final VoidCallback? onOpenKdsDiagnostics;
  final CashierKdsRuntime? kdsRuntime;
  final SettingsDestination? initialDestination;

  @override
  State<CashierManagementHubPage> createState() => _CashierManagementHubPageState();
}

class _CashierManagementHubPageState extends State<CashierManagementHubPage> {
  late Future<CashierSettingsOverview> _overview;
  SettingsDestination? _selected;
  bool _detailOpen = false;
  String _query = '';
  var _detailKey = GlobalKey<SettingsDetailPageState>();

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDestination;
    _overview = widget.repository.loadSettingsOverview();
  }

  @override
  void didUpdateWidget(CashierManagementHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.client != widget.client ||
        oldWidget.currentShopId != widget.currentShopId ||
        !setEquals(oldWidget.permissions, widget.permissions)) {
      // A new security/store context cannot retain old forms or pending results.
      _detailKey = GlobalKey<SettingsDetailPageState>();
      _selected = null;
      _detailOpen = false;
      _overview = widget.repository.loadSettingsOverview();
    }
  }

  Future<void> _select(SettingsDestination destination) async {
    if (_selected == destination && _detailOpen) return;
    final originalKey = _detailKey;
    if (!await (_detailKey.currentState?.confirmLeave() ?? Future.value(true)))
      return;
    if (!mounted || originalKey != _detailKey) return;
    setState(() {
      _selected = destination;
      _detailOpen = true;
      _detailKey = GlobalKey<SettingsDetailPageState>();
    });
  }

  void _reload() =>
      setState(() => _overview = widget.repository.loadSettingsOverview());

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: context.cashier.canvas,
      child: FutureBuilder<CashierSettingsOverview>(
      future: _overview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return SettingsErrorState(
            message: '管理模块加载失败：${snapshot.error ?? "未返回概览"}',
            onRetry: _reload,
          );
        }
        final destinations = visibleSettingsDestinations(
          snapshot.data!,
          widget.permissions,
        );
        if (destinations.isEmpty) {
          return const SettingsEmptyState(
            title: '暂无可用模块',
            description: '请联系管理员配置权限。',
          );
        }
        final selected = destinations.contains(_selected)
            ? _selected!
            : destinations.first;
        return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
            // Once a detail is visible, narrowing the window must retain it.
            if (wide) _detailOpen = true;
    final detail = SettingsDetailPage(
                      key: _detailKey,
              repository: widget.repository,
          paymentRepository: widget.paymentRepository,
          destination: selected,
          storeName: widget.storeName,
          client: widget.client,
          permissions: widget.permissions,
          currentShopId: widget.currentShopId,
          onPasswordChanged: widget.onPasswordChanged,
          kdsRuntime: widget.kdsRuntime,
              showBack: !wide,
              onBack: () => setState(() => _detailOpen = false),
            );
            if (wide) {
              return Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: _directory(destinations, selected),
                  ),
                  Expanded(child: detail),
                ],
              );
            }
            return _detailOpen ? detail : _directory(destinations, selected);
          },
        );
    },
    ),
  );

  Widget _directory(
    List<SettingsDestination> destinations,
    SettingsDestination selected,
  ) {
    final theme = context.cashier;
    final filtered = destinations
        .where(
          (d) =>
              _query.isEmpty ||
              d.label.contains(_query) ||
              d.sections.any((s) => s.label.contains(_query)),
        )
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(right: BorderSide(color: theme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '业务中台配置',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${destinations.length} 模块',
                    style: TextStyle(fontSize: 11, color: theme.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('manage-module-search'),
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '搜索模块或功能',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final d in filtered)
                    Material(
                      color: d == selected ? theme.subtle : Colors.transparent,
                      child: InkWell(
                        key: Key(
                          'manage-nav-${d == SettingsDestination.apiConsole ? "api-console" : d.name}',
                        ),
                        onTap: () => _select(d),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: d == selected
                                    ? theme.ink
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(d.icon, size: 19, color: theme.inkSecondary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  d.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: d == selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${d.sections.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('没有匹配的模块'),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '配置范围 · 当前门店',
              style: TextStyle(fontSize: 11, color: theme.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
