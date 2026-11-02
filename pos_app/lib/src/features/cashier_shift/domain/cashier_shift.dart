import '../../../core/settlement_day.dart';
import '../../reports/domain/daily_report.dart';

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
    this.drawerSessionId,
    this.terminalId,
    this.state,
    this.businessDay,
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
  final int? drawerSessionId;
  final String? terminalId;
  final String? state;
  final String? businessDay;

  bool get isOpen => state?.toUpperCase() == 'OPEN' || (startTime != null && endTime == null);

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
    drawerSessionId: _nullableInt(
      json['drawer_session_id'] ?? json['drawerSessionId'],
    ),
    terminalId:
        json['terminal_id']?.toString() ?? json['terminalId']?.toString(),
    state: json['state']?.toString(),
    businessDay:
        json['business_day']?.toString() ?? json['businessDay']?.toString(),
  );
}

class CashierTodayReport {
  const CashierTodayReport({
    this.startTime,
    this.endTime,
    this.settlementDate,
    this.revenue = 0,
    this.paidOrderCount = 0,
    this.totalOrderCount = 0,
    this.unpaidOrderCount = 0,
    this.memberRechargeAmount = 0,
    this.unpaidAmount = 0,
    this.refundAmount = 0,
    this.discountAmount = 0,
    this.revenueByPayChannel = const [],
  });

  final DateTime? startTime;
  final DateTime? endTime;

  /// YYYY-MM-DD from the API window end; preserved before time-zone conversion.
  final String? settlementDate;
  final double revenue;
  final int paidOrderCount;
  final int totalOrderCount;

  /// 当前营业日待支付（unsettled）订单笔数，与 unpaidAmount 同一口径。
  final int unpaidOrderCount;
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
      settlementDate:
          businessDay['businessDayDate']?.toString() ??
          businessDay['settlementDate']?.toString() ??
          settlementDateFromApiWindowStart(businessDay['startTime']) ??
          settlementDateFromApiWindowEnd(businessDay['endTime']),
      revenue: safeMoney(
        businessDay['todayRevenue'] ?? businessDay['businessRevenueNet'],
      ),
      paidOrderCount: _safeInt(businessDay['todayPaidOrderCount']),
      totalOrderCount: _safeInt(businessDay['todayOrderCount']),
      unpaidOrderCount: _safeInt(
        businessDay['todayUnpaidOrderCount'] ??
            businessDay['todayUnsettledOrderCount'],
      ),
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
    this.transactionCount = 0,
    this.refundCount = 0,
    this.refundAmount = 0,
  });

  final String code;
  final String label;
  final double amount;
  final int transactionCount;
  final int refundCount;
  final double refundAmount;

  int get successCount => transactionCount;

  factory CashierPayChannelRevenue.fromJson(Map<String, Object?> json) {
    final rawCode = '${json['channelCode'] ?? json['code'] ?? json['channel'] ?? json['channel_code'] ?? ''}'.trim();
    final rawLabel = '${json['channelLabel'] ?? json['channel_label'] ?? json['name'] ?? json['label'] ?? ''}'.trim();
    return CashierPayChannelRevenue(
      code: rawCode.isNotEmpty ? rawCode : rawLabel,
      label: cashierChannelLabel(
        rawCode,
        fallback: rawLabel.isNotEmpty ? rawLabel : rawCode,
      ),
      amount: json['net_amount_fen'] != null
          ? safeFen(json['net_amount_fen'])
          : safeMoney(json['amount'] ?? json['net_sales'] ?? json['total_amount']),
      transactionCount: _safeInt(
        json['transaction_count'] ?? json['success_count'] ?? json['order_count'] ?? json['orderCount'],
      ),
      refundCount: _safeInt(json['refund_count']),
      refundAmount: safeFen(json['refund_amount_fen']),
    );
  }
}

class CashierShiftWorkbenchData {
  const CashierShiftWorkbenchData({
    required this.businessDay,
    this.operator,
    this.terminal,
    this.drawer,
    this.currentShift = const {},
    this.latestCashMovement,
    this.previousShift,
    this.closeReadiness = const CashierCloseReadiness(),
  });

  final String businessDay;
  final CashierIdentity? operator;
  final CashierIdentity? terminal;
  final CashierDrawerIdentity? drawer;
  final Map<String, Object?> currentShift;
  final CashierCashEvent? latestCashMovement;
  final CashierPreviousShift? previousShift;
  final CashierCloseReadiness closeReadiness;

  factory CashierShiftWorkbenchData.fromJson(Map<String, Object?> json) {
    final operator = _map(json['operator']);
    final terminal = _map(json['terminal']);
    final drawer = _map(json['drawer']);
    final latest = _map(json['latest_cash_movement']);
    final previous = _map(json['previous_shift']);
    return CashierShiftWorkbenchData(
      businessDay: '${json['business_day'] ?? ''}',
      operator: operator.isEmpty ? null : CashierIdentity.fromJson(operator),
      terminal: terminal.isEmpty ? null : CashierIdentity.fromJson(terminal),
      drawer: drawer.isEmpty ? null : CashierDrawerIdentity.fromJson(drawer),
      currentShift: _map(json['current_shift']),
      latestCashMovement: latest.isEmpty
          ? null
          : CashierCashEvent.fromJson(latest),
      previousShift: previous.isEmpty
          ? null
          : CashierPreviousShift.fromJson(previous),
      closeReadiness: CashierCloseReadiness.fromJson(
        _map(json['close_readiness']),
      ),
    );
  }
}

class CashierIdentity {
  const CashierIdentity({
    this.id,
    required this.displayName,
    this.workNo = '',
    this.realName = '',
    this.jobTitle = '',
    this.userName = '',
  });

  final Object? id;
  final String displayName;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String userName;

  String get fullIdentityText {
    final name = realName.isNotEmpty ? realName : displayName;
    if (workNo.isNotEmpty && jobTitle.isNotEmpty) {
      return '$name ($workNo · $jobTitle)';
    } else if (workNo.isNotEmpty) {
      return '$name ($workNo)';
    } else if (jobTitle.isNotEmpty) {
      return '$name [$jobTitle]';
    }
    return name;
  }

