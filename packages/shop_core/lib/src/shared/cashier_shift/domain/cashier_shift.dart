class CashierShift {
  const CashierShift({
    required this.id,
    this.adminId,
    this.shopId,
    this.startTime,
    this.endTime,
    this.startCash = 0,
    this.endCash = 0,
    this.orderCount = 0,
    this.totalAmount = 0,
  });

  final int id;
  final int? adminId;
  final int? shopId;
  final DateTime? startTime;
  final DateTime? endTime;
  final double startCash;
  final double endCash;
  final int orderCount;
  final double totalAmount;

  factory CashierShift.fromJson(Map<String, Object?> json) => CashierShift(
    id: _safeInt(json['id']),
    adminId: _nullableInt(json['admin_id'] ?? json['adminId']),
    shopId: _nullableInt(json['shop_id'] ?? json['shopId']),
    startTime: _date(json['start_time'] ?? json['startTime']),
    endTime: _date(json['end_time'] ?? json['endTime']),
    startCash: safeMoney(json['start_cash'] ?? json['startCash']),
    endCash: safeMoney(json['end_cash'] ?? json['endCash']),
    orderCount: _safeInt(json['order_count'] ?? json['orderCount']),
    totalAmount: safeMoney(json['total_amount'] ?? json['totalAmount']),
  );
}

class CashierTodayReport {
  const CashierTodayReport({
    this.startTime,
    this.endTime,
    this.revenue = 0,
    this.paidOrderCount = 0,
    this.totalOrderCount = 0,
    this.memberRechargeAmount = 0,
    this.unpaidAmount = 0,
    this.refundAmount = 0,
    this.discountAmount = 0,
    this.revenueByPayChannel = const [],
  });

  final DateTime? startTime;
  final DateTime? endTime;
  final double revenue;
  final int paidOrderCount;
  final int totalOrderCount;
  final double memberRechargeAmount;
  final double unpaidAmount;
  final double refundAmount;
  final double discountAmount;
  final List<CashierPayChannelRevenue> revenueByPayChannel;

  factory CashierTodayReport.fromJson(Map<String, Object?> json) {
    final businessDay = _map(json['businessDay'] ?? json['business_day']);
    return CashierTodayReport(
      startTime: _date(businessDay['startTime']),
      endTime: _date(businessDay['endTime']),
      revenue: safeMoney(
        businessDay['todayRevenue'] ?? businessDay['businessRevenueNet'],
      ),
      paidOrderCount: _safeInt(businessDay['todayPaidOrderCount']),
      totalOrderCount: _safeInt(businessDay['todayOrderCount']),
      memberRechargeAmount: safeMoney(businessDay['todayMemberRechargeAmount']),
      unpaidAmount: safeMoney(businessDay['todayUnpaidAmount']),
      refundAmount: safeMoney(businessDay['totalRefundAmount']),
      discountAmount: safeMoney(businessDay['totalDiscountAmount']),
      revenueByPayChannel: _list(
        businessDay['revenueByPayChannel'],
      ).map(CashierPayChannelRevenue.fromJson).toList(growable: false),
    );
  }
}

class CashierPayChannelRevenue {
  const CashierPayChannelRevenue({
    required this.code,
    required this.label,
    required this.amount,
  });

  final String code;
  final String label;
  final double amount;

  factory CashierPayChannelRevenue.fromJson(Map<String, Object?> json) =>
      CashierPayChannelRevenue(
        code: '${json['channelCode'] ?? ''}'.trim(),
        label: '${json['channelLabel'] ?? json['channelCode'] ?? '其他'}'.trim(),
        amount: safeMoney(json['amount']),
      );
}

class CashierHandoverResult {
  const CashierHandoverResult({
    required this.orderCount,
    required this.totalAmount,
    this.sessionId,
    this.drawerSessionId,
    this.state,
    this.countedCash,
    this.variance,
    this.varianceApproved = false,
    this.report,
  });

  final int orderCount;
  final double totalAmount;
  final int? sessionId;
  final int? drawerSessionId;
  final String? state;
  final double? countedCash;
  final double? variance;
  final bool varianceApproved;

  /// 交班综合报表（handover 响应的 report 节点；可能为空）。
  final ShiftSummaryReport? report;

