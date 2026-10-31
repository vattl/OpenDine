import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/device/kds_device_code_resolver.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/storage/session_storage.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';
import 'package:kds_app/core/ws/kds_ws_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionState {
  const SessionState({
    this.device,
    this.token,
    this.apiBase = '',
    this.cloudApiBase = '',
    this.connectionMode = KdsConnectionMode.cloudFirst,
    this.activeChannel = KdsActiveChannel.cloud,
    this.loading = false,
    this.error,
    this.connectionGeneration = 0,
    this.lanLoginSuggested = false,
  });

  final KdsDevice? device;
  final String? token;
  final String apiBase;
  final String cloudApiBase;
  final KdsConnectionMode connectionMode;
  final KdsActiveChannel activeChannel;
  final bool loading;
  final String? error;
  final int connectionGeneration;
  final bool lanLoginSuggested;

  bool get isLoggedIn => device != null && token != null && token!.isNotEmpty;

  /// 当前通信使用的实际基址
  String get effectiveActiveBase =>
      activeChannel == KdsActiveChannel.cloud && cloudApiBase.isNotEmpty
          ? cloudApiBase
          : apiBase;

  /// 当前通信使用的有效 Token（统一使用云端签发的权威 token，两通道共用）
  String? get effectiveActiveToken => token;

  SessionState copyWith({
    KdsDevice? device,
    String? token,
    String? apiBase,
    String? cloudApiBase,
    KdsConnectionMode? connectionMode,
    KdsActiveChannel? activeChannel,
    bool? loading,
    String? error,
    bool clearError = false,
    int? connectionGeneration,
    bool? lanLoginSuggested,
  }) {
    return SessionState(
      device: device ?? this.device,
      token: token ?? this.token,
      apiBase: apiBase ?? this.apiBase,
      cloudApiBase: cloudApiBase ?? this.cloudApiBase,
      connectionMode: connectionMode ?? this.connectionMode,
      activeChannel: activeChannel ?? this.activeChannel,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      connectionGeneration: connectionGeneration ?? this.connectionGeneration,
      lanLoginSuggested: lanLoginSuggested ?? this.lanLoginSuggested,
    );
  }
}

KdsDevice mergeRemoteKdsDevice(
  KdsDevice current,
  KdsDevice remote, {
  required String token,
}) {
  final screenTag = remote.workflows.isNotEmpty
      ? KdsScreenTag.workflowBoard
      : remote.screenTag;
  return KdsDevice(
    id: remote.id,
    shopId: remote.shopId,
    screenTag: screenTag,
    deviceCode: remote.deviceCode,
    deviceToken: token,
    workflows: remote.workflows,
    // D026：岗配置以服务端（device/me 回显）为准
    screenTags: remote.screenTags,
    deviceName: remote.deviceName ?? current.deviceName,
  );
}

class SessionNotifier extends Notifier<SessionState> {
  SessionStorage? _storage;
  KdsApiClient? _client;
  KdsApi? _api;
  KdsWebSocketService? _ws;
  Timer? _heartbeat;

  SessionStorage? get storageOrNull => _storage;

  SessionStorage get storage {
    assert(_storage != null, 'call bootstrap() first');
    return _storage!;
  }

  bool _heartbeatPaused = false;

  /// 只有移动端切后台才允许挂起心跳。KDS 在桌面端是常驻看板，
  /// 窗口失焦/最小化不代表"退到后台"，挂起会导致收银端把设备判为离线、
  /// 停止推送新订单（Windows 版失焦不刷新的根因）。
  bool get _allowLifecyclePause =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void pauseHeartbeat() {
    _heartbeatPaused = true;
  }

  void resumeHeartbeat() {
    _heartbeatPaused = false;
  }

  void handleAppPaused() {
    if (!_allowLifecyclePause) return;
    pauseHeartbeat();
  }

  Future<void> handleAppResumed() async {
    resumeHeartbeat();
    final device = state.device;
    if (device == null || !state.isLoggedIn) return;
    try {
      await api.heartbeat(device.deviceCode);
    } catch (_) {
      // Reconnection below remains authoritative even if heartbeat is delayed.
    }
    await _syncDeviceFromServer(restartConnection: false);
    if (state.isLoggedIn) _startWsAndHeartbeat();
  }

  KdsWebSocketService? get webSocket => _ws;

  KdsApi get api {
    assert(_api != null, 'call bootstrap() first');
    return _api!;
  }

  KdsApiClient get apiClient {
    assert(_client != null, 'call bootstrap() first');
    return _client!;
  }