  factory CashierIdentity.fromJson(Map<String, Object?> json) {
    final workNo = (json['work_no'] ?? json['workNo'] ?? '').toString().trim();
    final realName = (json['real_name'] ?? json['realName'] ?? '').toString().trim();
    final jobTitle = (json['job_title'] ?? json['jobTitle'] ?? '').toString().trim();
    final userName = (json['user_name'] ?? json['userName'] ?? '').toString().trim();
    final rawDisplay = (json['display_name'] ??
            json['displayName'] ??
            json['operator_name'] ??
            json['admin_name'] ??
            json['name'] ??
            '')
        .toString()
        .trim();
    final effectiveDisplay = rawDisplay.isNotEmpty
        ? rawDisplay
        : (realName.isNotEmpty ? realName : (userName.isNotEmpty ? userName : ''));

    return CashierIdentity(
      id: json['id'],
      displayName: effectiveDisplay,
      workNo: workNo,
      realName: realName,
      jobTitle: jobTitle,
      userName: userName,
    );
  }
}

class CashierDrawerIdentity extends CashierIdentity {
  const CashierDrawerIdentity({
    super.id,
    required super.displayName,
    super.workNo = '',
    super.realName = '',
    super.jobTitle = '',
    super.userName = '',
    required this.sessionId,
    required this.code,
  });

  final int sessionId;
  final String code;

  factory CashierDrawerIdentity.fromJson(Map<String, Object?> json) {
    final base = CashierIdentity.fromJson(json);
    return CashierDrawerIdentity(
      id: base.id,
      displayName: base.displayName,
      workNo: base.workNo,
      realName: base.realName,
      jobTitle: base.jobTitle,
      userName: base.userName,
      sessionId: _safeInt(json['session_id'] ?? json['id']),
      code: '${json['code'] ?? ''}',
    );
  }
}

class CashierPreviousShift {
  const CashierPreviousShift({
    required this.sessionId,
    this.closedAt,
    required this.balanced,
  });

  final int sessionId;
  final DateTime? closedAt;
  final bool balanced;

  factory CashierPreviousShift.fromJson(Map<String, Object?> json) =>
      CashierPreviousShift(
        sessionId: _safeInt(json['session_id']),
        closedAt: _date(json['closed_at']),
        balanced: json['balanced'] == true,
      );
}

class CashierCloseReadiness {
  const CashierCloseReadiness({
    this.openDrawerCount = 0,
    this.unsettledOrderCount = 0,
    this.pendingPaymentCount = 0,
    this.unapprovedVarianceCount = 0,
  });

  final int openDrawerCount;
  final int unsettledOrderCount;
  final int pendingPaymentCount;
  final int unapprovedVarianceCount;

  bool get canSettle =>
      openDrawerCount == 0 &&
      unsettledOrderCount == 0 &&
      pendingPaymentCount == 0 &&
      unapprovedVarianceCount == 0;

  factory CashierCloseReadiness.fromJson(Map<String, Object?> json) =>
      CashierCloseReadiness(
        openDrawerCount: _safeInt(json['open_drawer_count']),
        unsettledOrderCount: _safeInt(json['unsettled_order_count']),
        pendingPaymentCount: _safeInt(json['pending_payment_count']),
        unapprovedVarianceCount: _safeInt(json['unapproved_variance_count']),
      );
}

class CashierCashEvent {
  const CashierCashEvent({
    required this.eventId,
    required this.type,
    this.amount,
    this.amountHidden = false,
    this.occurredAt,
    this.operatorName,
    this.operatorWorkNo,
    this.operatorJobTitle,
    this.referenceNo,
  });

  final int eventId;
  final String type;
  final double? amount;
  final bool amountHidden;
  final DateTime? occurredAt;
  final String? operatorName;
  final String? operatorWorkNo;
  final String? operatorJobTitle;
  final String? referenceNo;

  factory CashierCashEvent.fromJson(Map<String, Object?> json) {
    final opName = (json['operator_name'] ??
            json['operatorName'] ??
            json['real_name'] ??
            json['realName'] ??
            json['display_name'] ??
            json['displayName'] ??
            json['admin_name'] ??
            json['adminName'] ??
            '')
        .toString()
        .trim();
    return CashierCashEvent(
      eventId: _safeInt(json['event_id']),
      type: '${json['type'] ?? json['event_type'] ?? ''}',
      amount: json['amount_fen'] == null ? null : safeFen(json['amount_fen']),
      amountHidden: json['amount_hidden'] == true,
      occurredAt: _date(json['occurred_at']),
      operatorName: opName.isNotEmpty ? opName : null,
      operatorWorkNo: (json['work_no'] ?? json['workNo'] ?? json['operator_work_no'])?.toString(),
      operatorJobTitle: (json['job_title'] ?? json['jobTitle'] ?? json['operator_job_title'])?.toString(),
      referenceNo: json['reference_no']?.toString(),
    );
  }
}

class CashierCashEventPage {
  const CashierCashEventPage({
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
  });

  final List<CashierCashEvent> items;
  final int? nextCursor;
  final bool hasMore;

  factory CashierCashEventPage.fromJson(Map<String, Object?> json) =>
      CashierCashEventPage(
        items: _list(
          json['items'],
        ).map(CashierCashEvent.fromJson).toList(growable: false),
        nextCursor: _nullableInt(json['next_cursor']),
        hasMore: json['has_more'] == true,
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
  });

  final int orderCount;
  final double totalAmount;
  final int? sessionId;
  final int? drawerSessionId;
  final String? state;
  final double? countedCash;
  final double? variance;
  final bool varianceApproved;

  factory CashierHandoverResult.fromJson(Map<String, Object?> json) {
    final report = _map(json['report']);
    final cash = _map(report['cash_summary']);
    return CashierHandoverResult(
      orderCount: _safeInt(json['order_count'] ?? json['orderCount']),
      totalAmount: safeMoney(json['total_amount'] ?? json['totalAmount']),
      sessionId: _nullableInt(
        json['session_id'] ?? json['sessionId'] ?? report['session_id'],
      ),
      drawerSessionId: _nullableInt(
        json['drawer_session_id'] ??
            json['drawerSessionId'] ??
            report['session_id'] ??
            json['business_no'],
      ),
      state: json['state']?.toString() ?? report['state']?.toString(),
      countedCash: cash['counted_cash_fen'] != null
          ? safeFen(cash['counted_cash_fen'])
          : json.containsKey('counted_cash') || json.containsKey('countedCash')
          ? safeMoney(json['counted_cash'] ?? json['countedCash'])
          : null,
      variance: cash['variance_fen'] != null
          ? safeFen(cash['variance_fen'])
          : json.containsKey('variance')
          ? safeMoney(json['variance'])
          : null,
      varianceApproved:
          json['variance_approved'] == true ||
          json['varianceApproved'] == true ||
          report['approval_status'] == 'APPROVED',
    );
  }
}

