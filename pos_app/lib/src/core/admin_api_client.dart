import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'api_debug_log.dart';
import 'api_contract.dart';
import 'crash_log.dart';
import 'http_transport.dart';
import 'terminal_device_service.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfter,
    this.data,
    this.traceId,
    this.endpointPath,
    String? rateLimitScope,
    this.outcome,
    this.reasonCode,
    this.approval,
  }) : _rateLimitScope = rateLimitScope;

  final String message;
  final int? statusCode;
  final int? code;
  final Duration? retryAfter;
  final Object? data;
  final String? traceId;
  final String? endpointPath;
  final String? _rateLimitScope;
  final String? outcome;
  final String? reasonCode;
  final Map<String, Object?>? approval;

  String? get rateLimitScope {
    if (_rateLimitScope != null && _rateLimitScope.isNotEmpty) {
      return _rateLimitScope;
    }
    if (data is Map) {
      final map = data as Map;
      return (map['rateLimitScope'] ?? map['rate_limit_scope'])?.toString();
    }
    return null;
  }

  /// 限流错误：HTTP 429 或错误码 ACCESS_APPROVAL_RATE_LIMITED。
  bool get isRateLimited =>
      statusCode == 429 ||
      code == 429 ||
      message.contains('ACCESS_APPROVAL_RATE_LIMITED');

  /// 建议重试间隔（秒）。
  int? get retryAfterSeconds {
    if (retryAfter != null) return retryAfter!.inSeconds;
    if (data is Map) {
      final map = data as Map;
      final val = map['retryAfterSeconds'] ?? map['retry_after_seconds'];
      if (val is num) return val.toInt();
      if (val != null) return int.tryParse('$val');
    }
    return null;
  }

  /// 后端策略超限：需要店长现场授权后才能执行（40320 / APPROVAL_REQUIRED）。
  bool get isApprovalRequired =>
      code == 40320 || message.contains('APPROVAL_REQUIRED');

  /// 授权令牌无效、已过期或已被使用（40321 / ACCESS_APPROVAL_INVALID）。
  bool get isApprovalInvalid =>
      code == 40321 ||
      message.contains('ACCESS_APPROVAL_INVALID') ||
      message.contains('授权令牌无效');

  /// 敏感操作缺少现场授权（客户端/服务端统一文案"授权员工账号和密码"）。
  bool get isSensitiveAuthMissing => message.contains('授权员工账号和密码');

  /// 权限版本已变更：JWT 中的 permissionVersion 与服务端不一致（403）。
  bool get isPermissionChanged =>
      code == 403 && message.contains('ACCESS_PERMISSION_CHANGED');

  /// 账号被停用 / 离职：会话必须终止并重新登录。
  bool get isAccountDisabled =>
      message.contains('ACCESS_ACCOUNT_DISABLED') ||
      message.contains('ACCESS_ACCOUNT_RESIGNED');

  /// 账号锁定（423 / ACCESS_ACCOUNT_LOCKED；登录接口返回 423 + 账号已被锁定）。
  bool get isAccountLocked =>
      statusCode == 423 ||
      message.contains('ACCESS_ACCOUNT_LOCKED') ||
      message.contains('账号已被锁定');

  /// 会话被强制下线（401 / ACCESS_SESSION_REVOKED）。
  bool get isSessionRevoked => message.contains('ACCESS_SESSION_REVOKED');

  /// 门店超出有效数据范围（4003）。
  bool get isShopOutOfScope =>
      code == 4003 || message.contains('门店不在当前管理员可操作范围内');

  /// 接口权限未配置（403 系统部署/权限映射缺失异常，禁止静默降级，须带 traceId 诊断）。
  bool get isPermissionMappingMissing =>
      (statusCode == 403 || code == 403) &&
      message.contains('接口权限未配置');

  /// 显式权限拒绝（ACCESS_EXPLICIT_DENY / ACCESS_PERMISSION_DENIED）。
  bool get isExplicitDeny =>
      message.contains('ACCESS_EXPLICIT_DENY') ||
      message.contains('ACCESS_PERMISSION_DENIED');

  /// 授权所需的精确审批权限码（如 order:operate:refund）。
  String? get approvalPermission {
    if (approval == null) return null;
    final perm = approval!['permission'] ?? approval!['requiredApprovalPermission'];
    return perm?.toString();
  }

  /// 策略判定是否需要授权（权威字段 outcome == REQUIRE_APPROVAL，向下兼容 40320 / APPROVAL_REQUIRED）
  bool get isRequireApproval =>
      outcome == 'REQUIRE_APPROVAL' ||
      (outcome == null && isApprovalRequired);

  /// 策略判定是否明确拒绝（权威字段 outcome == DENY，向下兼容 ACCESS_EXPLICIT_DENY / ACCESS_PERMISSION_DENIED）
  bool get isDeny =>
      outcome == 'DENY' ||
      (outcome == null && isExplicitDeny);

  /// 订单乐观锁版本冲突（HTTP 409 / ORDER_VERSION_CONFLICT，WI-064）。
  bool get isOrderVersionConflict {
    if (statusCode == 409 || code == 409) {
      if (message.contains('ORDER_VERSION_CONFLICT') ||
          message.contains('订单已被其他终端修改')) {
        return true;
      }
      if (data is Map) {
        final d = data as Map;
        final ec = '${d['error_code'] ?? d['errorCode'] ?? d['error'] ?? ''}';
        if (ec == 'ORDER_VERSION_CONFLICT') return true;
      }
      return true;
    }
    return message.contains('ORDER_VERSION_CONFLICT');
  }

  /// 冲突发生时服务端返回的最新订单版本（若有）。
  int? get conflictRevision {
    if (data is Map) {
      final d = data as Map;
      final rev = d['revision'] ?? (d['data'] is Map ? (d['data'] as Map)['revision'] : null);
      if (rev is num) return rev.toInt();
      if (rev != null) return int.tryParse('$rev');
    }
    return null;
  }

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// multipart/form-data 上传的一个文件字段。
typedef MultipartFilePart = ({
  List<int> bytes,
  String filename,
  String contentType,
});

