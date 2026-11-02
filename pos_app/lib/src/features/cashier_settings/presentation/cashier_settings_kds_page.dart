import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../kds_local/presentation/cashier_kds_diagnostics_page.dart';
import '../../kds_local/presentation/kds_devices_page.dart';
import '../../kds_local/runtime/cashier_kds_runtime.dart';
import '../data/cashier_settings_repository.dart';
import 'cashier_settings_shared.dart';

/// Cashier-side KDS management is intentionally limited to proxy operations.
/// Business configuration and data remain cloud-owned.
class CashierSettingsKdsPage extends StatelessWidget {
  const CashierSettingsKdsPage({
    super.key,
    required this.repository,
    required this.section,
    this.client,
    this.currentShopId,
    this.kdsRuntime,
    this.canManageKds = false,
  });

  // Retained in the route contract so the generic settings host does not need
  // a KDS-only construction path. KDS business settings are no longer read.
  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;
  final AdminApiClient? client;
  final int? currentShopId;
  final CashierKdsRuntime? kdsRuntime;
  final bool canManageKds;

  @override
  Widget build(BuildContext context) {
    final runtime = kdsRuntime;
    if (section.id == 'devices') {
      final cloudClient = client;
      if (cloudClient == null) {
        return const Center(child: Text('当前收银会话未配置云端客户端'));
      }
      return KdsDevicesPage(
        client: cloudClient,
        currentShopId: currentShopId,
        kdsRuntime: runtime,
        canManage: canManageKds,
        showLanPairing: false,
        showCloudSync: false,
      );
    }
    if (runtime == null) {
      return const Center(child: Text('当前平台未启动 KDS 局域网代理'));
    }
    return switch (section.id) {
      'requests' => CashierKdsProxyRequestPanel(runtime: runtime),
      _ => CashierKdsConnectionPanel(runtime: runtime, canManage: canManageKds),
    };
  }
}