/// 成功会员充值汇总（v1.2.281，班次日结/今日概览共用）：本金为实际收款，赠送额仅为会员权益。
class MemberRechargeSummary {
  const MemberRechargeSummary({
    this.successCount = 0,
    this.principal = 0,
    this.gift = 0,
  });

  final int successCount;

  /// 充值本金（元）。
  final double principal;

  /// 赠送金额（元）。
  final double gift;

  /// 会员入账合计（元）= 本金 + 赠送。
  double get creditedTotal => principal + gift;

  static MemberRechargeSummary empty() =>
      const MemberRechargeSummary(successCount: 0, principal: 0, gift: 0);

  factory MemberRechargeSummary.fromJson(Map<String, Object?> json) {
    double money(dynamic v) => safeMoney(v);
    return MemberRechargeSummary(
      successCount: _safeInt(
        json['success_count'] ?? json['successCount'] ?? 0,
      ),
      principal: money(
        json['principal_amount'] ??
            json['principalAmount'] ??
            _fenToYuan(json['principal_fen']),
      ),
      gift: money(
        json['gift_amount'] ?? json['giftAmount'] ?? _fenToYuan(json['gift_fen']),
      ),
    );
  }

  static double _fenToYuan(Object? fen) {
    if (fen == null) return 0;
    final n = fen is num ? fen.toDouble() : double.tryParse('$fen') ?? 0;
    return n / 100;
  }
}

/// 钱箱班次综合报表（GET /cashier/shift/report/{sessionId}）
class ShiftSummaryReport {
  const ShiftSummaryReport({
    required this.sessionId,
    this.terminalId,
    this.drawerCode,
    this.state,
    this.operatorId,
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
    this.operatorName,
    this.terminalName,
    this.drawerName,
    this.durationSeconds = 0,
    this.approvalStatus,
    this.approvedByName,
    this.approvedAt,
    this.channels = const [],
    this.auditEvents = const [],
    this.integrity = const {},
    this.memberRechargeSummary,
    this.orderSalesSummary,
    this.changeSummary,
    this.dishOperations,
  });

  final int sessionId;
  final String? terminalId;
  final String? drawerCode;
  final String? state;
  final int? operatorId;
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
  final String? operatorName;
  final String? terminalName;
  final String? drawerName;
  final int durationSeconds;
  final String? approvalStatus;
  final String? approvedByName;
  final DateTime? approvedAt;
  final List<CashierPayChannelRevenue> channels;
  final List<CashierCashEvent> auditEvents;
  final Map<String, Object?> integrity;

  /// 本班成功会员充值汇总（v1.2.281）；旧服务端缺省时为空。
  final MemberRechargeSummary? memberRechargeSummary;

  /// 本班订单交易汇总（总营收/优惠/退款/赠送金实付/净营收，v1.2.282）；旧服务端缺省时为空。
  final ShiftOrderSalesSummary? orderSalesSummary;

  /// 本班现金找零汇总（v1.2.282）；旧服务端缺省时为空。
  final ShiftChangeSummary? changeSummary;

  /// 本班退菜/赠菜操作明细（v1.2.282）；旧服务端缺省时为空。
  final ShiftDishOperations? dishOperations;

  factory ShiftSummaryReport.fromJson(Map<String, Object?> json) {
    final cash = _map(json['cash_summary']);
    return ShiftSummaryReport(
      sessionId: _safeInt(json['session_id'] ?? json['sessionId']),
      terminalId:
          json['terminal_id']?.toString() ?? json['terminalId']?.toString(),
      drawerCode:
          json['drawer_code']?.toString() ?? json['drawerCode']?.toString(),
      state: json['state']?.toString(),
      operatorId: _nullableInt(json['operator_id'] ?? json['operatorId']),
      openedAt: _date(json['opened_at'] ?? json['openedAt']),
      closedAt: _date(json['closed_at'] ?? json['closedAt']),
      businessDay:
          json['business_day']?.toString() ?? json['businessDay']?.toString(),
      openingFloat: _moneyOrFen(
        cash['opening_float_yuan'] ??
            json['opening_float'] ??
            json['openingFloat'],
        cash['opening_float_fen'],
      ),
      cashSales: _moneyOrFen(
        cash['cash_sale_yuan'] ?? json['cash_sales'] ?? json['cashSales'],
        cash['cash_sale_fen'],
      ),
      cashRefunds: _moneyOrFen(
        cash['cash_refund_yuan'] ?? json['cash_refunds'] ?? json['cashRefunds'],
        cash['cash_refund_fen'],
      ),
      cashIn: _moneyOrFen(
        cash['cash_in_yuan'] ?? json['cash_in'] ?? json['cashIn'],
        cash['cash_in_fen'],
      ),
      cashOut: _moneyOrFen(
        cash['cash_out_yuan'] ?? json['cash_out'] ?? json['cashOut'],
        cash['cash_out_fen'],
      ),
      cashDrop: _moneyOrFen(
        cash['cash_drop_yuan'] ?? json['cash_drop'] ?? json['cashDrop'],
        cash['cash_drop_fen'],
      ),
      expectedCash: _moneyOrFen(
        cash['expected_cash_yuan'] ??
            json['expected_cash'] ??
            json['expectedCash'],
        cash['expected_cash_fen'],
      ),
      countedCash: _moneyOrFen(
        cash['counted_cash_yuan'] ??
            json['counted_cash'] ??
            json['countedCash'],
        cash['counted_cash_fen'],
      ),
      variance: _moneyOrFen(
        cash['variance_yuan'] ?? json['variance'],
        cash['variance_fen'],
      ),
      varianceReasonCode:
          cash['variance_reason_code']?.toString() ??
          json['variance_reason_code']?.toString() ??
          json['varianceReasonCode']?.toString(),
      varianceNote:
          cash['variance_note']?.toString() ??
          json['variance_note']?.toString() ??
          json['varianceNote']?.toString(),
      approvedBy: _nullableInt(json['approved_by'] ?? json['approvedBy']),
      operatorName: (json['operator_name'] ??
              json['operatorName'] ??
              json['real_name'] ??
              json['realName'] ??
              json['display_name'] ??
              json['displayName'] ??
              json['admin_name'] ??
              json['adminName'] ??
              '')
          .toString()
          .trim(),
      terminalName: json['terminal_name']?.toString(),
      drawerName: json['drawer_name']?.toString(),
      durationSeconds: _safeInt(json['duration_seconds']),
      approvalStatus: json['approval_status']?.toString(),
      approvedByName: (json['approved_by_name'] ??
              json['approvedByName'] ??
              json['reviewer_name'] ??
              json['reviewerName'] ??
              json['approver_name'] ??
              '')
          .toString()
          .trim(),
      approvedAt: _date(json['approved_at']),
      channels: _list(
        json['channels'],
      ).map(CashierPayChannelRevenue.fromJson).toList(growable: false),
      auditEvents: _list(
        json['audit_events'],
      ).map(CashierCashEvent.fromJson).toList(growable: false),
      integrity: _map(json['integrity']),
      memberRechargeSummary: json['member_recharge_summary'] is Map
          ? MemberRechargeSummary.fromJson(
              (json['member_recharge_summary'] as Map).cast<String, Object?>(),
            )
          : null,
      orderSalesSummary: json['order_sales_summary'] is Map
          ? ShiftOrderSalesSummary.fromJson(
              (json['order_sales_summary'] as Map).cast<String, Object?>(),
            )
          : null,
      changeSummary: json['change_summary'] is Map
          ? ShiftChangeSummary.fromJson(
              (json['change_summary'] as Map).cast<String, Object?>(),
            )
          : null,
      dishOperations: json['dish_operations'] is Map
          ? ShiftDishOperations.fromJson(
              (json['dish_operations'] as Map).cast<String, Object?>(),
            )
          : null,
    );
  }
}

