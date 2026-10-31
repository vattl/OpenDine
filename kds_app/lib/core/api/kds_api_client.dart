import 'package:dio/dio.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/api_response.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/security/kds_lan_transport_proof.dart';
import 'package:uuid/uuid.dart';

typedef UnauthorizedHandler = void Function();

class KdsApiClient {
  KdsApiClient({
    required this.getBaseUrl,
    required this.getToken,
    this.getDeviceCode,
    this.onUnauthorized,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
            validateStatus: (status) => status != null && status < 600,
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['sw'] = Stopwatch()..start();
          final base = getBaseUrl();
          if (base.isNotEmpty) {
            options.baseUrl = base;
          }
          final token = getToken();
          if (token != null &&
              token.isNotEmpty &&
              options.extra['skipAuth'] != true) {
            options.headers['X-Kds-Device-Token'] = token;
          }

          final requestId = (options.headers['X-Request-Id'] as String?)?.trim() ??
              (options.headers['X-KDS-Proxy-Request-Id'] as String?)?.trim() ??
              const Uuid().v4();
          options.headers['X-Request-Id'] = requestId;
          options.headers['X-KDS-Proxy-Request-Id'] = requestId;
          options.extra['requestId'] = requestId;

          String? commandId;
          final rawData = options.data;
          if (rawData is Map && rawData['command_id'] != null) {
            commandId = '${rawData['command_id']}'.trim();
            options.headers['X-KDS-Command-Id'] = commandId;
            options.extra['commandId'] = commandId;
          }

          final deviceCode = getDeviceCode?.call();
          if (deviceCode != null && deviceCode.isNotEmpty) {
            options.headers['X-KDS-Device-Code'] = deviceCode;
            options.extra['deviceCode'] = deviceCode;
          }

          if (token != null &&
              token.isNotEmpty &&
              isSecurePrivateLanApiBase(base) &&
              options.extra['skipAuth'] != true) {
            final uri = options.uri;
            final rawBody = options.data;
            final body = rawBody is Map
                ? rawBody.map<String, Object?>(
                    (key, value) => MapEntry('$key', value),
                  )
                : const <String, Object?>{};
            options.headers.addAll(
              createKdsLanTransportProof(
                token: token,
                method: options.method,
                path: uri.path,
                query: uri.queryParameters,
                body: body,
              ),
            );
          }
          final channel = isPrivateLanApiBase(base)
              ? KdsActiveChannel.lan
              : KdsActiveChannel.cloud;
          final isFetch = options.method == 'GET' ||
              options.path.contains('orders') ||
              options.path.contains('changes') ||
              options.path.contains('bootstrap');
          if (!isFetch) {
            KdsTraceHub.recordSend(
              channel: channel,
              action: '${options.method} ${options.path}',
              summary: '发送请求: ${options.path}',
              endpoint: options.path,
              requestPayload: options.data,
              requestId: requestId,
              commandId: commandId,
              deviceCode: deviceCode,
              metadata: {
                'baseUrl': base,
                'host': Uri.tryParse(base)?.host,
              },
            );
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final sw = response.requestOptions.extra['sw'] as Stopwatch?;
          final durationMs = sw?.elapsedMilliseconds;
          final status = response.statusCode ?? 0;
          final base = response.requestOptions.baseUrl;
          final channel = isPrivateLanApiBase(base)
              ? KdsActiveChannel.lan
              : KdsActiveChannel.cloud;
          final isFetch = response.requestOptions.method == 'GET' ||
              response.requestOptions.path.contains('orders') ||
              response.requestOptions.path.contains('changes') ||
              response.requestOptions.path.contains('bootstrap');

          final requestId = response.requestOptions.extra['requestId'] as String?;
          final commandId = response.requestOptions.extra['commandId'] as String?;
          final deviceCode = response.requestOptions.extra['deviceCode'] as String?;

          if (status >= 400) {
            final msg = formatHttpError(
              statusCode: status,
              path: response.requestOptions.path,
              data: response.data,
            );
            KdsFileLogger.warn(
                'HTTP $status ${response.requestOptions.path}: $msg');
            KdsTraceHub.recordResponse(
              channel: channel,
              action:
                  '${response.requestOptions.method} ${response.requestOptions.path}',
              summary: 'HTTP $status 异常: $msg',
              endpoint: response.requestOptions.path,
              durationMs: durationMs,
              statusCode: status,
              isSuccess: false,
              responsePayload: response.data,
              requestId: requestId,
              commandId: commandId,
              deviceCode: deviceCode,
              metadata: {
                'baseUrl': base,
                'host': Uri.tryParse(base)?.host,
              },
            );
            if (status == 401 ||
                (status == 403 &&
                    (msg.contains('未绑定') ||
                        msg.contains('已禁用') ||
                        msg.contains('无效') ||
                        msg.contains('token')))) {
              onUnauthorized?.call();
            }
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                message: msg,
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          try {
            final data = normalizeApiResponse(
              response.data,
              path: response.requestOptions.path,
            );
            _attachTransportMetadata(data, response.headers);
            response.data = data;
            final code = data['code'];
            final ok = code == 0 || code == 200;
            if (isFetch) {
              KdsTraceHub.recordFetch(
                channel: channel,
                action:
                    '${response.requestOptions.method} ${response.requestOptions.path}',
                summary:
                    '获取数据成功: ${response.requestOptions.path} (${durationMs ?? 0}ms)',
                endpoint: response.requestOptions.path,
                durationMs: durationMs,
                statusCode: status,
                isSuccess: ok,
                responsePayload: response.data,
                requestId: requestId,
                commandId: commandId,
                deviceCode: deviceCode,
                metadata: {
                  'baseUrl': base,
                  'host': Uri.tryParse(base)?.host,
                },
              );
            } else {
              KdsTraceHub.recordResponse(
                channel: channel,
                action:
                    '${response.requestOptions.method} ${response.requestOptions.path}',
                summary:
                    '响应成功: ${response.requestOptions.path} (${durationMs ?? 0}ms)',
                endpoint: response.requestOptions.path,
                durationMs: durationMs,
                statusCode: status,
                isSuccess: ok,
                responsePayload: response.data,
                requestId: requestId,
                commandId: commandId,
                deviceCode: deviceCode,
                metadata: {
                  'baseUrl': base,
                  'host': Uri.tryParse(base)?.host,
                },
              );
            }
            if (!ok) {
              final msg = data['msg']?.toString() ?? '请求失败';
              if (code == 401 || msg.contains('设备未绑定')) {
                onUnauthorized?.call();
              }
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  message: msg,
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
          } on ApiException catch (e) {
            KdsTraceHub.recordResponse(
              channel: channel,
              action:
                  '${response.requestOptions.method} ${response.requestOptions.path}',
              summary: '解析异常: ${e.message}',
              endpoint: response.requestOptions.path,
              durationMs: durationMs,
              statusCode: status,
              isSuccess: false,
              responsePayload: response.data,
              requestId: requestId,
              commandId: commandId,
              deviceCode: deviceCode,
              metadata: {
                'baseUrl': base,
                'host': Uri.tryParse(base)?.host,
              },
            );
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                message: e.message,
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final sw = error.requestOptions.extra['sw'] as Stopwatch?;
          final durationMs = sw?.elapsedMilliseconds;
          final base = error.requestOptions.baseUrl;
          final channel = isPrivateLanApiBase(base)
              ? KdsActiveChannel.lan
              : KdsActiveChannel.cloud;
          final requestId = error.requestOptions.extra['requestId'] as String?;
          final commandId = error.requestOptions.extra['commandId'] as String?;
          final deviceCode = error.requestOptions.extra['deviceCode'] as String?;
          KdsTraceHub.recordResponse(
            channel: channel,
            action:
                '${error.requestOptions.method} ${error.requestOptions.path}',
            summary: '网络错误: ${error.message}',
            endpoint: error.requestOptions.path,
            durationMs: durationMs,
            statusCode: error.response?.statusCode,
            isSuccess: false,
            responsePayload: error.response?.data,
            requestId: requestId,
            commandId: commandId,
            deviceCode: deviceCode,
            metadata: {
              'baseUrl': base,
              'host': Uri.tryParse(base)?.host,
            },
          );
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final String Function() getBaseUrl;
  final String? Function() getToken;
  final String? Function()? getDeviceCode;
  final UnauthorizedHandler? onUnauthorized;

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuth = false,
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(
          extra: {'skipAuth': skipAuth},
          headers: headers,
        ),
      );
      return normalizeApiResponse(res.data, path: path);
    } on DioException catch (e) {
      throw ApiException(
        _dioErrorMessage(e, path: path),
        code: readApiErrorCode(e.response?.data),
        statusCode: e.response?.statusCode,
        isNetworkError: _isNetworkError(e),
      );
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuth = false,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(extra: {'skipAuth': skipAuth}),
      );
      return normalizeApiResponse(res.data, path: path);
    } on DioException catch (e) {
      throw ApiException(
        _dioErrorMessage(e, path: path),
        code: readApiErrorCode(e.response?.data),
        statusCode: e.response?.statusCode,
        isNetworkError: _isNetworkError(e),
      );
    }
  }

  static bool _isNetworkError(DioException e) {
    if (e.response != null) return false;
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown;
  }

  static void _attachTransportMetadata(
    Map<String, dynamic> response,
    Headers headers,
  ) {
    final cacheState = headers.value('x-kds-cache')?.trim();
    final servedVia = headers.value('x-kds-served-via')?.trim();
    if ((cacheState == null || cacheState.isEmpty) &&
        (servedVia == null || servedVia.isEmpty)) {
      return;
    }
    final metadata = <String, dynamic>{
      if (cacheState != null && cacheState.isNotEmpty)
        'cache_state': cacheState.toUpperCase(),
      if (servedVia != null && servedVia.isNotEmpty) 'served_via': servedVia,
      if (int.tryParse(headers.value('age') ?? '') case final value?)
        'age_seconds': value,
      if (int.tryParse(headers.value('x-kds-cached-at') ?? '')
          case final value?)
        'cached_at_ms': value,
      if (int.tryParse(headers.value('x-kds-authority-cursor') ?? '')
          case final value?)
        'authority_cursor': value,
    };
    final rawData = response['data'];
    if (rawData is Map) {
      final data = Map<String, dynamic>.from(rawData);
      data['_transport_metadata'] = metadata;
      response['data'] = data;
    } else {
      response['_transport_metadata'] = metadata;
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool skipAuth = false,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
        options: Options(extra: {'skipAuth': skipAuth}),
      );
      return normalizeApiResponse(res.data, path: path);
    } on DioException catch (e) {
      throw ApiException(
        _dioErrorMessage(e, path: path),
        code: readApiErrorCode(e.response?.data),
        statusCode: e.response?.statusCode,
        isNetworkError: _isNetworkError(e),
      );
    }
  }

  static String _dioErrorMessage(DioException e, {String? path}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final formatted = formatHttpError(
      statusCode: status,
      path: path ?? e.requestOptions.path,
      data: data,
      fallback: e.message,
    );
    if (formatted.isNotEmpty) return formatted;

    if (data is String) {
      final text = data.trim();
      if (text.toLowerCase().contains('<html') || text.contains('<!doctype')) {
        return '服务器返回了网页而非 JSON（${path ?? '/kds/*'}）。'
            '请确认 nginx 已将 /kds 接口转发到后端。';
      }
    }

    if (_isNetworkError(e)) return '网络连接失败，请检查网络与 API 基址';
    return '请求失败';
  }
}
