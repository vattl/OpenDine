import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/cashier_kds_database.dart';
import '../domain/cashier_kds_models.dart';
import '../domain/cashier_kds_interaction_log.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/admin_api_cashier_kds_proxy_client.dart';
import 'cashier_kds_storage.dart';
import 'cashier_kds_token_vault.dart';
import 'cashier_kds_lan_binding.dart';
import 'cashier_kds_tls.dart';
import 'cashier_kds_cert_generator.dart';
import '../../../core/cashier_operation_audit.dart';

class CashierKdsRuntime {
  CashierKdsRuntime._({
    required CashierKdsStorage storage,
    required CashierKdsDatabase database,
    required CashierKdsLanServer server,
    required InternetAddress? bindAddress,
    required String? bindError,
    required int configuredPort,
    required String cashierDeviceCode,
    required CashierKdsAuthorityLock? authorityLock,
    required CashierKdsTokenVault tokenVault,
    required CashierKdsTlsConfiguration? tlsConfiguration,
  }) : _storage = storage,
       _database = database,
       _server = server,
       _bindAddress = bindAddress,
       _bindError = bindError,
       _configuredPort = configuredPort,
       _cashierDeviceCode = cashierDeviceCode,
       _authorityLock = authorityLock,
       _tokenVault = tokenVault,
       _tlsConfiguration = tlsConfiguration;

  final CashierKdsStorage _storage;
  CashierKdsTlsConfiguration? _tlsConfiguration;

  final CashierKdsDatabase _database;
  CashierKdsDatabase get database => _database;
  final CashierKdsLanServer _server;
  final InternetAddress? _bindAddress;
  final String? _bindError;
  final int _configuredPort;
  final String _cashierDeviceCode;
  final CashierKdsAuthorityLock? _authorityLock;
  final CashierKdsTokenVault _tokenVault;
  AdminApiCashierKdsProxyClient? _cloudProxy;
  bool _cloudProxyConfigured = false;
  Timer? _maintenanceTimer;
  Future<void> _activation = Future.value();
  int? _activeShopId;
  int? _listeningShopId;
  String _lanStatus = 'waiting_for_login';
  String? _lanError;

