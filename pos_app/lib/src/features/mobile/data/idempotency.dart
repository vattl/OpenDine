import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 订单幂等键生成。⚠️ 后端需支持幂等语义（见协调文档第 3 节）。
/// 弱网 Outbox 重试时同一 clientRequestId 必须被后端去重。
class IdempotencyKey {
  IdempotencyKey._();

  static int _counter = 0;

  /// 生成形如 `app-<ts>-<seq>-<hash>` 的幂等键。
  static String next(String prefix) {
    _counter += 1;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final digest = md5
        .convert(utf8.encode('$prefix-$ts-$_counter'))
        .toString()
        .substring(0, 8);
    return 'app-$ts-$_counter-$digest';
  }
}

/// 约定请求头（与后端协调）。
const kIdempotencyHeader = 'X-Client-Request-Id';
