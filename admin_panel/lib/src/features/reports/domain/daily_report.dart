import 'package:flutter/foundation.dart';

/// 商业级营业日报领域模型 (对应 GET /admin/report/daily?detail=true)
@immutable
class DailyReport {
  const DailyReport({
    required this.totalAmount,
    required this.orderCount,
    required this.grossRevenue,
    required this.netRevenue,
    required this.totalDiscount,
    required this.totalRefund,
    this.totalCollectionsFen = 0,
    double? totalCollections,
    this.receivableSummary,
    required this.metadata,
    required this.summary,
    required this.paymentChannels,
    required this.cashDrawer,
    required this.orderTypes,
    required this.member,
    required this.exceptions,
    required this.topDishes,
    this.printableText,
  }) : totalCollections = totalCollections ?? netRevenue;

  final double totalAmount;
  final int orderCount;
  final double grossRevenue;
  final double netRevenue;
  final double totalDiscount;
  final double totalRefund;
  final int totalCollectionsFen;
  final double totalCollections;
  final DailyReportReceivableSummary? receivableSummary;

  final DailyReportMetadata metadata;
  final DailyReportSummary summary;
  final List<DailyReportChannel> paymentChannels;
  final DailyReportCashDrawer cashDrawer;
  final List<DailyReportOrderType> orderTypes;
  final DailyReportMember member;
  final DailyReportExceptions exceptions;
  final List<DailyReportTopDish> topDishes;
  final String? printableText;

  factory DailyReport.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    final net = d(m['netRevenue'] ?? m['totalAmount'] ?? m['revenue']);
    final gross = d(m['grossRevenue'] ?? net);
    final disc = d(m['totalDiscount'] ?? m['discountAmount']);
    final ref = d(m['totalRefund'] ?? m['refundAmount']);
    final cnt = i(m['orderCount']);
    final totalCollFen = i(m['totalCollectionsFen'] ?? m['total_collections_fen']);
    final totalColl = m['totalCollections'] != null || m['total_collections'] != null
        ? d(m['totalCollections'] ?? m['total_collections'])
        : (totalCollFen > 0 ? totalCollFen / 100.0 : net);
    final recRaw = m['receivableSummary'] ?? m['receivable_summary'];

    return DailyReport(
      totalAmount: net,
      orderCount: cnt,
      grossRevenue: gross,
      netRevenue: net,
      totalDiscount: disc,
      totalRefund: ref,
      totalCollectionsFen: totalCollFen,
      totalCollections: totalColl,
      receivableSummary: recRaw != null ? DailyReportReceivableSummary.fromJson(recRaw) : null,
      metadata: DailyReportMetadata.fromJson(m['metadata']),
      summary: DailyReportSummary.fromJson(m['summary'], fallbackNet: net, fallbackOrders: cnt),
      paymentChannels: (m['paymentChannels'] as List? ?? const [])
          .map((e) => DailyReportChannel.fromJson(e))
          .toList(),
      cashDrawer: DailyReportCashDrawer.fromJson(m['cashDrawer']),
      orderTypes: (m['orderTypes'] as List? ?? const [])
          .map((e) => DailyReportOrderType.fromJson(e))
          .toList(),
      member: DailyReportMember.fromJson(m['member']),
      exceptions: DailyReportExceptions.fromJson(m['exceptions']),
      topDishes: (m['topDishes'] as List? ?? const [])
          .map((e) => DailyReportTopDish.fromJson(e))
          .toList(),
      printableText: m['printableText'] as String?,
    );
  }
}

/// 营业日报挂账与应收对账模型 (v1.2.306 / WI-029)
@immutable
class DailyReportReceivableSummary {
  const DailyReportReceivableSummary({
    required this.chargedFen,
    required this.collectedFen,
    required this.writeoffFen,
    required this.reversedFen,
    required this.outstandingFen,
    required this.cutoffLedgerId,
  });

  final int chargedFen;
  final int collectedFen;
  final int writeoffFen;
  final int reversedFen;
  final int outstandingFen;
  final int cutoffLedgerId;

  double get chargedAmount => chargedFen / 100.0;
  double get collectedAmount => collectedFen / 100.0;
  double get writeoffAmount => writeoffFen / 100.0;
  double get reversedAmount => reversedFen / 100.0;
  double get outstandingAmount => outstandingFen / 100.0;

