import 'dart:async';

import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';

enum KdsChannelState {
  stable,
  handover,
  probing,
  switchRecommended,
  unavailable,
}

class KdsChannelSwitchSuggestion {
  const KdsChannelSwitchSuggestion({
    required this.targetChannel,
    required this.reason,
    required this.detectedAt,
  });

  final KdsActiveChannel targetChannel;
  final String reason;
  final DateTime detectedAt;
}

class KdsCommandStillUnknown implements Exception {
  const KdsCommandStillUnknown(this.commandId);

  final String commandId;

  @override
  String toString() => 'KDS command remains UNKNOWN: $commandId';
}

/// 双模传输层调度器：
/// 实现 [KdsV2Transport]，封装局域网 Client 与云端 Client。
/// 根据配置模式 [KdsConnectionMode] 以及心跳探活与连续失败判定通道健康。
/// 生产 [KdsConnectionMode.cloudFirst] 模式只提出切换建议，必须由用户确认
/// 后才会经过 bootstrap/版本屏障切换活动通道，避免静默切换造成状态不对称。
class KdsDualModeTransport implements KdsV2Transport {
  KdsDualModeTransport({
    required this.lanTransport,
    this.cloudTransport,
    this.mode = KdsConnectionMode.cloudFirst,
    KdsActiveChannel? initialChannel,
    this.expectedShopId,
    this.onChannelSwitched,
    this.onChannelStateChanged,
    this.onChannelSwitchSuggested,
  }) {
    _activeChannel = initialChannel ??
        (((mode == KdsConnectionMode.cloudDirect ||
                    mode == KdsConnectionMode.cloudFirst) &&
                cloudTransport != null)
            ? KdsActiveChannel.cloud
            : KdsActiveChannel.lan);
    if (_activeChannel == KdsActiveChannel.cloud &&
        mode == KdsConnectionMode.lanFirst) {
      _scheduleLanRecoveryProbe();
    }
    if (_activeChannel == KdsActiveChannel.lan &&
        mode == KdsConnectionMode.cloudFirst &&
        cloudTransport != null) {
      _scheduleCloudRecoveryProbe();
    }
  }

  final KdsV2Transport lanTransport;
  final KdsV2Transport? cloudTransport;
  final int? expectedShopId;
  KdsConnectionMode mode;
  final void Function(KdsActiveChannel channel)? onChannelSwitched;
  final void Function(KdsChannelState state)? onChannelStateChanged;
  final void Function(KdsChannelSwitchSuggestion suggestion)?
      onChannelSwitchSuggested;

  KdsActiveChannel _activeChannel = KdsActiveChannel.lan;
  KdsActiveChannel get activeChannel => _activeChannel;

  KdsChannelState _channelState = KdsChannelState.stable;
  KdsChannelState get channelState => _channelState;

  Completer<void>? _handoverCompleter;
  int _inFlightWrites = 0;
  int get inFlightWrites => _inFlightWrites;
  int _channelGeneration = 0;
  int get channelGeneration => _channelGeneration;

  final Map<int, int> _cloudMaxObservedRevisionByDetailId = {};
  Map<int, int> get cloudMaxObservedRevisionByDetailId =>
      Map.unmodifiable(_cloudMaxObservedRevisionByDetailId);

  final Set<int> _cloudObservedActiveDetailIds = {};
  Set<int> get cloudObservedActiveDetailIds =>
      Set.unmodifiable(_cloudObservedActiveDetailIds);

  int _lanFailures = 0;
  DateTime? _lastLanProbeSuccess;
  DateTime? get lastLanProbeSuccess => _lastLanProbeSuccess;
  Timer? _lanRecoveryTimer;
  Timer? _cloudRecoveryTimer;
  bool _alternateProbeInProgress = false;
  KdsChannelSwitchSuggestion? _pendingSwitchSuggestion;
  KdsActiveChannel? _lastSuggestedTarget;
  final Map<int, int> _cloudDetailIdByObservedId = {};
  final Map<int, int> _cloudOrderIdByObservedId = {};
  final Map<int, int> _maxObservedRevisionByDetailId = {};
  final Set<int> _observedActiveDetailIds = {};
  int _maxObservedAuthorityCursor = 0;

  KdsChannelSwitchSuggestion? get pendingSwitchSuggestion =>
      _pendingSwitchSuggestion;