  @override
  SessionState build() {
    ref.onDispose(_dispose);
    return const SessionState();
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _storage = SessionStorage(const FlutterSecureStorage(), prefs);
    final storage = _storage!;
    // 迁移：修正历史错误 API 基址（htps、空格、:0 等）
    final rawApi = prefs.getString('kds_api_base');
    if (rawApi != null && rawApi.trim().isNotEmpty) {
      await storage.setApiBase(rawApi);
    }
    var apiBase = storage.getApiBase();
    var cloudApiBase = storage.getCloudApiBase();
    String? insecureLanMigrationError;
    if (apiBase.isNotEmpty && !isPrivateLanApiBase(apiBase)) {
      await storage.setApiBase('');
      apiBase = '';
    } else if (kReleaseMode &&
        apiBase.isNotEmpty &&
        !isSecurePrivateLanApiBase(apiBase)) {
      await storage.setApiBase('');
      apiBase = '';
      insecureLanMigrationError = '历史局域网地址使用明文 HTTP，已停用；请重新填写 HTTPS 收银端地址';
    }
    final rawMode = storage.getConnectionModeRaw();
    final mode = KdsConnectionMode.fromValue(rawMode);
    if (rawMode != mode.value) {
      await storage.setConnectionModeRaw(mode.value);
    }
    var token = await storage.readToken();
    var sessionJson = storage.readSessionJson();

    final initialChannel =
        cloudApiBase.isNotEmpty ? KdsActiveChannel.cloud : KdsActiveChannel.lan;

    state = state.copyWith(
      token: token,
      apiBase: apiBase,
      cloudApiBase: cloudApiBase,
      connectionMode: mode,
      activeChannel: initialChannel,
      error: insecureLanMigrationError,
    );

    _initClient(state.effectiveActiveBase, token);

    if (token != null && sessionJson != null) {
      final device = KdsDevice.fromJson(sessionJson, token: token);
      state = state.copyWith(
          device: device,
          token: token,
          apiBase: apiBase,
          cloudApiBase: cloudApiBase,
          connectionMode: mode,
          activeChannel: initialChannel,
          error: insecureLanMigrationError,
          clearError: insecureLanMigrationError == null);
      // 单 Token 迁移：删除历史版本留下的第二份云端凭据。
      await storage.clearCloudToken();
      await _validateAndConnect();
    }
  }

  void _initClient(String activeBase, String? token) {
    _client = KdsApiClient(
      getBaseUrl: () => state.effectiveActiveBase,
      getToken: () => state.effectiveActiveToken,
      onUnauthorized: () {
        logout();
      },
    );
    _api = KdsApi(_client!);
  }