class HttpRequestQueueFullException implements Exception {
  const HttpRequestQueueFullException();
}

class HttpRequestBudget {
  HttpRequestBudget({this.maxConcurrent = 8, this.maxQueued = 32})
    : assert(maxConcurrent > 0),
      assert(maxQueued >= 0);

  static final HttpRequestBudget shared = HttpRequestBudget();

  final int maxConcurrent;
  final int maxQueued;
  final Queue<_HttpRequestWaiter> _waiters = Queue<_HttpRequestWaiter>();
  int _inFlight = 0;

  /// Snapshot for diagnostics; never exposes request bodies, URLs or tokens.
  Map<String, int> get healthSnapshot => {
    'in_flight': _inFlight,
    'queued': _waiters.length,
    'max_concurrent': maxConcurrent,
    'max_queued': maxQueued,
  };

  _HttpRequestReservation reserve() {
    if (_inFlight < maxConcurrent) {
      _inFlight++;
      return _HttpRequestReservation.immediate(_HttpRequestLease(this));
    }
    if (_waiters.length >= maxQueued) {
      throw const HttpRequestQueueFullException();
    }
    final waiter = _HttpRequestWaiter();
    _waiters.addLast(waiter);
    return _HttpRequestReservation.queued(waiter.completer.future, () {
      _waiters.remove(waiter);
    });
  }

  void _release() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(_HttpRequestLease(this));
        return;
      }
    }
    _inFlight--;
  }
}

class _HttpRequestWaiter {
  final Completer<_HttpRequestLease> completer = Completer<_HttpRequestLease>();
}

class _HttpRequestReservation {
  _HttpRequestReservation.immediate(_HttpRequestLease lease)
    : future = Future<_HttpRequestLease>.value(lease),
      _cancel = null;

  _HttpRequestReservation.queued(this.future, this._cancel);

  final Future<_HttpRequestLease> future;
  final void Function()? _cancel;

  void cancel() => _cancel?.call();
}

class _HttpRequestLease {
  _HttpRequestLease(this._budget);

  final HttpRequestBudget _budget;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _budget._release();
  }
}

class AdminApiClient {
  AdminApiClient({
    required this.baseUrl,
    required this.transport,
    this.token,
    this.shopId,
    this.terminalId,
    this.requestTimeout = const Duration(seconds: 12),
    this.requestQueueTimeout = const Duration(seconds: 1),
    this.maxRequestBodyBytes = 1024 * 1024,
    this.maxMultipartBodyBytes = 10 * 1024 * 1024,
    this.maxResponseBodyBytes = 2 * 1024 * 1024,
    HttpRequestBudget? requestBudget,
    ApiDebugLogStore? debugLog,
    this.onPermissionChanged,
    this.onSessionTerminated,
  }) : requestBudget = requestBudget ?? HttpRequestBudget.shared,
       debugLog = debugLog ?? ApiDebugLogStore.instance;

