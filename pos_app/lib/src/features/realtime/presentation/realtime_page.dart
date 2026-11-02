import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/realtime_repository.dart';
import '../domain/realtime_models.dart';

class RealtimePage extends StatefulWidget {
  const RealtimePage({
    super.key,
    required this.appState,
    required this.repository,
  });

  final AppState appState;
  final RealtimeRepository repository;

  @override
  State<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends State<RealtimePage> {
  Map<String, Object?>? kdsConfig;
  List<Map<String, Object?>> deliveries = const [];
  String? error;
  bool loading = true;
  bool updatingConfig = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RealtimePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      _load();
    }
  }

  Map<String, Object?> get _config {
    final root = kdsConfig ?? const <String, Object?>{};
    return root['config'] is Map
        ? (root['config'] as Map).cast<String, Object?>()
        : root;
  }

  bool _isFlagTrue(Object? value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  Future<void> _load() async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final config = await widget.repository.loadKdsConfig(shopId: shopId);
      final takeout = await widget.repository.loadTakeoutDeliveries(
        shopId: shopId,
      );
      if (mounted) {
        setState(() {
          kdsConfig = config;
          deliveries = takeout;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _togglePrepWorkflow(bool enabled) async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null || updatingConfig) return;
    setState(() => updatingConfig = true);
    try {
      await widget.repository.saveKdsConfig(
        shopId: shopId,
        config: {
          'enable_prep_workflow': enabled ? 1 : 0,
          'prep_enabled': enabled ? 1 : 0,
        },
      );
      final updated = await widget.repository.loadKdsConfig(shopId: shopId);
      if (mounted) {
        setState(() => kdsConfig = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '已开启待配菜流程' : '已关闭待配菜流程（直推烤制屏）'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => updatingConfig = false);
    }
  }

  Future<void> _toggleServePrint(bool enabled) async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null || updatingConfig) return;
    setState(() => updatingConfig = true);
    try {
      await widget.repository.saveKdsConfig(
        shopId: shopId,
        config: {'serve_print_enabled': enabled ? 1 : 0},
      );
      final updated = await widget.repository.loadKdsConfig(shopId: shopId);
      if (mounted) {
        setState(() => kdsConfig = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '已开启待传菜打印传菜单' : '已关闭待传菜打印传菜单'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => updatingConfig = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const reconnect = KdsReconnectPlan(
      wsPath: '/ws/kds',
      incrementalSyncPath: '/kds/sync/changes',
      lastEventId: 1,
    );
    final prepVal = _config['enable_prep_workflow'] ??
        _config['prep_enabled'] ??
        _config['skewer_gate'];
    final prepWorkflowEnabled = _isFlagTrue(prepVal, fallback: true);
    final servePrintEnabled = _isFlagTrue(
      _config['serve_print_enabled'],
      fallback: true,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (loading || updatingConfig) const LinearProgressIndicator(),
        if (error != null)
          Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('实时模块加载失败'),
              subtitle: Text(error!),
              trailing: TextButton(onPressed: _load, child: const Text('重试')),
            ),
          ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(
                leading: Icon(Icons.settings_suggest_rounded),
                title: Text(
                  '厨房 KDS 工作流配置',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('控制厨房厨显屏流程与传菜打印联动'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('realtime-prep-workflow-switch'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                secondary: const Icon(Icons.soup_kitchen_rounded),
                title: const Text('待配菜流程 (enable_prep_workflow)'),
                subtitle: const Text(
                  '开启时新订单先进入待配菜环节（pending_prep）；关闭后下单直接进入待制作（pending_cook）',
                ),
                value: prepWorkflowEnabled,
                onChanged: updatingConfig ? null : _togglePrepWorkflow,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('realtime-serve-print-switch'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                secondary: const Icon(Icons.room_service_rounded),
                title: const Text('待传菜打印传菜单 (serve_print_enabled)'),
                subtitle: const Text('待传菜划单完成后，按实际传菜明细打印飞鹅传菜单'),
                value: servePrintEnabled,
                onChanged: updatingConfig ? null : _toggleServePrint,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('KDS 设备鉴权规则'),
            subtitle: const Text('厨显设备端必须使用 X-Kds-Device-Token，不复用 B 端 JWT。'),
            trailing: Text(kdsConfig == null ? '未加载' : '已加载配置'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('WebSocket 断线恢复'),
            subtitle: Text(
              '${reconnect.wsPath} 断线后通过 ${reconnect.incrementalSyncPath} 补齐状态',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delivery_dining_outlined),
            title: const Text('外卖配送履约'),
            subtitle: Text('当前接口返回 ${deliveries.length} 条配送记录；退款/取消必须展示责任提示。'),
          ),
        ),
        for (final delivery in deliveries.take(20))
          Card(
            child: ListTile(
              title: Text(
                '${delivery['order_no'] ?? delivery['orderNo'] ?? delivery['id'] ?? '-'}',
              ),
              subtitle: Text(
                '状态: ${delivery['dispatch_status'] ?? delivery['zsq_phase'] ?? '-'} / 骑手: ${delivery['zsq_rider_name'] ?? '-'}',
              ),
            ),
          ),
      ],
    );
  }
}
