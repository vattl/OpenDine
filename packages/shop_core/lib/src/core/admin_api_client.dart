import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_debug_log.dart';
import 'api_contract.dart';
import 'http_transport.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final int? code;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class AdminApiClient {
  AdminApiClient({
    required this.baseUrl,
    required this.transport,
    this.token,
    this.shopId,
    this.requestTimeout = const Duration(seconds: 12),
    this.onUnauthorized,
    ApiDebugLogStore? debugLog,
  }) : debugLog = debugLog ?? ApiDebugLogStore.instance;

  final String baseUrl;
  final HttpTransport transport;
  final String? token;
  final int? shopId;
  final Duration requestTimeout;
  final ApiDebugLogStore debugLog;

  /// 收到 401（登录过期/未授权）时的回调，应用层用于清除登录态并跳转登录页。
  final void Function()? onUnauthorized;

  AdminApiClient copyWith({
    String? baseUrl,
    HttpTransport? transport,
    Object? token = _sentinel,
    Object? shopId = _sentinel,
    Duration? requestTimeout,
  }) {
    return AdminApiClient(
      baseUrl: baseUrl ?? this.baseUrl,
      transport: transport ?? this.transport,
      token: identical(token, _sentinel) ? this.token : token as String?,
      shopId: identical(shopId, _sentinel) ? this.shopId : shopId as int?,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      debugLog: debugLog,
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
    Map<String, Object?> body = const {},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) {
    return request(endpoint, body: body, query: query, headers: headers);
  }

  Future<Object?> request(
    AdminEndpoint endpoint, {
    Map<String, Object?> body = const {},
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestId = debugLog.nextRequestId();
    final uri = _uri(endpoint.path, compactBody(query));
    final payload = endpoint.method == 'GET'
        ? null
        : jsonEncode(_requestBody(endpoint, body));
    final requestHeaders = {
      ...headers,
      ..._headers(endpoint, hasBody: payload != null),
    };
    HttpResponseData? response;
    Object? failure;
    try {
      if (_requiresShopContext(endpoint) && shopId == null) {
        throw const ApiException('缺少当前门店上下文，请重新选择门店后重试');
      }
      response = await transport
          .send(
            method: endpoint.method,
            uri: uri,
            headers: requestHeaders,
            body: payload,
          )
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          onUnauthorized?.call();
        }
        throw _httpError(response);
      }
      return unwrapResponse(response.body);
    } on TimeoutException {
      final exception = ApiException('请求超时，请检查网络后重试（${endpoint.path}）');
      failure = exception;
      throw exception;
    } catch (exception) {
      failure = exception;
      // 业务层 401（HTTP 200 + body code=401）有两类语义：
      // ① 登录过期（「未登录或登录已过期」「用户登录已过期，请重新登录」）→ 自动登出；
      // ② 现场授权失败（「员工账号或密码错误」「请输入授权员工账号和密码」、
      //    「未找到门店上下文」等）→ 仅业务失败，绝不登出。
      // 仅当消息含「登录」时才视为凭据过期。
      if (exception is ApiException &&
          exception.code == 401 &&
          exception.statusCode != 401 &&
          exception.message.contains('登录')) {
        onUnauthorized?.call();
      }
      rethrow;
    } finally {
      stopwatch.stop();
      // release 包跳过请求日志采集（sanitizeBody 的 JSON 美化在主线程，轮询场景下是无谓开销）。
      if (!kReleaseMode) {
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

ApiException _httpError(HttpResponseData response) {
  final body = response.body.trim();
  if (body.isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['msg'] ?? decoded['message'] ?? decoded['error'];
        final rawCode = decoded['code'];
        if (message != null && '$message'.trim().isNotEmpty) {
          return ApiException(
            '$message'.trim(),
            statusCode: response.statusCode,
            code: rawCode is num
                ? rawCode.toInt()
                : int.tryParse('${rawCode ?? ''}'),
          );
        }
      }
    } on FormatException {
      // 非 JSON 错误体在下方按纯文本处理。
    }
  }
  return ApiException(
    body.isEmpty ? '请求失败，请稍后重试' : body,
    statusCode: response.statusCode,
  );
}

Object? unwrapResponse(String body) {
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
    throw ApiException(
      '${decoded['msg'] ?? decoded['message'] ?? nested['msg'] ?? nested['message'] ?? '接口请求失败'}',
      code: code is num ? code.toInt() : int.tryParse('$code'),
    );
  }
  if (decoded.containsKey('data')) return data;
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