  static Future<CashierKdsRuntime> start({
    Directory? applicationDataRoot,
    InternetAddress? bindAddress,
    int? port,
    CashierKdsTokenVault? tokenVault,
    CashierKdsTlsConfiguration? tlsConfiguration,
    bool autoGenerateTls = true,
    bool inMemory = false,
  }) async {
    final root = applicationDataRoot ?? await _applicationDataRoot();
    final storage = CashierKdsStorage(root);
    CashierKdsAuthorityLock? authorityLock;
    late final CashierKdsDatabase database;
    if (inMemory) {
      database = CashierKdsDatabase.inMemory();
    } else {
      await storage.prepare();
      authorityLock = await storage.acquireAuthorityLock();
      try {
        database = CashierKdsDatabase.open(storage.databasePath);
      } catch (_) {
        authorityLock.release();
        rethrow;
      }
    }
    database.cleanupRetention(nowMs: DateTime.now().millisecondsSinceEpoch);
    database.cleanupInteractionLogRetention(
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final resolvedTokenVault = tokenVault ?? CashierKdsTokenVault();
    CashierKdsTlsConfiguration? resolvedTlsConfiguration = tlsConfiguration;
    String? tlsConfigurationError;
    if (resolvedTlsConfiguration == null) {
      try {
        final detectedIps = <String>['127.0.0.1'];
        try {
          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              if (_isPrivateIpv4(addr.address)) {
                detectedIps.add(addr.address);
              }
            }
          }
        } catch (_) {}

        resolvedTlsConfiguration = await CashierKdsTlsConfiguration.resolve(
          applicationDataRoot: root,
          environment: Platform.environment,
          lanIps: detectedIps,
          autoGenerateIfMissing: autoGenerateTls,
        );
      } catch (error) {
        tlsConfigurationError = '$error';
      }
    }
    late final CashierKdsRuntime runtime;
    final server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onProxyLogin: (payload) async {
        final proxy = runtime._cloudProxy;
        if (proxy != null) {
          return proxy.proxyDeviceLogin(payload, shopId: runtime._activeShopId);
        }
        throw Exception('Cloud proxy not available');
      },
      onCacheCloudDeviceToken:
          ({required shopId, required deviceCode, required token}) =>
              resolvedTokenVault.cacheToken(
                shopId: shopId,
                deviceCode: deviceCode,
                token: token,
              ),
      onProxyHttp: (request) async {
        final proxy = runtime._cloudProxy;
        if (proxy != null) {
          return proxy.proxyKdsHttp(request, shopId: runtime._activeShopId);
        }
        throw Exception('Cloud proxy not available');
      },
      onProxyWebSocket: (deviceToken, queryParameters) async {
        final proxy = runtime._cloudProxy;
        if (proxy == null) {
          throw Exception('Cloud proxy not available');
        }
        final base = Uri.parse(proxy.cloudBaseUrl);
        final upstreamQuery = Map<String, String>.from(queryParameters)
          ..remove('token')
          ..remove('device_token');
        final upstreamUri = base.replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          path: '/ws/kds/v2',
          queryParameters: upstreamQuery,
        );
        return WebSocket.connect(
          upstreamUri.toString(),
          headers: {
            'X-Kds-Device-Token': deviceToken,
            if (runtime._activeShopId case final shopId?)
              'X-Shop-Id': '$shopId',
            'X-KDS-Proxy-Device-Code': proxy.cashierDeviceCode,
            'Via': 'cashier-lan/1.0',
          },
        ).timeout(const Duration(seconds: 8));
      },
    );
    final configuredPort =
        port ??
        database.readConfiguredLanPort() ??
        int.tryParse(Platform.environment['CASHIER_KDS_PORT'] ?? '') ??
        17026;
    final cashierDeviceCode = database.ensureCashierDeviceCode(
      Platform.environment['CASHIER_DEVICE_CODE'],
    );
    var binding = bindAddress == null
        ? await _selectBindAddress()
        : bindAddress.isLoopback || _isPrivateIpv4(bindAddress.address)
        ? (address: bindAddress, error: null)
        : (address: null, error: 'LAN KDS 监听地址必须是回环测试地址或明确的私网 IPv4，禁止通配监听');
    if (binding.address != null &&
        !binding.address!.isLoopback &&
        resolvedTlsConfiguration == null) {
      binding = (
        address: null,
        error:
            tlsConfigurationError ??
            'LAN KDS 私网代理未启动：TLS 证书未配置且自动生成失败',
      );
    }
    runtime = CashierKdsRuntime._(
      storage: storage,
      database: database,
      server: server,
      bindAddress: binding.address,
      bindError: binding.error,
      configuredPort: configuredPort,
      cashierDeviceCode: cashierDeviceCode,
      authorityLock: authorityLock,
      tokenVault: resolvedTokenVault,
      tlsConfiguration: resolvedTlsConfiguration,
    );
    runtime._maintenanceTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(runtime.runPeriodicMaintenance()),
    );
    return runtime;
  }

  static Future<Directory> _applicationDataRoot() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        return supportDir;
      } catch (_) {
        // Fallback if running in non-Flutter headless/test environment
        if (Platform.isAndroid) {
          return Directory(p.join(Directory.systemTemp.parent.path, 'files'));
        }
      }
    }
    final appData = Platform.environment['LOCALAPPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) return Directory(appData);
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, '.local', 'share'));
    }
    return Directory.current;
  }

  static Future<({InternetAddress? address, String? error})>
  _selectBindAddress() async {
    final configured = Platform.environment['CASHIER_KDS_BIND_ADDRESS']?.trim();
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final selected = CashierKdsLanBindingPolicy.select([
        for (final interface in interfaces)
          for (final address in interface.addresses)
            CashierKdsLanInterfaceAddress(
              interfaceName: interface.name,
              address: address.address,
            ),
      ], configuredAddress: configured);
      return (address: InternetAddress(selected.address), error: null);
    } catch (error) {
      return (address: null, error: '$error');
    }
  }

  static bool _isPrivateIpv4(String address) =>
      CashierKdsLanBindingPolicy.isPrivateIpv4(address);

  bool get isAvailable => _server.port > 0;
  String get cashierDeviceCode => _cashierDeviceCode;
  String get lanStatus => _lanStatus;
  String? get lanError => _lanError;
  String? get lanCertificateSha256 => _tlsConfiguration?.certificateSha256;
  String? get caCertificatePath => _tlsConfiguration?.caCertificatePath;
  String? get serverCertificatePath => _tlsConfiguration?.certificatePath;

  Future<void> regenerateTlsCertificates({List<String>? extraIps}) async {
    final certsDir = _storage.certsDirectory;
    final ips = <String>{'127.0.0.1'};
    if (_bindAddress != null) {
      ips.add(_bindAddress.address);
    }
    if (extraIps != null) {
      ips.addAll(extraIps);
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivateIpv4(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}

    await CashierKdsCertGenerator.generate(
      certsDirectory: certsDir,
      ipAddresses: ips.toList(),
      dnsNames: const ['localhost', 'lan-cashier.local'],
      force: true,
    );

    _tlsConfiguration = CashierKdsTlsConfiguration.fromDirectory(certsDir);
    _lanError = null;
    await restartLanServer();
  }

  int get lanPort => _server.port;
  int get configuredPort => _configuredPort;
  int get connectedDeviceCount => _server.connectedDeviceCount;
  List<CashierKdsDevice> get pairedDevices => _server.pairedDevices;
  int get droppedInteractionLogCount => _database.droppedInteractionLogCount;
  List<CashierKdsInteractionLog> get interactionLogs {
    final shopId = _activeShopId;
    if (shopId == null) return const [];
    return _database.readInteractionLogs(
      CashierKdsInteractionLogFilter(
        shopId: shopId,
        fromMs:
            DateTime.now().millisecondsSinceEpoch -
            const Duration(days: 30).inMilliseconds,
      ),
    );
  }

  void setActiveShop(int? shopId) {
    final normalized = shopId != null && shopId > 0 ? shopId : null;
    if (_activeShopId == normalized) return;
    _activeShopId = normalized;
    _server.setActiveShop(normalized);
    unawaited(refreshProxyListener());
  }

  String generatePairingCode() => _server.generatePairingCode();

  Future<void> unbindDevice({
    required int shopId,
    required String deviceCode,
  }) async {
    final device = _database.readDeviceByCode(deviceCode);
    await _server.revokeDevice(deviceCode);
    if (device != null) {
      await _tokenVault.deleteToken(
        shopId: device.shopId,
        deviceCode: device.deviceCode,
      );
    }
    _database.removeDevice(deviceCode);
  }

  Future<CashierKdsDevice> upsertBoundDevice({
    required int shopId,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    List<String> workflows = const ['prep', 'cook', 'serve'],
    List<String> screenTags = const [],
    bool enabled = true,
  }) async => _database.upsertBoundDevice(
    shopId: shopId,
    deviceCode: deviceCode,
    deviceName: deviceName,
    screenTag: screenTag,
    workflows: workflows,
    screenTags: screenTags,
    enabled: enabled,
  );

  Future<void> syncBoundDevices(
    List<Map<String, Object?>> devices, {
    required int shopId,
  }) async {
    for (final raw in devices) {
      final code = '${raw['deviceCode'] ?? raw['device_code'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      final workflows = raw['workflows'] is List
          ? (raw['workflows'] as List).map((item) => '$item').toList()
          : const ['prep', 'cook', 'serve'];
      final rawTags = raw['screenTags'] ?? raw['screen_tags'];
      _database.upsertBoundDevice(
        shopId: shopId,
        deviceCode: code,
        deviceName: '${raw['deviceName'] ?? raw['device_name'] ?? code}'.trim(),
        screenTag:
            '${raw['screenTag'] ?? raw['screen_tag'] ?? 'workflow_board'}'
                .trim(),
        workflows: workflows,
        screenTags: rawTags is List
            ? rawTags.map((item) => '$item').toList()
            : const [],
        enabled:
            raw['enabled'] == null ||
            raw['enabled'] == 1 ||
            raw['enabled'] == true ||
            raw['enabled'] == '1',
      );
    }
  }

  Future<List<String>> lanAddresses() async {
    final address = _server.address;
    final port = _server.port > 0 ? _server.port : _configuredPort;
    if (address != null && _isPrivateIpv4(address.address)) {
      return ['https://${address.address}:$port'];
    }
    final bindAddress = _bindAddress;
    if (bindAddress != null && _isPrivateIpv4(bindAddress.address)) {
      return ['https://${bindAddress.address}:$port'];
    }
    return const [];
  }

  void configureCloudProxy(AdminApiCashierKdsProxyClient? proxy) {
    _cloudProxy = proxy;
    _cloudProxyConfigured = proxy != null;
    unawaited(refreshProxyListener());
  }

  Future<void> restartLanServer() async {
    await _server.close();
    if (_activeShopId != null && _cloudProxyConfigured) {
      final bindAddress = _bindAddress;
      if (bindAddress == null) {
        _lanStatus = 'listen_blocked';
        _lanError = _bindError ?? '未发现可信私网网卡';
        return;
      }
      try {
        await _server.start(
          address: bindAddress,
          port: _configuredPort,
          securityContext: _tlsConfiguration?.securityContext,
        );
        _lanStatus = 'active';
        _lanError = null;
      } catch (error) {
        _lanStatus = 'listen_failed';
        _lanError = '局域网 KDS 端口重启失败：$error';
        rethrow;
      }
    } else {
      await refreshProxyListener();
    }
  }

  Future<void> refreshProxyListener() {
    final next = _activation.then((_) => _reconcileProxyListener());
    _activation = next.catchError((_) {});
    return next;
  }

  Future<void> _reconcileProxyListener() async {
    final shopId = _activeShopId;
    if (shopId == null || !_cloudProxyConfigured) {
      await _server.close();
      _listeningShopId = null;
      _lanStatus = shopId == null
          ? 'waiting_for_login'
          : 'waiting_for_cloud_proxy';
      _lanError = null;
      return;
    }
    if (_listeningShopId != null && _listeningShopId != shopId) {
      await _server.close();
      _listeningShopId = null;
    }
    final bindAddress = _bindAddress;
    if (bindAddress == null) {
      await _server.close();
      _listeningShopId = null;
      _lanStatus = 'listen_blocked';
      _lanError = _bindError ?? '未发现可信私网网卡';
      return;
    }
    if (_server.port == 0) {
      try {
        await _server.start(
          address: bindAddress,
          port: _configuredPort,
          securityContext: _tlsConfiguration?.securityContext,
        );
      } catch (error) {
        _lanStatus = 'listen_failed';
        _lanError = '局域网 KDS 端口启动失败：$error';
        return;
      }
    }
    _listeningShopId = shopId;
    _lanStatus = 'active';
    _lanError = null;
  }

  Future<void> runPeriodicMaintenance({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    try {
      _database.cleanupRetention(nowMs: now, maxTerminalRowsPerRun: 10000);
    } catch (e) {
      stderr.writeln('[KDS-MAINTENANCE] cleanupRetention warning: $e');
    }
    try {
      _database.cleanupInteractionLogRetention(nowMs: now);
    } catch (e) {
      stderr.writeln('[KDS-MAINTENANCE] cleanupInteractionLogRetention warning: $e');
    }
    try {
      _database.walCheckpointPassive();
    } catch (e) {
      stderr.writeln('[KDS-MAINTENANCE] walCheckpointPassive warning: $e');
    }
    try {
      CashierOperationAuditStore.instance.trim();
    } catch (e) {
      stderr.writeln('[KDS-MAINTENANCE] CashierOperationAuditStore trim warning: $e');
    }
    try {
      _server.pruneStaleLoginAttempts(nowMs: now);
    } catch (e) {
      stderr.writeln('[KDS-MAINTENANCE] pruneStaleLoginAttempts warning: $e');
    }
  }

  Future<void> close() async {
    _maintenanceTimer?.cancel();
    try {
      await _server.close();
    } finally {
      try {
        _database.close();
      } finally {
        _authorityLock?.release();
      }
    }
  }
}