  Future<bool> login({
    required String deviceCode,
    required KdsScreenTag screenTag,
    int? shopId,
    String? kdsPin,
    List<KdsWorkflow> workflows = const [],
    List<String> screenTags = const [],
    String? deviceName,
    String? pairingCode,
    required String apiBase,
    String? cloudApiBase,
    KdsConnectionMode mode = KdsConnectionMode.cloudFirst,
    KdsActiveChannel initialChannel = KdsActiveChannel.cloud,
  }) async {
    const effectiveMode = KdsConnectionMode.cloudFirst;
    final trimmedLan = apiBase.trim();
    if (trimmedLan.isNotEmpty) {
      if (!isValidApiBase(trimmedLan)) {
        state = state.copyWith(loading: false, error: '局域网收银端地址无效');
        return false;
      }
      if (!isPrivateLanApiBase(trimmedLan)) {
        state = state.copyWith(loading: false, error: '收银端地址仅支持私有局域网');
        return false;
      }
      if (kReleaseMode && !isSecurePrivateLanApiBase(trimmedLan)) {
        state = state.copyWith(
          loading: false,
          error: '正式版仅允许 HTTPS 局域网代理，禁止通过明文 HTTP 传输设备 Token',
        );
        return false;
      }
    }
    if (cloudApiBase == null || cloudApiBase.isEmpty) {
      state = state.copyWith(loading: false, error: '云端优先模式必须填写云端 API 地址');
      return false;
    }
    if (!isValidApiBase(cloudApiBase)) {
      state = state.copyWith(loading: false, error: '云端 API 地址无效');
      return false;
    }
    state = state.copyWith(
      loading: true,
      clearError: true,
      lanLoginSuggested: false,
    );
    try {
      await storage.setApiBase(trimmedLan);
      await storage.setCloudApiBase(cloudApiBase);
      await storage.setConnectionModeRaw(effectiveMode.value);

      final effectiveCloud = storage.getCloudApiBase();
      state = state.copyWith(
        apiBase: storage.getApiBase(),
        cloudApiBase: effectiveCloud,
        connectionMode: effectiveMode,
        activeChannel: initialChannel,
      );
      _initClient(state.effectiveActiveBase, state.token);

      // D026：重登回传本地持久化的可见岗；显式传入可覆盖（换岗走重新登录）
      final effectiveScreenTags = screenTags.isNotEmpty
          ? screenTags
          : (state.device?.screenTags ?? const []);

      Future<KdsDevice> loginOnActiveChannel() => api.login(
            deviceCode: deviceCode.trim(),
            screenTag: screenTag,
            shopId: shopId,
            kdsPin: kdsPin?.trim(),
            workflows: workflows,
            screenTags: effectiveScreenTags,
            deviceName: deviceName?.trim(),
            pairingCode: pairingCode?.trim(),
            currentToken: state.token,
          );

      var device = await loginOnActiveChannel();

      device = _asWorkflowBoardDevice(device, requested: workflows);

      await storage.saveToken(device.deviceToken);
      await storage.saveSessionJson(device.toJson());
      await storage.clearCloudToken();
      if (device.shopId > 0) {
        await storage.setLastShopId(device.shopId);
      }
      if (device.workflows.isNotEmpty) {
        await storage.setLastWorkflows(
          device.workflows.map((w) => w.apiValue).toList(),
        );
      }
      if (device.deviceName != null && device.deviceName!.isNotEmpty) {
        await storage.setLastDeviceName(device.deviceName!);
      }

      state = state.copyWith(
        device: device,
        token: device.deviceToken,
        loading: false,
        clearError: true,
        lanLoginSuggested: false,
      );

      await KdsDeviceCodeResolver().persistSuccessfulLogin(device.deviceCode);

      // 访问审计：登录成功（不记录 token 等敏感信息）
      KdsFileLogger.info(
          '[AUTH] 登录成功 device=${device.deviceCode} screen=${screenTag.value} workflows=${workflows.map((w) => w.apiValue).join(',')}');

      _startWsAndHeartbeat();
      unawaited(_syncDeviceFromServer(restartConnection: false));
      return true;
    } on ApiException catch (e) {
      KdsFileLogger.warn('[AUTH] 登录失败: ${e.message}');
      final pairingCredentialRequired = _requiresPairingCredential(e);
      final canRetryViaLan = initialChannel == KdsActiveChannel.cloud &&
          e.isNetworkError &&
          state.apiBase.isNotEmpty;
      state = state.copyWith(
        loading: false,
        error: pairingCredentialRequired
            ? '设备 Token 已失效，请在收银端生成一次性配对码后重新登录'
            : canRetryViaLan
                ? '云端延迟过高或无响应，可切换局域网代理重试'
                : e.message,
        lanLoginSuggested: canRetryViaLan,
      );
      return false;
    } catch (e) {
      KdsFileLogger.warn('[AUTH] 登录失败: $e');
      state = state.copyWith(
        loading: false,
        error: e.toString(),
        lanLoginSuggested: false,
      );
      return false;
    }
  }

  bool _requiresPairingCredential(ApiException error) {
    final forbidden = error.code == 403 || error.statusCode == 403;
    if (!forbidden) return false;
    return error.message.contains('有效设备 Token') ||
        error.message.contains('重新配对');
  }

  KdsDevice _asWorkflowBoardDevice(KdsDevice device,
      {List<KdsWorkflow> requested = const []}) {
    final flows = device.workflows.isNotEmpty ? device.workflows : requested;
    if (flows.isEmpty) return device;
    return KdsDevice(
      id: device.id,
      shopId: device.shopId,
      screenTag: KdsScreenTag.workflowBoard,
      deviceCode: device.deviceCode,
      deviceToken: device.deviceToken,
      workflows: flows,
      screenTags: device.screenTags,
      deviceName: device.deviceName,
    );
  }

  /// 看板 / device/me 回写服务端 workflows（v1.2.118 会话缓存）
  Future<void> applyRemoteWorkflows(List<KdsWorkflow> workflows) async {
    final device = state.device;
    if (device == null) return;
    if (_sameWorkflows(device.workflows, workflows)) return;
    final next = _asWorkflowBoardDevice(
      KdsDevice(
        id: device.id,
        shopId: device.shopId,
        screenTag: device.screenTag,
        deviceCode: device.deviceCode,
        deviceToken: device.deviceToken,
        workflows: workflows,
        screenTags: device.screenTags,
        deviceName: device.deviceName,
      ),
    );
    await storage.saveSessionJson(next.toJson());
    state = state.copyWith(device: next);
  }