  factory CashierHandoverResult.fromJson(Map<String, Object?> json) =>
      CashierHandoverResult(
        orderCount: _safeInt(json['order_count'] ?? json['orderCount']),
        totalAmount: safeMoney(json['total_amount'] ?? json['totalAmount']),
        sessionId: _nullableInt(json['session_id'] ?? json['sessionId']),
        drawerSessionId: _nullableInt(
          json['drawer_session_id'] ?? json['drawerSessionId'] ?? json['business_no'],
        ),
        state: json['state']?.toString(),
        countedCash: json.containsKey('counted_cash') || json.containsKey('countedCash')
            ? safeMoney(json['counted_cash'] ?? json['countedCash'])
            : null,
        variance: json.containsKey('variance') ? safeMoney(json['variance']) : null,
        varianceApproved: json['variance_approved'] == true ||
            json['varianceApproved'] == true,
        report: json['report'] is Map
            ? ShiftSummaryReport.fromJson((json['report'] as Map).cast<String, Object?>())
            : null,
      );
}

/// 钱箱班次综合报表（GET /cashier/shift/report/{sessionId}，以及交班响应 report 节点）。
class ShiftSummaryReport {
  const ShiftSummaryReport({
    required this.sessionId,
    this.terminalId,
    this.drawerCode,
    this.state,
    this.operatorId,
    this.operatorName,
    this.openedAt,
    this.closedAt,
    this.businessDay,
    this.openingFloat = 0,
    this.cashSales = 0,
    this.cashRefunds = 0,
    this.cashIn = 0,
    this.cashOut = 0,
    this.cashDrop = 0,
    this.expectedCash = 0,
    this.countedCash = 0,
    this.variance = 0,
    this.varianceReasonCode,
    this.varianceNote,
    this.approvedBy,
    this.approvalStatus,
    this.channels = const [],
  });

  final int sessionId;
  final String? terminalId;
  final String? drawerCode;
  final String? state;
  final int? operatorId;
  final String? operatorName;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? businessDay;
  final double openingFloat;
  final double cashSales;
  final double cashRefunds;
  final double cashIn;
  final double cashOut;
  final double cashDrop;
  final double expectedCash;
  final double countedCash;
  final double variance;
  final String? varianceReasonCode;
  final String? varianceNote;
  final int? approvedBy;
  final String? approvalStatus;
  final List<CashierPayChannelRevenue> channels;

  factory ShiftSummaryReport.fromJson(Map<String, Object?> json) {
    // 后端现金汇总放在嵌套 cash_summary（fen/yuan 双写），同时兼容扁平字段。
    final cash = _map(json['cash_summary']);
    final channelsRaw = _list(json['channels']);
    return ShiftSummaryReport(
      sessionId: _safeInt(json['session_id'] ?? json['sessionId']),
      terminalId: json['terminal_id']?.toString() ?? json['terminalId']?.toString(),
      drawerCode: json['drawer_code']?.toString() ?? json['drawerCode']?.toString(),
      state: json['state']?.toString(),
      operatorId: _nullableInt(json['operator_id'] ?? json['operatorId'] ?? json['opened_by'] ?? json['closed_by']),
      operatorName: json['operator_name']?.toString(),
      openedAt: _date(json['opened_at'] ?? json['openedAt']),
      closedAt: _date(json['closed_at'] ?? json['closedAt']),
      businessDay: json['business_day']?.toString() ?? json['businessDay']?.toString(),
      openingFloat: _pickYuan(cash, json, 'opening_float', 'opening_float_yuan', 'openingFloat'),
      cashSales: _pickYuan(cash, json, 'cash_sales', 'cash_sale_yuan', 'cashSales'),
      cashRefunds: _pickYuan(cash, json, 'cash_refunds', 'cash_refund_yuan', 'cashRefunds'),
      cashIn: _pickYuan(cash, json, 'cash_in', 'cash_in_yuan', 'cashIn'),
      cashOut: _pickYuan(cash, json, 'cash_out', 'cash_out_yuan', 'cashOut'),
      cashDrop: _pickYuan(cash, json, 'cash_drop', 'cash_drop_yuan', 'cashDrop'),
      expectedCash: _pickYuan(cash, json, 'expected_cash', 'expected_cash_yuan', 'expectedCash'),
      countedCash: _pickYuan(cash, json, 'counted_cash', 'counted_cash_yuan', 'countedCash'),
      variance: _pickYuan(cash, json, 'variance', 'variance_yuan', 'variance'),
      varianceReasonCode: cash['variance_reason_code']?.toString() ??
          json['variance_reason_code']?.toString(),
      varianceNote: cash['variance_note']?.toString() ?? json['variance_note']?.toString(),
      approvedBy: _nullableInt(json['approved_by'] ?? json['approvedBy']),
      approvalStatus: json['approval_status']?.toString(),
      channels: channelsRaw.map(CashierPayChannelRevenue.fromJson).toList(growable: false),
    );
  }
}

