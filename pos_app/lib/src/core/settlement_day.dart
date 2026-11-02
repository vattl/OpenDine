/// 结算日与时间窗口工具函数。
///
/// 遵循 OpenAPI v1.2.245（统一时间窗口标准与严格无兜底校验，D031）：
/// - 实时数据接口以当前活动营业班次 24 小时周期为准：`[班次起始日 settle_time, 班次起始日+1天 settle_time)`；
/// - 已结算报表未传 date 时取最近已完成 24 小时周期：`[最近结算日-1天 settle_time, 最近结算日 settle_time)`；
/// - 客户端未传特定日期时交由后端按门店配置的权威 settle_time 自动解析，本函数仅供离线或初始未请求时的视觉占位兜底。
DateTime mostRecentCompletedSettlementDate({DateTime? now, int settleHour = 4}) {
  final current = now ?? DateTime.now();
  final cutoff = DateTime(current.year, current.month, current.day, settleHour);
  final date = current.isBefore(cutoff)
      ? DateTime(current.year, current.month, current.day - 1)
      : cutoff;
  return DateTime(date.year, date.month, date.day);
}


/// Reads an operational/settlement date from an API window start without converting an
/// offset-bearing timestamp through the device time zone first.
String? settlementDateFromApiWindowStart(Object? windowStart) {
  if (windowStart is String) {
    final match = RegExp(r'^\s*(\d{4}-\d{2}-\d{2})').firstMatch(windowStart);
    return match?.group(1);
  }
  if (windowStart is num) {
    return formatSettlementDate(
      DateTime.fromMillisecondsSinceEpoch(windowStart.toInt()),
    );
  }
  return null;
}

/// Reads a settlement date from an API window end without converting an
/// offset-bearing timestamp through the device time zone first.
String? settlementDateFromApiWindowEnd(Object? windowEnd) {
  if (windowEnd is String) {
    final match = RegExp(r'^\s*(\d{4}-\d{2}-\d{2})').firstMatch(windowEnd);
    return match?.group(1);
  }
  if (windowEnd is num) {
    return formatSettlementDate(
      DateTime.fromMillisecondsSinceEpoch(windowEnd.toInt()),
    );
  }
  return null;
}

String formatSettlementDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
