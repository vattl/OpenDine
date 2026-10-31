/// 日志落盘 / 实时缓冲前的敏感字段脱敏
String redactSensitiveLog(String message) {
  var out = message;

  out = out.replaceAllMapped(
    RegExp(r'(token=)([^\s&]+)', caseSensitive: false),
    (m) => '${m[1]}***',
  );

  out = out.replaceAllMapped(
    RegExp(r'(X-Kds-Device-Token\s*[:=]\s*)([^\s,]+)', caseSensitive: false),
    (m) => '${m[1]}***',
  );

  out = out.replaceAllMapped(
    RegExp(r'(X-Kds-Pairing-Secret\s*[:=]\s*)([^\s,]+)', caseSensitive: false),
    (m) => '${m[1]}***',
  );

  out = out.replaceAllMapped(
    RegExp(r'("device_token"\s*:\s*")([^"]+)', caseSensitive: false),
    (m) => '${m[1]}***',
  );

  out = out.replaceAllMapped(
    RegExp(r'("client_id"\s*:\s*")([^"]+)', caseSensitive: false),
    (m) => '${m[1]}***',
  );

  return out;
}
