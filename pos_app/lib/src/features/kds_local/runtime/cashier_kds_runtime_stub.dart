import 'dart:async';

import '../domain/cashier_kds_interaction_log.dart';
import '../domain/cashier_kds_models.dart';
import '../sync/admin_api_cashier_kds_proxy_client.dart';

class CashierKdsRuntime {
  const CashierKdsRuntime._();

  static Future<CashierKdsRuntime> start({
    Object? applicationDataRoot,
    Object? bindAddress,
    int? port,
    Object? tokenVault,
    Object? tlsConfiguration,
    bool autoGenerateTls = true,
    bool inMemory = false,
  }) async => const CashierKdsRuntime._();

  dynamic get database =>
      throw UnsupportedError('Local KDS storage is unavailable');
  bool get isAvailable => false;
  String get cashierDeviceCode => '';
  String get lanStatus => 'unavailable';
  String? get lanError => null;
  String? get lanCertificateSha256 => null;
  String? get caCertificatePath => null;
  String? get serverCertificatePath => null;

  int get lanPort => 0;
  int get configuredPort => 17026;
  int get connectedDeviceCount => 0;
  List<CashierKdsDevice> get pairedDevices => const [];
  int get droppedInteractionLogCount => 0;
  List<CashierKdsInteractionLog> get interactionLogs => const [];
  void setActiveShop(int? shopId) {}

  String generatePairingCode() =>
      throw UnsupportedError('LAN KDS is unavailable');

  Future<void> unbindDevice({
    required int shopId,
    required String deviceCode,
  }) async {}

  Future<CashierKdsDevice?> upsertBoundDevice({
    required int shopId,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    List<String> workflows = const ['prep', 'cook', 'serve'],
    List<String> screenTags = const [],
    bool enabled = true,
  }) async => null;

  Future<void> syncBoundDevices(
    List<Map<String, Object?>> devices, {
    required int shopId,
  }) async {}

  Future<List<String>> lanAddresses() async => const [];

  Future<void> restartLanServer() async =>
      throw UnsupportedError('LAN KDS is unavailable');

  Future<void> regenerateTlsCertificates({List<String>? extraIps}) async =>
      throw UnsupportedError('LAN KDS is unavailable');

  void configureCloudProxy(AdminApiCashierKdsProxyClient? proxy) {}

  Future<void> refreshProxyListener() async {}

  Future<void> runPeriodicMaintenance({int? nowMs}) async {}

  Future<void> close() async {}
}
