import 'package:flutter/foundation.dart';

/// 对账全景概览模型
@immutable
class ReconciliationOverview {
  const ReconciliationOverview({
    required this.businessDay,
    required this.shopId,
    required this.shopName,
    required this.hasChannelStatement,
    required this.summaryStatus,
    required this.openCasesCount,
    required this.totalCasesCount,
    required this.batchesCount,
    required this.layer1,
    required this.layer2,
    required this.layer3,
  });

  final String businessDay;
  final int shopId;
  final String shopName;
  final bool hasChannelStatement;
  /// UNIMPORTED, DISCREPANCY, RECONCILED
  final String summaryStatus;
  final int openCasesCount;
  final int totalCasesCount;
  final int batchesCount;
  final ReconciliationLayer1 layer1;
  final ReconciliationLayer2 layer2;
  final ReconciliationLayer3 layer3;

  factory ReconciliationOverview.fromJson(Map<String, dynamic> json) {
    return ReconciliationOverview(
      businessDay: json['business_day']?.toString() ?? '',
      shopId: (json['shop_id'] as num?)?.toInt() ?? 0,
      shopName: json['shop_name']?.toString() ?? '',
      hasChannelStatement: json['has_channel_statement'] == true,
      summaryStatus: json['summary_status']?.toString() ?? 'UNIMPORTED',
      openCasesCount: (json['open_cases_count'] as num?)?.toInt() ?? 0,
      totalCasesCount: (json['total_cases_count'] as num?)?.toInt() ?? 0,
      batchesCount: (json['batches_count'] as num?)?.toInt() ?? 0,
      layer1: ReconciliationLayer1.fromJson(json['layer1'] as Map<String, dynamic>? ?? {}),
      layer2: ReconciliationLayer2.fromJson(json['layer2'] as Map<String, dynamic>? ?? {}),
      layer3: ReconciliationLayer3.fromJson(json['layer3'] as Map<String, dynamic>? ?? {}),
    );
  }
}

/// 第一层：订单 vs 内部支付台账
@immutable
class ReconciliationLayer1 {
  const ReconciliationLayer1({
    required this.layer,
    required this.name,
    required this.orderCount,
    required this.orderNetSalesFen,
    required this.ledgerCount,
    required this.ledgerNetAmountFen,
    required this.differenceFen,
    required this.balanced,
  });

  final int layer;
  final String name;
  final int orderCount;
  final int orderNetSalesFen;
  final int ledgerCount;
  final int ledgerNetAmountFen;
  final int differenceFen;
  final bool balanced;

  double get orderNetSalesYuan => orderNetSalesFen / 100.0;
  double get ledgerNetAmountYuan => ledgerNetAmountFen / 100.0;
  double get differenceYuan => differenceFen / 100.0;

  factory ReconciliationLayer1.fromJson(Map<String, dynamic> json) {
    return ReconciliationLayer1(
      layer: (json['layer'] as num?)?.toInt() ?? 1,
      name: json['name']?.toString() ?? '订单与内部台账核对',
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
      orderNetSalesFen: (json['order_net_sales_fen'] as num?)?.toInt() ?? 0,
      ledgerCount: (json['ledger_count'] as num?)?.toInt() ?? 0,
      ledgerNetAmountFen: (json['ledger_net_amount_fen'] as num?)?.toInt() ?? 0,
      differenceFen: (json['difference_fen'] as num?)?.toInt() ?? 0,
      balanced: json['balanced'] == true,
    );
  }
}

/// 第二层：内部支付台账 vs 渠道对账单
@immutable
class ReconciliationLayer2 {
  const ReconciliationLayer2({
    required this.layer,
    required this.name,
    required this.hasStatement,
    this.status,
    this.message,
    required this.channelTradeCount,
    required this.channelTotalAmountFen,
    required this.matchedCount,
    required this.amountMismatchCount,
    required this.unmatchedInternalCount,
    required this.unmatchedChannelCount,
    required this.differenceFen,
  });

  final int layer;
  final String name;
  final bool hasStatement;
  final String? status;
  final String? message;
  final int channelTradeCount;
  final int channelTotalAmountFen;
  final int matchedCount;
  final int amountMismatchCount;
  final int unmatchedInternalCount;
  final int unmatchedChannelCount;
  final int differenceFen;

  double get channelTotalAmountYuan => channelTotalAmountFen / 100.0;
  double get differenceYuan => differenceFen / 100.0;

