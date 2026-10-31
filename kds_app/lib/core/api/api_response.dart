import 'dart:convert';

import 'package:kds_app/core/api/api_exception.dart';

/// 将 Dio 原始响应规范化为 Map，识别 HTML / 非 JSON 并抛出可读错误。
Map<String, dynamic> normalizeApiResponse(dynamic raw, {String? path}) {
  if (raw == null) return {};

  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return {};
    if (_looksLikeHtml(text)) {
      throw ApiException(
        _htmlHint(path),
        statusCode: 200,
      );
    }
    try {
      final decoded = jsonDecode(text);
      return normalizeApiResponse(decoded, path: path);
    } catch (_) {
      throw ApiException(
        '服务器返回非 JSON 数据${path != null ? '（$path）' : ''}',
        statusCode: 200,
      );
    }
  }

  if (raw is! Map) {
    throw ApiException('服务器响应格式异常：${raw.runtimeType}');
  }

  return Map<String, dynamic>.from(raw);
}

bool _looksLikeHtml(String text) {
  final lower = text.toLowerCase();
  return lower.startsWith('<!doctype') ||
      lower.startsWith('<html') ||
      lower.contains('<head>') ||
      lower.contains('<body');
}

String _htmlHint(String? path) {
  final p = path ?? '/kds/*';
  return '服务器返回了网页而非 JSON（$p）。'
      '请确认 API 基址正确，且 nginx 已将 /kds 接口转发到后端（勿走前端 SPA 路由）。';
}

/// 安全读取嵌套 Map（支持 JSON 字符串）
Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

/// 从响应中读取 device（兼容顶层或 data.device）
Map<String, dynamic> readDeviceJson(Map<String, dynamic> body) {
  final direct = asJsonMap(body['device']);
  if (direct != null) return direct;

  final nested = asJsonMap(body['data']);
  if (nested != null) {
    final fromData = asJsonMap(nested['device']);
    if (fromData != null) return fromData;
    if (nested.containsKey('device_token') ||
        nested.containsKey('device_code')) {
      return nested;
    }
  }

  if (body['device'] != null) {
    throw ApiException('登录响应 device 字段格式异常（${body['device'].runtimeType}）');
  }
  return {};
}

/// 从 Dio 错误响应中安全读取业务 code
int? readApiErrorCode(dynamic data) {
  final map = asJsonMap(data);
  if (map == null) return null;
  return (map['code'] as num?)?.toInt();
}

/// 从错误响应体读取服务端 msg（兼容 data.msg / message / error）
String? readServerErrorMessage(dynamic data) {
  final map = asJsonMap(data);
  if (map == null) return null;
  for (final key in const ['msg', 'message', 'error', 'detail']) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final nested = asJsonMap(map['data']);
  if (nested != null) {
    for (final key in const ['msg', 'message', 'error']) {
      final value = nested[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

/// 将 HTTP 状态码转为用户可读中文（避免 Dio validateStatus 英文堆栈）
String formatHttpError({
  required int? statusCode,
  String? path,
  dynamic data,
  String? fallback,
}) {
  final serverMsg = readServerErrorMessage(data);
  if (serverMsg != null && !_isDioBoilerplate(serverMsg)) {
    return serverMsg;
  }

  final endpoint = path ?? '/kds/*';
  return switch (statusCode) {
    400 => '请求参数错误(400)：$endpoint',
    401 => '登录已失效，请重新登录(401)',
    403 => '当前设备无权访问该接口(403)',
    404 => '接口不存在(404)：$endpoint',
    405 => '接口方法不允许(405)：$endpoint',
    408 => '请求超时(408)，请稍后重试',
    422 => serverMsg ?? '请求无法处理(422)',
    500 => '服务器内部错误(500)，请稍后重试或联系管理员检查后端日志',
    502 => '网关错误(502)，请确认 nginx 已正确转发 $endpoint',
    503 => '服务暂不可用(503)，请稍后重试',
    504 => '网关超时(504)，请稍后重试',
    _ => fallback != null &&
            fallback.trim().isNotEmpty &&
            !_isDioBoilerplate(fallback)
        ? fallback
        : '请求失败${statusCode != null ? '($statusCode)' : ''}：$endpoint',
  };
}

bool _isDioBoilerplate(String text) {
  final lower = text.toLowerCase();
  return lower.contains('validatestatus') ||
      lower.contains('status code of') ||
      lower.contains('this exception was thrown because');
}