  factory DailyReportReceivableSummary.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return DailyReportReceivableSummary(
      chargedFen: i(m['chargedFen'] ?? m['charged_fen']),
      collectedFen: i(m['collectedFen'] ?? m['collected_fen']),
      writeoffFen: i(m['writeoffFen'] ?? m['writeoff_fen']),
      reversedFen: i(m['reversedFen'] ?? m['reversed_fen']),
      outstandingFen: i(m['outstandingFen'] ?? m['outstanding_fen']),
      cutoffLedgerId: i(m['cutoffLedgerId'] ?? m['cutoff_ledger_id']),
    );
  }
}

@immutable
class DailyReportMetadata {
  const DailyReportMetadata({
    required this.shopId,
    required this.shopName,
    required this.businessDay,
    required this.windowStart,
    required this.windowEnd,
    required this.generatedAt,
    required this.isSettled,
    required this.reportType,
    required this.operatorName,
    required this.snapshotNo,
    this.closedAt,
  });

  final int shopId;
  final String shopName;
  final String businessDay;
  final String windowStart;
  final String windowEnd;
  final String generatedAt;
  final bool isSettled;
  final String reportType;
  final String operatorName;
  final String snapshotNo;
  final String? closedAt;

  factory DailyReportMetadata.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return DailyReportMetadata(
      shopId: i(m['shopId']),
      shopName: m['shopName'] as String? ?? '收银门店',
      businessDay: m['businessDay'] as String? ?? '',
      windowStart: m['windowStart'] as String? ?? '',
      windowEnd: m['windowEnd'] as String? ?? '',
      generatedAt: m['generatedAt'] as String? ?? '',
      isSettled: m['isSettled'] == true,
      reportType: m['reportType'] as String? ?? (m['isSettled'] == true ? 'Z_REPORT' : 'X_REPORT'),
      operatorName: m['operatorName'] as String? ?? '系统实时',
      snapshotNo: m['snapshotNo'] as String? ?? '',
      closedAt: m['closedAt'] as String?,
    );
  }
}

@immutable
class DailyReportSummary {
  const DailyReportSummary({
    required this.grossRevenue,
    required this.totalDiscount,
    required this.netRevenue,
    required this.totalRefund,
    this.totalCollections,
    required this.orderCount,
    required this.dinerCount,
    required this.avgOrderAmount,
    required this.avgDinerAmount,
    required this.tableTurnoverRate,
  });

  final double grossRevenue;
  final double totalDiscount;
  final double netRevenue;
  final double totalRefund;
  final double? totalCollections;
  final int orderCount;
  final int dinerCount;
  final double avgOrderAmount;
  final double avgDinerAmount;
  final double tableTurnoverRate;

  factory DailyReportSummary.fromJson(Object? raw, {double fallbackNet = 0, int fallbackOrders = 0}) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    final net = d(m['netRevenue'] ?? fallbackNet);
    final cnt = i(m['orderCount'] ?? fallbackOrders);
    final diners = i(m['dinerCount']);

    return DailyReportSummary(
      grossRevenue: d(m['grossRevenue']),
      totalDiscount: d(m['totalDiscount']),
      netRevenue: net,
      totalRefund: d(m['totalRefund']),
      totalCollections: m['totalCollections'] != null || m['total_collections'] != null
          ? d(m['totalCollections'] ?? m['total_collections'])
          : null,
      orderCount: cnt,
      dinerCount: diners > 0 ? diners : cnt,
      avgOrderAmount: d(m['avgOrderAmount'] ?? (cnt > 0 ? net / cnt : 0)),
      avgDinerAmount: d(m['avgDinerAmount'] ?? (diners > 0 ? net / diners : 0)),
      tableTurnoverRate: d(m['tableTurnoverRate']),
    );
  }
}

@immutable
class DailyReportChannel {
  const DailyReportChannel({
    required this.channelCode,
    required this.channelLabel,
    required this.amount,
    required this.orderCount,
    required this.refundCount,
    required this.percentage,
  });

  final String channelCode;
  final String channelLabel;
  final double amount;
  final int orderCount;
  final int refundCount;
  final double percentage;

