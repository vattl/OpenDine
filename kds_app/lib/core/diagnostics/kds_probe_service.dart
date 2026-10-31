import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kds_app/core/api/api_response.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/core/ws/kds_ws_connect_common.dart';
import 'package:kds_app/core/ws/kds_ws_uri.dart';
import 'package:web_socket_channel/io.dart';

class KdsProbeItemResult {
  const KdsProbeItemResult({
    required this.name,
    required this.url,
    required this.isSuccess,
    required this.durationMs,
    required this.message,
    this.statusCode,
  });

  final String name;
  final String url;
  final bool isSuccess;
  final int durationMs;
  final String message;
  final int? statusCode;
}

class KdsProbeReport {
  const KdsProbeReport({
    required this.timestamp,
    required this.lanHttp,
    required this.lanWs,
    required this.cloudHttp,
    required this.cloudWs,
  });

  final DateTime timestamp;
  final KdsProbeItemResult lanHttp;
  final KdsProbeItemResult lanWs;
  final KdsProbeItemResult cloudHttp;
  final KdsProbeItemResult cloudWs;

  List<KdsProbeItemResult> get all => [lanHttp, lanWs, cloudHttp, cloudWs];
}

/// 全链路探针服务
class KdsProbeService {
  KdsProbeService._();

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  /// 执行一键全链路探测
  static Future<KdsProbeReport> runFullProbe({
    required String lanBase,
    required String cloudBase,
    required String token,
    int shopId = 1,
  }) async {
    final results = await Future.wait([
      _probeHttp(
        name: '局域网收银端 HTTP',
        base: lanBase,
        endpoint: '/kds/v2/bootstrap',
        token: token,
      ),
      _probeWs(
        name: '局域网收银端 WS',
        base: lanBase,
        shopId: shopId,
        token: token,
      ),
      _probeHttp(
        name: '云端服务 HTTP',
        base: cloudBase,
        endpoint: '/kds/device/me',
        token: token,
      ),
      _probeWs(
        name: '云端服务 WS',
        base: cloudBase,
        shopId: shopId,
        token: token,
      ),
    ]);

    final report = KdsProbeReport(
      timestamp: DateTime.now(),
      lanHttp: results[0],
      lanWs: results[1],
      cloudHttp: results[2],
      cloudWs: results[3],
    );

    // 记录到全局 Trace
    for (final item in report.all) {
      KdsTraceHub.recordProbe(
        channel: item.name.contains('局域网')
            ? KdsActiveChannel.lan
            : KdsActiveChannel.cloud,
        target: item.name,
        summary: '${item.name}: ${item.message} (${item.durationMs}ms)',
        isSuccess: item.isSuccess,
        durationMs: item.durationMs,
        metadata: {'url': item.url, 'status_code': item.statusCode},
      );
    }

    return report;
  }

  /// 单独探测局域网收银端地址可用性
  static Future<KdsProbeItemResult> probeLanBase(
    String lanBase, {
    String token = '',
  }) async {
    return _probeHttp(
      name: '收银端局域网地址',
      base: lanBase,
      endpoint: '/kds/v2/health',
      token: token,
    );
  }