/// 日结预检阻断项（POS-SDC-301）。
class DailyPrecheckBlocker {
  const DailyPrecheckBlocker({
    required this.code,
    required this.message,
    required this.count,
    this.details = const [],
  });

  final String code;
  final String message;
  final int count;
  final List<Map<String, Object?>> details;

  factory DailyPrecheckBlocker.fromJson(Map<String, Object?> json) =>
      DailyPrecheckBlocker(
        code: '${json['code'] ?? ''}',
        message: '${json['message'] ?? ''}',
        count: _safeInt(json['count']),
        details: _list(json['details']),
      );
}

/// 日结预检警告项（POS-SDC-301）。
class DailyPrecheckWarning {
  const DailyPrecheckWarning({
    required this.code,
    required this.message,
    required this.count,
  });

  final String code;
  final String message;
  final int count;

  factory DailyPrecheckWarning.fromJson(Map<String, Object?> json) =>
      DailyPrecheckWarning(
        code: '${json['code'] ?? ''}',
        message: '${json['message'] ?? ''}',
        count: _safeInt(json['count']),
      );
}

/// 日结预检综合结果（POS-SDC-301）。
class DailyPrecheckResult {
  const DailyPrecheckResult({
    required this.canSettle,
    required this.isAlreadySettled,
    required this.statDate,
    this.windowStart,
    this.windowEnd,
    this.blockers = const [],
    this.warnings = const [],
    this.precheckToken,
    this.precheckExpiresAt,
    this.currentBusinessDay = '',
    this.nextCloseBusinessDay = '',
    this.pendingDayCount = 0,
    this.hasPreviousUnclosedDay = false,
    this.preview = const {},
    this.closedAt,
  });

  final bool canSettle;
  final bool isAlreadySettled;
  final String statDate;

  /// 当前权威营业日（yyyy-MM-dd）。
  final String currentBusinessDay;

  /// 下一个可关闭的营业日（yyyy-MM-dd）。
  final String nextCloseBusinessDay;

  /// 未结营业日数量（含当前）。
  final int pendingDayCount;

  /// 是否存在更早的未结营业日（false 时当前即最早待结日）。
  final bool hasPreviousUnclosedDay;

  final DateTime? windowStart;
  final DateTime? windowEnd;
  final List<DailyPrecheckBlocker> blockers;
  final List<DailyPrecheckWarning> warnings;
  final String? precheckToken;
  final DateTime? precheckExpiresAt;
  final Map<String, Object?> preview;
  final DateTime? closedAt;

  factory DailyPrecheckResult.fromJson(Map<String, Object?> json) {
    final rawBlockers = json['blockers'];
    final rawWarnings = json['warnings'];
    return DailyPrecheckResult(
      canSettle: json['can_settle'] == true,
      isAlreadySettled: json['is_already_settled'] == true,
      statDate: '${json['stat_date'] ?? ''}',
      currentBusinessDay: '${json['current_business_day'] ?? ''}',
      nextCloseBusinessDay: '${json['next_close_business_day'] ?? ''}',
      pendingDayCount: _safeInt(json['pending_day_count']),
      hasPreviousUnclosedDay: json['has_previous_unclosed_day'] == true,
      windowStart: _date(json['window_start']),
      windowEnd: _date(json['window_end']),
      blockers: rawBlockers is List
          ? rawBlockers
              .whereType<Map>()
              .map((e) => DailyPrecheckBlocker.fromJson(e.cast<String, Object?>()))
              .toList(growable: false)
          : const [],
      warnings: rawWarnings is List
          ? rawWarnings
              .whereType<Map>()
              .map((e) => DailyPrecheckWarning.fromJson(e.cast<String, Object?>()))
              .toList(growable: false)
          : const [],
      precheckToken: json['precheck_token']?.toString(),
      precheckExpiresAt: _date(json['precheck_expires_at']),
      preview: _map(json['preview']),
      closedAt: _date(json['closed_at']),
    );
  }
}