  bool _sameWorkflows(List<KdsWorkflow> a, List<KdsWorkflow> b) {
    if (a.length != b.length) return false;
    const order = [KdsWorkflow.prep, KdsWorkflow.cook, KdsWorkflow.serve];
    return order.every((w) => a.contains(w) == b.contains(w));
  }

  Future<void> _syncDeviceFromServer({bool restartConnection = true}) async {
    final token = state.token;
    final device = state.device;
    if (token == null || token.isEmpty || device == null) return;
    try {
      final remote = await api.fetchDeviceMe(token: token);
      final next = mergeRemoteKdsDevice(device, remote, token: token);
      await storage.saveSessionJson(next.toJson());
      state = state.copyWith(device: next);
      if (restartConnection) _startWsAndHeartbeat();
    } on ApiException catch (e) {
      if (e.isUnauthorized ||
          e.statusCode == 401 ||
          e.code == 401 ||
          e.message.contains('未绑定') ||
          e.message.contains('已禁用')) {
        KdsFileLogger.warn('[AUTH] 设备凭据已被云端判定失效或解绑 (${e.message})，自动返回登录页');
        await logout();
      }
    } catch (_) {
      // device/me 不可用时保留本地会话
    }
  }

  Future<void> _validateAndConnect() async {
    final device = state.device;
    if (device == null) return;
    try {
      // health 是收银管理员诊断接口；KDS 设备恢复会话必须使用
      // 自身的 device token 读取服务端权威身份。
      await _syncDeviceFromServer(restartConnection: false);
      if (!state.isLoggedIn) return;
      await api.heartbeat(device.deviceCode);
      _startWsAndHeartbeat();
    } catch (_) {
      // 收银端暂时不可达时保留设备身份；业务看板冷启动仍保持为空。
      if (state.isLoggedIn) _startWsAndHeartbeat();
    }
  }

  /// WebSocket 订阅 screen_tag（v1.2.118：统一看板用 workflow_board）
  String? _wsScreenTag(KdsDevice? device) {
    if (device == null) return null;
    if (device.screenTag == KdsScreenTag.workflowBoard ||
        device.workflows.isNotEmpty) {
      return KdsScreenTag.workflowBoard.value;
    }
    return device.screenTag.value;
  }