/// 交班报告订单交易汇总（v1.2.282：order_sales_summary）。
class ShiftOrderSalesSummary {
  const ShiftOrderSalesSummary({
    this.paidOrderCount = 0,
    this.grossSales = 0,
    this.discount = 0,
    this.refund = 0,
    this.giftPaid = 0,
    this.netSales = 0,
  });

  factory ShiftOrderSalesSummary.fromJson(Map<String, Object?> json) =>
      ShiftOrderSalesSummary(
        paidOrderCount: _safeInt(json['paid_order_count']),
        grossSales: safeFen(json['gross_sales_fen']),
        discount: safeFen(json['discount_fen']),
        refund: safeFen(json['refund_fen']),
        giftPaid: safeFen(json['gift_paid_fen']),
        netSales: safeFen(json['net_sales_fen']),
      );

  /// 已结订单数（去重 order_no）。
  final int paidOrderCount;

  /// 总营收 = Σ(sett_amount + service_fee) 订单原价合计。
  final double grossSales;

  /// 优惠 = Σ(discount_amount) 合计。
  final double discount;

  /// 退款 = Σ(refund_amount) 累计成功退款合计。
  final double refund;

  /// 赠送金实付 = Σ(pay_amount_gift) 合计。
  final double giftPaid;

  /// 净营收 = Σ(sett_amount + service_fee - discount_amount - refund_amount - pay_amount_gift)。
  final double netSales;
}

/// 交班报告现金找零汇总（v1.2.282：change_summary）。
class ShiftChangeSummary {
  const ShiftChangeSummary({this.totalChange = 0, this.byChannel = const {}});

  factory ShiftChangeSummary.fromJson(Map<String, Object?> json) {
    final byChannel = <String, double>{};
    final raw = json['by_channel'];
    if (raw is Map) {
      raw.forEach((key, value) {
        byChannel['$key'] = safeFen(value);
      });
    }
    return ShiftChangeSummary(
      totalChange: safeFen(json['total_change_fen']),
      byChannel: byChannel,
    );
  }

  /// 找零合计（元）。
  final double totalChange;

  /// 按找零渠道（wechat/cash/alipay）分组的找零金额（元）。
  final Map<String, double> byChannel;
}

/// 交班报告退菜/赠菜操作明细（v1.2.282：dish_operations）。
class ShiftDishOperations {
  const ShiftDishOperations({
    this.refundDishCount = 0,
    this.refundDishAmount = 0,
    this.giveDishCount = 0,
    this.giveDishAmount = 0,
  });

  factory ShiftDishOperations.fromJson(Map<String, Object?> json) =>
      ShiftDishOperations(
        refundDishCount: _safeInt(json['refund_dish_count']),
        refundDishAmount: safeFen(json['refund_dish_amount_fen']),
        giveDishCount: _safeInt(json['give_dish_count']),
        giveDishAmount: safeFen(json['give_dish_amount_fen']),
      );

  /// 退菜道数（Σ refunded_quantity）。
  final int refundDishCount;

  /// 退菜金额（元）。
  final double refundDishAmount;

  /// 赠菜道数（Σ 单价为 0 行 quantity）。
  final int giveDishCount;

  /// 赠菜金额（元，无原价来源恒为 0）。
  final double giveDishAmount;
}