/// 门店日结结果（POST /admin/daily/settle）。
class CashierDailySettleResult {
  const CashierDailySettleResult({
    required this.statDate,
    required this.totalAmount,
    required this.discountAmount,
    required this.refundAmount,
    this.settledAt,
    this.idempotent = false,
    this.message = '',
  });

  final String statDate;
  final double totalAmount;
  final double discountAmount;
  final double refundAmount;
  final DateTime? settledAt;
  final bool idempotent;
  final String message;

  factory CashierDailySettleResult.fromJson(Map<String, Object?> json) {
    final stat = _map(json['dailyStat']);
    final snapshot = _map(json['snapshot']);
    final settledAt = _date(stat['settled_at'] ?? stat['settledAt'] ?? snapshot['closed_at']);
    final rawDate = snapshot['business_day']?.toString() ??
        stat['stat_date']?.toString() ??
        stat['statDate']?.toString() ??
        '';
    return CashierDailySettleResult(
      statDate: rawDate,
      totalAmount: safeMoney(
        stat['total_amount'] ?? stat['totalAmount'] ??
            (snapshot['net_sales_fen'] != null ? safeMoney(snapshot['net_sales_fen']) / 100.0 : 0),
      ),
      discountAmount: safeMoney(
        stat['discount_amount'] ?? stat['discountAmount'] ??
            (snapshot['discount_amount_fen'] != null ? safeMoney(snapshot['discount_amount_fen']) / 100.0 : 0),
      ),
      refundAmount: safeMoney(
        stat['refund_amount'] ?? stat['refundAmount'] ??
            (snapshot['refund_amount_fen'] != null ? safeMoney(snapshot['refund_amount_fen']) / 100.0 : 0),
      ),
      settledAt: settledAt,
      idempotent: json['idempotent'] == true,
      message: '${json['message'] ?? ''}',
    );
  }
}

/// 商用 Z 报表（GET /admin/daily/z-report，POS-SDC-304）。
class CommercialZReport {
  const CommercialZReport({
    required this.reportType,
    required this.isClosed,
    required this.shopId,
    required this.shopName,
    required this.businessDay,
    this.snapshotNo,
    this.closedAt,
    required this.totalSales,
    required this.discountAmount,
    required this.refundAmount,
    required this.netSales,
    required this.orderCount,
    this.channels = const {},
    required this.totalCashVariance,
    required this.totalAdjustment,
    required this.adjustedNetSales,
    this.adjustments = const [],
    required this.printableText,
  });

  final String reportType;
  final bool isClosed;
  final int shopId;
  final String shopName;
  final String businessDay;
  final String? snapshotNo;
  final DateTime? closedAt;
  final double totalSales;
  final double discountAmount;
  final double refundAmount;
  final double netSales;
  final int orderCount;
  final Map<String, double> channels;
  final double totalCashVariance;
  final double totalAdjustment;
  final double adjustedNetSales;
  final List<Map<String, Object?>> adjustments;
  final String printableText;

  factory CommercialZReport.fromJson(Map<String, Object?> json) {
    final sales = _map(json['sales_summary']);
    final rawChannels = _map(json['channels']);
    final channelsMap = <String, double>{};
    for (final e in rawChannels.entries) {
      channelsMap[e.key] = safeMoney(e.value);
    }
    return CommercialZReport(
      reportType: '${json['report_type'] ?? 'Z_REPORT'}',
      isClosed: json['is_closed'] == true,
      shopId: _safeInt(json['shop_id']),
      shopName: '${json['shop_name'] ?? '收银门店'}',
      businessDay: '${json['business_day'] ?? ''}',
      snapshotNo: json['snapshot_no']?.toString(),
      closedAt: _date(json['closed_at']),
      totalSales: safeMoney(sales['total_sales'] ?? sales['total_amount']),
      discountAmount: safeMoney(sales['discount_amount']),
      refundAmount: safeMoney(sales['refund_amount']),
      netSales: safeMoney(sales['net_sales'] ?? sales['total_amount']),
      orderCount: _safeInt(sales['order_count']),
      channels: channelsMap,
      totalCashVariance: safeMoney(json['total_cash_variance']),
      totalAdjustment: safeMoney(json['total_adjustment']),
      adjustedNetSales: safeMoney(json['adjusted_net_sales']),
      adjustments: _list(json['adjustments']),
      printableText: '${json['printable_text'] ?? ''}',
    );
  }
}