  void _startWsAndHeartbeat() {
    _ws?.dispose();
    final device = state.device;
    if (device == null) return;

    final workflows = device.workflows.map((w) => w.apiValue).toList();
    KdsWsLogger.sessionAttach(
      apiBase: state.effectiveActiveBase,
      shopId: device.shopId,
      screenTag: _wsScreenTag(device),
      workflows: workflows,
    );
    _ws = KdsWebSocketService(
      getBaseUrl: () => state.effectiveActiveBase,
      getShopId: () => state.device?.shopId,
      getScreenTag: () => _wsScreenTag(state.device),
      getToken: () => state.effectiveActiveToken,
      getWorkflows: () =>
          state.device?.workflows.map((w) => w.apiValue).toList() ?? const [],
      onUnauthorized: () {
        KdsFileLogger.warn('[WS] 收到凭据失效 (1008)，自动登出并返回登录页');
        logout();
      },
    );
    ref.read(wsConnectedProvider.notifier).attach(_ws!);
    _ws!.connect();
    state =
        state.copyWith(connectionGeneration: state.connectionGeneration + 1);

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_heartbeatPaused) return;
      try {
        await api.heartbeat(device.deviceCode);
      } catch (_) {}
    });
  }

  Future<void> logout() async {
    // 访问审计：退出设备
    KdsFileLogger.info('[AUTH] 退出设备');
    _heartbeat?.cancel();
    _ws?.dispose();
    _ws = null;
    ref.read(wsConnectedProvider.notifier).detach();
    final apiBase = storage.getApiBase();
    final cloudApiBase = storage.getCloudApiBase();
    if (state.device != null) {
      if (state.device!.shopId > 0) {
        await storage.setLastShopId(state.device!.shopId);
      }
      if (state.device!.workflows.isNotEmpty) {
        await storage.setLastWorkflows(
          state.device!.workflows.map((w) => w.apiValue).toList(),
        );
      }
      if (state.device!.deviceName != null &&
          state.device!.deviceName!.isNotEmpty) {
        await storage.setLastDeviceName(state.device!.deviceName!);
      }
    }
    state = SessionState(apiBase: apiBase, cloudApiBase: cloudApiBase);
    await storage.clearAll();
  }

  /// 彻底清除运行时临时缓存（会话凭证、快照、待发队列），默认保护后厨设置参数
  Future<void> clearAllCache({bool preserveSettings = true}) async {
    KdsFileLogger.info('[AUTH] 清除本地缓存与凭证 (preserveSettings=$preserveSettings)');
    _heartbeat?.cancel();
    _ws?.dispose();
    _ws = null;
    ref.read(wsConnectedProvider.notifier).detach();

    try {
      await storage.clearAll();
      final prefs = await SharedPreferences.getInstance();
      if (preserveSettings) {
        final preserved = <String, Object>{};
        for (final key in prefs.getKeys()) {
          if (SessionStorage.isPreservedSettingKey(key)) {
            final val = prefs.get(key);
            if (val != null) preserved[key] = val;
          }
        }
        await prefs.clear();
        for (final entry in preserved.entries) {
          final val = entry.value;
          if (val is bool) await prefs.setBool(entry.key, val);
          if (val is int) await prefs.setInt(entry.key, val);
          if (val is double) await prefs.setDouble(entry.key, val);
          if (val is String) await prefs.setString(entry.key, val);
          if (val is List<String>) await prefs.setStringList(entry.key, val);
        }
      } else {
        await prefs.clear();
      }
      const secure = FlutterSecureStorage();
      await secure.deleteAll();
    } catch (e) {
      KdsFileLogger.warn('[AUTH] 清理缓存异常: $e');
    }

    final defaultCloud = storage.getCloudApiBase().isNotEmpty
        ? storage.getCloudApiBase()
        : platformDefaultCloudApiBase();
    state = SessionState(
      apiBase: storage.getApiBase(),
      cloudApiBase: defaultCloud,
    );
  }

  Future<void> updateApiBase(String apiBase) async {
    if (apiBase.trim().isNotEmpty && !isValidApiBase(apiBase)) {
      return;
    }
    if (kReleaseMode &&
        apiBase.trim().isNotEmpty &&
        !isSecurePrivateLanApiBase(apiBase)) {
      state = state.copyWith(error: '正式版仅允许 HTTPS 局域网代理');
      return;
    }
    await storage.setApiBase(apiBase);
    final next = storage.getApiBase();
    state = state.copyWith(apiBase: next);
    _initClient(state.effectiveActiveBase, state.token);
    if (state.isLoggedIn) {
      _startWsAndHeartbeat();
    }
  }

  Future<void> updateCloudApiBase(String cloudApiBase) async {
    if (cloudApiBase.trim().isNotEmpty && !isValidApiBase(cloudApiBase)) {
      return;
    }
    await storage.setCloudApiBase(cloudApiBase);
    final next = storage.getCloudApiBase();
    state = state.copyWith(cloudApiBase: next);
    _initClient(state.effectiveActiveBase, state.token);
    if (state.isLoggedIn && state.activeChannel == KdsActiveChannel.cloud) {
      _startWsAndHeartbeat();
    }
  }

  Future<void> switchConnectionMode(KdsConnectionMode mode) async {
    const effectiveMode = KdsConnectionMode.cloudFirst;
    await storage.setConnectionModeRaw(effectiveMode.value);
    final nextChannel = state.cloudApiBase.isNotEmpty
        ? KdsActiveChannel.cloud
        : KdsActiveChannel.lan;
    state = state.copyWith(
      connectionMode: effectiveMode,
      activeChannel: nextChannel,
    );
    _initClient(state.effectiveActiveBase, state.token);
    if (state.isLoggedIn) {
      _startWsAndHeartbeat();
    }
  }

  void switchActiveChannel(KdsActiveChannel channel) {
    if (state.activeChannel == channel) return;
    if (channel == KdsActiveChannel.lan &&
        kReleaseMode &&
        !isSecurePrivateLanApiBase(state.apiBase)) {
      state = state.copyWith(error: '局域网代理不是受保护的 HTTPS 地址，已拒绝切换');
      return;
    }
    KdsFileLogger.info('[AUTH] 切换会话活跃通道 → ${channel.label}');
    state = state.copyWith(activeChannel: channel);
    _initClient(state.effectiveActiveBase, state.effectiveActiveToken);
    if (state.isLoggedIn) {
      _startWsAndHeartbeat();
    }
  }

  void _dispose() {
    _heartbeat?.cancel();
    _ws?.dispose();
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

final wsConnectedProvider =
    NotifierProvider<_WsConnectedNotifier, bool>(_WsConnectedNotifier.new);

class _WsConnectedNotifier extends Notifier<bool> {
  StreamSubscription<bool>? _sub;

  @override
  bool build() => false;

  void attach(KdsWebSocketService ws) {
    _sub?.cancel();
    _sub = ws.connectedStream.listen((v) => state = v);
    state = ws.isConnected;
  }

  void detach() {
    _sub?.cancel();
    state = false;
  }
}