  factory ReconciliationLayer2.fromJson(Map<String, dynamic> json) {
    return ReconciliationLayer2(
      layer: (json['layer'] as num?)?.toInt() ?? 2,
      name: json['name']?.toString() ?? '内部台账与渠道账单核对',
      hasStatement: json['has_statement'] == true,
      status: json['status']?.toString(),
      message: json['message']?.toString(),
      channelTradeCount: (json['channel_trade_count'] as num?)?.toInt() ?? 0,
      channelTotalAmountFen: (json['channel_total_amount_fen'] as num?)?.toInt() ?? 0,
      matchedCount: (json['matched_count'] as num?)?.toInt() ?? 0,
      amountMismatchCount: (json['amount_mismatch_count'] as num?)?.toInt() ?? 0,
      unmatchedInternalCount: (json['unmatched_internal_count'] as num?)?.toInt() ?? 0,
      unmatchedChannelCount: (json['unmatched_channel_count'] as num?)?.toInt() ?? 0,
      differenceFen: (json['difference_fen'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 第三层：渠道账单 vs 扣费到账净额
@immutable
class ReconciliationLayer3 {
  const ReconciliationLayer3({
    required this.layer,
    required this.name,
    required this.channelGrossFen,
    required this.feeFen,
    required this.netSettlementFen,
  });

  final int layer;
  final String name;
  final int channelGrossFen;
  final int feeFen;
  final int netSettlementFen;

  double get channelGrossYuan => channelGrossFen / 100.0;
  double get feeYuan => feeFen / 100.0;
  double get netSettlementYuan => netSettlementFen / 100.0;

  factory ReconciliationLayer3.fromJson(Map<String, dynamic> json) {
    return ReconciliationLayer3(
      layer: (json['layer'] as num?)?.toInt() ?? 3,
      name: json['name']?.toString() ?? '渠道账单与资金结算核对',
      channelGrossFen: (json['channel_gross_fen'] as num?)?.toInt() ?? 0,
      feeFen: (json['fee_fen'] as num?)?.toInt() ?? 0,
      netSettlementFen: (json['net_settlement_fen'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 渠道对账导入批次
@immutable
class ChannelStatementBatch {
  const ChannelStatementBatch({
    required this.id,
    required this.batchNo,
    required this.shopId,
    required this.channel,
    required this.statementDate,
    required this.fileName,
    required this.fileHashSha256,
    required this.totalCount,
    required this.totalAmountFen,
    required this.feeFen,
    required this.netAmountFen,
    required this.status,
    this.errorSummary,
    this.importedAt,
  });

  final int id;
  final String batchNo;
  final int shopId;
  final String channel;
  final String statementDate;
  final String fileName;
  final String fileHashSha256;
  final int totalCount;
  final int totalAmountFen;
  final int feeFen;
  final int netAmountFen;
  final String status;
  final String? errorSummary;
  final String? importedAt;

  double get totalAmountYuan => totalAmountFen / 100.0;
  double get feeYuan => feeFen / 100.0;
  double get netAmountYuan => netAmountFen / 100.0;

  factory ChannelStatementBatch.fromJson(Map<String, dynamic> json) {
    return ChannelStatementBatch(
      id: (json['id'] as num?)?.toInt() ?? 0,
      batchNo: json['batch_no']?.toString() ?? '',
      shopId: (json['shop_id'] as num?)?.toInt() ?? 0,
      channel: json['channel']?.toString() ?? '',
      statementDate: json['statement_date']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileHashSha256: json['file_hash_sha256']?.toString() ?? '',
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      totalAmountFen: (json['total_amount_fen'] as num?)?.toInt() ?? 0,
      feeFen: (json['fee_fen'] as num?)?.toInt() ?? 0,
      netAmountFen: (json['net_amount_fen'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'PARSED',
      errorSummary: json['error_summary']?.toString(),
      importedAt: json['imported_at']?.toString(),
    );
  }
}

/// 对账差异处理单
@immutable
class ReconciliationCase {
  const ReconciliationCase({
    required this.id,
    required this.caseNo,
    required this.shopId,
    required this.businessDay,
    required this.channel,
    required this.layer,
    required this.discrepancyType,
    required this.status,
    this.orderId,
    this.ledgerId,
    this.statementEntryId,
    required this.internalAmountFen,
    required this.channelAmountFen,
    required this.differenceFen,
    this.reason,
    this.resolutionNote,
    this.responsiblePerson,
    this.resolvedAt,
    this.createdAt,
  });

  final int id;
  final String caseNo;
  final int shopId;
  final String businessDay;
  final String channel;
  final int layer;
  final String discrepancyType;
  /// OPEN, INVESTIGATING, ADJUSTED, WRITTEN_OFF, CLOSED
  final String status;
  final int? orderId;
  final int? ledgerId;
  final int? statementEntryId;
  final int internalAmountFen;
  final int channelAmountFen;
  final int differenceFen;
  final String? reason;
  final String? resolutionNote;
  final String? responsiblePerson;
  final String? resolvedAt;
  final String? createdAt;

  double get internalAmountYuan => internalAmountFen / 100.0;
  double get channelAmountYuan => channelAmountFen / 100.0;
  double get differenceYuan => differenceFen / 100.0;

  bool get isOpen => status != 'CLOSED';

  factory ReconciliationCase.fromJson(Map<String, dynamic> json) {
    return ReconciliationCase(
      id: (json['id'] as num?)?.toInt() ?? 0,
      caseNo: json['case_no']?.toString() ?? '',
      shopId: (json['shop_id'] as num?)?.toInt() ?? 0,
      businessDay: json['business_day']?.toString() ?? '',
      channel: json['channel']?.toString() ?? '',
      layer: (json['layer'] as num?)?.toInt() ?? 1,
      discrepancyType: json['discrepancy_type']?.toString() ?? '',
      status: json['status']?.toString() ?? 'OPEN',
      orderId: (json['order_id'] as num?)?.toInt(),
      ledgerId: (json['ledger_id'] as num?)?.toInt(),
      statementEntryId: (json['statement_entry_id'] as num?)?.toInt(),
      internalAmountFen: (json['internal_amount_fen'] as num?)?.toInt() ?? 0,
      channelAmountFen: (json['channel_amount_fen'] as num?)?.toInt() ?? 0,
      differenceFen: (json['difference_fen'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString(),
      resolutionNote: json['resolution_note']?.toString(),
      responsiblePerson: json['responsible_person']?.toString(),
      resolvedAt: json['resolved_at']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}