  final String baseUrl;
  final HttpTransport transport;
  final String? token;
  final int? shopId;
  final String? terminalId;
  final Duration requestTimeout;
  final Duration requestQueueTimeout;
  final int maxRequestBodyBytes;
  final int maxMultipartBodyBytes;
  final int maxResponseBodyBytes;
  final HttpRequestBudget requestBudget;
  final ApiDebugLogStore debugLog;

  /// 权限版本不一致（ACCESS_PERMISSION_CHANGED）时回调：调用方应刷新权限缓存。
  final void Function()? onPermissionChanged;

  /// 会话终止（账号停用/离职/锁定/强制下线/401）时回调：调用方应退出登录。
  final void Function()? onSessionTerminated;

  AdminApiClient copyWith({
    String? baseUrl,
    HttpTransport? transport,
    Object? token = _sentinel,
    Object? shopId = _sentinel,
    Object? terminalId = _sentinel,
    Duration? requestTimeout,
    Duration? requestQueueTimeout,
    int? maxRequestBodyBytes,
    int? maxMultipartBodyBytes,
    int? maxResponseBodyBytes,
    HttpRequestBudget? requestBudget,
    Object? onPermissionChanged = _sentinel,
    Object? onSessionTerminated = _sentinel,
  }) {
    return AdminApiClient(
      baseUrl: baseUrl ?? this.baseUrl,
      transport: transport ?? this.transport,
      token: identical(token, _sentinel) ? this.token : token as String?,
      shopId: identical(shopId, _sentinel) ? this.shopId : shopId as int?,
      terminalId: identical(terminalId, _sentinel)
          ? this.terminalId
          : terminalId as String?,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      requestQueueTimeout: requestQueueTimeout ?? this.requestQueueTimeout,
      maxRequestBodyBytes: maxRequestBodyBytes ?? this.maxRequestBodyBytes,
      maxMultipartBodyBytes:
          maxMultipartBodyBytes ?? this.maxMultipartBodyBytes,
      maxResponseBodyBytes: maxResponseBodyBytes ?? this.maxResponseBodyBytes,
      requestBudget: requestBudget ?? this.requestBudget,
      debugLog: debugLog,
      onPermissionChanged: identical(onPermissionChanged, _sentinel)
          ? this.onPermissionChanged
          : onPermissionChanged as void Function()?,
      onSessionTerminated: identical(onSessionTerminated, _sentinel)
          ? this.onSessionTerminated
          : onSessionTerminated as void Function()?,
    );
  }

  Future<Object?> get(
    AdminEndpoint endpoint, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) {
    return request(endpoint, query: query, headers: headers);
  }

