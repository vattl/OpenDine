import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import '../data/cashier_kds_database.dart';
import '../domain/cashier_kds_command_service.dart';
import '../domain/cashier_kds_interaction_log.dart';
import '../domain/cashier_kds_models.dart';
import 'cashier_kds_transport_proof.dart';

typedef CashierKdsUpstreamWebSocketConnector =
    Future<WebSocket> Function(
      String deviceToken,
      Map<String, String> queryParameters,
    );

typedef CashierKdsCloudTokenCache =
    Future<void> Function({
      required int shopId,
      required String deviceCode,
      required String token,
    });

class CashierKdsLanServer {
  CashierKdsLanServer(
    this._database, {
    this.onCloudEventQueued,
    this.onLocalConfigChanged,
    this.onProxyLogin,
    this.onCacheCloudDeviceToken,
    this.onProxyHttp,
    this.onProxyWebSocket,
    required this.cloudAuthorityMode,
    this.enableStaleFallback = false,
    this.maxConnectedDevices = 32,
    this.maxPendingFramesPerDevice = 32,
    this.maxPendingBytesPerDevice = 64 * 1024,
    this.socketWriteTimeout = const Duration(seconds: 5),
    this.socketAckTimeout = const Duration(seconds: 15),
    this.staleReadTtl = const Duration(minutes: 15),
    this.maxStaleCacheBodyBytes = 2 * 1024 * 1024,
  }) : assert(maxConnectedDevices > 0),
       assert(maxPendingFramesPerDevice > 0),
       assert(maxPendingBytesPerDevice > 0),
       assert(maxStaleCacheBodyBytes > 0),
       assert(
         !socketWriteTimeout.isNegative && socketWriteTimeout != Duration.zero,
       ),
       assert(
         !socketAckTimeout.isNegative && socketAckTimeout != Duration.zero,
       ),
       assert(!staleReadTtl.isNegative && staleReadTtl != Duration.zero),
       _commands = LocalKdsCommandService(_database);

  static const _queues = [
    'pending_prep',
    'pending_cook',
    'ready_serve',
    'done',
  ];

  final CashierKdsDatabase _database;
  final LocalKdsCommandService _commands;
  final void Function()? onCloudEventQueued;
  final void Function()? onLocalConfigChanged;
  final Future<Object?> Function(CashierKdsLoginRequest request)? onProxyLogin;
  final CashierKdsCloudTokenCache? onCacheCloudDeviceToken;
  final Future<CashierKdsProxyResponse> Function(
    CashierKdsProxyRequest request,
  )?
  onProxyHttp;
  final CashierKdsUpstreamWebSocketConnector? onProxyWebSocket;
  final bool cloudAuthorityMode;
  final bool enableStaleFallback;

  /// Hard limits prevent reconnect storms and unresponsive kitchen displays
  /// from consuming unbounded sockets or event memory in the cashier process.
  final int maxConnectedDevices;
  final int maxPendingFramesPerDevice;
  final int maxPendingBytesPerDevice;
  final Duration socketWriteTimeout;
  final Duration socketAckTimeout;
  final Duration staleReadTtl;
  final int maxStaleCacheBodyBytes;
  final Map<WebSocket, _KdsSocketSession> _sockets = {};
  final Map<String, WebSocket> _deviceSockets = {};
  final Map<WebSocket, WebSocket> _upstreamSockets = {};
  final Random _random = Random.secure();
  final Map<String, List<int>> _loginAttempts = {};
  final CashierKdsTransportProofVerifier _transportProofVerifier =
      CashierKdsTransportProofVerifier();
  HttpServer? _server;
  bool _requiresTransportProof = false;
  int? _activeShopId;
  Digest? _adminBearerDigest;

  int get port => _server?.port ?? 0;
  InternetAddress? get address => _server?.address;
  int get connectedDeviceCount => _sockets.length;
  int? get activeShopId => _activeShopId;
  CashierKdsDatabase get database => _database;
  List<CashierKdsDevice> get pairedDevices => _activeShopId == null
      ? const []
      : _database.readDevices(shopId: _activeShopId!);

  CashierKdsDevice upsertBoundDevice({
    required int shopId,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    List<String> workflows = const ['prep', 'cook', 'serve'],
    List<String> screenTags = const [],
    bool enabled = true,
  }) => _database.upsertBoundDevice(
    shopId: shopId,
    deviceCode: deviceCode,
    deviceName: deviceName,
    screenTag: screenTag,
    workflows: workflows,
    screenTags: screenTags,
    enabled: enabled,
  );

  void setActiveShop(int? shopId) {
    _activeShopId = shopId != null && shopId > 0 ? shopId : null;
  }

  void setAdminBearerToken(String? token) {
    final normalized = token?.trim() ?? '';
    _adminBearerDigest = normalized.isEmpty
        ? null
        : sha256.convert(utf8.encode(normalized));
  }

  String generatePairingCode({Duration validity = const Duration(minutes: 5)}) {
    final shopId = _activeShopId;
    if (shopId == null) {
      throw StateError('请先选择门店，再生成 KDS 配对码');
    }
    final code = (100000 + _random.nextInt(900000)).toString();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _database.createPairingCode(
      shopId: shopId,
      codeHash: _hashSecret(code),
      expiresAtMs: nowMs + validity.inMilliseconds,
      createdAtMs: nowMs,
    );
    return code;
  }

  Future<void> start({
    InternetAddress? address,
    int port = 17026,
    SecurityContext? securityContext,
  }) async {
    if (_server != null) return;
    final bindAddress = address ?? InternetAddress.loopbackIPv4;
    if (!bindAddress.isLoopback && securityContext == null) {
      throw StateError('LAN KDS 私网监听必须配置 TLS 证书');
    }
    final server = securityContext == null
        ? await HttpServer.bind(bindAddress, port, shared: false)
        : await HttpServer.bindSecure(
            bindAddress,
            port,
            securityContext,
            shared: false,
          );
    _server = server;
    _requiresTransportProof = securityContext != null;
    unawaited(server.forEach(_handleRequest));
  }

  Future<void> close() async {
    final sessions = _sockets.values.toList(growable: false);
    for (final session in sessions) {
      await _closeSocket(session);
    }
    await _server?.close(force: true);
    _server = null;
    _requiresTransportProof = false;
  }

  Future<void> revokeDevice(String deviceCode) async {
    final device = _database.disableDevice(deviceCode);
    if (device == null) {
      throw const CashierKdsValidation('device not found');
    }
    final sockets = _sockets.values
        .where((entry) => entry.device.deviceCode == deviceCode)
        .toList(growable: false);
    for (final socket in sockets) {
      await _closeSocket(
        socket,
        code: WebSocketStatus.policyViolation,
        reason: 'device revoked',
      );
    }
  }