double _pickYuan(Map<String, Object?> cash, Map<String, Object?> flat,
    String flatKey, String cashKey, String camelKey) {
  if (cash.containsKey(cashKey)) return safeMoney(cash[cashKey]);
  if (cash.containsKey(cashKey.replaceFirst('_yuan', '_fen'))) {
    return safeMoney(cash[cashKey.replaceFirst('_yuan', '_fen')]) / 100.0;
  }
  if (flat.containsKey(flatKey)) return safeMoney(flat[flatKey]);
  if (flat.containsKey(camelKey)) return safeMoney(flat[camelKey]);
  return 0;
}

double safeMoney(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : 0;
}

String formatCashierMoney(Object? value) => safeMoney(value).toStringAsFixed(2);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Map<String, Object?>> _list(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList(growable: false)
    : const [];

int _safeInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _nullableInt(Object? value) => value == null ? null : _safeInt(value);

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value'.trim().replaceFirst(' ', 'T'));
}

/// 支付渠道显示名（byChannel / Z 报表 channels 返回 payment_method 原始值，
/// 或 /admin/daily/income 返回的中文渠道键，中文键原样透出）。
String dailyChannelLabel(String code) => switch (code) {
  'wechat' || 'wxpay' || '微信支付' => '微信支付',
  'wechat_qr' || '微信收款码' => '微信收款码',
  'alipay' || '支付宝' => '支付宝',
  'alipay_qr' || '支付宝收款码' => '支付宝收款码',
  'cash' || '现金' => '现金',
  'balance' || '会员余额' || '余额' => '会员余额',
  'gift' || '赠送金' => '赠送金',
  'receivable' || '挂账' => '挂账',
  'other' || '其他' => '其他',
  _ => code.isEmpty ? '其他' : code,
};

/// 日结工作台统一上下文聚合（GET /admin/daily/context）。
/// 单请求覆盖：营业日时序、汇总、渠道、预检阻断与超时外卖单。
class DailyContext {
  const DailyContext({
    required this.statDate,
    required this.isAlreadySettled,
    required this.canSettle,
    this.currentBusinessDay = '',
    this.nextCloseBusinessDay = '',
    this.pendingDayCount = 0,
    this.hasPreviousUnclosedDay = false,
    this.summary = const {},
    this.channels = const {},
    this.channelDetails = const [],
    this.blockers = const [],
    this.warnings = const [],
    this.precheckToken,
    this.precheckExpiresAt,
    this.voidableStalePackTakeout = const [],
    this.adjustments = const [],
    this.closedAt,
  });

  final String statDate;
  final bool isAlreadySettled;
  final bool canSettle;
  final String currentBusinessDay;
  final String nextCloseBusinessDay;
  final int pendingDayCount;
  final bool hasPreviousUnclosedDay;

  /// summary（DailyStat 子集，元为单位；含 *_fen 分单位兼容）。
  final Map<String, Object?> summary;

  /// 渠道实收（中文渠道名 -> 元），与 /admin/daily/byChannel 同源。
  final Map<String, double> channels;

  /// 渠道明细（code/label/net_amount_fen/…）。
  final List<Map<String, Object?>> channelDetails;
  final List<DailyPrecheckBlocker> blockers;
  final List<DailyPrecheckWarning> warnings;
  final String? precheckToken;
  final DateTime? precheckExpiresAt;

  /// 超时未支付打包/外卖单（可一键作废）。
  final List<Map<String, Object?>> voidableStalePackTakeout;

  /// 已结日返回的日结后差异调整。
  final List<Map<String, Object?>> adjustments;
  final DateTime? closedAt;