  Future<Object?> post(
    AdminEndpoint endpoint, {
    Object? body = const <String, Object?>{},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) {
    return request(endpoint, body: body, query: query, headers: headers);
  }

  Future<Object?> put(
    AdminEndpoint endpoint, {
    Object? body = const <String, Object?>{},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) {
    return request(endpoint, body: body, query: query, headers: headers);
  }

  Future<Object?> delete(
    AdminEndpoint endpoint, {
    Object? body = const <String, Object?>{},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) {
    return request(endpoint, body: body, query: query, headers: headers);
  }

  Future<Object?> request(
    AdminEndpoint endpoint, {
    Object? body = const <String, Object?>{},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestId = debugLog.nextRequestId();
    final uri = _uri(endpoint.path, compactBody(query));
    final payload = endpoint.method == 'GET'
        ? null
        : (body is List
            ? jsonEncode(body)
            : jsonEncode(_requestBody(
                endpoint,
                body is Map<String, Object?>
                    ? body
                    : (body is Map
                        ? body.cast<String, Object?>()
                        : const <String, Object?>{}),
              )));
    _ensureBodyWithinBudget(
      payload == null ? 0 : utf8.encode(payload).length,
      maxRequestBodyBytes,
      '请求正文',
    );
    final requestHeaders = {
      ..._headers(endpoint, hasBody: payload != null),
      ...headers,
    };
    HttpResponseData? response;
    Object? failure;
    try {
      if (_requiresShopContext(endpoint) && shopId == null) {
        throw const ApiException('缺少当前门店上下文，请重新选择门店后重试');
      }
      response = await _sendWithinBudget(
        method: endpoint.method,
        uri: uri,
        headers: requestHeaders,
        body: payload,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response, endpointPath: endpoint.path);
      }
      return unwrapResponse(
        response.body,
        endpointPath: endpoint.path,
        traceId: _extractTraceId(response),
      );
    } on TimeoutException {
      final exception = ApiException('请求超时，请检查网络后重试（${endpoint.path}）');
      failure = exception;
      CrashLog.instance.recordBreadcrumb(
        category: 'api',
        message: 'API超时: ${endpoint.method} ${endpoint.path}',
        level: 'warn',
        data: {'method': endpoint.method, 'path': endpoint.path},
      );
      throw exception;
    } catch (exception) {
      failure = exception;
      CrashLog.instance.recordBreadcrumb(
        category: 'api',
        message:
            'API失败: ${endpoint.method} ${endpoint.path} (status: ${response?.statusCode})',
        level: 'error',
        data: {
          'method': endpoint.method,
          'path': endpoint.path,
          if (response?.statusCode != null) 'status': response!.statusCode,
        },
      );
      _notifyAccessState(exception, endpoint);
      rethrow;
    } finally {
      stopwatch.stop();
      debugLog.add(
        ApiDebugLogEntry(
          id: requestId,
          startedAt: startedAt,
          method: endpoint.method,
          uri: ApiDebugLogStore.sanitizeUri(uri),
          requestHeaders: ApiDebugLogStore.sanitizeHeaders(requestHeaders),
          requestBody: ApiDebugLogStore.sanitizeBody(payload),
          statusCode: response?.statusCode,
          responseBody: ApiDebugLogStore.sanitizeBody(response?.body),
          duration: stopwatch.elapsed,
          succeeded: failure == null,
          error: ApiDebugLogStore.sanitizeBody(failure?.toString()),
        ),
      );
    }
  }

  /// 会话生命周期钩子：根据服务端语义错误码通知调用方刷新权限或退出登录。
  /// 登录接口与权限刷新接口（/admin/me/*）自身的错误不属于会话终止，跳过避免死循环；
  /// 店长现场授权接口（/cashier/access/authorize）的 401/423 是授权人凭证或锁定错误，
  /// 由授权弹窗展示，不判定当前收银会话终止。
  void _notifyAccessState(Object? exception, AdminEndpoint endpoint) {
    if (exception is! ApiException) return;
    if (exception.statusCode == 429) return;
    final path = endpoint.path;
    if (path == '/adminLogin' ||
        path == '/admin/me/permissions' ||
        path.startsWith('/admin/me/') ||
        path.startsWith('/cashier/access/') ||
        path.startsWith('/admin/access/qr/')) {
      return;
    }
    if (exception.isPermissionChanged) {
      onPermissionChanged?.call();
    } else if (exception.isAccountDisabled ||
        exception.isAccountLocked ||
        exception.isSessionRevoked ||
        exception.statusCode == 401) {
      onSessionTerminated?.call();
    }
  }

  /// Sends an API request without unwrapping the response envelope or turning
  /// non-2xx statuses into exceptions. Used by bounded transparent proxies
  /// that must preserve the upstream HTTP contract exactly.
  Future<HttpResponseData> requestRaw(
    AdminEndpoint endpoint, {
    Object? body = const <String, Object?>{},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestId = debugLog.nextRequestId();
    final uri = _uri(endpoint.path, compactBody(query));
    final payload = endpoint.method == 'GET'
        ? null
        : (body is List
            ? jsonEncode(body)
            : jsonEncode(_requestBody(
                endpoint,
                body is Map<String, Object?>
                    ? body
                    : (body is Map
                        ? body.cast<String, Object?>()
                        : const <String, Object?>{}),
              )));
    _ensureBodyWithinBudget(
      payload == null ? 0 : utf8.encode(payload).length,
      maxRequestBodyBytes,
      '请求正文',
    );
    final requestHeaders = {
      ..._headers(endpoint, hasBody: payload != null),
      ...headers,
    };
    HttpResponseData? response;
    Object? failure;
    try {
      if (_requiresShopContext(endpoint) && shopId == null) {
        throw const ApiException('缺少当前门店上下文，请重新选择门店后重试');
      }
      response = await _sendWithinBudget(
        method: endpoint.method,
        uri: uri,
        headers: requestHeaders,
        body: payload,
      );
      return response;
    } on TimeoutException {
      final exception = ApiException('请求超时，请检查网络后重试（${endpoint.path}）');
      failure = exception;
      throw exception;
    } catch (exception) {
      failure = exception;
      rethrow;
    } finally {
      stopwatch.stop();
      debugLog.add(
        ApiDebugLogEntry(
          id: requestId,
          startedAt: startedAt,
          method: endpoint.method,
          uri: ApiDebugLogStore.sanitizeUri(uri),
          requestHeaders: ApiDebugLogStore.sanitizeHeaders(requestHeaders),
          requestBody: ApiDebugLogStore.sanitizeBody(payload),
          statusCode: response?.statusCode,
          responseBody: ApiDebugLogStore.sanitizeBody(response?.body),
          duration: stopwatch.elapsed,
          succeeded:
              failure == null &&
              response != null &&
              response.statusCode >= 200 &&
              response.statusCode < 300,
          error: ApiDebugLogStore.sanitizeBody(failure?.toString()),
        ),
      );
    }
  }

  /// multipart/form-data 上传（如收款码原图、Excel 批量发券），
  /// 文件字段经 [files] 传入，普通表单字段经 [fields] 传入。
  Future<Object?> postMultipart(
    AdminEndpoint endpoint, {
    required Map<String, MultipartFilePart> files,
    Map<String, Object?> fields = const {},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestId = debugLog.nextRequestId();
    final uri = _uri(endpoint.path, compactBody(query));
    final boundary = '----laofei${DateTime.now().microsecondsSinceEpoch}';
    final bodyBytes = _multipartBody(boundary, fields, files);
    _ensureBodyWithinBudget(bodyBytes.length, maxMultipartBodyBytes, '上传文件');
    final requestHeaders = {
      ..._headers(endpoint, hasBody: true),
      ...headers,
      'Content-Type': 'multipart/form-data; boundary=$boundary',
    };
    HttpResponseData? response;
    Object? failure;
    try {
      if (_requiresShopContext(endpoint) && shopId == null) {
        throw const ApiException('缺少当前门店上下文，请重新选择门店后重试');
      }
      response = await _sendWithinBudget(
        method: endpoint.method,
        uri: uri,
        headers: requestHeaders,
        bodyBytes: bodyBytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response, endpointPath: endpoint.path);
      }
      return unwrapResponse(
        response.body,
        endpointPath: endpoint.path,
        traceId: _extractTraceId(response),
      );
    } on TimeoutException {
      final exception = ApiException('请求超时，请检查网络后重试（${endpoint.path}）');
      failure = exception;
      throw exception;
    } catch (exception) {
      failure = exception;
      rethrow;
    } finally {
      stopwatch.stop();
      debugLog.add(
        ApiDebugLogEntry(
          id: requestId,
          startedAt: startedAt,
          method: endpoint.method,
          uri: ApiDebugLogStore.sanitizeUri(uri),
          requestHeaders: ApiDebugLogStore.sanitizeHeaders(requestHeaders),
          requestBody: '<multipart ${bodyBytes.length} bytes>',
          statusCode: response?.statusCode,
          responseBody: ApiDebugLogStore.sanitizeBody(response?.body),
          duration: stopwatch.elapsed,
          succeeded: failure == null,
          error: ApiDebugLogStore.sanitizeBody(failure?.toString()),
        ),
      );
    }
  }

  List<int> _multipartBody(
    String boundary,
    Map<String, Object?> fields,
    Map<String, MultipartFilePart> files,
  ) {
    final buffer = BytesBuilder();
    void writeAscii(String text) => buffer.add(utf8.encode(text));
    fields.forEach((field, value) {
      writeAscii('--$boundary\r\n');
      writeAscii(
        'Content-Disposition: form-data; name="$field"\r\n\r\n',
      );
      writeAscii('$value\r\n');
    });
    files.forEach((field, file) {
      final filename = file.filename.replaceAll('"', '');
      writeAscii('--$boundary\r\n');
      writeAscii(
        'Content-Disposition: form-data; name="$field"; filename="$filename"\r\n',
      );
      writeAscii('Content-Type: ${file.contentType}\r\n\r\n');
      buffer.add(file.bytes);
      writeAscii('\r\n');
    });
    writeAscii('--$boundary--\r\n');
    return buffer.takeBytes();
  }

  Future<HttpResponseData> _sendWithinBudget({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    late final _HttpRequestReservation reservation;
    try {
      reservation = requestBudget.reserve();
    } on HttpRequestQueueFullException {
      throw const ApiException('请求过多，请稍后重试');
    }
    _HttpRequestLease? lease;
    final cancellation = HttpRequestCancellation();
    try {
      lease = await reservation.future.timeout(
        requestQueueTimeout,
        onTimeout: () {
          reservation.cancel();
          throw TimeoutException('request queue wait exceeded');
        },
      );
    } on HttpRequestQueueFullException {
      throw const ApiException('请求过多，请稍后重试');
    } on TimeoutException {
      throw const ApiException('请求排队超时，请稍后重试');
    }

    try {
      final responseFuture = transport is CancellableHttpTransport
          ? (transport as CancellableHttpTransport).sendCancellable(
              method: method,
              uri: uri,
              headers: headers,
              body: body,
              bodyBytes: bodyBytes,
              cancellation: cancellation,
              maxResponseBytes: maxResponseBodyBytes,
            )
          : transport.send(
              method: method,
              uri: uri,
              headers: headers,
              body: body,
              bodyBytes: bodyBytes,
            );
      return await responseFuture.timeout(
        requestTimeout,
        onTimeout: () {
          cancellation.cancel();
          throw TimeoutException('request timeout');
        },
      );
    } on HttpResponseBodyTooLargeException {
      throw ApiException(
        '响应内容超过 ${maxResponseBodyBytes ~/ 1024} KiB 上限，请缩小查询范围后重试',
      );
    } finally {
      lease.release();
    }
  }

  void _ensureBodyWithinBudget(int size, int limit, String subject) {
    if (size > limit) {
      throw ApiException('$subject超过 ${limit ~/ 1024} KiB 上限，请缩小内容后重试');
    }
  }

  bool _requiresShopContext(AdminEndpoint endpoint) {
    if (token == null || token!.isEmpty) return false;
    return endpoint.attachShopHeader &&
        !shopHeaderExcludedPaths.contains(endpoint.path);
  }

  Map<String, Object?> _requestBody(
    AdminEndpoint endpoint,
    Map<String, Object?> body,
  ) {
    if (!endpoint.preserveEmptyStrings && !endpoint.preserveEmptyCollections) {
      return compactBody(body);
    }
    return Map.fromEntries(
      body.entries.where((entry) {
        final value = entry.value;
        if (value == null) return false;
        if (value is String) {
          return endpoint.preserveEmptyStrings || value.trim().isNotEmpty;
        }
        if (value is Iterable) {
          return endpoint.preserveEmptyCollections || value.isNotEmpty;
        }
        if (value is Map) {
          return endpoint.preserveEmptyCollections || value.isNotEmpty;
        }
        return true;
      }),
    );
  }

  Map<String, String> _headers(
    AdminEndpoint endpoint, {
    required bool hasBody,
  }) {
    final headers = <String, String>{
      if (hasBody) 'Content-Type': 'application/json;charset=utf-8',
      'Accept': 'application/json',
    };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (shopId != null &&
        endpoint.attachShopHeader &&
        !shopHeaderExcludedPaths.contains(endpoint.path)) {
      headers['X-Shop-Id'] = '${shopId!}';
    }
    final effectiveTerminalId = (terminalId != null && terminalId!.trim().isNotEmpty)
        ? terminalId!.trim()
        : TerminalDeviceService.instance.currentTerminalId;
    if (effectiveTerminalId != null && effectiveTerminalId.isNotEmpty) {
      headers['X-Terminal-Id'] = effectiveTerminalId;
    }
    if (endpoint.method != 'GET') {
      headers['X-Client-Request-Id'] =
          'req-${DateTime.now().microsecondsSinceEpoch}';
    }
    return headers;
  }

  Uri _uri(String path, Map<String, Object?> query) {
    final base = baseUrl.trim();
    final raw = base.isEmpty
        ? path
        : '${base.replaceFirst(RegExp(r'/$'), '')}$path';
    final uri = Uri.parse(raw);
    if (query.isEmpty) return uri;
    final nextQuery = Map<String, String>.from(uri.queryParameters);
    for (final entry in query.entries) {
      nextQuery[entry.key] = '${entry.value}';
    }
    return uri.replace(queryParameters: nextQuery);
  }
}

String _sanitizeErrorMessage(String message, int? statusCode) {
  final trimmed = message.trim();
  final lower = trimmed.toLowerCase();
  final hasHtml =
      lower.contains('<html') ||
      lower.contains('<!doctype') ||
      lower.contains('<body') ||
      lower.contains('<head') ||
      lower.contains('<center>') ||
      trimmed.contains(RegExp(r'<[a-zA-Z\/][^>]*>'));

  if (hasHtml || trimmed.isEmpty) {
    return switch (statusCode) {
      502 => '服务器网关连接异常（502 Bad Gateway），请稍后重试',
      504 => '服务器响应超时（504 Gateway Timeout），请检查网络',
      500 => '服务器内部异常（500），请稍后重试',
      503 => '服务暂时不可用（503 Service Unavailable），请稍后重试',
      404 => '请求的服务地址不存在（404 Not Found）',
      403 => '无权限访问该资源（403 Forbidden）',
      401 => '登录已过期或未授权，请重新登录',
      _ => '服务器连接异常，请稍后重试',
    };
  }
  return trimmed;
}

String? _extractTraceId(HttpResponseData? response, [Map? decoded]) {
  if (response != null) {
    for (final key in const ['x-trace-id', 'x-request-id', 'traceparent', 'trace-id']) {
      final val = response.headers[key];
      if (val != null && val.trim().isNotEmpty) return val.trim();
    }
  }
  if (decoded != null) {
    for (final key in const ['traceId', 'trace_id', 'requestId', 'request_id']) {
      final val = decoded[key];
      if (val != null && '$val'.trim().isNotEmpty) return '$val'.trim();
    }
  }
  return null;
}

ApiException _httpError(HttpResponseData response, {String? endpointPath}) {
  final body = response.body.trim();
  String? traceId = _extractTraceId(response);
  if (body.isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        traceId ??= _extractTraceId(null, decoded);
        final message =
            decoded['msg'] ?? decoded['message'] ?? decoded['error'];
        final rawCode = decoded['code'];
        final rawData = decoded['data'];
        int? retrySeconds;
        String? rateLimitScope;
        if (rawData is Map) {
          traceId ??= _extractTraceId(null, rawData);
          final rawRetry =
              rawData['retryAfterSeconds'] ?? rawData['retry_after_seconds'];
          if (rawRetry != null) {
            retrySeconds = rawRetry is num
                ? rawRetry.toInt()
                : int.tryParse('$rawRetry');
          }
          rateLimitScope = rawData['rateLimitScope']?.toString() ??
              rawData['rate_limit_scope']?.toString();
        }
        final headerRetry = _retryAfter(response.headers['retry-after']);
        final effectiveRetry = retrySeconds != null && retrySeconds > 0
            ? Duration(seconds: retrySeconds)
            : headerRetry;
        final rawOutcome = decoded['outcome'] ??
            (rawData is Map ? rawData['outcome'] : null);
        final rawReasonCode = decoded['reasonCode'] ??
            (rawData is Map ? rawData['reasonCode'] : null);
        final rawApproval = decoded['approval'] is Map
            ? (decoded['approval'] as Map).cast<String, Object?>()
            : (rawData is Map && rawData['approval'] is Map
                ? (rawData['approval'] as Map).cast<String, Object?>()
                : null);

        if (message != null && '$message'.trim().isNotEmpty) {
          final cleanMsg = _sanitizeErrorMessage(
            '$message'.trim(),
            response.statusCode,
          );
          return ApiException(
            cleanMsg,
            statusCode: response.statusCode,
            code: rawCode is num
                ? rawCode.toInt()
                : int.tryParse('${rawCode ?? ''}'),
            retryAfter: effectiveRetry,
            data: rawData,
            traceId: traceId,
            endpointPath: endpointPath,
            rateLimitScope: rateLimitScope,
            outcome: rawOutcome?.toString(),
            reasonCode: rawReasonCode?.toString(),
            approval: rawApproval,
          );
        }
      }
    } on FormatException {
      // 非 JSON 错误体在下方按纯文本/状态码映射处理。
    }
  }
  final cleanMsg = _sanitizeErrorMessage(body, response.statusCode);
  return ApiException(
    cleanMsg,
    statusCode: response.statusCode,
    retryAfter: _retryAfter(response.headers['retry-after']),
    traceId: traceId,
    endpointPath: endpointPath,
  );
}

Duration? _retryAfter(String? value) {
  final seconds = int.tryParse(value?.trim() ?? '');
  return seconds == null || seconds <= 0
      ? null
      : Duration(seconds: seconds.clamp(1, 900));
}

Object? unwrapResponse(String body, {String? endpointPath, String? traceId}) {
  if (body.trim().isEmpty) return null;
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, Object?>) return decoded;

  final code = decoded['code'];
  final hasCode = code != null;
  final ok =
      !hasCode ||
      code == 0 ||
      code == 200 ||
      '$code' == '0' ||
      '$code' == '200';
  final data = decoded['data'];
  if (!ok ||
      _hasExplicitFailure(decoded, includeStatus: hasCode) ||
      _hasExplicitFailure(data, includeStatus: false)) {
    final nested = data is Map ? data : const {};
    final rawMsg =
        '${decoded['msg'] ?? decoded['message'] ?? nested['msg'] ?? nested['message'] ?? '接口请求失败'}';
    final cleanMsg = _sanitizeErrorMessage(rawMsg, null);
    final resolvedTraceId = traceId ??
        _extractTraceId(null, decoded) ??
        _extractTraceId(null, nested);
    final rawOutcome = decoded['outcome'] ?? nested['outcome'];
    final rawReasonCode = decoded['reasonCode'] ?? nested['reasonCode'];
    final rawApproval = decoded['approval'] is Map
        ? (decoded['approval'] as Map).cast<String, Object?>()
        : (nested['approval'] is Map
            ? (nested['approval'] as Map).cast<String, Object?>()
            : null);
    throw ApiException(
      cleanMsg,
      code: code is num ? code.toInt() : int.tryParse('$code'),
      data: data,
      traceId: resolvedTraceId,
      endpointPath: endpointPath,
      outcome: rawOutcome?.toString(),
      reasonCode: rawReasonCode?.toString(),
      approval: rawApproval,
    );
  }
  if (decoded.containsKey('data')) {
    if (data is Map && decoded.containsKey('revision') && !data.containsKey('revision')) {
      return {...data, 'revision': decoded['revision']};
    }
    return data;
  }
  return decoded;
}

bool _hasExplicitFailure(Object? value, {bool includeStatus = true}) {
  if (value is! Map) return false;
  for (final key in const ['success', 'ok']) {
    if (!value.containsKey(key)) continue;
    final flag = value[key];
    if (flag == false || flag == 0 || '$flag'.trim().toLowerCase() == 'false') {
      return true;
    }
  }
  if (!includeStatus) return false;
  final status = '${value['status'] ?? ''}'.trim().toLowerCase();
  return status == 'error' || status == 'failed' || status == 'failure';
}

List<Map<String, Object?>> objectList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }
  if (value is Map) {
    for (final key in const [
      'records',
      'rows',
      'list',
      'items',
      'data',
      'orderList',
      'order_list',
      'orderDetailList',
      'order_detail_list',
      'detailList',
      'detail_list',
      'dishList',
      'dish_list',
      'tableList',
      'table_list',
      'couponList',
      'coupon_list',
      'materialList',
      'material_list',
      'deliveryList',
      'delivery_list',
      'stationList',
      'station_list',
      'deviceList',
      'device_list',
      'roleList',
      'role_list',
      'permissionList',
      'permission_list',
      'apiPermissionList',
      'api_permission_list',
      'announcementList',
      'announcement_list',
      'rechargeList',
      'recharge_list',
      'logs',
      'logList',
      'log_list',
      'merchants',
      'owned',
      'plans',
      'bomList',
      'bom_list',
      'user',
      'users',
    ]) {
      final nested = value[key];
      if (nested is List) return objectList(nested);
    }
  }
  return const [];
}

int totalFrom(Object? value, int fallback) {
  if (value is Map) {
    for (final key in const ['total', 'count', 'totalCount']) {
      final raw = value[key];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      final parsed = int.tryParse('$raw');
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

const Object _sentinel = Object();
