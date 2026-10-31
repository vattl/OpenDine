import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';

/// WebSocket 诊断日志（写入 kds_logs，设置页可导出）
class KdsWsLogger {
  KdsWsLogger._();

  static const _tag = '[WS]';

  static void skipConnect(String reason) {
    KdsFileLogger.warn('$_tag skip connect: $reason');
  }

  static void connecting(Uri uri) {
    KdsFileLogger.info('$_tag connecting ${_maskUri(uri)}');
  }

  static void connectorSelected(String connector) {
    KdsFileLogger.info('$_tag connector=$connector');
  }

  static void connected(Uri uri) {
    KdsFileLogger.info('$_tag connected ${_maskUri(uri)}');
  }

  static void disconnected({String? reason}) {
    KdsFileLogger.warn(
        '$_tag disconnected${reason != null ? ': $reason' : ''}');
  }

  static void reconnectScheduled({required int attempt, required int delayMs}) {
    KdsFileLogger.info('$_tag reconnect #$attempt in ${delayMs}ms');
  }

  static void connectError(Object err, [StackTrace? stack, Uri? uri]) {
    final hint = _connectErrorHint(err, uri);
    KdsFileLogger.error(
        '$_tag connect failed${hint.isEmpty ? '' : ': $hint'}', err, stack);
    if (uri != null) {
      KdsFileLogger.error('$_tag failed uri ${_maskUri(uri)}');
    }
  }

  static String _connectErrorHint(Object err, Uri? uri) {
    final msg = err.toString().toLowerCase();
    if (msg.contains('not upgraded') || msg.contains('connection refused')) {
      if (msg.contains(':0/') || msg.contains(':0?')) {
        return 'URL 含无效端口 :0，请检查设置中的 API 基址';
      }
      return '服务端未升级 WebSocket，请确认收银端已开放 /ws/kds/v2';
    }
    if (msg.contains('htps') || msg.contains(':0/')) {
      return 'API 基址格式错误，应为 http://localhost:8080';
    }
    return '';
  }

  static void streamError(Object err) {
    KdsFileLogger.error('$_tag stream error', err);
  }

  static void ping() {
    KdsFileLogger.debug('$_tag >> ping');
  }

  static void pong() {
    KdsFileLogger.debug('$_tag << pong');
  }

  static void rxRaw(String text) {
    final preview = text.length > 500 ? '${text.substring(0, 500)}…' : text;
    KdsFileLogger.debug('$_tag << $preview');
  }

  static void parseError(String text, Object err) {
    KdsFileLogger.warn('$_tag parse error: $err | raw=${_preview(text)}');
  }

  static void eventAccepted(KdsWsEvent event,
      {String? boundTag, List<String> workflows = const []}) {
    KdsFileLogger.info(
      '$_tag accept type=${event.type} envelope=${event.screenTag ?? '-'} '
      'bound=$boundTag workflows=${workflows.join(',')}',
    );
  }

  static void eventIgnored(
    KdsWsEvent event, {
    required String reason,
    String? boundTag,
    List<String> workflows = const [],
  }) {
    KdsFileLogger.info(
      '$_tag ignore type=${event.type} envelope=${event.screenTag ?? '-'} '
      'bound=$boundTag workflows=${workflows.join(',')} reason=$reason',
    );
  }

  static void refreshScheduled(String eventType) {
    KdsFileLogger.info('$_tag refresh scheduled ($eventType)');
  }

  static void stateChanged({required bool connected}) {
    KdsFileLogger.info('$_tag state ${connected ? 'ONLINE' : 'OFFLINE'}');
  }

  static void sessionAttach({
    required String apiBase,
    required int? shopId,
    required String? screenTag,
    required List<String> workflows,
  }) {
    KdsFileLogger.info(
      '$_tag attach base=$apiBase shop=$shopId screen=$screenTag workflows=${workflows.join(',')}',
    );
  }

  static void sessionDetach() {
    KdsFileLogger.info('$_tag detach');
  }

  static void fallbackLegacyQueryToken({required int livedMs}) {
    KdsFileLogger.warn(
      '$_tag header auth closed after ${livedMs}ms; retry with query token',
    );
  }

  static String _maskUri(Uri uri) {
    final q = Map<String, String>.from(uri.queryParameters);
    final token = q['token'];
    if (token != null && token.isNotEmpty) {
      q['token'] =
          token.length <= 8 ? '***' : '***${token.substring(token.length - 4)}';
    }
    return uri.replace(queryParameters: q).toString();
  }

  static String _preview(String text) {
    if (text.length <= 120) return text;
    return '${text.substring(0, 120)}…';
  }
}