  factory DailyContext.fromJson(Map<String, Object?> json) {
    final rawBlockers = json['blockers'];
    final rawWarnings = json['warnings'];
    final rawChannels = _map(json['channels']);
    final channelsMap = <String, double>{};
    for (final e in rawChannels.entries) {
      final v = e.value is num
          ? (e.value as num).toDouble()
          : double.tryParse('${e.value}');
      if (v == null || !v.isFinite) continue;
      channelsMap[e.key] = e.key.endsWith('_fen') ? v / 100.0 : v;
    }
    return DailyContext(
      statDate: '${json['stat_date'] ?? ''}',
      isAlreadySettled: json['is_already_settled'] == true,
      canSettle: json['can_settle'] == true,
      currentBusinessDay: '${json['current_business_day'] ?? ''}',
      nextCloseBusinessDay: '${json['next_close_business_day'] ?? ''}',
      pendingDayCount: _safeInt(json['pending_day_count']),
      hasPreviousUnclosedDay: json['has_previous_unclosed_day'] == true,
      summary: _map(json['summary']),
      channels: channelsMap,
      channelDetails: _list(json['channel_details']),
      blockers: rawBlockers is List
          ? rawBlockers
              .whereType<Map>()
              .map((e) => DailyPrecheckBlocker.fromJson(e.cast<String, Object?>()))
              .toList(growable: false)
          : const [],
      warnings: rawWarnings is List
          ? rawWarnings
              .whereType<Map>()
              .map((e) => DailyPrecheckWarning.fromJson(e.cast<String, Object?>()))
              .toList(growable: false)
          : const [],
      precheckToken: json['precheck_token']?.toString(),
      precheckExpiresAt: _date(json['precheck_expires_at']),
      voidableStalePackTakeout: _list(json['voidable_stale_pack_takeout']),
      adjustments: _list(json['adjustments']),
      closedAt: _date(json['closed_at']),
    );
  }

  /// 从 summary 提取数值字段（兼容 *_fen 分单位与元单位）。
  double summaryMoney(String key) {
    final fen = summary['${key}_fen'];
    if (fen != null) return safeMoney(fen) / 100.0;
    final raw = summary[key] ?? summary[_camel(key)];
    return safeMoney(raw);
  }

  static String _camel(String snake) {
    final parts = snake.split('_');
    if (parts.length <= 1) return snake;
    return parts.first +
        parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
  }
}

/// 作废超时外卖单结果（POST /admin/daily/void-stale-takeout-orders）。
class VoidStaleTakeoutResult {
  const VoidStaleTakeoutResult({
    required this.statDate,
    this.voidedCount = 0,
    this.voidedAmount = 0,
    this.orderNos = const [],
  });

  final String statDate;
  final int voidedCount;
  final double voidedAmount;
  final List<String> orderNos;

  factory VoidStaleTakeoutResult.fromJson(Map<String, Object?> json) {
    final orderNos = _list(json['order_nos'] ?? json['orderNos'])
        .map((m) => '${m['order_no'] ?? m['orderNo'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return VoidStaleTakeoutResult(
      statDate: '${json['stat_date'] ?? ''}',
      voidedCount: _safeInt(json['voided_count'] ?? json['voidedCount']),
      voidedAmount: safeMoney(json['voided_amount'] ?? json['voidedAmount']),
      orderNos: orderNos,
    );
  }
}

/// 历史 Z 报表时序项（GET /admin/daily/z-reports items）。
class DailyZReportItem {
  const DailyZReportItem({
    required this.businessDay,
    required this.closeState,
    required this.canClose,
    required this.isNextCloseBusinessDay,
    this.snapshotId,
    this.snapshotNo,
    this.snapshotHash,
    this.closedAt,
    this.netSales = 0,
    this.orderCount = 0,
    this.memberRechargePrincipal = 0,
    this.memberRechargeGift = 0,
    this.receivableTotal = 0,
    this.totalCollections = 0,
    this.operatorId,
    this.operatorName,
  });

  final String businessDay;

  /// CLOSED / PENDING / REOPENED。
  final String closeState;
  final bool canClose;
  final bool isNextCloseBusinessDay;
  final int? snapshotId;
  final String? snapshotNo;
  final String? snapshotHash;
  final DateTime? closedAt;
  final double netSales;
  final int orderCount;
  final double memberRechargePrincipal;
  final double memberRechargeGift;
  final double receivableTotal;
  final double totalCollections;
  final int? operatorId;
  final String? operatorName;

  bool get isClosed => closeState == 'CLOSED';
  bool get isReopened => closeState == 'REOPENED';
  bool get isPending => closeState == 'PENDING';