  void broadcastNewOrder(int shopId, CashierOrderReceipt receipt) {
    final journal = receipt.eventSeq > 0
        ? _database
              .readChanges(
                shopId: shopId,
                afterSeq: receipt.eventSeq - 1,
                limit: 1,
              )
              .where((change) => change.eventSeq == receipt.eventSeq)
              .firstOrNull
        : null;
    final journalPatches = journal?.patches;
    final patches = (journalPatches != null && journalPatches.isNotEmpty)
        ? journalPatches
        : _database.readOrderPatches(receipt.orderId);
    if (patches.isEmpty) return;
    final orderDetails = _database.readOrderDetailsProjection(
      shopId: shopId,
      orderIds: [receipt.orderId],
    );
    final cloudOrderId = orderDetails
        .map((detail) => _readInt(detail['cloud_order_id']))
        .where((id) => id > 0)
        .firstOrNull;
    final cloudOrderNo = patches
        .map((patch) => '${patch['order_no'] ?? ''}'.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    final recipients = _broadcast(
      shopId,
      _eventEnvelopeV2(
        eventSeq: receipt.eventSeq,
        eventId: receipt.eventId,
        type: journal?.type ?? 'order_created',
        shopId: shopId,
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        patches: patches,
        orderDetails: orderDetails,
        queueCounts: _database.readQueueCounts(
          shopId,
          startMs: _businessDayStartMs(shopId),
          endMs: _businessDayEndMs(shopId),
        ),
        cloudOrderId: cloudOrderId,
        cloudOrderNo: cloudOrderNo,
      ),
    );
    _database.tryRecordInteraction(
      CashierKdsInteractionLogDraft(
        traceId: receipt.eventId.isEmpty
            ? 'order:$shopId:${receipt.orderId}'
            : receipt.eventId.startsWith('cloud:')
            ? receipt.eventId.substring('cloud:'.length)
            : receipt.eventId,
        shopId: shopId,
        orderId: receipt.orderId,
        orderNo: receipt.orderNo,
        eventId: receipt.eventId,
        source: KdsInteractionSide.cashier,
        target: KdsInteractionSide.kds,
        direction: KdsInteractionDirection.outbound,
        stage: KdsInteractionStage.kdsEventPush,
        action: journal?.type ?? 'order_created',
        status: recipients > 0
            ? KdsInteractionStatus.sent
            : KdsInteractionStatus.noRecipient,
        metadata: {'recipient_count': recipients},
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void broadcastConfigChanged({
    required int shopId,
    required int eventSeq,
    required int configVersion,
  }) {
    _broadcast(
      shopId,
      _eventEnvelopeV2(
        eventSeq: eventSeq,
        eventId: 'config:$shopId:$configVersion',
        type: 'config_changed',
        shopId: shopId,
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        patches: const [],
        queueCounts: _database.readQueueCounts(
          shopId,
          startMs: _businessDayStartMs(shopId),
          endMs: _businessDayEndMs(shopId),
        ),
      ),
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/ws/kds/v2' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        await _upgradeWebSocket(request);
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/kds/v2/health') {
        if (!_hasValidAdminBearer(request)) {
          _writeJson(request.response, {
            'code': 401,
            'msg': '缺少或无效的收银管理员凭证',
          }, statusCode: HttpStatus.unauthorized);
          return;
        }
        final shopId = _activeShopId;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final health = _database.readHealthSnapshot(nowMs: nowMs);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {
            'service': 'cashier-lan-kds',
            'shop_id': shopId,
            'server_time_ms': nowMs,
            'protocol_version': 2,
            'schema_version': 2,
            'event_seq': _database.latestEventSeq,
            'config_version': _configVersion(shopId),
            'connected_devices': connectedDeviceCount,
            ...health,
          },
        });
        return;
      }
      if (_isLegacyKdsDataPath(path)) {
        _writeJson(request.response, {
          'code': 4260,
          'msg': 'KDS protocol v1 is retired; use /kds/v2',
          'data': {'protocol_version': 2},
        }, statusCode: HttpStatus.upgradeRequired);
        return;
      }
      if (request.method == 'POST' && path == '/kds/device/login') {
        await _deviceLogin(request);
        return;
      }
      if (cloudAuthorityMode &&
          _isTransparentCloudRoute(request.method, path)) {
        await _proxyCloudHttp(request);
        return;
      }
      if (cloudAuthorityMode &&
          request.method == 'POST' &&
          (path == '/kds/settings' || path == '/admin/kds/config/save')) {
        _writeJson(request.response, {
          'code': 4260,
          'msg': 'Cloud authority requires POST /kds/v2/config',
          'data': {'protocol_version': 2},
        }, statusCode: HttpStatus.upgradeRequired);
        return;
      }
      if (request.method == 'POST' && path == '/kds/device/heartbeat') {
        final session = _requireSession(request, heartbeat: true);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {
            'shop_id': session.shopId,
            'server_time_ms': DateTime.now().millisecondsSinceEpoch,
            'protocol_version': 2,
          },
        });
        return;
      }
      if (request.method == 'GET' && path == '/kds/device/me') {
        final session = _requireSession(request);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {...session.toJson(), 'protocol_version': 2},
        });
        return;
      }
      if (request.method == 'GET' && path == '/kds/v2/bootstrap') {
        final session = _requireSession(request);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': _bootstrapData(session),
        });
        return;
      }
      if (request.method == 'GET' && path == '/kds/v2/business-day/orders') {
        final session = _requireSession(request);
        final cachedWindow = _database.readBusinessDayWindow(session.shopId);
        final startMs = _readInt(
          request.uri.queryParameters['start_ms'],
          fallback: cachedWindow?['start_ms'] ?? 0,
        );
        final endMs = _readInt(
          request.uri.queryParameters['end_ms'],
          fallback: cachedWindow?['end_ms'] ?? 0,
        );
        if (startMs <= 0 || endMs <= startMs) {
          throw const CashierKdsValidation('business-day window is not ready');
        }
        final afterId = _readInt(request.uri.queryParameters['after_id']);
        final afterCreatedMs = _readIntNullable(
          request.uri.queryParameters['after_created_ms'],
        );
        final limit = _readInt(
          request.uri.queryParameters['limit'],
          fallback: 200,
        );
        final rows = _database.readBusinessDayOrders(
          shopId: session.shopId,
          startMs: startMs,
          endMs: endMs,
          afterId: afterId,
          afterCreatedMs: afterCreatedMs,
          limit: limit,
        );
        final pageSize = limit.clamp(1, 200);
        final complete = rows.length <= pageSize;
        final pageRows = complete
            ? rows
            : rows.take(pageSize).toList(growable: false);
        final nextId = pageRows.isEmpty
            ? afterId
            : (pageRows.last['order_id'] as int? ?? afterId);
        final nextCreatedMs = pageRows.isEmpty
            ? afterCreatedMs
            : (pageRows.last['created_at_ms'] as int? ?? afterCreatedMs);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {
            'protocol_version': 2,
            'shop_id': session.shopId,
            'business_day_start_ms': startMs,
            'business_day_end_ms': endMs,
            'orders': pageRows,
            'next_after_id': complete ? null : nextId,
            'next_after_created_ms': complete ? null : nextCreatedMs,
            'complete': complete,
          },
        });
        return;
      }
      if (request.method == 'GET' && path == '/kds/v2/changes') {
        final session = _requireSession(request);
        final afterSeq = _readInt(request.uri.queryParameters['after_seq']);
        final earliest = _database.earliestRetainedEventSeq;
        final snapshotRequired = earliest > 0 && afterSeq < earliest - 1;
        final changes = snapshotRequired
            ? const <CashierKdsChange>[]
            : _database.readChanges(shopId: session.shopId, afterSeq: afterSeq);
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {
            'protocol_version': 2,
            'snapshot_required': snapshotRequired,
            'event_seq': _database.latestEventSeq,
            'latest_event_seq': _database.latestEventSeq,
            'events': changes
                .map((change) => _changeEnvelope(change, session))
                .toList(growable: false),
          },
        });
        return;
      }
      if (request.method == 'GET' &&
          path == '/kds/v2/diagnostics/interaction-logs') {
        final session = _requireSession(request);
        final limit = _readInt(
          request.uri.queryParameters['limit'],
          fallback: 50,
        ).clamp(1, 200);
        final logs = _database.readInteractionLogs(
          CashierKdsInteractionLogFilter(shopId: session.shopId, limit: limit),
        );
        _writeJson(request.response, {
          'code': 0,
          'msg': 'ok',
          'data': {
            'protocol_version': 2,
            'shop_id': session.shopId,
            'logs': logs.map((log) => log.toJson()).toList(growable: false),
          },
        });
        return;
      }
      if (request.method == 'POST' && path == '/kds/v2/commands') {
        await _executeV2Command(request);
        return;
      }
      if (request.method == 'GET' && path.startsWith('/kds/v2/commands/')) {
        await _resolveV2Command(
          request,
          path.substring('/kds/v2/commands/'.length),
        );
        return;
      }
      if (request.method == 'POST' &&
          (path == '/kds/v2/config' ||
              path == '/kds/settings' ||
              path == '/admin/kds/config/save')) {
        final session = _requireSession(request);
        final body = await _readJson(request);
        final prepVal =
            body['enable_prep_workflow'] ??
            body['prep_enabled'] ??
            body['prep_flow_enabled'];
        if (prepVal != null) {
          final enabled = _parseConfigBoolean(
            prepVal,
            field: 'enable_prep_workflow',
          );
          final change = _database.setEnablePrepWorkflow(
            shopId: session.shopId,
            enabled: enabled,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (change != null) {
            broadcastConfigChanged(
              shopId: session.shopId,
              eventSeq: change.eventSeq,
              configVersion: change.configVersion,
            );
            onLocalConfigChanged?.call();
          }
        }
        _writeJson(request.response, {'code': 0, 'msg': 'success'});
        return;
      }
      _writeJson(request.response, {
        'code': 404,
        'msg': 'LAN KDS route not found: $path',
      }, statusCode: HttpStatus.notFound);
    } on CashierKdsConflict catch (error) {
      _writeJson(request.response, {
        'code': 4090,
        'msg': error.message,
      }, statusCode: HttpStatus.conflict);
    } on CashierKdsValidation catch (error) {
      _writeJson(request.response, {
        'code': 4000,
        'msg': error.message,
      }, statusCode: HttpStatus.badRequest);
    } on _Forbidden catch (error) {
      _writeJson(request.response, {
        'code': 403,
        'msg': error.message,
      }, statusCode: HttpStatus.forbidden);
    } on _Unauthorized catch (error) {
      _writeJson(request.response, {
        'code': 401,
        'msg': error.message,
      }, statusCode: HttpStatus.unauthorized);
    } on _RateLimited catch (error) {
      _writeJson(request.response, {
        'code': 4290,
        'msg': error.message,
      }, statusCode: HttpStatus.tooManyRequests);
    } on _ServiceUnavailable catch (error) {
      _writeJson(request.response, {
        'code': 5030,
        'msg': error.message,
      }, statusCode: HttpStatus.serviceUnavailable);
    } catch (error, stackTrace) {
      final firstStackFrame = stackTrace
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.isNotEmpty,
            orElse: () => 'stack unavailable',
          );
      _database.tryRecordInteraction(
        CashierKdsInteractionLogDraft(
          traceId: 'err:${DateTime.now().millisecondsSinceEpoch}',
          shopId: _activeShopId ?? 0,
          orderId: 0,
          source: KdsInteractionSide.cashier,
          target: KdsInteractionSide.kds,
          direction: KdsInteractionDirection.inbound,
          stage: KdsInteractionStage.kdsEventPush,
          action: 'internal_error',
          status: KdsInteractionStatus.failed,
          errorType: 'server_unhandled_exception',
          errorSummary: '${error.runtimeType}: $firstStackFrame',
          metadata: {'method': request.method, 'path': request.uri.path},
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _writeJson(request.response, {
        'code': 500,
        'msg': 'LAN KDS internal error',
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  bool _hasValidAdminBearer(HttpRequest request) {
    final configured = _adminBearerDigest;
    if (configured == null) return false;
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null) return false;
    final match = RegExp(
      r'^Bearer\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(authorization.trim());
    final token = match?.group(1)?.trim() ?? '';
    if (token.isEmpty) return false;
    final candidate = sha256.convert(utf8.encode(token));
    var difference = configured.bytes.length ^ candidate.bytes.length;
    final length = min(configured.bytes.length, candidate.bytes.length);
    for (var index = 0; index < length; index += 1) {
      difference |= configured.bytes[index] ^ candidate.bytes[index];
    }
    return difference == 0;
  }

  static bool _isTransparentCloudRoute(String method, String path) {
    if (method == 'GET') {
      return path == '/kds/device/me' ||
          path == '/kds/v2/bootstrap' ||
          path == '/kds/v2/changes' ||
          path == '/kds/v2/business-day/orders';
    }
    return method == 'POST' &&
        (path == '/kds/device/heartbeat' || path == '/kds/v2/config');
  }

  Future<void> _proxyCloudHttp(HttpRequest request) async {
    final proxy = onProxyHttp;
    if (proxy == null) {
      throw const _ServiceUnavailable('云端代理服务暂不可用，请稍后重试');
    }
    final token = _sessionToken(request);
    if (token == null || token.isEmpty) {
      throw const _Unauthorized('missing or invalid device token');
    }
    final body = request.method == 'GET'
        ? const <String, Object?>{}
        : await _readJson(request);
    _verifyTransportProof(request, token: token, body: body);
    final requestId =
        request.headers.value('X-Request-Id')?.trim() ??
        request.headers.value('X-KDS-Proxy-Request-Id')?.trim() ??
        'lan-${DateTime.now().microsecondsSinceEpoch}';
    final commandId =
        request.headers.value('X-KDS-Command-Id')?.trim() ??
        (body['command_id'] != null ? '${body['command_id']}'.trim() : null);
    // Local device rows are cache/audit metadata only. They must never decide
    // whether a KDS request is admitted; the cloud evaluates the bearer token.
    var cachedSession = _database.authenticateDevice(_hashSecret(token));
    final deviceCode =
        request.headers.value('X-KDS-Device-Code')?.trim() ??
        cachedSession?.deviceCode ??
        '';
    final stopwatch = Stopwatch()..start();
    final cacheIdentity = _staleCacheIdentity(
      request,
      token: token,
      cachedSession: cachedSession,
    );
    late CashierKdsProxyResponse upstream;
    try {
      upstream = await proxy(
        CashierKdsProxyRequest(
          method: request.method,
          path: request.uri.path,
          query: request.uri.queryParameters.map(
            (key, value) => MapEntry<String, Object?>(key, value),
          ),
          body: body,
          deviceToken: token,
          requestId: requestId,
          commandId: commandId,
          deviceCode: deviceCode,
        ),
      );
    } catch (error) {
      if (enableStaleFallback) {
        final stale = cacheIdentity == null
            ? null
            : _readStaleCache(cacheIdentity.cacheKey);
        if (stale != null) {
          _recordProxyForward(
            shopId: cachedSession?.shopId ?? _activeShopId ?? 0,
            deviceCode: deviceCode,
            requestId: requestId,
            commandId: commandId,
            method: request.method,
            path: request.uri.path,
            status: KdsInteractionStatus.succeeded,
            httpStatus: stale.statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            servedVia: 'lan-cache',
          );
          await _writeProxyResponse(request.response, stale, requestId: requestId);
          return;
        }
      }
      _recordProxyForward(
        shopId: cachedSession?.shopId ?? _activeShopId ?? 0,
        deviceCode: deviceCode,
        requestId: requestId,
        commandId: commandId,
        method: request.method,
        path: request.uri.path,
        status: KdsInteractionStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        errorType: 'proxy_transport_error',
        errorSummary: '$error',
      );
      throw const _ServiceUnavailable('云端代理服务暂不可用，请稍后重试');
    }
    if (enableStaleFallback && cacheIdentity != null && _isTransientUpstreamFailure(upstream)) {
      final stale = _readStaleCache(cacheIdentity.cacheKey);
      if (stale != null) {
        _recordProxyForward(
          shopId: cachedSession?.shopId ?? _activeShopId ?? 0,
          deviceCode: cachedSession?.deviceCode ?? '',
          requestId: requestId,
          method: request.method,
          path: request.uri.path,
          status: KdsInteractionStatus.succeeded,
          httpStatus: stale.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          servedVia: 'lan-cache',
        );
        await _writeProxyResponse(request.response, stale);
        return;
      }
    }
    if (request.uri.path == '/kds/device/me' &&
        upstream.statusCode >= HttpStatus.ok &&
        upstream.statusCode < HttpStatus.multipleChoices) {
      cachedSession =
          _cacheCloudSessionResponse(token: token, response: upstream) ??
          cachedSession;
    }
    if (cacheIdentity != null &&
        upstream.statusCode >= HttpStatus.ok &&
        upstream.statusCode < HttpStatus.multipleChoices &&
        utf8.encode(upstream.body).length <= maxStaleCacheBodyBytes) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _database.writeKdsHttpCache(
        cacheKey: cacheIdentity.cacheKey,
        shopId: cachedSession?.shopId ?? _activeShopId ?? 0,
        path: request.uri.path,
        varyHash: cacheIdentity.varyHash,
        bodyJson: upstream.body,
        etag: _header(upstream.headers, 'etag'),
        authorityCursor: _authorityCursor(upstream),
        cachedAtMs: nowMs,
        expiresAtMs: nowMs + staleReadTtl.inMilliseconds,
      );
      upstream = CashierKdsProxyResponse(
        statusCode: upstream.statusCode,
        body: upstream.body,
        headers: {...upstream.headers, 'X-KDS-Cache': 'MISS'},
      );
    }
    _recordProxyForward(
      shopId: cachedSession?.shopId ?? _activeShopId ?? 0,
      deviceCode: deviceCode,
      requestId: requestId,
      commandId: commandId,
      method: request.method,
      path: request.uri.path,
      status: upstream.statusCode >= 400
          ? KdsInteractionStatus.failed
          : KdsInteractionStatus.succeeded,
      httpStatus: upstream.statusCode,
      durationMs: stopwatch.elapsedMilliseconds,
      servedVia: _header(upstream.headers, 'x-kds-served-via') ?? 'lan-proxy',
    );
    await _writeProxyResponse(request.response, upstream, requestId: requestId);
  }

  Future<CashierKdsProxyResponse> _fetchAndCacheCloudSession({
    required Future<CashierKdsProxyResponse> Function(
      CashierKdsProxyRequest request,
    )
    proxy,
    required String token,
    required String requestId,
  }) async {
    final response = await proxy(
      CashierKdsProxyRequest(
        method: 'GET',
        path: '/kds/device/me',
        query: const {},
        body: const {},
        deviceToken: token,
        requestId: '$requestId:device-me',
      ),
    );
    _cacheCloudSessionResponse(token: token, response: response);
    return response;
  }

  CashierKdsDevice? _cacheCloudSessionResponse({
    required String token,
    required CashierKdsProxyResponse response,
  }) {
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      return null;
    }
    Map<String, Object?> envelope;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      envelope = decoded.cast<String, Object?>();
    } catch (_) {
      return null;
    }
    if (_readInt(envelope['code'], fallback: 0) != 0) return null;
    final rawDevice = envelope['data'] ?? envelope['device'];
    if (rawDevice is! Map) return null;
    final device = rawDevice.cast<String, Object?>();
    final shopId = _readInt(device['shop_id'] ?? device['shopId']);
    final deviceCode = '${device['device_code'] ?? device['deviceCode'] ?? ''}'
        .trim();
    if (shopId <= 0 || deviceCode.isEmpty || deviceCode.length > 64) {
      return null;
    }
    List<String>? stringList(Object? raw) => raw is List
        ? raw
              .map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cloudDevice = CashierKdsDevice(
      shopId: shopId,
      deviceCode: deviceCode,
      deviceName: '${device['device_name'] ?? device['deviceName'] ?? ''}',
      screenTag: '${device['screen_tag'] ?? device['screenTag'] ?? ''}',
      workflows:
          stringList(device['workflows'] ?? device['workflows_json']) ??
          const [],
      screenTags:
          stringList(device['screen_tags'] ?? device['screenTags']) ?? const [],
      pairedAtMs: nowMs,
      lastHeartbeatAtMs: nowMs,
      enabled: true,
    );
    if (_activeShopId != null && _activeShopId != shopId) {
      // The cloud response remains authoritative. A cashier for another shop
      // simply must not retain that response in its local cache.
      return cloudDevice;
    }
    return _database.syncCloudDeviceSession(
      shopId: shopId,
      deviceCode: deviceCode,
      tokenHash: _hashSecret(token),
      deviceName: '${device['device_name'] ?? device['deviceName'] ?? ''}',
      screenTag: '${device['screen_tag'] ?? device['screenTag'] ?? ''}',
      workflows: stringList(device['workflows'] ?? device['workflows_json']),
      screenTags: stringList(device['screen_tags'] ?? device['screenTags']),
      nowMs: nowMs,
    );
  }

  void _recordProxyForward({
    required int shopId,
    required String deviceCode,
    required String requestId,
    String? commandId,
    required String method,
    required String path,
    required KdsInteractionStatus status,
    int? httpStatus,
    int? durationMs,
    String? servedVia,
    String? errorType,
    String? errorSummary,
    KdsInteractionStage stage = KdsInteractionStage.proxyHttpForward,
  }) {
    _database.tryRecordInteraction(
      CashierKdsInteractionLogDraft(
        traceId: requestId,
        shopId: shopId,
        operationId: commandId,
        eventId: commandId,
        source: KdsInteractionSide.kds,
        target: KdsInteractionSide.cloud,
        direction: KdsInteractionDirection.outbound,
        stage: stage,
        action: '$method $path',
        status: status,
        httpStatus: httpStatus,
        durationMs: durationMs,
        deviceCode: deviceCode,
        errorType: errorType,
        errorSummary: errorSummary,
        metadata: {
          'method': method,
          'path': path,
          if (commandId != null) 'command_id': commandId,
          if (servedVia != null) 'served_via': servedVia,
        },
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  ({String cacheKey, String varyHash})? _staleCacheIdentity(
    HttpRequest request, {
    required String token,
    required CashierKdsDevice? cachedSession,
  }) {
    if (request.method != 'GET' || request.uri.path != '/kds/v2/bootstrap') {
      return null;
    }
    final queryEntries = request.uri.queryParameters.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final query = queryEntries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    final shopId = cachedSession?.shopId ?? _activeShopId;
    if (shopId == null) return null;
    final varyHash = sha256.convert(utf8.encode('$shopId:$token')).toString();
    final cacheKey = sha256
        .convert(utf8.encode('$shopId|${request.uri.path}|$query|$varyHash'))
        .toString();
    return (cacheKey: cacheKey, varyHash: varyHash);
  }

  CashierKdsProxyResponse? _readStaleCache(String cacheKey) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cached = _database.readKdsHttpCache(cacheKey: cacheKey, nowMs: nowMs);
    if (cached == null) return null;
    final ageSeconds = max(0, (nowMs - cached.cachedAtMs) ~/ 1000);
    return CashierKdsProxyResponse(
      statusCode: HttpStatus.ok,
      body: cached.bodyJson,
      headers: {
        if (cached.etag != null) 'ETag': cached.etag!,
        'Age': '$ageSeconds',
        'X-KDS-Authority': 'cloud',
        'X-KDS-Authority-Cursor': '${cached.authorityCursor}',
        'X-KDS-Cache': 'STALE',
        'X-KDS-Cached-At': '${cached.cachedAtMs}',
        'X-KDS-Served-Via': 'lan-cache',
      },
    );
  }

  static bool _isTransientUpstreamFailure(CashierKdsProxyResponse response) =>
      response.statusCode == HttpStatus.badGateway ||
      response.statusCode == HttpStatus.serviceUnavailable ||
      response.statusCode == HttpStatus.gatewayTimeout;

  static int _authorityCursor(CashierKdsProxyResponse response) {
    final fromHeader = int.tryParse(
      _header(response.headers, 'x-kds-authority-cursor') ?? '',
    );
    if (fromHeader != null && fromHeader >= 0) return fromHeader;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final data = decoded['data'];
        final raw = data is Map ? data['event_seq'] : decoded['event_seq'];
        return _readInt(raw);
      }
    } catch (_) {}
    return 0;
  }

  static String? _header(Map<String, String> headers, String name) {
    final normalized = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    return null;
  }

  static const _proxyResponseHeaders = {
    'content-type',
    'etag',
    'age',
    'retry-after',
    'x-kds-authority-cursor',
    'x-kds-authority',
    'x-kds-cache',
    'x-kds-cached-at',
    'x-kds-served-via',
    'x-request-id',
    'x-kds-command-id',
    'x-kds-device-code',
  };

  Future<void> _writeProxyResponse(
    HttpResponse response,
    CashierKdsProxyResponse upstream, {
    String? requestId,
  }) async {
    response.statusCode = upstream.statusCode;
    if (requestId != null && requestId.trim().isNotEmpty) {
      response.headers.set('X-Request-Id', requestId.trim());
    }
    var hasContentType = false;
    var hasServedVia = false;
    for (final entry in upstream.headers.entries) {
      final normalizedName = entry.key.toLowerCase();
      if (!_proxyResponseHeaders.contains(normalizedName)) continue;
      if (normalizedName == HttpHeaders.contentTypeHeader) {
        hasContentType = _trySetProxyContentType(response.headers, entry.value);
      } else if (normalizedName == 'x-kds-served-via') {
        hasServedVia = _trySetProxyHeader(
          response.headers,
          entry.key,
          entry.value,
        );
      } else {
        _trySetProxyHeader(response.headers, entry.key, entry.value);
      }
    }
    if (!hasServedVia) {
      response.headers.set('X-KDS-Served-Via', 'lan-proxy');
    }
    if (!hasContentType) {
      response.headers.contentType = ContentType.json;
    }
    // JSON is UTF-8 by contract. Writing a String after forwarding an
    // upstream `application/json` header without a charset makes dart:io
    // select its ASCII encoder, which throws for Chinese dish names/messages
    // and turns an otherwise successful cloud response into a LAN 500.
    response.add(utf8.encode(upstream.body));
    await response.close();
  }

  static bool _trySetProxyHeader(
    HttpHeaders headers,
    String name,
    String value,
  ) {
    if (!_isSafeHeaderValue(value)) return false;
    try {
      headers.set(name, value);
      return true;
    } on ArgumentError {
      return false;
    } on FormatException {
      return false;
    }
  }

  static bool _trySetProxyContentType(HttpHeaders headers, String value) {
    final firstValue = value.split(',').first.trim();
    if (firstValue.isEmpty || !_isSafeHeaderValue(firstValue)) return false;
    try {
      headers.contentType = ContentType.parse(firstValue);
      return true;
    } on ArgumentError {
      return false;
    } on FormatException {
      return false;
    }
  }

  static bool _isSafeHeaderValue(String value) =>
      !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

  Future<void> _deviceLogin(HttpRequest request) async {
    _checkLoginRateLimit(
      request.connectionInfo?.remoteAddress.address ?? 'unknown',
    );
    final body = await _readJson(request);
    final deviceCode = '${body['device_code'] ?? body['deviceCode'] ?? ''}'
        .trim();
    final deviceName = '${body['device_name'] ?? ''}'.trim();
    final screenTag = '${body['screen_tag'] ?? ''}'.trim();
    final workflows = (body['workflows'] as List? ?? const [])
        .map((value) => '$value')
        .where((value) => const {'prep', 'cook', 'serve'}.contains(value))
        .toList(growable: false);
    // D026：设备可见烤制岗（荤烤/素烤/海鲜），由设备端登录回传持久化配置。
    final screenTags =
        (body['screen_tags'] as List? ??
                body['screenTags'] as List? ??
                const [])
            .map((value) => '$value')
            .where(kIsGrillTag)
            .toList(growable: false);

    if (deviceCode.isEmpty ||
        deviceCode.length > 64 ||
        deviceName.length > 100 ||
        (screenTag.isNotEmpty &&
            !const {'workflow_board'}.contains(screenTag))) {
      throw const CashierKdsValidation('device_code is required');
    }

    if (cloudAuthorityMode) {
      final proxyLogin = onProxyLogin;
      if (proxyLogin == null) {
        throw const _ServiceUnavailable('云端登录服务暂不可用，请稍后重试');
      }
      final requestId =
          request.headers.value('X-KDS-Proxy-Request-Id')?.trim() ??
          'login-${DateTime.now().microsecondsSinceEpoch}';
      final stopwatch = Stopwatch()..start();
      try {
        final rawCloudResponse = await proxyLogin(
          CashierKdsLoginRequest(
            body: body,
            requestId: requestId,
            deviceToken: request.headers.value('X-Kds-Device-Token')?.trim(),
          ),
        );
        CashierKdsProxyResponse? transparentResponse;
        late final Map<String, Object?> cloudResp;
        if (rawCloudResponse is CashierKdsProxyResponse) {
          transparentResponse = rawCloudResponse;
          if (rawCloudResponse.statusCode < HttpStatus.ok ||
              rawCloudResponse.statusCode >= HttpStatus.multipleChoices) {
            _recordProxyForward(
              shopId: _activeShopId ?? 0,
              deviceCode: deviceCode,
              requestId: requestId,
              method: 'POST',
              path: '/kds/device/login',
              status: KdsInteractionStatus.failed,
              httpStatus: rawCloudResponse.statusCode,
              durationMs: stopwatch.elapsedMilliseconds,
              servedVia: 'lan-proxy',
            );
            await _writeProxyResponse(request.response, rawCloudResponse);
            return;
          }
          final decoded = jsonDecode(rawCloudResponse.body);
          if (decoded is! Map) {
            throw const _ServiceUnavailable('云端登录服务返回无效响应，请稍后重试');
          }
          cloudResp = decoded.cast<String, Object?>();
          if (_readInt(cloudResp['code'], fallback: 0) != 0) {
            _recordProxyForward(
              shopId: _activeShopId ?? 0,
              deviceCode: deviceCode,
              requestId: requestId,
              method: 'POST',
              path: '/kds/device/login',
              status: KdsInteractionStatus.failed,
              httpStatus: rawCloudResponse.statusCode,
              durationMs: stopwatch.elapsedMilliseconds,
              servedVia: 'lan-proxy',
            );
            await _writeProxyResponse(request.response, rawCloudResponse);
            return;
          }
        } else if (rawCloudResponse is Map) {
          cloudResp = rawCloudResponse.cast<String, Object?>();
        } else {
          throw const _ServiceUnavailable('云端登录服务返回无效响应，请稍后重试');
        }
        final rawCloudData = cloudResp['data'] ?? cloudResp['device'];
        final cloudData = rawCloudData is Map
            ? rawCloudData.cast<String, Object?>()
            : cloudResp;
        final cloudToken =
            '${cloudData['device_token'] ?? cloudData['deviceToken'] ?? cloudData['token'] ?? ''}'
                .trim();
        final shopId = _readInt(
          cloudData['shop_id'] ?? cloudData['shopId'],
          fallback: 0,
        );
        final cloudDeviceCode =
            '${cloudData['device_code'] ?? cloudData['deviceCode'] ?? deviceCode}'
                .trim();
        if (cloudToken.isEmpty ||
            shopId <= 0 ||
            cloudDeviceCode != deviceCode) {
          throw const _ServiceUnavailable('云端登录服务返回无效响应，请稍后重试');
        }
        final cacheCloudToken = onCacheCloudDeviceToken;
        if (cacheCloudToken == null) {
          throw const _ServiceUnavailable('设备安全凭据存储不可用，请稍后重试');
        }
        await cacheCloudToken(
          shopId: shopId,
          deviceCode: cloudDeviceCode,
          token: cloudToken,
        );
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final cachedDevice = _database.syncCloudDeviceSession(
          shopId: shopId,
          deviceCode: deviceCode,
          tokenHash: _hashSecret(cloudToken),
          deviceName: deviceName.isEmpty
              ? '${cloudData['device_name'] ?? ''}'
              : deviceName,
          screenTag: screenTag.isEmpty
              ? '${cloudData['screen_tag'] ?? ''}'
              : screenTag,
          workflows: workflows,
          screenTags: screenTags,
          nowMs: nowMs,
        );

        final sockets = _sockets.values
            .where((entry) => entry.device.deviceCode == deviceCode)
            .toList(growable: false);
        for (final socket in sockets) {
          await _closeSocket(
            socket,
            code: WebSocketStatus.normalClosure,
            reason: 'device re-login (cloud authoritative)',
          );
        }

        _recordProxyForward(
          shopId: shopId,
          deviceCode: cloudDeviceCode,
          requestId: requestId,
          method: 'POST',
          path: '/kds/device/login',
          status: KdsInteractionStatus.succeeded,
          httpStatus: HttpStatus.ok,
          durationMs: stopwatch.elapsedMilliseconds,
          servedVia: 'lan-proxy',
        );

        if (transparentResponse != null) {
          await _writeProxyResponse(request.response, transparentResponse);
        } else {
          _writeJson(request.response, {
            'code': 0,
            'msg': 'ok',
            'data': {
              ...cachedDevice.toJson(),
              'device_token': cloudToken,
              'protocol_version': 2,
            },
          });
        }
        return;
      } on _ServiceUnavailable catch (error) {
        _recordProxyForward(
          shopId: _activeShopId ?? 0,
          deviceCode: deviceCode,
          requestId: requestId,
          method: 'POST',
          path: '/kds/device/login',
          status: KdsInteractionStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: 'proxy_login_error',
          errorSummary: error.message,
        );
        rethrow;
      } catch (error) {
        final safeMessage = error is ApiException
            ? error.message
            : '云端登录服务暂不可用，请稍后重试';
        _recordProxyForward(
          shopId: _activeShopId ?? 0,
          deviceCode: deviceCode,
          requestId: requestId,
          method: 'POST',
          path: '/kds/device/login',
          status: KdsInteractionStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: 'proxy_login_error',
          errorSummary: safeMessage,
        );
        throw _ServiceUnavailable(safeMessage);
      }
    }

    final pairingCode =
        '${body['pairing_code'] ?? body['pairingCode'] ?? body['pairing_secret'] ?? body['pairingSecret'] ?? ''}'
            .trim();
    final boundDevice = _database.readDeviceByCode(deviceCode);
    if (boundDevice == null) {
      if (pairingCode.isEmpty) {
        throw const _Forbidden('设备未绑定，请先在收银端绑定此设备编码');
      }
    } else {
      if (pairingCode.isEmpty && !boundDevice.enabled) {
        throw const _Forbidden('设备已被禁用，请先在收银端重新启用此设备');
      }
    }

    // 若原设备此前已有活跃的 WebSocket 连接，关闭旧连接以切换到本次新签发的 token
    final sockets = _sockets.values
        .where((entry) => entry.device.deviceCode == deviceCode)
        .toList(growable: false);
    for (final socket in sockets) {
      await _closeSocket(
        socket,
        code: WebSocketStatus.normalClosure,
        reason: 'device re-login',
      );
    }

    final token = _randomSecret();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    late final CashierKdsDevice device;
    if (pairingCode.isNotEmpty) {
      try {
        device = _database.pairDevice(
          pairingCodeHash: _hashSecret(pairingCode),
          tokenHash: _hashSecret(token),
          deviceCode: deviceCode,
          deviceName: deviceName.isEmpty
              ? (boundDevice?.deviceName ?? deviceCode)
              : deviceName,
          screenTag: screenTag.isEmpty
              ? (boundDevice?.screenTag ?? 'workflow_board')
              : screenTag,
          workflows: workflows.isEmpty
              ? (boundDevice?.workflows ?? const ['prep', 'cook', 'serve'])
              : workflows,
          screenTags: screenTags.isEmpty
              ? (boundDevice?.screenTags ?? const [])
              : screenTags,
          nowMs: nowMs,
        );
      } on CashierKdsValidation catch (error) {
        if (error.message.contains('pairing code') ||
            error.message.contains('配对码')) {
          throw const _Unauthorized('配对码无效或已过期，请在收银端重新生成');
        }
        throw _Forbidden(error.message);
      }
    } else {
      try {
        device = _database.loginBoundDevice(
          deviceCode: deviceCode,
          tokenHash: _hashSecret(token),
          deviceName: deviceName.isEmpty ? boundDevice!.deviceName : deviceName,
          screenTag: screenTag.isEmpty ? boundDevice!.screenTag : screenTag,
          workflows: workflows.isEmpty ? boundDevice!.workflows : workflows,
          screenTags: screenTags.isEmpty ? boundDevice!.screenTags : screenTags,
          nowMs: nowMs,
        );
      } on CashierKdsValidation catch (error) {
        if (error.message.contains('设备未绑定')) {
          throw _Forbidden(error.message);
        }
        rethrow;
      }
    }
    _writeJson(request.response, {
      'code': 0,
      'msg': 'ok',
      'data': {
        ...device.toJson(),
        'device_token': token,
        'protocol_version': 2,
      },
    });
  }

  Future<void> _executeV2Command(HttpRequest request) async {
    final body = await _readJson(request);
    if (cloudAuthorityMode) {
      final token = _sessionToken(request);
      if (token == null || token.isEmpty) {
        throw const _Unauthorized('missing or invalid device token');
      }
      _verifyTransportProof(request, token: token, body: body);
      final proxy = onProxyHttp;
      if (proxy == null) {
        throw const _ServiceUnavailable('云端代理服务暂不可用，请稍后重试');
      }
      final requestId = '${body['command_id'] ?? ''}'.trim();
      final cached = _database.authenticateDevice(_hashSecret(token));
      final stopwatch = Stopwatch()..start();
      late final CashierKdsProxyResponse upstream;
      try {
        upstream = await proxy(
          CashierKdsProxyRequest(
            method: 'POST',
            path: '/kds/v2/commands',
            query: request.uri.queryParameters.map(
              (key, value) => MapEntry<String, Object?>(key, value),
            ),
            body: body,
            deviceToken: token,
            requestId: requestId.isEmpty
                ? 'command-${DateTime.now().microsecondsSinceEpoch}'
                : requestId,
          ),
        );
      } catch (error) {
        _recordProxyForward(
          shopId: cached?.shopId ?? _activeShopId ?? 0,
          deviceCode: cached?.deviceCode ?? '',
          requestId: requestId,
          method: 'POST',
          path: '/kds/v2/commands',
          status: KdsInteractionStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: 'proxy_command_transport_error',
          errorSummary: '$error',
        );
        throw const _ServiceUnavailable(
          '云端暂不可达；命令未被收银端接受，请由 KDS 保留原 command_id 后重试',
        );
      }
      _recordProxyForward(
        shopId: cached?.shopId ?? _activeShopId ?? 0,
        deviceCode: cached?.deviceCode ?? '',
        requestId: requestId,
        method: 'POST',
        path: '/kds/v2/commands',
        status: upstream.statusCode >= 400
            ? KdsInteractionStatus.failed
            : KdsInteractionStatus.succeeded,
        httpStatus: upstream.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        servedVia: 'lan-proxy',
      );
      await _writeProxyResponse(request.response, upstream);
      return;
    }
    final session = _requireSession(request);
    final rawTarget = body['target'];
    if (rawTarget is! Map) {
      throw const CashierKdsValidation('target must be an object');
    }
    final target = rawTarget.cast<String, Object?>();
    final type = LocalKdsCommandType.parse('${body['type'] ?? ''}');
    final fromQueue = target['from_queue'] == null
        ? null
        : '${target['from_queue']}';
    final rawIds = target['detail_ids'];
    final command = LocalKdsCommand(
      commandId: '${body['command_id'] ?? ''}'.trim(),
      type: type,
      shopId: session.shopId,
      target: LocalKdsCommandTarget(
        orderId: _nullablePositiveInt(target['order_id']),
        detailId: _nullablePositiveInt(target['detail_id']),
        detailIds: rawIds is List
            ? rawIds.map(_readInt).where((id) => id > 0).toList(growable: false)
            : const [],
        fromQueue: fromQueue,
      ),
      quantity: body['quantity'] == null ? null : _readInt(body['quantity']),
      expectedRevision: body['expected_revision'] == null
          ? null
          : _readInt(body['expected_revision']),
      payload: body['payload'] is Map
          ? (body['payload'] as Map).cast<String, Object?>()
          : const {},
      actorDeviceCode: session.deviceCode,
      occurredAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _recordCommand(
      command,
      stage: KdsInteractionStage.kdsCommandReceived,
      status: KdsInteractionStatus.received,
      source: KdsInteractionSide.kds,
      target: KdsInteractionSide.cashier,
      direction: KdsInteractionDirection.inbound,
    );
    try {
      _authorizeCommand(session, command);
      _recordCommand(
        command,
        stage: KdsInteractionStage.kdsCommandAuthorized,
        status: KdsInteractionStatus.succeeded,
      );
    } catch (error) {
      _recordCommand(
        command,
        stage: KdsInteractionStage.kdsCommandAuthorized,
        status: KdsInteractionStatus.rejected,
        errorType: 'authorization_or_validation',
        errorSummary: '$error',
      );
      rethrow;
    }
    late final LocalKdsCommandResult result;
    try {
      result = _commands.execute(command);
      _recordCommand(
        command,
        stage: KdsInteractionStage.localProjectionApply,
        status: result.duplicate
            ? KdsInteractionStatus.duplicate
            : KdsInteractionStatus.succeeded,
        metadata: {'duplicate': result.duplicate},
      );
      _recordCommand(
        command,
        stage: KdsInteractionStage.cloudEventQueued,
        status: KdsInteractionStatus.queued,
        source: KdsInteractionSide.cashier,
        target: KdsInteractionSide.cloud,
        direction: KdsInteractionDirection.outbound,
      );
    } catch (error) {
      _recordCommand(
        command,
        stage: KdsInteractionStage.localProjectionApply,
        status: KdsInteractionStatus.failed,
        errorType: 'local_projection_error',
        errorSummary: '$error',
      );
      rethrow;
    }
    final orderDetails = _orderDetailsForPatches(
      session.shopId,
      result.patches,
    );
    onCloudEventQueued?.call();
    _writeJson(request.response, {
      'code': 0,
      'msg': 'ok',
      'data': {...result.toJson(), 'order_details': orderDetails},
    });
    _recordCommand(
      command,
      stage: KdsInteractionStage.kdsCommandResponse,
      status: KdsInteractionStatus.responded,
      source: KdsInteractionSide.cashier,
      target: KdsInteractionSide.kds,
      direction: KdsInteractionDirection.outbound,
    );
    if (!result.duplicate) {
      final recipients = _broadcast(
        session.shopId,
        _eventEnvelopeV2(
          eventSeq: result.eventSeq,
          eventId: result.commandId,
          type: type.wireName,
          shopId: session.shopId,
          occurredAtMs: command.occurredAtMs,
          patches: result.patches,
          orderDetails: orderDetails,
          queueCounts: result.queueCounts,
        ),
      );
      _recordCommand(
        command,
        stage: KdsInteractionStage.kdsEventPush,
        status: recipients > 0
            ? KdsInteractionStatus.sent
            : KdsInteractionStatus.noRecipient,
        source: KdsInteractionSide.cashier,
        target: KdsInteractionSide.kds,
        direction: KdsInteractionDirection.outbound,
        metadata: {'recipient_count': recipients},
      );
    }
  }

  Future<void> _resolveV2Command(
    HttpRequest request,
    String rawCommandId,
  ) async {
    final commandId = Uri.decodeComponent(rawCommandId).trim();
    if (commandId.isEmpty || commandId.contains('/')) {
      throw const CashierKdsValidation('command_id is invalid');
    }
    if (cloudAuthorityMode) {
      final token = _sessionToken(request);
      if (token == null || token.isEmpty) {
        throw const _Unauthorized('missing or invalid device token');
      }
      _verifyTransportProof(request, token: token, body: const {});
      final proxy = onProxyHttp;
      if (proxy == null) {
        throw const _ServiceUnavailable('云端代理服务暂不可用，请稍后重试');
      }
      final cached = _database.authenticateDevice(_hashSecret(token));
      final stopwatch = Stopwatch()..start();
      late final CashierKdsProxyResponse upstream;
      try {
        upstream = await proxy(
          CashierKdsProxyRequest(
            method: 'GET',
            path: '/kds/v2/commands/${Uri.encodeComponent(commandId)}',
            query: const {},
            body: const {},
            deviceToken: token,
            requestId: commandId,
          ),
        );
      } catch (error) {
        _recordProxyForward(
          shopId: cached?.shopId ?? _activeShopId ?? 0,
          deviceCode: cached?.deviceCode ?? '',
          requestId: commandId,
          method: 'GET',
          path: '/kds/v2/commands/$commandId',
          status: KdsInteractionStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: 'proxy_command_resolution_error',
          errorSummary: '$error',
        );
        throw const _ServiceUnavailable('云端命令账本暂不可达，请由 KDS 保留原 command_id 后重试');
      }
      _recordProxyForward(
        shopId: cached?.shopId ?? _activeShopId ?? 0,
        deviceCode: cached?.deviceCode ?? '',
        requestId: commandId,
        method: 'GET',
        path: '/kds/v2/commands/$commandId',
        status: upstream.statusCode >= 400
            ? KdsInteractionStatus.failed
            : KdsInteractionStatus.succeeded,
        httpStatus: upstream.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        servedVia: 'lan-proxy',
      );
      await _writeProxyResponse(request.response, upstream);
      return;
    }
    final session = _requireSession(request);
    final row = _database.readPendingCommand(session.shopId, commandId);
    final data = <String, Object?>{
      'protocol_version': 2,
      'command_id': commandId,
    };
    if (row == null) {
      // Local absence cannot prove that the cloud command ledger has no row.
      // Keep the result non-terminal until the authority can be queried.
      data['status'] = 'EXECUTING';
    } else if ('${row['status']}' == 'APPLIED' &&
        row['result_json'] is String) {
      data['status'] = 'APPLIED';
      data['result'] = jsonDecode(row['result_json'] as String);
    } else if ('${row['status']}' == 'REJECTED') {
      data['status'] = 'REJECTED';
      if (row['result_json'] is String) {
        final rejection = jsonDecode(row['result_json'] as String);
        if (rejection is Map && rejection['message'] != null) {
          data['message'] = '${rejection['message']}';
        }
      }
    } else {
      data['status'] = 'EXECUTING';
    }
    _writeJson(request.response, {'code': 0, 'msg': 'ok', 'data': data});
  }

  void _recordCommand(
    LocalKdsCommand command, {
    required KdsInteractionStage stage,
    required KdsInteractionStatus status,
    KdsInteractionSide source = KdsInteractionSide.cashier,
    KdsInteractionSide target = KdsInteractionSide.cashier,
    KdsInteractionDirection direction = KdsInteractionDirection.internal,
    String? errorType,
    String? errorSummary,
    Map<String, Object?> metadata = const {},
  }) {
    _database.tryRecordInteraction(
      CashierKdsInteractionLogDraft(
        traceId: command.commandId,
        shopId: command.shopId,
        orderId: command.target.orderId,
        eventId: command.commandId,
        operationId: command.commandId,
        source: source,
        target: target,
        direction: direction,
        stage: stage,
        action: command.type.wireName,
        status: status,
        deviceCode: command.actorDeviceCode,
        errorType: errorType,
        errorSummary: errorSummary,
        metadata: {
          if (command.target.detailId != null)
            'detail_id': command.target.detailId,
          if (command.quantity != null) 'quantity': command.quantity,
          ...metadata,
        },
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Map<String, Object?> _bootstrapData(CashierKdsDevice session) {
    final visibleQueues = _queues
        .where((queue) => _canReadQueue(session, queue))
        .toList(growable: false);
    final allowedCommands = LocalKdsCommandType.values
        .where(
          (type) =>
              type != LocalKdsCommandType.archiveClear ||
              const {'prep', 'cook', 'serve'}.every(session.workflows.contains),
        )
        .map((type) => type.wireName)
        .toList(growable: false);
    final permissions = <String, Object?>{
      'visible_queues': visibleQueues,
      'allowed_commands': allowedCommands,
    };
    final dishScreenTags = _dishScreenTags(session.shopId);
    final queues = <String, List<Map<String, Object?>>>{};
    for (final queue in _queues) {
      queues[queue] = !_canReadQueue(session, queue)
          ? const []
          : _database
                .readWorkflowBoard(
                  shopId: session.shopId,
                  queue: queue,
                  startMs: _businessDayStartMs(session.shopId),
                  endMs: _businessDayEndMs(session.shopId),
                )
                .lines
                .where(
                  (line) =>
                      _canDeviceSeeDish(session, line.dishId, dishScreenTags) &&
                      (!cloudAuthorityMode ||
                          (line.cloudDetailId != null &&
                              line.cloudDetailId! > 0 &&
                              line.cloudOrderId != null &&
                              line.cloudOrderId! > 0)),
                )
                .map(
                  (line) =>
                      line.toApiJson(canonicalCloudIds: cloudAuthorityMode),
                )
                .toList(growable: false);
    }
    final rawCounts = _database.readQueueCounts(
      session.shopId,
      startMs: _businessDayStartMs(session.shopId),
      endMs: _businessDayEndMs(session.shopId),
    );
    final queueCounts = <String, int>{
      for (final queue in _queues)
        queue: visibleQueues.contains(queue) ? (rawCounts[queue] ?? 0) : 0,
    };
    final snapshot = _database.readConfigSnapshot(
      shopId: session.shopId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      allowExpired: true,
    );
    final payload = snapshot?.payload ?? const <String, Object?>{};
    final workflow = payload['workflow'] is Map
        ? (payload['workflow'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final sla = payload['sla'] is Map
        ? (payload['sla'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final config = <String, Object?>{
      ...workflow,
      ...sla,
      if (payload['fixed_order'] is List) 'fixed_order': payload['fixed_order'],
      'print_on_advance': _database.readPrintOnAdvance(shopId: session.shopId),
      'enable_prep_workflow':
          _database.readEnablePrepWorkflow(shopId: session.shopId) ? 1 : 0,
      'prep_enabled': _database.readEnablePrepWorkflow(shopId: session.shopId)
          ? 1
          : 0,
      ...permissions,
    };
    final fixedCatalog = _database
        .readDishCatalog(shopId: session.shopId)
        .map(
          (item) => <String, Object?>{
            'id': item.id > 0 ? item.id : item.dishId,
            if (item.id > 0) 'catalog_id': item.id,
            'dish_id': item.dishId,
            'dish_name': item.dishName,
            'unit': item.unit,
            'sequence': item.sequence,
            if (item.categoryId != null) 'category_id': item.categoryId,
            if (item.categoryName != null) 'category_name': item.categoryName,
            if (item.categorySequence != null)
              'category_sequence': item.categorySequence,
            if (item.dishSequence != null) 'dish_sequence': item.dishSequence,
            'stock': item.stock,
            'onsale': item.onSale,
            'sold_out': item.soldOut,
            if (item.screenTag != null && item.screenTag!.isNotEmpty)
              'screen_tag': item.screenTag,
          },
        )
        .toList(growable: false);
    final legacyCatalog = fixedCatalog
        .map(
          (item) => <String, Object?>{
            ...item,
            'id': item['dish_id'],
            'name': item['dish_name'],
            'sorting': item['sequence'],
          },
        )
        .toList(growable: false);
    final outbox = _database.readOutboxStats();
    final stats = <String, Object?>{
      'outbox_pending': outbox.pending,
      'outbox_retrying': outbox.retrying,
      'outbox_dead_letter': outbox.deadLetter,
      'outbox_auth_paused': outbox.authPaused,
    };
    final patches = queues.values
        .expand((lines) => lines)
        .toList(growable: false);
    final orderDetails = _orderDetailsForPatches(session.shopId, patches);
    return {
      'protocol_version': 2,
      'event_seq': _database.latestEventSeq,
      'shop_id': session.shopId,
      'device': {...session.toJson(), 'permissions': permissions},
      'permissions': permissions,
      'queues': queues,
      'queue_counts': queueCounts,
      'fixed_catalog': fixedCatalog,
      'order_details': orderDetails,
      'config': config,
      'stats': stats,
      'config_version': _database.readLanConfigVersion(session.shopId),
      'authority_mode': cloudAuthorityMode ? 'cloud' : 'local_legacy',
      // Transitional aliases for pre-v2.184 Cashier clients.
      'patches': patches,
      'catalog': legacyCatalog,
    };
  }

  Map<String, Object?> _changeEnvelope(
    CashierKdsChange change,
    CashierKdsDevice session,
  ) {
    final catalog = _dishScreenTags(change.shopId);
    final patches = change.patches
        .where((patch) => _canDeviceSeePatch(session, patch, catalog))
        .toList(growable: false);
    return _eventEnvelopeV2(
      eventSeq: change.eventSeq,
      eventId: change.eventId,
      type: change.type,
      shopId: change.shopId,
      occurredAtMs: change.occurredAtMs,
      patches: patches,
      orderDetails: _orderDetailsForPatches(change.shopId, patches),
      queueCounts: _database.readQueueCounts(
        change.shopId,
        startMs: _businessDayStartMs(change.shopId),
        endMs: _businessDayEndMs(change.shopId),
      ),
    );
  }

  Map<String, Object?> _eventEnvelopeV2({
    required int eventSeq,
    required String eventId,
    required String type,
    required int shopId,
    required int occurredAtMs,
    required List<Map<String, Object?>> patches,
    List<Map<String, Object?>> orderDetails = const [],
    required Map<String, int> queueCounts,
    int? cloudOrderId,
    String? cloudOrderNo,
  }) => {
    'protocol_version': 2,
    'event_seq': eventSeq,
    'event_id': eventId,
    'type': type,
    'shop_id': shopId,
    'occurred_at_ms': occurredAtMs,
    'patches': patches,
    'order_details': orderDetails,
    'queue_counts': queueCounts,
    'config_version': _configVersion(shopId),
    // KDS 侧用 cloud_order_id 显示云端订单数字 ID；缺失时回退订单号。
    if (cloudOrderId != null && cloudOrderId > 0)
      'cloud_order_id': cloudOrderId,
    if (cloudOrderNo != null && cloudOrderNo.trim().isNotEmpty)
      'cloud_order_no': cloudOrderNo,
  };

  List<Map<String, Object?>> _orderDetailsForPatches(
    int shopId,
    Iterable<Map<String, Object?>> patches,
  ) => _database.readOrderDetailsProjection(
    shopId: shopId,
    orderIds: patches
        .map((patch) => _readInt(patch['order_id']))
        .where((id) => id > 0),
  );

  (int, int)? _businessDayWindow(int shopId) {
    final window = _database.readBusinessDayWindow(shopId);
    if (window == null) return null;
    final startMs = window['start_ms'];
    final endMs = window['end_ms'];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // 仅当当前时刻落在窗口内时窗口才有效：窗口已结束（打烊后/日切中）
    // 或尚未开始（次日营业前）时，若仍按窗口过滤，会把窗口外新下的
    // 正常订单全部排除，导致 KDS bootstrap 返回空、订单消失。
    // 此时视为无窗口 → 不过滤。
    if (startMs == null ||
        endMs == null ||
        startMs <= 0 ||
        endMs <= startMs ||
        nowMs < startMs ||
        nowMs >= endMs) {
      return null;
    }
    return (startMs, endMs);
  }

  int? _businessDayStartMs(int shopId) {
    final window = _businessDayWindow(shopId);
    return window == null ? null : window.$1;
  }

  int? _businessDayEndMs(int shopId) {
    final window = _businessDayWindow(shopId);
    return window == null ? null : window.$2;
  }

  int _configVersion(int? shopId) {
    if (shopId == null) return 0;
    return _database.readLanConfigVersion(shopId);
  }

  bool _canReadQueue(CashierKdsDevice device, String queue) {
    final required = switch (queue) {
      'pending_prep' => 'prep',
      'pending_cook' => 'cook',
      'ready_serve' => 'serve',
      'done' => 'serve',
      _ => null,
    };
    return required != null && device.workflows.contains(required);
  }

  Set<String> _visibleQueuesForPatch(Map<Object?, Object?> patch) {
    int read(String key) {
      final value = patch[key];
      return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    }

    final queues = <String>{};
    final active = read('line_quantity') - read('refunded_quantity');
    final prep = read('prep_remaining');
    final cook = read('cook_remaining');
    final ready = read('ready_remaining');
    if (prep > 0) queues.add('pending_prep');
    if (cook - prep > 0) queues.add('pending_cook');
    if (ready - cook > 0) queues.add('ready_serve');
    if (active - ready > 0) queues.add('done');
    for (final key in const ['workflow_queue', 'from_queue']) {
      final queue = '${patch[key] ?? ''}';
      if (_queues.contains(queue)) queues.add(queue);
    }
    return queues;
  }

  /// D026：菜品所属烤制岗索引（dish_id -> screen_tag），无岗菜品不在索引中。
  Map<int, String> _dishScreenTags(int shopId) {
    final map = <int, String>{};
    for (final item in _database.readDishCatalog(shopId: shopId)) {
      final tag = item.screenTag;
      if (tag != null && tag.isNotEmpty) map[item.dishId] = tag;
    }
    return map;
  }

  /// 设备是否可见该菜品：设备未配置可见岗（旧设备）= 三岗全选可见；
  /// 菜品无岗（未配置/数据源未带）= 保守可见（防漏单）。
  bool _canDeviceSeeDish(
    CashierKdsDevice device,
    int dishId,
    Map<int, String> catalog,
  ) {
    if (device.screenTags.isEmpty) return true;
    final tag = catalog[dishId];
    if (tag == null || tag.isEmpty) return true;
    return device.screenTags.contains(tag);
  }

  bool _canDeviceSeePatch(
    CashierKdsDevice device,
    Map<Object?, Object?> patch,
    Map<int, String> catalog,
  ) {
    if (!_canDeviceSeeDish(device, _readInt(patch['dish_id']), catalog)) {
      return false;
    }
    return _visibleQueuesForPatch(
      patch,
    ).any((queue) => _canReadQueue(device, queue));
  }

  void _authorizeWorkflow(CashierKdsDevice device, String? fromQueue) {
    if (fromQueue != null && !_canReadQueue(device, fromQueue)) {
      throw const _Unauthorized('device is not authorized for this workflow');
    }
  }

  void _authorizeCommand(CashierKdsDevice device, LocalKdsCommand command) {
    _authorizeWorkflow(device, command.target.fromQueue);
    if (command.type == LocalKdsCommandType.archiveClear) {
      if (!const {'prep', 'cook', 'serve'}.every(device.workflows.contains)) {
        throw const _Unauthorized('device cannot clear the archive');
      }
      return;
    }
    // In cloud-authority mode the edge may enforce the cloud-cached device
    // scope, but it must not use a possibly stale order projection to decide
    // whether the canonical cloud command is valid.
    if (cloudAuthorityMode) return;
    final detailIds = <int>{
      if (command.target.detailId case final id?) id,
      ...command.target.detailIds,
    };
    for (final queue in _queues) {
      final affected = _database
          .readWorkflowBoard(shopId: device.shopId, queue: queue)
          .lines
          .any(
            (line) =>
                detailIds.contains(line.detailId) ||
                (line.cloudDetailId != null &&
                    detailIds.contains(line.cloudDetailId)) ||
                (command.target.orderId != null &&
                    (line.orderId == command.target.orderId ||
                        line.cloudOrderId == command.target.orderId)),
          );
      if (affected && !_canReadQueue(device, queue)) {
        throw const _Unauthorized(
          'device is not authorized for the target workflow',
        );
      }
    }
  }

  static bool _isLegacyKdsDataPath(String path) =>
      path.startsWith('/kds/workflow') ||
      path.startsWith('/kds/order/item') ||
      path.startsWith('/kds/sync') ||
      path == '/dish/listAll' ||
      path == '/ws/kds';

  static int? _nullablePositiveInt(Object? raw) {
    if (raw == null) return null;
    final value = _readInt(raw);
    return value > 0 ? value : null;
  }

  Future<void> _upgradeWebSocket(HttpRequest request) async {
    final token = _sessionToken(request);
    if (token == null || token.trim().isEmpty) {
      throw const _Unauthorized('missing KDS device token');
    }
    _verifyTransportProof(request, token: token, body: const {});
    late CashierKdsDevice session;
    if (cloudAuthorityMode) {
      // A cached row is used only as connection metadata. Admission is still
      // decided by the cloud WebSocket handshake. For a token first seen on
      // LAN, ask the cloud /me endpoint for the metadata before relaying.
      var cloudDevice = _database.authenticateDevice(_hashSecret(token));
      if (cloudDevice == null) {
        final proxy = onProxyHttp;
        if (proxy == null) {
          throw const _ServiceUnavailable('云端设备鉴权暂不可用，请稍后重试');
        }
        late CashierKdsProxyResponse authorization;
        try {
          authorization = await _fetchAndCacheCloudSession(
            proxy: proxy,
            token: token,
            requestId: 'ws-auth-${DateTime.now().microsecondsSinceEpoch}',
          );
        } catch (_) {
          throw const _ServiceUnavailable('云端设备鉴权暂不可用，请稍后重试');
        }
        if (authorization.statusCode < HttpStatus.ok ||
            authorization.statusCode >= HttpStatus.multipleChoices) {
          await _writeProxyResponse(request.response, authorization);
          return;
        }
        cloudDevice = _cacheCloudSessionResponse(
          token: token,
          response: authorization,
        );
        if (cloudDevice == null) {
          throw const _ServiceUnavailable('云端设备鉴权响应无效，请稍后重试');
        }
      }
      session = cloudDevice;
    } else {
      session = _requireSession(request);
    }
    final requestId =
        request.headers.value('X-KDS-Proxy-Request-Id')?.trim() ??
        'ws-${session.deviceCode}-${DateTime.now().microsecondsSinceEpoch}';
    final stopwatch = Stopwatch()..start();
    if (_sockets.length >= maxConnectedDevices) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    WebSocket? upstream;
    if (cloudAuthorityMode) {
      final connector = onProxyWebSocket;
      if (connector == null) {
        throw const _ServiceUnavailable('云端实时代理暂不可用，请稍后重试');
      }
      try {
        upstream = await connector(token, request.uri.queryParameters);
        _recordProxyForward(
          shopId: session.shopId,
          deviceCode: session.deviceCode,
          requestId: requestId,
          method: 'WS',
          path: '/ws/kds/v2',
          status: KdsInteractionStatus.succeeded,
          httpStatus: HttpStatus.switchingProtocols,
          durationMs: stopwatch.elapsedMilliseconds,
          servedVia: 'lan-proxy',
          stage: KdsInteractionStage.proxyWebSocketForward,
        );
      } catch (error) {
        _recordProxyForward(
          shopId: session.shopId,
          deviceCode: session.deviceCode,
          requestId: requestId,
          method: 'WS',
          path: '/ws/kds/v2',
          status: KdsInteractionStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          errorType: 'proxy_websocket_connect_error',
          errorSummary: '$error',
          stage: KdsInteractionStage.proxyWebSocketForward,
        );
        throw const _ServiceUnavailable('云端实时代理暂不可用，请稍后重试');
      }
    }
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } catch (error) {
      if (upstream != null) {
        unawaited(
          upstream.close(
            WebSocketStatus.goingAway,
            'downstream upgrade failed',
          ),
        );
      }
      rethrow;
    }
    final stillEnabled = cloudAuthorityMode
        ? session
        : _database.authenticateDevice(_hashSecret(token));
    if (stillEnabled == null) {
      if (upstream != null) {
        unawaited(
          upstream.close(
            WebSocketStatus.policyViolation,
            'device revoked',
          ),
        );
      }
      await socket.close(WebSocketStatus.policyViolation, 'device revoked');
      return;
    }
    final previousSocket = _deviceSockets[stillEnabled.deviceCode];
    if (previousSocket != null && !identical(previousSocket, socket)) {
      final previous = _sockets[previousSocket];
      if (previous != null) {
        await _closeSocket(
          previous,
          code: WebSocketStatus.normalClosure,
          reason: 'device reconnected',
        );
      }
    }
    final connection = _KdsSocketSession(
      socket: socket,
      device: stillEnabled,
      maxPendingFrames: maxPendingFramesPerDevice,
      maxPendingBytes: maxPendingBytesPerDevice,
      writeTimeout: socketWriteTimeout,
      ackTimeout: socketAckTimeout,
      onBackpressure:
          (
            reason,
            pendingFrames,
            pendingBytes,
            unacknowledgedFrames,
            unacknowledgedBytes,
          ) {
            final occurredAtMs = DateTime.now().millisecondsSinceEpoch;
            _database.tryRecordInteraction(
              CashierKdsInteractionLogDraft(
                traceId:
                    'ws-backpressure-' +
                    stillEnabled.deviceCode +
                    '-' +
                    occurredAtMs.toString(),
                shopId: stillEnabled.shopId,
                source: KdsInteractionSide.cashier,
                target: KdsInteractionSide.kds,
                direction: KdsInteractionDirection.outbound,
                stage: KdsInteractionStage.kdsEventPush,
                action: 'ws_session_closed',
                status: KdsInteractionStatus.failed,
                deviceCode: stillEnabled.deviceCode,
                errorType: reason,
                errorSummary: 'KDS WebSocket delivery did not make progress',
                metadata: {
                  'pending_frames': pendingFrames,
                  'pending_bytes': pendingBytes,
                  'unacknowledged_frames': unacknowledgedFrames,
                  'unacknowledged_bytes': unacknowledgedBytes,
                },
                occurredAtMs: occurredAtMs,
              ),
            );
          },
      onClosed: () => _removeSocket(socket),
    );
    _sockets[socket] = connection;
    _deviceSockets[stillEnabled.deviceCode] = socket;
    if (upstream != null) {
      var lastUpstreamEventSeq = _readInt(
        request.uri.queryParameters['after_seq'],
      );
      _upstreamSockets[socket] = upstream;
      upstream.listen(
        (message) {
          if (message is! String) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.unsupportedData,
                reason: 'binary upstream frames are not supported',
              ),
            );
            return;
          }
          final size = utf8.encode(message).length;
          if (size > maxPendingBytesPerDevice) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.messageTooBig,
                reason: 'upstream frame too large',
              ),
            );
            return;
          }
          try {
            final eventSeq = _journalCloudEnvelope(
              session,
              message,
              afterEventSeq: lastUpstreamEventSeq,
            );
            if (eventSeq != null) {
              lastUpstreamEventSeq = eventSeq;
            }
          } catch (_) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.protocolError,
                reason: 'invalid cloud event envelope',
              ),
            );
            return;
          }
          if (!connection.enqueue(
            message,
            acknowledgementKey: _eventAcknowledgementKey(message),
          )) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.policyViolation,
                reason: 'downstream backpressure',
              ),
            );
          }
        },
        onDone: () => unawaited(
          _closeSocket(
            connection,
            code: WebSocketStatus.goingAway,
            reason: 'cloud upstream closed',
          ),
        ),
        onError: (_) => unawaited(
          _closeSocket(
            connection,
            code: WebSocketStatus.goingAway,
            reason: 'cloud upstream error',
          ),
        ),
        cancelOnError: true,
      );
    }
    connection.listen(
      (message) {
        if (upstream != null) {
          if (message is! String) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.unsupportedData,
                reason: 'binary client frames are not supported',
              ),
            );
            return;
          }
          if (utf8.encode(message).length > 4096) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.messageTooBig,
                reason: 'client control frame too large',
              ),
            );
            return;
          }
          if (message.trim() == 'ping') {
            upstream.add(message);
            return;
          }
          final acknowledgementKey = _clientAcknowledgementKey(message);
          if (acknowledgementKey == null) {
            unawaited(
              _closeSocket(
                connection,
                code: WebSocketStatus.protocolError,
                reason: 'unsupported client control frame',
              ),
            );
            return;
          }
          if (connection.acknowledge(acknowledgementKey)) {
            upstream.add(message);
          }
        } else if ('$message'.trim() == 'ping') {
          connection.enqueue(
            jsonEncode(
              _eventEnvelopeV2(
                eventSeq: _database.latestEventSeq,
                eventId:
                    'pong-${session.deviceCode}-${DateTime.now().millisecondsSinceEpoch}',
                type: 'pong',
                shopId: session.shopId,
                occurredAtMs: DateTime.now().millisecondsSinceEpoch,
                patches: const [],
                queueCounts: _database.readQueueCounts(
                  session.shopId,
                  startMs: _businessDayStartMs(session.shopId),
                  endMs: _businessDayEndMs(session.shopId),
                ),
              ),
            ),
          );
        }
      },
      onDone: () => _removeSocket(socket),
      onError: (_) => _removeSocket(socket),
      cancelOnError: true,
    );
  }

  int? _journalCloudEnvelope(
    CashierKdsDevice session,
    String envelope, {
    required int afterEventSeq,
  }) {
    final decoded = jsonDecode(envelope);
    if (decoded is! Map) {
      throw const FormatException('cloud event must be a JSON object');
    }
    final data = decoded.cast<String, Object?>();
    final type = '${data['type'] ?? ''}';
    final eventSeq = _readInt(data['event_seq']);
    final eventId = '${data['event_id'] ?? ''}'.trim();
    if (const {'pong', 'transport_control'}.contains(type) &&
        eventSeq <= 0 &&
        eventId.isEmpty) {
      return null;
    }
    if (_readInt(data['protocol_version']) != 2 ||
        _readInt(data['shop_id']) != session.shopId) {
      throw const FormatException('cloud event identity mismatch');
    }
    if (eventSeq <= afterEventSeq) {
      throw const FormatException('cloud event sequence is not monotonic');
    }
    _database.appendCloudEventEnvelope(
      shopId: session.shopId,
      eventSeq: eventSeq,
      eventId: eventId,
      envelopeJson: envelope,
      receivedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    return eventSeq;
  }

  static String? _eventAcknowledgementKey(String envelope) {
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map ||
          (decoded['type'] ?? '').toString() == 'pong' ||
          _readInt(decoded['protocol_version']) != 2 ||
          _readInt(decoded['event_seq']) <= 0) {
        return null;
      }
      final eventId = (decoded['event_id'] ?? '').toString().trim();
      if (eventId.isEmpty) return null;
      return _readInt(decoded['event_seq']).toString() + ':' + eventId;
    } catch (_) {
      return null;
    }
  }

  static String? _clientAcknowledgementKey(String frame) {
    try {
      final decoded = jsonDecode(frame);
      if (decoded is! Map || (decoded['type'] ?? '').toString() != 'ack') {
        return null;
      }
      return _eventAcknowledgementKey(frame);
    } catch (_) {
      return null;
    }
  }

  int _broadcast(int shopId, Map<String, Object?> event) {
    if (cloudAuthorityMode) return 0;
    var recipients = 0;
    final catalog = _dishScreenTags(shopId);
    for (final entry in _sockets.entries.toList(growable: false)) {
      final connection = entry.value;
      final device = connection.device;
      if (device.shopId != shopId) continue;
      try {
        final rawPatches = event['patches'];
        final filtered = rawPatches is List
            ? rawPatches
                  .where((value) {
                    if (value is! Map) return false;
                    return _canDeviceSeePatch(device, value, catalog);
                  })
                  .toList(growable: false)
            : null;
        if (rawPatches is List && rawPatches.isNotEmpty && filtered!.isEmpty) {
          continue;
        }
        final visibleOrderIds = filtered == null
            ? const <int>{}
            : filtered
                  .whereType<Map>()
                  .map((patch) => _readInt(patch['order_id']))
                  .where((id) => id > 0)
                  .toSet();
        final rawDetails = event['order_details'];
        final filteredDetails = rawDetails is List && rawPatches is List
            ? rawDetails
                  .where(
                    (detail) =>
                        detail is Map &&
                        visibleOrderIds.contains(_readInt(detail['order_id'])),
                  )
                  .toList(growable: false)
            : rawDetails;
        if (connection.enqueue(
          jsonEncode({
            ...event,
            if (filtered != null) 'patches': filtered,
            if (filteredDetails != null) 'order_details': filteredDetails,
          }),
        )) {
          recipients++;
        }
      } catch (_) {
        unawaited(_closeSocket(connection));
      }
    }
    return recipients;
  }

  void _removeSocket(WebSocket socket) {
    final session = _sockets.remove(socket);
    final upstream = _upstreamSockets.remove(socket);
    if (upstream != null) {
      unawaited(
        upstream.close(WebSocketStatus.normalClosure, 'downstream closed'),
      );
    }
    if (session != null &&
        identical(_deviceSockets[session.device.deviceCode], socket)) {
      _deviceSockets.remove(session.device.deviceCode);
    }
  }

  Future<void> _closeSocket(
    _KdsSocketSession session, {
    int? code,
    String? reason,
  }) async {
    _removeSocket(session.socket);
    await session.close(code: code, reason: reason);
  }

  CashierKdsDevice _requireSession(
    HttpRequest request, {
    bool heartbeat = false,
  }) {
    final token = _sessionToken(request);
    if (token == null || token.trim().isEmpty) {
      throw const _Unauthorized('missing KDS device token');
    }
    final device = _database.authenticateDevice(
      _hashSecret(token),
      heartbeatAtMs: heartbeat ? DateTime.now().millisecondsSinceEpoch : null,
    );
    if (device == null) {
      throw const _Unauthorized('invalid or disabled KDS device token');
    }
    return device;
  }

  String? _sessionToken(HttpRequest request) =>
      request.headers.value('X-Kds-Device-Token') ??
      request.uri.queryParameters['token'];

  void _verifyTransportProof(
    HttpRequest request, {
    required String token,
    required Map<String, Object?> body,
  }) {
    if (!_requiresTransportProof) return;
    final valid = _transportProofVerifier.verify(
      token: token,
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      body: body,
      timestamp: request.headers.value(kKdsLanTimestampHeader),
      nonce: request.headers.value(kKdsLanNonceHeader),
      bodySha256: request.headers.value(kKdsLanBodySha256Header),
      signature: request.headers.value(kKdsLanSignatureHeader),
    );
    if (!valid) {
      throw const _Unauthorized('invalid or replayed LAN transport proof');
    }
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    const maxBodyBytes = 64 * 1024;
    final declaredLength = request.contentLength;
    if (declaredLength > maxBodyBytes) {
      throw const CashierKdsValidation('request body is too large');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) {
        throw const CashierKdsValidation('request body is too large');
      }
    }
    final text = utf8.decode(bytes);
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const CashierKdsValidation('request body must be a JSON object');
    }
    return decoded.cast<String, Object?>();
  }

  bool _parseConfigBoolean(Object value, {required String field}) {
    if (value is bool) return value;
    if (value is num && (value == 0 || value == 1)) return value == 1;
    final normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    throw CashierKdsValidation('$field must be true, false, 1, or 0');
  }

  void _writeJson(
    HttpResponse response,
    Map<String, Object?> data, {
    int statusCode = HttpStatus.ok,
  }) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(data));
    unawaited(response.close());
  }

  static int _readInt(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  static int? _readIntNullable(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final text = '$value'.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  String _randomSecret() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _hashSecret(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  void _checkLoginRateLimit(String address) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - const Duration(minutes: 15).inMilliseconds;
    final recent = (_loginAttempts[address] ?? const <int>[])
        .where((timestamp) => timestamp >= cutoff)
        .toList(growable: true);
    if (recent.length >= 10) {
      throw const _RateLimited('too many pairing attempts');
    }
    recent.add(nowMs);
    _loginAttempts[address] = recent;
  }

  int pruneStaleLoginAttempts({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(minutes: 15).inMilliseconds;
    var removed = 0;
    _loginAttempts.removeWhere((_, attempts) {
      attempts.removeWhere((timestamp) => timestamp < cutoff);
      if (attempts.isEmpty) {
        removed++;
        return true;
      }
      return false;
    });
    return removed;
  }
}

class _Unauthorized implements Exception {
  const _Unauthorized(this.message);

  final String message;
}

class _Forbidden implements Exception {
  const _Forbidden(this.message);

  final String message;
}

class _RateLimited implements Exception {
  const _RateLimited(this.message);

  final String message;
}

class _ServiceUnavailable implements Exception {
  const _ServiceUnavailable(this.message);

  final String message;
}

class _KdsSocketSession {
  _KdsSocketSession({
    required this.socket,
    required this.device,
    required this.maxPendingFrames,
    required this.maxPendingBytes,
    required this.writeTimeout,
    required this.ackTimeout,
    required this.onBackpressure,
    required this.onClosed,
  });

  final WebSocket socket;
  final CashierKdsDevice device;
  final int maxPendingFrames;
  final int maxPendingBytes;
  final Duration writeTimeout;
  final Duration ackTimeout;
  final void Function(String reason, int, int, int, int) onBackpressure;
  final void Function() onClosed;
  final Queue<String> _pending = Queue<String>();
  final Map<String, _PendingSocketAcknowledgement> _acknowledgements = {};
  StreamSubscription<dynamic>? _subscription;
  var _pendingBytes = 0;
  var _writing = false;
  var _closed = false;

  void listen(
    void Function(dynamic message) onData, {
    required void Function() onDone,
    required void Function(Object error) onError,
    required bool cancelOnError,
  }) {
    _subscription = socket.listen(
      onData,
      onDone: onDone,
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }

  bool enqueue(String frame, {String? acknowledgementKey}) {
    if (_closed) return false;
    final frameBytes = utf8.encode(frame).length;
    if (acknowledgementKey != null &&
        (_acknowledgements.length >= maxPendingFrames ||
            _acknowledgements.values.fold<int>(
                      0,
                      (total, pending) => total + pending.bytes,
                    ) +
                    frameBytes >
                maxPendingBytes)) {
      _fail('ack window overflow');
      return false;
    }
    if (_pending.length >= maxPendingFrames ||
        _pendingBytes + frameBytes > maxPendingBytes) {
      _fail('slow consumer');
      return false;
    }
    _pending.addLast(frame);
    _pendingBytes += frameBytes;
    if (acknowledgementKey != null &&
        !_acknowledgements.containsKey(acknowledgementKey)) {
      final pending = _PendingSocketAcknowledgement(frameBytes);
      pending.timeout = Timer(ackTimeout, () => _fail('ack timeout'));
      _acknowledgements[acknowledgementKey] = pending;
    }
    if (!_writing) unawaited(_drain());
    return true;
  }

  bool acknowledge(String acknowledgementKey) {
    final pending = _acknowledgements.remove(acknowledgementKey);
    if (pending == null) return false;
    pending.timeout?.cancel();
    return true;
  }

  Future<void>? _currentWrite;

  Future<void> _drain() async {
    if (_writing || _closed) return;
    _writing = true;
    try {
      while (!_closed && _pending.isNotEmpty) {
        final frame = _pending.first;
        final writeFuture = socket
            .addStream(Stream<dynamic>.value(frame))
            .timeout(writeTimeout);
        _currentWrite = writeFuture;
        await writeFuture;
        _pending.removeFirst();
        _pendingBytes -= utf8.encode(frame).length;
      }
    } catch (_) {
      _recordBackpressure('socket write failed');
      await close(
        code: WebSocketStatus.policyViolation,
        reason: 'socket write failed',
      );
    } finally {
      _currentWrite = null;
      _writing = false;
    }
  }

  Future<void> close({int? code, String? reason}) async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    _pendingBytes = 0;
    for (final acknowledgement in _acknowledgements.values) {
      acknowledgement.timeout?.cancel();
    }
    _acknowledgements.clear();
    onClosed();
    await _subscription?.cancel();
    if (_writing && _currentWrite != null) {
      try {
        await _currentWrite;
      } catch (_) {}
    }
    try {
      await socket.close(code, reason);
    } catch (_) {}
  }

  void _fail(String reason) {
    if (_closed) return;
    _recordBackpressure(reason);
    unawaited(close(code: WebSocketStatus.policyViolation, reason: reason));
  }

  void _recordBackpressure(String reason) {
    onBackpressure(
      reason,
      _pending.length,
      _pendingBytes,
      _acknowledgements.length,
      _acknowledgements.values.fold<int>(
        0,
        (total, pending) => total + pending.bytes,
      ),
    );
  }
}

class _PendingSocketAcknowledgement {
  _PendingSocketAcknowledgement(this.bytes);

  final int bytes;
  Timer? timeout;
}