class CashierShiftReportPage {
  const CashierShiftReportPage({
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ShiftSummaryReport> items;
  final int? nextCursor;
  final bool hasMore;

  factory CashierShiftReportPage.fromJson(Map<String, Object?> json) =>
      CashierShiftReportPage(
        items: _list(
          json['items'],
        ).map(ShiftSummaryReport.fromJson).toList(growable: false),
        nextCursor: _nullableInt(json['next_cursor']),
        hasMore: json['has_more'] == true,
      );
}

/// 结算日日结汇总（GET /admin/daily/summary + byChannel）。
class CashierDailySummary {
  const CashierDailySummary({
    required this.statDate,
    required this.totalAmount,
    required this.discountAmount,
    required this.refundAmount,
    required this.settled,
    this.settledAt,
    this.channels = const {},
  });

  final String statDate;
  final double totalAmount;
  final double discountAmount;
  final double refundAmount;
  final bool settled;
  final DateTime? settledAt;

  /// 支付渠道对账（payment_method → 金额），来自 byChannel。
  final Map<String, double> channels;
}

/// 门店日结结果（POST /admin/daily/settle 的 dailyStat）。
class CashierDailySettleResult {
  const CashierDailySettleResult({
    required this.statDate,
    required this.totalAmount,
    required this.discountAmount,
    required this.refundAmount,
    required this.settledAt,
  });

  final String statDate;
  final double totalAmount;
  final double discountAmount;
  final double refundAmount;
  final DateTime settledAt;
}

/// 可作废超时打包外卖订单简要信息 (v1.2.289 / WI-014)
class VoidableStaleOrderInfo {
  const VoidableStaleOrderInfo({
    required this.id,
    required this.orderNo,
    this.orderTime,
    this.settAmount = 0,
    this.payableAmount = 0,
    this.dineInOrTakeOut = '',
    this.ageMinutes = 0,
  });

  final int id;
  final String orderNo;
  final String? orderTime;
  final double settAmount;
  final double payableAmount;
  final String dineInOrTakeOut;
  final int ageMinutes;

  factory VoidableStaleOrderInfo.fromJson(Map<String, Object?> json) =>
      VoidableStaleOrderInfo(
        id: _safeInt(json['id']),
        orderNo: '${json['order_no'] ?? json['orderNo'] ?? ''}',
        orderTime: json['order_time']?.toString() ?? json['orderTime']?.toString(),
        settAmount: _moneyOrFen(json['sett_amount'] ?? json['settAmount'], null),
        payableAmount: _moneyOrFen(json['payable_amount'] ?? json['payableAmount'], null),
        dineInOrTakeOut: '${json['dineInOrTakeOut'] ?? json['dine_in_or_take_out'] ?? ''}',
        ageMinutes: _safeInt(json['age_minutes'] ?? json['ageMinutes']),
      );
}

/// 可作废超时打包外卖订单汇总 (v1.2.289 / WI-014)
class VoidableStalePackTakeoutSummary {
  const VoidableStalePackTakeoutSummary({
    this.count = 0,
    this.amount = 0,
    this.thresholdMinutes = 30,
    this.canOneClickVoid = false,
    this.orders = const [],
  });

  final int count;
  final double amount;
  final int thresholdMinutes;
  final bool canOneClickVoid;
  final List<VoidableStaleOrderInfo> orders;

  factory VoidableStalePackTakeoutSummary.fromJson(Map<String, Object?> json) {
    final rawOrders = json['orders'];
    return VoidableStalePackTakeoutSummary(
      count: _safeInt(json['count']),
      amount: _moneyOrFen(json['amount'], null),
      thresholdMinutes: _safeInt(json['threshold_minutes'] ?? json['thresholdMinutes'] ?? 30),
      canOneClickVoid: json['can_one_click_void'] == true || json['canOneClickVoid'] == true,
      orders: rawOrders is List
          ? rawOrders
                .whereType<Map>()
                .map((e) => VoidableStaleOrderInfo.fromJson(e.cast<String, Object?>()))
                .toList(growable: false)
          : const [],
    );
  }
}

/// 一键作废超时打包外卖订单结果 (v1.2.289 / WI-014)
class VoidStaleTakeoutResult {
  const VoidStaleTakeoutResult({
    this.voidedCount = 0,
    this.voidedAmount = 0,
    this.thresholdMinutes = 30,
    this.voidedOrderNos = const [],
  });

  final int voidedCount;
  final double voidedAmount;
  final int thresholdMinutes;
  final List<String> voidedOrderNos;

  factory VoidStaleTakeoutResult.fromJson(Map<String, Object?> json) {
    final rawNos = json['voided_order_nos'] ?? json['voidedOrderNos'];
    return VoidStaleTakeoutResult(
      voidedCount: _safeInt(json['voided_count'] ?? json['voidedCount']),
      voidedAmount: _moneyOrFen(json['voided_amount'] ?? json['voidedAmount'], null),
      thresholdMinutes: _safeInt(json['threshold_minutes'] ?? json['thresholdMinutes'] ?? 30),
      voidedOrderNos: rawNos is List ? rawNos.map((e) => '$e').toList(growable: false) : const [],
    );
  }
}

/// 流水异常明细项 (WI-026 / v1.2.302)
class LedgerMismatchItem {
  const LedgerMismatchItem({
    required this.orderId,
    required this.orderNo,
    required this.reasonCode,
    required this.reason,
    required this.orderAmountFen,
    required this.ledgerAmountFen,
    required this.differenceFen,
    this.channelMismatches = const [],
  });

  final int orderId;
  final String orderNo;
  final String reasonCode;
  final String reason;
  final int orderAmountFen;
  final int ledgerAmountFen;
  final int differenceFen;
  final List<Object?> channelMismatches;

  double get orderAmountYuan => orderAmountFen / 100.0;
  double get ledgerAmountYuan => ledgerAmountFen / 100.0;
  double get differenceYuan => differenceFen / 100.0;

  factory LedgerMismatchItem.fromJson(Map<String, Object?> json) {
    return LedgerMismatchItem(
      orderId: _safeInt(json['order_id'] ?? json['orderId']),
      orderNo: '${json['order_no'] ?? json['orderNo'] ?? ''}',
      reasonCode: '${json['reason_code'] ?? json['reasonCode'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      orderAmountFen: _safeInt(json['order_amount_fen'] ?? json['orderAmountFen']),
      ledgerAmountFen: _safeInt(json['ledger_amount_fen'] ?? json['ledgerAmountFen']),
      differenceFen: _safeInt(json['difference_fen'] ?? json['differenceFen']),
      channelMismatches: json['channel_mismatches'] is List
          ? (json['channel_mismatches'] as List).cast<Object?>()
          : const [],
    );
  }
}

/// 日结预检阻断项 (POS-SDC-301)
class DailyPrecheckBlocker {
  const DailyPrecheckBlocker({
    required this.code,
    required this.message,
    required this.count,
    this.details = const [],
    this.voidablePackTakeout,
    this.reasonSummary,
    this.ledgerMismatches = const [],
  });

  final String code;
  final String message;
  final int count;
  final List<Map<String, Object?>> details;
  final VoidableStalePackTakeoutSummary? voidablePackTakeout;
  final String? reasonSummary;
  final List<LedgerMismatchItem> ledgerMismatches;

  factory DailyPrecheckBlocker.fromJson(Map<String, Object?> json) {
    final rawVoidable = json['voidable_pack_takeout'] ?? json['voidablePackTakeout'];
    final rawDetails = json['details'];
    final detailsList = _list(rawDetails);
    final isLedgerMismatch = '${json['code'] ?? ''}' == 'ORDER_LEDGER_MISMATCH';
    return DailyPrecheckBlocker(
      code: '${json['code'] ?? ''}',
      message: '${json['message'] ?? ''}',
      count: _safeInt(json['count']),
      details: detailsList,
      voidablePackTakeout: rawVoidable is Map
          ? VoidableStalePackTakeoutSummary.fromJson(rawVoidable.cast<String, Object?>())
          : null,
      reasonSummary: json['reason_summary']?.toString() ?? json['reasonSummary']?.toString(),
      ledgerMismatches: isLedgerMismatch
          ? (((json['ledger_mismatches'] is List
                      ? json['ledger_mismatches']
                      : (json['ledgerMismatches'] is List
                          ? json['ledgerMismatches']
                          : rawDetails)) as List?) ??
                  const [])
              .whereType<Map>()
              .map((e) => LedgerMismatchItem.fromJson(e.cast<String, Object?>()))
              .toList(growable: false)
          : const [],
    );
  }
}

/// 日结预检警告项 (POS-SDC-301)
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

/// 日结预检综合结果 (POS-SDC-301 / WI-067)
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
    this.watermarks = const {},
    this.preview = const {},
    this.voidableStalePackTakeout,
    this.currentBusinessDay,
    this.nextCloseBusinessDay,
    this.pendingDayCount = 0,
    this.hasPreviousUnclosedDay = false,
    this.summary = const {},
    this.channels = const {},
    this.channelDetails = const [],
    this.existingSnapshotNo,
    this.canReopen = false,
  });

  final bool canSettle;
  final bool isAlreadySettled;
  final String statDate;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final List<DailyPrecheckBlocker> blockers;
  final List<DailyPrecheckWarning> warnings;
  final String? precheckToken;
  final DateTime? precheckExpiresAt;
  final Map<String, Object?> watermarks;
  final Map<String, Object?> preview;
  final VoidableStalePackTakeoutSummary? voidableStalePackTakeout;

  /// 服务端权威当前营业日（WI-067 / INV-CLOSE-SEQ-001）
  final String? currentBusinessDay;

  /// 服务端权威最早待关账营业日（目标日）
  final String? nextCloseBusinessDay;

  /// 积压待关账营业日数量
  final int pendingDayCount;

  /// 是否存在历史待关账营业日积压（跳日保护）
  final bool hasPreviousUnclosedDay;

  /// 统一聚合财务汇总 (GET /admin/daily/context)
  final Map<String, Object?> summary;

  /// 统一聚合渠道映射 (payment_method -> amount)
  final Map<String, double> channels;

  /// 统一聚合渠道结构化明细
  final List<CashierPayChannelRevenue> channelDetails;

  /// 历史快照编号（若已结）
  final String? existingSnapshotNo;

  /// 是否可重开（仅最后一张已结快照为 true）
  final bool canReopen;

  factory DailyPrecheckResult.fromJson(Map<String, Object?> json) {
    final rawBlockers = json['blockers'];
    final rawWarnings = json['warnings'];
    final rawStale = json['voidable_stale_pack_takeout'] ?? json['voidableStalePackTakeout'];
    final statDate = json['stat_date']?.toString() ??
        json['statDate']?.toString() ??
        json['next_close_business_day']?.toString() ??
        json['nextCloseBusinessDay']?.toString() ??
        '';

    final summaryMap = _map(json['summary']);
    final channelsMap = <String, double>{};
    if (json['channels'] is Map) {
      for (final e in (json['channels'] as Map).entries) {
        final v = e.value;
        channelsMap[e.key.toString()] = v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
      }
    }
    final detailsList = <CashierPayChannelRevenue>[];
    final rawDetails = json['channel_details'];
    if (rawDetails is List) {
      for (final raw in rawDetails.whereType<Map>()) {
        detailsList.add(CashierPayChannelRevenue.fromJson(raw.cast<String, Object?>()));
      }
    }

    return DailyPrecheckResult(
      canSettle: json['can_settle'] == true || json['canSettle'] == true,
      isAlreadySettled: json['is_already_settled'] == true || json['isAlreadySettled'] == true,
      statDate: statDate,
      windowStart: _date(json['window_start'] ?? json['windowStart']),
      windowEnd: _date(json['window_end'] ?? json['windowEnd']),
      blockers: rawBlockers is List
          ? rawBlockers
                .whereType<Map>()
                .map(
                  (e) =>
                      DailyPrecheckBlocker.fromJson(e.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const [],
      warnings: rawWarnings is List
          ? rawWarnings
                .whereType<Map>()
                .map(
                  (e) =>
                      DailyPrecheckWarning.fromJson(e.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const [],
      precheckToken: (json['precheck_token'] ?? json['precheckToken'])?.toString(),
      precheckExpiresAt: _date(json['precheck_expires_at'] ?? json['precheckExpiresAt']),
      watermarks: _map(json['watermarks']),
      preview: _map(json['preview']),
      voidableStalePackTakeout: rawStale is Map
          ? VoidableStalePackTakeoutSummary.fromJson(rawStale.cast<String, Object?>())
          : null,
      currentBusinessDay:
          (json['current_business_day'] ?? json['currentBusinessDay'])?.toString(),
      nextCloseBusinessDay:
          (json['next_close_business_day'] ?? json['nextCloseBusinessDay'])?.toString(),
      pendingDayCount: _safeInt(json['pending_day_count'] ?? json['pendingDayCount']),
      hasPreviousUnclosedDay:
          json['has_previous_unclosed_day'] == true ||
          json['hasPreviousUnclosedDay'] == true,
      summary: summaryMap,
      channels: channelsMap,
      channelDetails: detailsList,
      existingSnapshotNo: (json['existing_snapshot_no'] ?? json['existingSnapshotNo'])?.toString(),
      canReopen: json['can_reopen'] == true || json['canReopen'] == true,
    );
  }
}

/// 商用 Z 报表 (POS-SDC-304)
class CommercialZReport {
  const CommercialZReport({
    required this.reportType,
    required this.isClosed,
    required this.shopId,
    required this.shopName,
    required this.businessDay,
    this.windowStart,
    this.windowEnd,
    this.snapshotNo,
    this.closedAt,
    this.snapshotHash,
    this.watermarks = const {},
    required this.totalSales,
    required this.discountAmount,
    required this.refundAmount,
    required this.netSales,
    required this.orderCount,
    this.channels = const {},
    this.channelDetails = const [],
    this.drawerSummary = const {},
    required this.totalCashVariance,
    required this.totalAdjustment,
    required this.adjustedNetSales,
    this.adjustments = const [],
    required this.printableText,
    this.operatorName,
    this.operatorWorkNo,
    this.operatorJobTitle,
    this.reviewerName,
    this.reviewerJobTitle,
    this.dailyDetail,
    this.receivableSummary,
    this.totalCollections,
  });

  final String reportType;
  final bool isClosed;
  final int shopId;
  final String shopName;
  final String businessDay;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final String? snapshotNo;
  final DateTime? closedAt;
  final String? snapshotHash;
  final Map<String, Object?> watermarks;
  final double totalSales;
  final double discountAmount;
  final double refundAmount;
  final double netSales;
  final int orderCount;
  final Map<String, double> channels;
  final List<CashierPayChannelRevenue> channelDetails;
  final Map<String, Object?> drawerSummary;
  final double totalCashVariance;
  final double totalAdjustment;
  final double adjustedNetSales;
  final List<Map<String, Object?>> adjustments;
  final String printableText;
  final String? operatorName;
  final String? operatorWorkNo;
  final String? operatorJobTitle;
  final String? reviewerName;
  final String? reviewerJobTitle;
  final DailyReport? dailyDetail;
  final DailyReportReceivableSummary? receivableSummary;
  final double? totalCollections;

  DailyReportReceivableSummary? get receivables => receivableSummary ?? dailyDetail?.receivableSummary;
  double get actualCollections => totalCollections ?? dailyDetail?.totalCollections ?? netSales;

  int get dinerCount => dailyDetail?.summary.dinerCount ?? (orderCount > 0 ? orderCount : 0);
  double get avgOrderAmount => dailyDetail?.summary.avgOrderAmount ?? (orderCount > 0 ? (netSales / orderCount) : 0.0);
  double get avgDinerAmount => dailyDetail?.summary.avgDinerAmount ?? (dinerCount > 0 ? (netSales / dinerCount) : 0.0);
  double get tableTurnoverRate => dailyDetail?.summary.tableTurnoverRate ?? 0.0;
  List<DailyReportOrderType> get orderTypes => dailyDetail?.orderTypes ?? const [];
  DailyReportMember? get member => dailyDetail?.member;
  DailyReportExceptions? get exceptions => dailyDetail?.exceptions;
  List<DailyReportTopDish> get topDishes => dailyDetail?.topDishes ?? const [];

  CommercialZReport copyWith({
    DailyReport? dailyDetail,
    DailyReportReceivableSummary? receivableSummary,
    double? totalCollections,
    String? printableText,
    String? operatorName,
  }) {
    return CommercialZReport(
      reportType: reportType,
      isClosed: isClosed,
      shopId: shopId,
      shopName: shopName,
      businessDay: businessDay,
      windowStart: windowStart,
      windowEnd: windowEnd,
      snapshotNo: snapshotNo,
      closedAt: closedAt,
      snapshotHash: snapshotHash,
      watermarks: watermarks,
      totalSales: totalSales,
      discountAmount: discountAmount,
      refundAmount: refundAmount,
      netSales: netSales,
      orderCount: orderCount,
      channels: channels,
      channelDetails: channelDetails,
      drawerSummary: drawerSummary,
      totalCashVariance: totalCashVariance,
      totalAdjustment: totalAdjustment,
      adjustedNetSales: adjustedNetSales,
      adjustments: adjustments,
      printableText: printableText ?? this.printableText,
      operatorName: operatorName ?? this.operatorName,
      operatorWorkNo: operatorWorkNo,
      operatorJobTitle: operatorJobTitle,
      reviewerName: reviewerName,
      reviewerJobTitle: reviewerJobTitle,
      dailyDetail: dailyDetail ?? this.dailyDetail,
      receivableSummary: receivableSummary ?? this.receivableSummary,
      totalCollections: totalCollections ?? this.totalCollections,
    );
  }

  factory CommercialZReport.fromJson(Map<String, Object?> json) {
    final sales = _map(json['sales_summary']);
    final channelsMap = <String, double>{};
    final channelDetails = <CashierPayChannelRevenue>[];
    final rawChannels = json['channels'];
    if (rawChannels is Map) {
      for (final e in rawChannels.entries) {
        channelsMap['${e.key}'] = safeMoney(e.value);
      }
    } else if (rawChannels is List) {
      for (final row in rawChannels.whereType<Map>()) {
        final detail = CashierPayChannelRevenue.fromJson(
          row.cast<String, Object?>(),
        );
        channelDetails.add(detail);
        channelsMap[detail.code] = detail.amount;
      }
    }
    return CommercialZReport(
      reportType: '${json['report_type'] ?? 'Z_REPORT'}',
      isClosed: json['is_closed'] == true,
      shopId: _safeInt(json['shop_id']),
      shopName: '${json['shop_name'] ?? '收银门店'}',
      businessDay: '${json['business_day'] ?? ''}',
      windowStart: _date(json['window_start']),
      windowEnd: _date(json['window_end']),
      snapshotNo: json['snapshot_no']?.toString(),
      closedAt: _date(json['closed_at']),
      snapshotHash: json['snapshot_hash']?.toString(),
      watermarks: _map(json['watermarks']),
      totalSales: _moneyOrFen(
        sales['total_sales'] ?? sales['total_amount'],
        sales['gross_sales_fen'] ?? sales['total_sales_fen'],
      ),
      discountAmount: _moneyOrFen(
        sales['discount_amount'],
        sales['discount_amount_fen'],
      ),
      refundAmount: _moneyOrFen(
        sales['refund_amount'],
        sales['refund_amount_fen'],
      ),
      netSales: _moneyOrFen(
        sales['net_sales'] ?? sales['total_amount'],
        sales['net_sales_fen'],
      ),
      orderCount: _safeInt(sales['order_count']),
      channels: channelsMap,
      channelDetails: channelDetails,
      drawerSummary: _map(json['drawer_summary']),
      totalCashVariance: safeMoney(json['total_cash_variance']),
      totalAdjustment: safeMoney(json['total_adjustment']),
      adjustedNetSales: safeMoney(json['adjusted_net_sales']),
      adjustments: _list(json['adjustments']),
      printableText: '${json['printable_text'] ?? ''}',
      operatorName: (json['operator_name'] ??
              json['operatorName'] ??
              json['closed_by_name'] ??
              json['closedByName'] ??
              json['real_name'] ??
              json['realName'] ??
              json['display_name'] ??
              json['displayName'] ??
              json['admin_name'] ??
              json['adminName'] ??
              '')
          .toString()
          .trim(),
      operatorWorkNo: (json['operator_work_no'] ?? json['work_no'] ?? json['workNo'] ?? json['closed_by_work_no'])?.toString(),
      operatorJobTitle: (json['operator_job_title'] ?? json['job_title'] ?? json['jobTitle'])?.toString(),
      reviewerName: (json['reviewer_name'] ??
              json['reviewerName'] ??
              json['reviewed_by_name'] ??
              json['approved_by_name'] ??
              json['approvedByName'] ??
              '')
          .toString()
          .trim(),
      reviewerJobTitle: (json['reviewer_job_title'] ?? json['reviewerJobTitle'])?.toString(),
      dailyDetail: () {
        final dailyRaw = json['daily_report'] ?? json['dailyReport'] ?? json['report'];
        if (dailyRaw is Map) {
          return DailyReport.fromJson(dailyRaw.cast<String, Object?>());
        }
        if (json.containsKey('summary') || json.containsKey('paymentChannels')) {
          return DailyReport.fromJson(json);
        }
        return null;
      }(),
      receivableSummary: () {
        final recRaw = json['receivable_summary'] ?? json['receivableSummary'];
        if (recRaw != null) {
          return DailyReportReceivableSummary.fromJson(recRaw);
        }
        return null;
      }(),
      totalCollections: () {
        final totalCollFen = _safeInt(json['total_collections_fen'] ?? json['totalCollectionsFen']);
        if (json['total_collections'] != null || json['totalCollections'] != null) {
          return safeMoney(json['total_collections'] ?? json['totalCollections']);
        }
        if (totalCollFen > 0) {
          return totalCollFen / 100.0;
        }
        return null;
      }(),
    );
  }
}

class CashierZReportHistoryItem {
  const CashierZReportHistoryItem({
    this.id,
    this.snapshotNo = '',
    required this.businessDay,
    this.netSales = 0,
    this.orderCount = 0,
    this.snapshotHash,
    this.closedAt,
    this.watermarks = const {},
    this.closeState = 'CLOSED',
    this.canClose = false,
    this.isNextCloseBusinessDay = false,
  });

  /// 快照主键 ID；待日结（PENDING）项尚未产生快照，此时为 null (WI-068)
  final int? id;
  final String snapshotNo;
  final String businessDay;
  final double netSales;
  final int orderCount;
  final String? snapshotHash;
  final DateTime? closedAt;
  final Map<String, Object?> watermarks;

  /// 日结状态：CLOSED（已结）、PENDING（待日结）、REOPENED（已重开）
  final String closeState;

  /// 是否允许对该营业日执行日结（仅服务端权威 next_close_business_day 为 true）
  final bool canClose;

  /// 是否为最早待关账营业日
  final bool isNextCloseBusinessDay;

  factory CashierZReportHistoryItem.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final closeState = (json['close_state'] ??
            json['closeState'] ??
            (rawId != null ? 'CLOSED' : 'PENDING'))
        .toString();
    return CashierZReportHistoryItem(
      id: _nullableInt(rawId),
      snapshotNo: '${json['snapshot_no'] ?? json['snapshotNo'] ?? ''}',
      businessDay: '${json['business_day'] ?? json['businessDay'] ?? ''}',
      netSales: safeFen(json['net_sales_fen'] ?? json['netSalesFen']),
      orderCount: _safeInt(json['order_count'] ?? json['orderCount']),
      snapshotHash: (json['snapshot_hash'] ?? json['snapshotHash'])?.toString(),
      closedAt: _date(json['closed_at'] ?? json['closedAt']),
      watermarks: _map(json['watermarks']),
      closeState: closeState,
      canClose: json['can_close'] == true || json['canClose'] == true,
      isNextCloseBusinessDay: json['is_next_close_business_day'] == true ||
          json['isNextCloseBusinessDay'] == true,
    );
  }
}

class CashierZReportHistoryPage {
  const CashierZReportHistoryPage({
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
    this.currentBusinessDay,
    this.nextCloseBusinessDay,
    this.pendingDayCount = 0,
  });

  final List<CashierZReportHistoryItem> items;
  final Object? nextCursor;
  final bool hasMore;
  final String? currentBusinessDay;
  final String? nextCloseBusinessDay;
  final int pendingDayCount;

  factory CashierZReportHistoryPage.fromJson(Map<String, Object?> json) =>
      CashierZReportHistoryPage(
        items: _list(
          json['items'],
        ).map(CashierZReportHistoryItem.fromJson).toList(growable: false),
        nextCursor: json['next_cursor'] ?? json['nextCursor'],
        hasMore: json['has_more'] == true || json['hasMore'] == true,
        currentBusinessDay:
            (json['current_business_day'] ?? json['currentBusinessDay'])?.toString(),
        nextCloseBusinessDay:
            (json['next_close_business_day'] ?? json['nextCloseBusinessDay'])?.toString(),
        pendingDayCount:
            _safeInt(json['pending_day_count'] ?? json['pendingDayCount']),
      );
}

/// 支付渠道显示名（byChannel 返回 payment_method 原始值）。
String cashierChannelLabel(String code, {String fallback = ''}) {
  final cleanCode = code.trim();
  final normalized = cleanCode.toLowerCase();
  return switch (normalized) {
    'wechat' || 'wxpay' || 'wechat_native' => '微信支付',
    'wechat_qr' || 'offline_wechat_qr' || 'wechat_code' || 'wechat_pay_code' =>
      '微信收款码',
    'alipay' || 'alipay_native' => '支付宝',
    'alipay_qr' || 'offline_alipay_qr' || 'alipay_code' || 'alipay_pay_code' =>
      '支付宝收款码',
    'cash' => '现金',
    'balance' => '余额',
    'gift' => '赠送金',
    _ =>
      fallback.trim().isNotEmpty
          ? fallback.trim()
          : (cleanCode.isEmpty ? '其他' : cleanCode),
  };
}

/// 支付渠道显示名（byChannel 返回 payment_method 原始值或稳定中文键）。
String dailyChannelLabel(String code) => cashierChannelLabel(code);

double safeMoney(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : 0;
}

double safeFen(Object? value) => safeMoney(value) / 100.0;

double _moneyOrFen(Object? money, Object? fen) =>
    money == null && fen != null ? safeFen(fen) : safeMoney(money);

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
