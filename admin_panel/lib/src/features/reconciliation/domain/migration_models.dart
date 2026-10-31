/// 历史账本回填与双写影子切读模型 (POS-SDC-501 & POS-SDC-502)
class BackfillReport {
  final bool dryRun;
  final int? shopId;
  final String? statDate;
  final int totalOrdersScanned;
  final int backfilledOrders;
  final int skippedOrders;
  final int totalRowsInserted;
  final int totalAmountFen;
  final Map<String, int> channelTotalsFen;
  final int anomaliesCount;
  final List<Map<String, dynamic>> anomalies;
  final String integrityHash;
  final String executedAt;

  const BackfillReport({
    required this.dryRun,
    this.shopId,
    this.statDate,
    required this.totalOrdersScanned,
    required this.backfilledOrders,
    required this.skippedOrders,
    required this.totalRowsInserted,
    required this.totalAmountFen,
    required this.channelTotalsFen,
    required this.anomaliesCount,
    required this.anomalies,
    required this.integrityHash,
    required this.executedAt,
  });

  factory BackfillReport.fromJson(Map<String, dynamic> json) {
    final rawTotals = json['channel_totals_fen'] as Map<String, dynamic>? ?? {};
    final totals = <String, int>{};
    rawTotals.forEach((k, v) {
      totals[k] = (v as num?)?.toInt() ?? 0;
    });

    final rawAnomalies = (json['anomalies'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    return BackfillReport(
      dryRun: json['dry_run'] == true,
      shopId: json['shop_id'] as int?,
      statDate: json['stat_date'] as String?,
      totalOrdersScanned: (json['total_orders_scanned'] as num?)?.toInt() ?? 0,
      backfilledOrders: (json['backfilled_orders'] as num?)?.toInt() ?? 0,
      skippedOrders: (json['skipped_orders'] as num?)?.toInt() ?? 0,
      totalRowsInserted: (json['total_rows_inserted'] as num?)?.toInt() ?? 0,
      totalAmountFen: (json['total_amount_fen'] as num?)?.toInt() ?? 0,
      channelTotalsFen: totals,
      anomaliesCount: (json['anomalies_count'] as num?)?.toInt() ?? 0,
      anomalies: rawAnomalies,
      integrityHash: json['integrity_hash'] as String? ?? '',
      executedAt: json['executed_at'] as String? ?? '',
    );
  }
}

class ShadowVerifyResult {
  final int shopId;
  final String statDate;
  final bool readyForCutover;
  final int netVarianceFen;
  final int discrepancyCount;
  final List<Map<String, dynamic>> discrepancies;
  final Map<String, dynamic> legacyOrderSummary;
  final Map<String, dynamic> ledgerSummary;
  final Map<String, dynamic> channelVariances;

  const ShadowVerifyResult({
    required this.shopId,
    required this.statDate,
    required this.readyForCutover,
    required this.netVarianceFen,
    required this.discrepancyCount,
    required this.discrepancies,
    required this.legacyOrderSummary,
    required this.ledgerSummary,
    required this.channelVariances,
  });

  factory ShadowVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawDiscrepancies = (json['discrepancies'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    return ShadowVerifyResult(
      shopId: (json['shop_id'] as num?)?.toInt() ?? 0,
      statDate: json['stat_date'] as String? ?? '',
      readyForCutover: json['ready_for_cutover'] == true,
      netVarianceFen: (json['net_variance_fen'] as num?)?.toInt() ?? 0,
      discrepancyCount: (json['discrepancy_count'] as num?)?.toInt() ?? 0,
      discrepancies: rawDiscrepancies,
      legacyOrderSummary: Map<String, dynamic>.from(json['legacy_order_summary'] as Map? ?? {}),
      ledgerSummary: Map<String, dynamic>.from(json['ledger_summary'] as Map? ?? {}),
      channelVariances: Map<String, dynamic>.from(json['channel_variances'] as Map? ?? {}),
    );
  }
}

class CutoverStatus {
  final int? shopId;
  final String currentReadSource;
  final bool isCutoverToLedger;
  final int totalLedgerRows;
  final int nativeRows;
  final int backfilledRows;
  final Map<String, dynamic>? lastBackfillLog;

  const CutoverStatus({
    this.shopId,
    required this.currentReadSource,
    required this.isCutoverToLedger,
    required this.totalLedgerRows,
    required this.nativeRows,
    required this.backfilledRows,
    this.lastBackfillLog,
  });

  factory CutoverStatus.fromJson(Map<String, dynamic> json) {
    return CutoverStatus(
      shopId: json['shop_id'] as int?,
      currentReadSource: json['current_read_source'] as String? ?? 'PAYMENT_LEDGER',
      isCutoverToLedger: json['is_cutover_to_ledger'] == true,
      totalLedgerRows: (json['total_ledger_rows'] as num?)?.toInt() ?? 0,
      nativeRows: (json['native_rows'] as num?)?.toInt() ?? 0,
      backfilledRows: (json['backfilled_rows'] as num?)?.toInt() ?? 0,
      lastBackfillLog: json['last_backfill_log'] != null
          ? Map<String, dynamic>.from(json['last_backfill_log'] as Map)
          : null,
    );
  }
}