  factory DailyReportChannel.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportChannel(
      channelCode: m['channelCode'] as String? ?? 'other',
      channelLabel: m['channelLabel'] as String? ?? '其他',
      amount: d(m['amount']),
      orderCount: i(m['orderCount']),
      refundCount: i(m['refundCount']),
      percentage: d(m['percentage']),
    );
  }
}

@immutable
class DailyReportCashDrawer {
  const DailyReportCashDrawer({
    required this.openingFloat,
    required this.cashIn,
    required this.cashRefund,
    required this.cashOut,
    required this.theoreticalCash,
    required this.countedCash,
    required this.variance,
    required this.sessionCount,
  });

  final double openingFloat;
  final double cashIn;
  final double cashRefund;
  final double cashOut;
  final double theoreticalCash;
  final double countedCash;
  final double variance;
  final int sessionCount;

  factory DailyReportCashDrawer.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportCashDrawer(
      openingFloat: d(m['openingFloat']),
      cashIn: d(m['cashIn']),
      cashRefund: d(m['cashRefund']),
      cashOut: d(m['cashOut']),
      theoreticalCash: d(m['theoreticalCash']),
      countedCash: d(m['countedCash']),
      variance: d(m['variance']),
      sessionCount: i(m['sessionCount']),
    );
  }
}

@immutable
class DailyReportOrderType {
  const DailyReportOrderType({
    required this.type,
    required this.label,
    required this.orderCount,
    required this.amount,
    required this.percentage,
  });

  final String type;
  final String label;
  final int orderCount;
  final double amount;
  final double percentage;

  factory DailyReportOrderType.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportOrderType(
      type: m['type'] as String? ?? '',
      label: m['label'] as String? ?? '',
      orderCount: i(m['orderCount']),
      amount: d(m['amount']),
      percentage: d(m['percentage']),
    );
  }
}

@immutable
class DailyReportMember {
  const DailyReportMember({
    required this.rechargeTotal,
    required this.rechargePrincipal,
    required this.rechargeGift,
    required this.rechargeCount,
    required this.memberConsumption,
    required this.newMembers,
  });

  final double rechargeTotal;
  final double rechargePrincipal;
  final double rechargeGift;
  final int rechargeCount;
  final double memberConsumption;
  final int newMembers;

  factory DailyReportMember.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportMember(
      rechargeTotal: d(m['rechargeTotal']),
      rechargePrincipal: d(m['rechargePrincipal']),
      rechargeGift: d(m['rechargeGift']),
      rechargeCount: i(m['rechargeCount']),
      memberConsumption: d(m['memberConsumption']),
      newMembers: i(m['newMembers']),
    );
  }
}

@immutable
class DailyReportExceptions {
  const DailyReportExceptions({
    required this.uncheckoutCount,
    required this.uncheckoutAmount,
    required this.refundCount,
    required this.refundAmount,
    required this.discountAmount,
    required this.freeDishesCount,
    required this.freeDishesAmount,
  });

  final int uncheckoutCount;
  final double uncheckoutAmount;
  final int refundCount;
  final double refundAmount;
  final double discountAmount;
  final int freeDishesCount;
  final double freeDishesAmount;

  factory DailyReportExceptions.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportExceptions(
      uncheckoutCount: i(m['uncheckoutCount']),
      uncheckoutAmount: d(m['uncheckoutAmount']),
      refundCount: i(m['refundCount']),
      refundAmount: d(m['refundAmount']),
      discountAmount: d(m['discountAmount']),
      freeDishesCount: i(m['freeDishesCount']),
      freeDishesAmount: d(m['freeDishesAmount']),
    );
  }
}

@immutable
class DailyReportTopDish {
  const DailyReportTopDish({
    required this.rank,
    required this.dishName,
    required this.quantity,
    required this.amount,
    required this.percentage,
  });

  final int rank;
  final String dishName;
  final int quantity;
  final double amount;
  final double percentage;

  factory DailyReportTopDish.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    return DailyReportTopDish(
      rank: i(m['rank']),
      dishName: m['dishName'] as String? ?? '',
      quantity: i(m['quantity']),
      amount: d(m['amount']),
      percentage: d(m['percentage']),
    );
  }
}