  static Future<KdsProbeItemResult> _probeHttp({
    required String name,
    required String base,
    required String endpoint,
    required String token,
  }) async {
    if (base.trim().isEmpty || !isValidApiBase(base)) {
      return KdsProbeItemResult(
        name: name,
        url: base,
        isSuccess: false,
        durationMs: 0,
        message: '未配置或无效地址',
      );
    }
    final url = '$base$endpoint';
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: {
            if (token.isNotEmpty) kKdsDeviceTokenHeader: token,
          },
        ),
      );
      sw.stop();
      final code = res.statusCode ?? 0;
      final ok = code >= 200 && code < 400;
      String desc;
      if (ok) {
        desc = 'HTTP $code 连通正常';
      } else {
        final serverMsg = readServerErrorMessage(res.data);
        if (serverMsg != null && serverMsg.isNotEmpty) {
          desc = 'HTTP $code ($serverMsg)';
        } else if (code == 401) {
          desc = 'HTTP 401 (设备未绑定或已禁用)';
        } else {
          desc = 'HTTP $code (${res.statusMessage ?? '异常'})';
        }
      }
      return KdsProbeItemResult(
        name: name,
        url: url,
        isSuccess: ok,
        durationMs: sw.elapsedMilliseconds,
        statusCode: code,
        message: desc,
      );
    } catch (e) {
      sw.stop();
      return KdsProbeItemResult(
        name: name,
        url: url,
        isSuccess: false,
        durationMs: sw.elapsedMilliseconds,
        message: '连接失败: ${_formatError(e)}',
      );
    }
  }

  static Future<KdsProbeItemResult> _probeWs({
    required String name,
    required String base,
    required int shopId,
    required String token,
  }) async {
    if (base.trim().isEmpty || !isValidApiBase(base)) {
      return KdsProbeItemResult(
        name: name,
        url: base,
        isSuccess: false,
        durationMs: 0,
        message: '未配置或无效地址',
      );
    }

    late final Uri wsUri;
    try {
      wsUri = buildKdsWebSocketUri(
        apiBase: base,
        shopId: shopId,
        screenTag: 'workflow_board',
      );
    } catch (e) {
      return KdsProbeItemResult(
        name: name,
        url: base,
        isSuccess: false,
        durationMs: 0,
        message: '构建 WS URI 失败: $e',
      );
    }

    final sw = Stopwatch()..start();
    IOWebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    try {
      final headers = <String, dynamic>{
        kKdsDeviceTokenHeader: token,
      };
      channel = IOWebSocketChannel.connect(wsUri, headers: headers);
      await channel.ready.timeout(const Duration(seconds: 4));
      sw.stop();

      // 进一步监听首帧或断开事件（等待 300ms），侦测服务端是否因 Token 鉴权失败立即关闭通道
      final closeCompleter = Completer<String?>();
      sub = channel.stream.listen(
        (_) {},
        onDone: () {
          final code = channel?.closeCode;
          final reason = channel?.closeReason;
          if (code != null && code != 1000) {
            closeCompleter.complete(reason != null && reason.isNotEmpty
                ? '服务端拒绝($code: $reason)'
                : '服务端拒绝断开($code)');
          } else {
            closeCompleter.complete('连接关闭');
          }
        },
        onError: (e) {
          closeCompleter.complete('流异常: ${_formatError(e)}');
        },
      );

      final immediateClose = await closeCompleter.future
          .timeout(const Duration(milliseconds: 300), onTimeout: () => null);

      await sub.cancel();
      await channel.sink.close();

      if (immediateClose != null) {
        return KdsProbeItemResult(
          name: name,
          url: wsUri.toString(),
          isSuccess: false,
          durationMs: sw.elapsedMilliseconds,
          message: immediateClose,
        );
      }

      return KdsProbeItemResult(
        name: name,
        url: wsUri.toString(),
        isSuccess: true,
        durationMs: sw.elapsedMilliseconds,
        message: '握手成功，鉴权及延时正常',
      );
    } catch (e) {
      sw.stop();
      try {
        await sub?.cancel();
        await channel?.sink.close();
      } catch (_) {}
      return KdsProbeItemResult(
        name: name,
        url: wsUri.toString(),
        isSuccess: false,
        durationMs: sw.elapsedMilliseconds,
        message: 'WS 握手失败: ${_formatError(e)}',
      );
    }
  }

  static String _formatError(Object e) {
    if (e is SocketException) {
      return e.osError?.message ?? e.message;
    }
    if (e is TimeoutException) {
      return '连接超时(>4s)';
    }
    return e.toString().split('\n').first;
  }
}