  factory DailyZReportItem.fromJson(Map<String, Object?> json) {
    final recharge = _map(json['member_recharge_summary']);
    final receivable = _map(json['receivable_summary']);
    return DailyZReportItem(
      businessDay: '${json['business_day'] ?? ''}',
      closeState: '${json['close_state'] ?? 'PENDING'}',
      canClose: json['can_close'] == true,
      isNextCloseBusinessDay: json['is_next_close_business_day'] == true,
      snapshotId: _nullableInt(json['id'] ?? json['snapshot_id']),
      snapshotNo: json['snapshot_no']?.toString(),
      snapshotHash: json['snapshot_hash']?.toString(),
      closedAt: _date(json['closed_at']),
      netSales: _fenOrYuan(json['net_sales_fen'], json['net_sales']),
      orderCount: _safeInt(json['order_count']),
      memberRechargePrincipal: _fenOrYuan(
        recharge['principal_fen'],
        recharge['principal'],
      ),
      memberRechargeGift: _fenOrYuan(recharge['gift_fen'], recharge['gift']),
      receivableTotal: _fenOrYuan(
        receivable['total_fen'],
        receivable['total'],
      ),
      totalCollections: _fenOrYuan(
        json['total_collections_fen'],
        json['total_collections'],
      ),
      operatorId: _nullableInt(json['operator_id'] ?? json['operatorId']),
      operatorName: json['operator_name']?.toString() ??
          json['operatorName']?.toString(),
    );
  }
}

/// 历史 Z 报表时序分页（GET /admin/daily/z-reports）。
class DailyZReportsPage {
  const DailyZReportsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.currentBusinessDay = '',
    this.nextCloseBusinessDay = '',
    this.pendingDayCount = 0,
  });

  final List<DailyZReportItem> items;
  final bool hasMore;

  /// 不透明游标：只能原样回传 next_cursor。
  final int? nextCursor;
  final String currentBusinessDay;
  final String nextCloseBusinessDay;
  final int pendingDayCount;

  factory DailyZReportsPage.fromJson(Map<String, Object?> json) {
    final rawItems = _list(json['items']);
    return DailyZReportsPage(
      items: rawItems
          .map(DailyZReportItem.fromJson)
          .toList(growable: false),
      hasMore: json['has_more'] == true,
      nextCursor: _nullableInt(json['next_cursor']),
      currentBusinessDay: '${json['current_business_day'] ?? ''}',
      nextCloseBusinessDay: '${json['next_close_business_day'] ?? ''}',
      pendingDayCount: _safeInt(json['pending_day_count']),
    );
  }
}

/// 钱箱人工现金事件（POST /cashier/shift/cash-movement 与
/// GET /cashier/shift/{sessionId}/cash-events 流水项）。
class CashMovementEvent {
  const CashMovementEvent({
    required this.movementType,
    required this.amount,
    this.id,
    this.reasonCode,
    this.remark,
    this.operatorId,
    this.operatorName,
    this.createdAt,
  });

  final int? id;

  /// CASH_IN 加钞 / CASH_OUT 支出 / CASH_DROP 投库。
  final String movementType;
  final double amount;
  final String? reasonCode;
  final String? remark;
  final int? operatorId;
  final String? operatorName;
  final DateTime? createdAt;

  String get movementLabel => switch (movementType) {
    'CASH_IN' => '加钞',
    'CASH_OUT' => '现金支出',
    'CASH_DROP' => '大钞投库',
    _ => movementType,
  };

  factory CashMovementEvent.fromJson(Map<String, Object?> json) =>
      CashMovementEvent(
        id: _nullableInt(json['id'] ?? json['event_id']),
        movementType: '${json['movement_type'] ?? json['type'] ?? ''}',
        amount: _fenOrYuan(json['amount_fen'], json['amount']),
        reasonCode: json['reason_code']?.toString(),
        remark: json['remark']?.toString(),
        operatorId: _nullableInt(json['operator_id'] ?? json['operatorId']),
        operatorName: json['operator_name']?.toString() ??
            json['operatorName']?.toString(),
        createdAt: _date(json['created_at'] ?? json['createdAt']),
      );
}

/// 钱箱人工现金事件流水分页（GET /cashier/shift/{sessionId}/cash-events）。
class CashEventsPage {
  const CashEventsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<CashMovementEvent> items;
  final bool hasMore;
  final int? nextCursor;

  factory CashEventsPage.fromJson(Map<String, Object?> json) {
    final raw = json['items'] is List
        ? json['items'] as List
        : (json['list'] is List ? json['list'] as List : const []);
    final events = raw
        .whereType<Map>()
        .map((e) => CashMovementEvent.fromJson(e.cast<String, Object?>()))
        .toList(growable: false);
    return CashEventsPage(
      items: events,
      hasMore: json['has_more'] == true,
      nextCursor: _nullableInt(json['next_cursor']),
    );
  }
}

double _fenOrYuan(Object? fen, Object? yuan) {
  if (fen != null) return safeMoney(fen) / 100.0;
  return safeMoney(yuan);
}