  void completeHandover() {
    if (_channelState == KdsChannelState.handover) {
      _exitHandover();
    }
  }

  void _enterHandover() {
    _channelState = KdsChannelState.handover;
    if (_handoverCompleter == null || _handoverCompleter!.isCompleted) {
      _handoverCompleter = Completer<void>();
    }
    onChannelStateChanged?.call(_channelState);
  }

  void _exitHandover() {
    _channelState = KdsChannelState.stable;
    final completer = _handoverCompleter;
    _handoverCompleter = null;
    completer?.complete();
    onChannelStateChanged?.call(_channelState);
  }

  Future<void> _barrierWait() async {
    while (_channelState == KdsChannelState.handover) {
      final completer = _handoverCompleter;
      if (completer != null && !completer.isCompleted) {
        await completer.future.timeout(const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
                'KDS channel handover bootstrap did not complete'));
      } else {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  void updateMode(KdsConnectionMode newMode) {
    if (mode == newMode) return;
    mode = newMode;
    if (mode == KdsConnectionMode.cloudDirect && cloudTransport != null) {
      _switchTo(KdsActiveChannel.cloud, reason: '用户切换至云端直连模式');
    } else if (mode == KdsConnectionMode.lanOnly) {
      _switchTo(KdsActiveChannel.lan, reason: '用户切换至纯局域网模式');
    } else if (mode == KdsConnectionMode.lanFirst) {
      if (_activeChannel == KdsActiveChannel.cloud) {
        _scheduleLanRecoveryProbe();
      }
    } else if (mode == KdsConnectionMode.cloudFirst && cloudTransport != null) {
      _switchTo(KdsActiveChannel.cloud, reason: '用户切换至云端优先模式');
    }
  }

  void _switchTo(
    KdsActiveChannel target, {
    required String reason,
    bool bootstrapReady = false,
  }) {
    if (_activeChannel == target) return;
    _enterHandover();
    _activeChannel = target;
    _channelGeneration++;
    KdsFileLogger.info('[DUAL_MODE] 切换活动通道 → ${target.label} (原因: $reason)');
    onChannelSwitched?.call(target);
    _pendingSwitchSuggestion = null;
    _lastSuggestedTarget = null;
    if (bootstrapReady) {
      _exitHandover();
    }
    if (target == KdsActiveChannel.cloud &&
        mode == KdsConnectionMode.lanFirst) {
      _scheduleLanRecoveryProbe();
    }
    if (target == KdsActiveChannel.lan &&
        mode == KdsConnectionMode.cloudFirst) {
      _scheduleCloudRecoveryProbe();
    }
  }

  void _recordLanSuccess() {
    _lanFailures = 0;
    _lastLanProbeSuccess = DateTime.now();
    _markActiveChannelAvailable();
  }

  void _recordCloudSuccess() {
    if (_activeChannel == KdsActiveChannel.cloud &&
        _pendingSwitchSuggestion?.targetChannel == KdsActiveChannel.lan) {
      _pendingSwitchSuggestion = null;
      _lastSuggestedTarget = null;
    }
    _markActiveChannelAvailable();
  }

  void _markActiveChannelAvailable() {
    if (_channelState != KdsChannelState.unavailable &&
        _channelState != KdsChannelState.probing) {
      return;
    }
    _channelState = KdsChannelState.stable;
    onChannelStateChanged?.call(_channelState);
  }

  void _recordCloudFailure(Object error) {
    if (_isAuthFailure(error)) {
      KdsFileLogger.warn('[DUAL_MODE] 云端返回 401 认证失败，不允许通过 LAN 绕过鉴权');
      return;
    }
    if (mode == KdsConnectionMode.cloudFirst &&
        lanTransport != cloudTransport &&
        _activeChannel == KdsActiveChannel.cloud &&
        _isLinkFailure(error)) {
      _channelState = KdsChannelState.probing;
      onChannelStateChanged?.call(_channelState);
      unawaited(_probeLanForSuggestion('云端延迟过高或无响应'));
    }
  }

  void reportActiveChannelUnavailable(Object error) {
    _channelState = KdsChannelState.unavailable;
    KdsFileLogger.warn('[DUAL_MODE] 云端与局域网当前均不可用，操作保留在本地 outbox: $error');
    onChannelStateChanged?.call(_channelState);
  }

  void _recordLanFailure(Object error) {
    _lanFailures++;
    KdsFileLogger.warn('[DUAL_MODE] 局域网请求失败 ($_lanFailures 次): $error');
    // 401 认证失败不切通道——收银端可达但 token 失效，应触发重新登录而非降级云端
    if (_isAuthFailure(error)) {
      KdsFileLogger.warn('[DUAL_MODE] 局域网返回 401 认证失败，需要重新登录而非切换通道');
      return;
    }
    if (mode == KdsConnectionMode.lanFirst &&
        cloudTransport != null &&
        _activeChannel == KdsActiveChannel.lan) {
      _switchTo(KdsActiveChannel.cloud,
          reason: '局域网请求失败 ($_lanFailures 次)，即刻触发云端容灾降级');
      return;
    }
    if (mode == KdsConnectionMode.cloudFirst &&
        _activeChannel == KdsActiveChannel.lan &&
        _isLinkFailure(error)) {
      reportActiveChannelUnavailable(error);
      unawaited(_probeCloudForSuggestion('局域网代理无响应，云端通道可用'));
    }
  }

  /// Reports that the realtime socket bound to [channel] is no longer usable.
  ///
  /// HTTP requests already trigger failover through [_recordLanFailure], but a
  /// quiet KDS receives no HTTP traffic between orders. Without this signal a
  /// broken LAN WebSocket is only discovered by the periodic `changes` poll,
  /// delaying cloud-created orders. A current LAN socket failure therefore
  /// starts the same guarded cloud handover immediately. Disconnect callbacks
  /// from an obsolete socket are ignored by matching [channel] to the active
  /// channel.
  void reportRealtimeDisconnected(KdsActiveChannel channel) {
    if (channel != _activeChannel) return;
    if (channel == KdsActiveChannel.cloud &&
        mode == KdsConnectionMode.cloudFirst) {
      KdsFileLogger.warn('[DUAL_MODE] 云端实时通道断开，探测收银 LAN 代理并等待用户确认');
      _channelState = KdsChannelState.probing;
      onChannelStateChanged?.call(_channelState);
      unawaited(_probeLanForSuggestion('云端实时连接已断开'));
      return;
    }
    if (channel == KdsActiveChannel.lan &&
        mode == KdsConnectionMode.cloudFirst) {
      reportActiveChannelUnavailable('LAN WebSocket disconnected');
      unawaited(_probeCloudForSuggestion('局域网实时连接已断开，云端通道可用'));
      return;
    }
    if (channel != KdsActiveChannel.lan ||
        mode != KdsConnectionMode.lanFirst ||
        cloudTransport == null) {
      return;
    }
    KdsFileLogger.warn('[DUAL_MODE] 局域网实时通道断开，立即切换云端以继续接收新订单');
    _switchTo(
      KdsActiveChannel.cloud,
      reason: '局域网 WebSocket 断开，实时链路立即由云端接管',
    );
  }

  bool _isLinkFailure(Object error) =>
      error is TimeoutException ||
      (error is ApiException && error.isNetworkError);

  bool _isAuthFailure(Object error) =>
      error is ApiException && error.isUnauthorized;

  void _emitSwitchSuggestion(
    KdsActiveChannel target, {
    required String reason,
  }) {
    if (target == _activeChannel || _lastSuggestedTarget == target) return;
    final suggestion = KdsChannelSwitchSuggestion(
      targetChannel: target,
      reason: reason,
      detectedAt: DateTime.now(),
    );
    _pendingSwitchSuggestion = suggestion;
    _lastSuggestedTarget = target;
    _channelState = KdsChannelState.switchRecommended;
    onChannelStateChanged?.call(_channelState);
    KdsFileLogger.info(
        '[DUAL_MODE] 建议切换至 ${target.label}，等待用户确认 (原因: $reason)');
    onChannelSwitchSuggested?.call(suggestion);
  }

  void dismissChannelSwitchSuggestion(KdsActiveChannel target) {
    if (_pendingSwitchSuggestion?.targetChannel != target) return;
    _pendingSwitchSuggestion = null;
    if (_channelState == KdsChannelState.switchRecommended) {
      _channelState = KdsChannelState.stable;
      onChannelStateChanged?.call(_channelState);
    }
  }

  Future<void> _probeLanForSuggestion(String reason) async {
    if (_alternateProbeInProgress || _activeChannel != KdsActiveChannel.cloud) {
      return;
    }
    _alternateProbeInProgress = true;
    try {
      final boot =
          await lanTransport.bootstrap().timeout(const Duration(seconds: 4));
      if (!verifyLanRecoveryBarrier(boot)) {
        reportActiveChannelUnavailable('LAN recovery barrier rejected');
        return;
      }
      _rememberBootstrap(boot, fromLan: true);
      _emitSwitchSuggestion(KdsActiveChannel.lan, reason: reason);
    } catch (error) {
      _lastSuggestedTarget = null;
      reportActiveChannelUnavailable(error);
    } finally {
      _alternateProbeInProgress = false;
    }
  }

  Future<void> _probeCloudForSuggestion(String reason) async {
    final cloud = cloudTransport;
    if (_alternateProbeInProgress ||
        cloud == null ||
        _activeChannel != KdsActiveChannel.lan) {
      return;
    }
    _alternateProbeInProgress = true;
    try {
      final boot = await cloud.bootstrap().timeout(const Duration(seconds: 4));
      if (!verifyCloudRecoveryBarrier(boot)) return;
      _rememberBootstrap(boot, fromLan: false);
      _emitSwitchSuggestion(KdsActiveChannel.cloud, reason: reason);
    } catch (error) {
      _lastSuggestedTarget = null;
      KdsFileLogger.info('[DUAL_MODE] 云端候选通道探测失败: $error');
    } finally {
      _alternateProbeInProgress = false;
    }
  }

  Future<bool> requestChannelSwitch(KdsActiveChannel target) async {
    if (target == _activeChannel) return true;
    if (_inFlightWrites > 0) {
      throw StateError('当前有写请求正在确认，暂不能切换连接通道');
    }
    final targetTransport =
        target == KdsActiveChannel.cloud ? cloudTransport : lanTransport;
    if (targetTransport == null) {
      throw StateError('${target.label}未配置，无法切换');
    }
    final boot =
        await targetTransport.bootstrap().timeout(const Duration(seconds: 4));
    final allowed = target == KdsActiveChannel.cloud
        ? verifyCloudRecoveryBarrier(boot)
        : verifyLanRecoveryBarrier(boot);
    if (!allowed) {
      throw StateError('${target.label}尚未通过一致性检查，已保持当前通道');
    }
    _rememberBootstrap(boot, fromLan: target == KdsActiveChannel.lan);
    _switchTo(target, reason: '用户确认切换连接通道');
    return true;
  }

  bool verifyCloudRecoveryBarrier(KdsV2Bootstrap cloudBoot) {
    if (_inFlightWrites > 0) return false;
    if ((cloudBoot.shopId ?? 0) <= 0) return false;
    if (expectedShopId != null &&
        expectedShopId! > 0 &&
        cloudBoot.shopId != expectedShopId) {
      KdsFileLogger.warn(
          '[DUAL_MODE] 云端恢复屏障拦截：shopId(${cloudBoot.shopId}) 与期望门店($expectedShopId)不匹配');
      return false;
    }
    final candidateCursor = cloudBoot.authorityCursor ?? cloudBoot.eventSeq;
    if (candidateCursor < _maxObservedAuthorityCursor) {
      KdsFileLogger.info(
          '[DUAL_MODE] 云端恢复屏障拦截：候选游标($candidateCursor)落后于已观察游标($_maxObservedAuthorityCursor)');
      return false;
    }
    final candidateById = {
      for (final line in cloudBoot.lines) line.detailId: line,
    };
    for (final detailId in _observedActiveDetailIds) {
      final candidate = candidateById[detailId];
      if (candidate == null) {
        KdsFileLogger.info('[DUAL_MODE] 云端恢复屏障拦截：候选快照缺少活动明细 detail=$detailId');
        return false;
      }
      final observedRevision = _maxObservedRevisionByDetailId[detailId] ?? 0;
      if (candidate.revision < observedRevision) {
        KdsFileLogger.info(
            '[DUAL_MODE] 云端恢复屏障拦截：detail=$detailId 候选版本(${candidate.revision})落后于已观察版本($observedRevision)');
        return false;
      }
    }
    return true;
  }

  bool verifyLanRecoveryBarrier(KdsV2Bootstrap lanBoot) {
    // 1. 无飞行中的写操作
    if (_inFlightWrites > 0) {
      KdsFileLogger.info('[DUAL_MODE] 恢复屏障拦截：当前有 $_inFlightWrites 个在途写请求');
      return false;
    }
    // 2. 门店 ID 有效性与精确匹配校验
    if ((lanBoot.shopId ?? 0) <= 0) {
      KdsFileLogger.warn(
          '[DUAL_MODE] 恢复屏障拦截：局域网返回非法 shopId: ${lanBoot.shopId}');
      return false;
    }
    if (expectedShopId != null &&
        expectedShopId! > 0 &&
        lanBoot.shopId != expectedShopId) {
      KdsFileLogger.warn(
          '[DUAL_MODE] 恢复屏障拦截：局域网 shopId(${lanBoot.shopId}) 与期望门店($expectedShopId)不匹配');
      return false;
    }
    // 3. 收银端同步状态异常检查（auth_paused）
    final authPaused = lanBoot.stats['outbox_auth_paused'];
    if (authPaused is int && authPaused > 0) {
      KdsFileLogger.warn(
          '[DUAL_MODE] 恢复屏障拦截：收银端同步队列认证挂起 (auth_paused=$authPaused)');
      return false;
    }
    // 4. 云端在制明细全集比对：云端观察到的在制明细，收银端快照必须全集包含（未追齐前拒绝回切）
    final lanDetailIds = <int>{};
    for (final line in lanBoot.lines) {
      lanDetailIds.add(line.detailId);
      if (line.cloudDetailId != null && line.cloudDetailId! > 0) {
        lanDetailIds.add(line.cloudDetailId!);
      }
    }
    for (final cloudActiveId in _observedActiveDetailIds) {
      if (!lanDetailIds.contains(cloudActiveId)) {
        KdsFileLogger.info(
            '[DUAL_MODE] 恢复屏障拦截：局域网缺失云端在制明细 detail=$cloudActiveId，收银端尚未追齐新单/加菜');
        return false;
      }
    }
    // 5. 状态单调性防复活校验：收银端所有可见菜品的版本不得落后于在云端观察到的版本
    for (final line in lanBoot.lines) {
      final directRevision = _maxObservedRevisionByDetailId[line.detailId];
      final mappedRevision = line.cloudDetailId == null
          ? null
          : _maxObservedRevisionByDetailId[line.cloudDetailId!];
      final cloudRev = directRevision == null
          ? mappedRevision
          : mappedRevision == null
              ? directRevision
              : directRevision > mappedRevision
                  ? directRevision
                  : mappedRevision;
      if (cloudRev != null && line.revision < cloudRev) {
        KdsFileLogger.info(
            '[DUAL_MODE] 恢复屏障拦截：菜品 detail=${line.detailId} 收银端版本(${line.revision})落后于云端观察版本($cloudRev)，收银尚未追齐云端变更');
        return false;
      }
    }
    return true;
  }

  void _scheduleLanRecoveryProbe() {
    _lanRecoveryTimer?.cancel();
    if (mode != KdsConnectionMode.lanFirst || cloudTransport == null) return;
    _lanRecoveryTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_activeChannel != KdsActiveChannel.cloud ||
          mode != KdsConnectionMode.lanFirst) {
        timer.cancel();
        return;
      }
      _channelState = KdsChannelState.probing;
      onChannelStateChanged?.call(_channelState);
      try {
        final boot =
            await lanTransport.bootstrap().timeout(const Duration(seconds: 4));
        if (verifyLanRecoveryBarrier(boot)) {
          _recordLanSuccess();
          timer.cancel();
          _rememberBootstrap(boot, fromLan: true);
          _switchTo(KdsActiveChannel.lan,
              reason: '局域网收银机探活且通过多重恢复屏障，安全回切局域网', bootstrapReady: false);
        } else {
          KdsFileLogger.info('[DUAL_MODE] 局域网探活未通过恢复屏障，保持云端直连');
          _channelState = KdsChannelState.stable;
          onChannelStateChanged?.call(_channelState);
        }
      } catch (e) {
        // LAN still down, keep cloud active
        KdsFileLogger.info('[DUAL_MODE] 局域网探活异常: $e');
        _channelState = KdsChannelState.stable;
        onChannelStateChanged?.call(_channelState);
      }
    });
  }

  void _scheduleCloudRecoveryProbe() {
    _cloudRecoveryTimer?.cancel();
    if (mode != KdsConnectionMode.cloudFirst || cloudTransport == null) return;
    _cloudRecoveryTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_activeChannel != KdsActiveChannel.lan ||
          mode != KdsConnectionMode.cloudFirst) {
        timer.cancel();
        return;
      }
      final wasUnavailable = _channelState == KdsChannelState.unavailable;
      _channelState = KdsChannelState.probing;
      onChannelStateChanged?.call(_channelState);
      try {
        final boot = await cloudTransport!
            .bootstrap()
            .timeout(const Duration(seconds: 4));
        if (!verifyCloudRecoveryBarrier(boot)) return;
        timer.cancel();
        _rememberBootstrap(boot, fromLan: false);
        _emitSwitchSuggestion(
          KdsActiveChannel.cloud,
          reason: '云端连接已恢复并通过一致性检查',
        );
      } catch (error) {
        _lastSuggestedTarget = null;
        KdsFileLogger.info('[DUAL_MODE] 云端恢复探活异常: $error');
        _channelState = wasUnavailable
            ? KdsChannelState.unavailable
            : KdsChannelState.stable;
        onChannelStateChanged?.call(_channelState);
      }
    });
  }

  KdsV2Transport get _currentTransport {
    if (mode == KdsConnectionMode.cloudDirect && cloudTransport != null) {
      return cloudTransport!;
    }
    if (mode == KdsConnectionMode.lanOnly) {
      return lanTransport;
    }
    if (_activeChannel == KdsActiveChannel.cloud && cloudTransport != null) {
      return cloudTransport!;
    }
    return lanTransport;
  }

  @override
  Future<KdsV2Bootstrap> bootstrap() async {
    final transport = _currentTransport;
    try {
      final res = await transport.bootstrap();
      _rememberBootstrap(res, fromLan: transport == lanTransport);
      if (_channelState == KdsChannelState.handover) _exitHandover();
      if (transport == lanTransport) {
        _recordLanSuccess();
      } else {
        _recordCloudSuccess();
      }
      return res;
    } catch (e) {
      if (transport == cloudTransport &&
          mode == KdsConnectionMode.cloudFirst &&
          _isLinkFailure(e)) {
        _recordCloudFailure(e);
        if (_activeChannel == KdsActiveChannel.lan) {
          KdsFileLogger.info('[DUAL_MODE] bootstrap 故障转移至 LAN 代理重试');
          try {
            final lan = await lanTransport.bootstrap();
            _rememberBootstrap(lan, fromLan: true);
            if (_channelState == KdsChannelState.handover) _exitHandover();
            _recordLanSuccess();
            return lan;
          } catch (lanError) {
            reportActiveChannelUnavailable(lanError);
            rethrow;
          }
        }
      }
      if (transport == lanTransport) {
        _recordLanFailure(e);
        if (_activeChannel == KdsActiveChannel.cloud &&
            cloudTransport != null) {
          KdsFileLogger.info('[DUAL_MODE] bootstrap 故障转移至云端重试');
          final cloud = await cloudTransport!.bootstrap();
          _rememberBootstrap(cloud, fromLan: false);
          if (_channelState == KdsChannelState.handover) _exitHandover();
          return cloud;
        }
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> businessDayOrders(
      {int? afterId, int limit = 200}) async {
    final transport = _currentTransport;
    try {
      final res =
          await transport.businessDayOrders(afterId: afterId, limit: limit);
      if (transport == lanTransport) {
        _recordLanSuccess();
      } else {
        _recordCloudSuccess();
      }
      return res;
    } catch (e) {
      if (transport == cloudTransport &&
          mode == KdsConnectionMode.cloudFirst &&
          _isLinkFailure(e)) {
        _recordCloudFailure(e);
        if (_activeChannel == KdsActiveChannel.lan) {
          try {
            final lan = await lanTransport.businessDayOrders(
                afterId: afterId, limit: limit);
            _recordLanSuccess();
            return lan;
          } catch (lanError) {
            reportActiveChannelUnavailable(lanError);
            rethrow;
          }
        }
      }
      if (transport == lanTransport) {
        _recordLanFailure(e);
        if (_activeChannel == KdsActiveChannel.cloud &&
            cloudTransport != null) {
          KdsFileLogger.info('[DUAL_MODE] businessDayOrders 故障转移至云端重试');
          return await cloudTransport!
              .businessDayOrders(afterId: afterId, limit: limit);
        }
      }
      rethrow;
    }
  }

  @override
  Future<KdsV2Changes> changes(int afterSeq) async {
    final transport = _currentTransport;
    try {
      final res = await transport.changes(afterSeq);
      _rememberAuthorityCursor(res.eventSeq);
      _rememberPatches(res.events.expand((event) => event.patches),
          fromLan: transport == lanTransport);
      if (transport == lanTransport) {
        _recordLanSuccess();
      } else {
        _recordCloudSuccess();
      }
      return res;
    } catch (e) {
      if (transport == cloudTransport &&
          mode == KdsConnectionMode.cloudFirst &&
          _isLinkFailure(e)) {
        _recordCloudFailure(e);
        if (_activeChannel == KdsActiveChannel.lan) {
          try {
            final lan = await lanTransport.changes(afterSeq);
            _rememberAuthorityCursor(lan.eventSeq);
            _rememberPatches(lan.events.expand((event) => event.patches),
                fromLan: true);
            _recordLanSuccess();
            return lan;
          } catch (lanError) {
            reportActiveChannelUnavailable(lanError);
            rethrow;
          }
        }
      }
      if (transport == lanTransport) {
        _recordLanFailure(e);
        if (_activeChannel == KdsActiveChannel.cloud &&
            cloudTransport != null) {
          KdsFileLogger.info('[DUAL_MODE] changes 故障转移至云端重试');
          final cloud = await cloudTransport!.changes(afterSeq);
          _rememberAuthorityCursor(cloud.eventSeq);
          _rememberPatches(cloud.events.expand((event) => event.patches),
              fromLan: false);
          return cloud;
        }
      }
      rethrow;
    }
  }

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async {
    if (_channelState == KdsChannelState.handover) {
      await _barrierWait();
    }
    _inFlightWrites++;
    try {
      final transport = _currentTransport;
      try {
        final res = await transport.command(command);
        _rememberAuthorityCursor(res.eventSeq);
        _rememberPatches(res.patches, fromLan: transport == lanTransport);
        if (transport == lanTransport) _recordLanSuccess();
        return res;
      } catch (e) {
        if (transport == cloudTransport &&
            mode == KdsConnectionMode.cloudFirst &&
            _isLinkFailure(e)) {
          _recordCloudFailure(e);
          KdsFileLogger.warn(
              '[DUAL_MODE] command 结果不确定，已建议切换 LAN 且禁止盲重放 cmd=${command.commandId}');
        }
        if (transport == lanTransport && _isLinkFailure(e)) {
          _recordLanFailure(e);
          KdsFileLogger.warn(
              '[DUAL_MODE] command 结果不确定，禁止跨通道盲重放 cmd=${command.commandId}');
        }
        rethrow;
      }
    } finally {
      _inFlightWrites--;
    }
  }

  void _rememberPatches(
    Iterable<KdsV2Patch> patches, {
    required bool fromLan,
  }) {
    _rememberLines(
      patches.map((patch) => patch.line).whereType<KdsV2Line>(),
      fromLan: fromLan,
    );
  }

  void _rememberBootstrap(
    KdsV2Bootstrap bootstrap, {
    required bool fromLan,
  }) {
    _rememberAuthorityCursor(bootstrap.authorityCursor ?? bootstrap.eventSeq);
    _rememberLines(bootstrap.lines, fromLan: fromLan);
  }

  void _rememberAuthorityCursor(int cursor) {
    if (cursor > _maxObservedAuthorityCursor) {
      _maxObservedAuthorityCursor = cursor;
    }
  }

  void _rememberLines(
    Iterable<KdsV2Line> lines, {
    required bool fromLan,
  }) {
    for (final line in lines) {
      final canonicalDetailId =
          fromLan ? (line.cloudDetailId ?? line.detailId) : line.detailId;
      final observedRevision =
          _maxObservedRevisionByDetailId[canonicalDetailId] ?? 0;
      if (line.revision > observedRevision) {
        _maxObservedRevisionByDetailId[canonicalDetailId] = line.revision;
      }
      if (line.quantity > 0 &&
          line.queue != 'done' &&
          line.raw['removed'] != true) {
        _observedActiveDetailIds.add(canonicalDetailId);
      } else {
        _observedActiveDetailIds.remove(canonicalDetailId);
      }
      if (fromLan) {
        final cloudDetailId = line.cloudDetailId;
        final cloudOrderId = line.cloudOrderId;
        if (cloudDetailId != null) {
          _cloudDetailIdByObservedId[line.detailId] = cloudDetailId;
          _cloudDetailIdByObservedId[cloudDetailId] = cloudDetailId;
        }
        if (cloudOrderId != null) {
          _cloudOrderIdByObservedId[line.orderId] = cloudOrderId;
          _cloudOrderIdByObservedId[cloudOrderId] = cloudOrderId;
        }
      } else {
        _cloudDetailIdByObservedId[line.detailId] = line.detailId;
        _cloudOrderIdByObservedId[line.orderId] = line.orderId;
        final currentRev =
            _cloudMaxObservedRevisionByDetailId[line.detailId] ?? 0;
        if (line.revision > currentRev) {
          _cloudMaxObservedRevisionByDetailId[line.detailId] = line.revision;
        }
        if (line.quantity > 0 &&
            line.queue != 'done' &&
            line.raw['removed'] != true) {
          _cloudObservedActiveDetailIds.add(line.detailId);
        }
      }
    }
  }

  /// Resolves an ambiguous write against the cloud authority through its
  /// origin channel. A LAN-origin request still reaches the same cloud ledger;
  /// the cashier never owns or replays the command.
  Future<KdsV2CommandResolution> resolveCommand(
    String commandId, {
    required KdsActiveChannel originChannel,
  }) async {
    final cloudReplicaProbe = originChannel == KdsActiveChannel.lan &&
        _activeChannel == KdsActiveChannel.cloud &&
        cloudTransport != null;
    final lanProxyProbe = originChannel == KdsActiveChannel.cloud &&
        _activeChannel == KdsActiveChannel.lan &&
        mode == KdsConnectionMode.cloudFirst;
    final KdsV2Transport? transport = cloudReplicaProbe
        ? cloudTransport
        : lanProxyProbe
            ? lanTransport
            : originChannel == KdsActiveChannel.lan
                ? lanTransport
                : cloudTransport;
    if (transport == null || transport is! KdsV2CommandResolver) {
      throw StateError(
        '${originChannel.label}通道不支持 UNKNOWN 指令查证',
      );
    }
    final resolver = transport as KdsV2CommandResolver;
    try {
      final resolution = await resolver.resolveCommand(commandId);
      if (cloudReplicaProbe &&
          resolution.status == KdsV2CommandResolutionStatus.notFound) {
        throw KdsCommandStillUnknown(commandId);
      }
      if (lanProxyProbe &&
          resolution.status == KdsV2CommandResolutionStatus.notFound) {
        throw KdsCommandStillUnknown(commandId);
      }
      if (resolution.status == KdsV2CommandResolutionStatus.applied &&
          resolution.result != null) {
        _rememberPatches(resolution.result!.patches,
            fromLan: transport == lanTransport);
      }
      if (transport == lanTransport) _recordLanSuccess();
      return resolution;
    } catch (error) {
      if (transport == lanTransport && _isLinkFailure(error)) {
        _recordLanFailure(error);
      }
      rethrow;
    }
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    final transport = _currentTransport;
    try {
      await transport.updateConfig(config);
      if (transport == lanTransport) {
        _recordLanSuccess();
      } else {
        _recordCloudSuccess();
      }
    } catch (e) {
      if (transport == cloudTransport &&
          mode == KdsConnectionMode.cloudFirst &&
          _isLinkFailure(e)) {
        _recordCloudFailure(e);
        KdsFileLogger.warn('[DUAL_MODE] updateConfig 结果不确定，已切 LAN 但禁止盲重放');
      }
      if (transport == lanTransport) {
        _recordLanFailure(e);
        if (_activeChannel == KdsActiveChannel.cloud &&
            cloudTransport != null) {
          KdsFileLogger.info('[DUAL_MODE] updateConfig 故障转移至云端重试');
          await cloudTransport!.updateConfig(config);
          return;
        }
      }
      rethrow;
    }
  }

  void dispose() {
    _lanRecoveryTimer?.cancel();
    _cloudRecoveryTimer?.cancel();
  }
}
