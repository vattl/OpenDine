import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/cashier_operation_audit.dart';
import '../../reports/domain/daily_report.dart';
import '../domain/cashier_shift.dart';
import 'cashier_shift_repository.dart';

class RealCashierShiftRepository implements CashierShiftRepository {
  const RealCashierShiftRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierShift?> loadCurrentShift() async {
    final response = await client.get(cashierShiftCurrentEndpoint);
    final map = _map(response);
    final rawShift = map.containsKey('shift') ? map['shift'] : response;
    if (rawShift == null) return null;
    final shift = _map(rawShift);
    return shift.isEmpty ? null : CashierShift.fromJson(shift);
  }

  @override
  Future<CashierShiftWorkbenchData> loadWorkbench({int? shopId}) async {
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(cashierShiftWorkbenchEndpoint);
    return CashierShiftWorkbenchData.fromJson(_map(response));
  }

  @override
  Future<CashierTodayReport> loadTodayReport({int? shopId}) async {
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(reportDashboardEndpoint);
    return CashierTodayReport.fromJson(_map(response));
  }

  @override
  Future<CashierShift> startShift({
    required double startCash,
    int? shopId,
    String? idempotencyKey,
  }) async {
    await client.post(
      cashierShiftStartEndpoint,
      body: {
        'start_cash': startCash,
        'openingFloatFen': (startCash * 100).round(),
        if (shopId != null) 'shop_id': shopId,
        if (idempotencyKey?.isNotEmpty == true)
          'idempotency_key': idempotencyKey,
      },
    );
    final shift = await loadCurrentShift();
    if (shift == null) {
      throw const FormatException('开班成功，但未能读取当前班次');
    }
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shift',
        action: 'open',
        result: 'success',
        shopId: shopId,
        targetType: 'shift',
        targetId: '${shift.id}',
        amountFen: (startCash * 100).round(),
      ),
    );
    return shift;
  }

  @override
  Future<CashierHandoverResult> handover({
    required double endCash,
    double? countedCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    int? shopId,
    String? idempotencyKey,
  }) async {
    final response = await client.post(
      cashierShiftHandoverEndpoint,
      body: {
        'end_cash': endCash,
        'countedCashFen': ((countedCash ?? endCash) * 100).round(),
        if (countedCash != null) 'counted_cash': countedCash,
        if (varianceReasonCode != null)
          'variance_reason_code': varianceReasonCode,
        if (varianceNote != null) 'variance_note': varianceNote,
        if (approvedBy != null) 'approved_by': approvedBy,
        if (shopId != null) 'shop_id': shopId,
        if (idempotencyKey?.isNotEmpty == true)
          'idempotency_key': idempotencyKey,
      },
    );
    final result = CashierHandoverResult.fromJson(_map(response));
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shift',
        action: 'handover',
        result: 'success',
        shopId: shopId,
        amountFen: (endCash * 100).round(),
      ),
    );
    return result;
  }

  @override
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String? reasonCode,
    String? remark,
    int? approverId,
    int? shopId,
    String? idempotencyKey,
  }) async {
    await client.post(
      cashierShiftCashMovementEndpoint,
      body: {
        'movement_type': movementType,
        'amount': amount,
        'amount_fen': (amount * 100).round(),
        if (reasonCode != null) 'reason_code': reasonCode,
        if (remark != null) 'remark': remark,
        if (approverId != null) 'approver_id': approverId,
        if (shopId != null) 'shop_id': shopId,
        if (idempotencyKey?.isNotEmpty == true)
          'idempotency_key': idempotencyKey,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shift',
        action: 'cash_movement_$movementType'.toLowerCase(),
        result: 'success',
        shopId: shopId,
        amountFen: (amount * 100).round(),
      ),
    );
  }

  @override
  Future<ShiftSummaryReport> loadShiftReport(
    int sessionId, {
    int? shopId,
  }) async {
    final targetClient = shopId != null
        ? client.copyWith(shopId: shopId)
        : client;
    final response = await targetClient.get(
      cashierShiftReportEndpoint(sessionId),
    );
    final map = _map(response);
    final report = _map(map['report']);
    return ShiftSummaryReport.fromJson(report.isEmpty ? map : report);
  }

  @override
  Future<CashierShiftReportPage> loadShiftReports({
    int? shopId,
    int? cursor,
    int limit = 20,
  }) async {
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(
          cashierShiftReportsEndpoint,
          query: {
            if (cursor != null) 'cursor': cursor,
            'limit': limit.clamp(1, 100),
          },
        );
    return CashierShiftReportPage.fromJson(_map(response));
  }

  @override
  Future<CashierCashEventPage> loadCashEvents(
    int sessionId, {
    int? shopId,
    int? cursor,
    int limit = 20,
  }) async {
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(
          cashierShiftCashEventsEndpoint(sessionId),
          query: {
            if (cursor != null) 'cursor': cursor,
            'limit': limit.clamp(1, 100),
          },
        );
    return CashierCashEventPage.fromJson(_map(response));
  }

  @override
  Future<CashierDailySummary> loadDailySummary({
    String? statDate,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final targetClient = shopId != null ? client.copyWith(shopId: shopId) : client;
    try {
      final response = await targetClient.get(
        dailySummaryEndpoint,
        query: {
          if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate,
        },
      );
      final map = _map(response);
      final summary = _map(map['summary']);
      return CashierDailySummary(
        statDate: summary['stat_date']?.toString() ?? cleanDate ?? '',
        totalAmount: safeMoney(
          summary['total_amount'] ?? summary['totalAmount'] ?? map['income'],
        ),
        discountAmount: safeMoney(
          summary['discount_amount'] ?? summary['discountAmount'] ?? map['deduction'],
        ),
        refundAmount: safeMoney(
          summary['refund_amount'] ?? summary['refundAmount'],
        ),
        settled: summary['settled'] == true ||
            summary['settled_at'] != null ||
            summary['settledAt'] != null,
        settledAt: _date(summary['settled_at'] ?? summary['settledAt']),
      );
    } catch (_) {
      final context = await loadDailyContext(
        statDate: cleanDate,
        shopId: shopId,
      );
      final resolvedDate = context.statDate.isNotEmpty ? context.statDate : (context.summary['stat_date']?.toString() ?? cleanDate ?? '');
      final summary = context.summary;
      return CashierDailySummary(
        statDate: resolvedDate,
        totalAmount: safeMoney(
          summary['gross_sales'] ??
              (summary['gross_sales_fen'] != null ? safeFen(summary['gross_sales_fen']) : null) ??
              summary['total_amount'] ??
              summary['net_sales'],
        ),
        discountAmount: safeMoney(
          summary['discount_amount'] ??
              (summary['discount_amount_fen'] != null ? safeFen(summary['discount_amount_fen']) : null),
        ),
        refundAmount: safeMoney(
          summary['refund_amount'] ??
              (summary['refund_amount_fen'] != null ? safeFen(summary['refund_amount_fen']) : null),
        ),
        settled: context.isAlreadySettled ||
            summary['settled'] == true ||
            summary['settled_at'] != null,
        settledAt: _date(summary['settled_at'] ?? summary['settledAt']),
        channels: context.channels,
      );
    }
  }

  @override
  Future<Map<String, double>> loadDailyChannels({
    String? statDate,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final targetClient = shopId != null ? client.copyWith(shopId: shopId) : client;
    try {
      final response = await targetClient.get(
        dailyByChannelEndpoint,
        query: {
          if (cleanDate != null && cleanDate.isNotEmpty) 'date': cleanDate,
        },
      );
      final map = _map(response);
      final raw = map['channels'];
      final result = <String, double>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          result['$key'] = safeMoney(value);
        });
      }
      return result;
    } catch (_) {
      try {
        final context = await loadDailyContext(
          statDate: cleanDate,
          shopId: shopId,
        );
        return context.channels;
      } catch (_) {
        return const {};
      }
    }
  }

  @override
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
    String? idempotencyKey,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.post(
      dailySettleEndpoint,
      body: {
        if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate,
        if (shopId != null) 'shop_id': shopId,
        if (precheckToken != null && precheckToken.isNotEmpty)
          'precheck_token': precheckToken,
        if (password != null && password.isNotEmpty) 'password': password,
        if (force) 'force': true,
        if (idempotencyKey?.isNotEmpty == true)
          'idempotency_key': idempotencyKey,
      },
    );
    final map = _map(response);
    final stat = _map(map['dailyStat']);
    final snapshot = _map(map['snapshot']);
    final settledAt = _date(
      stat['settled_at'] ?? stat['settledAt'] ?? snapshot['closed_at'],
    );
    final rawDate =
        snapshot['business_day']?.toString() ??
        stat['stat_date']?.toString() ??
        stat['statDate']?.toString() ??
        statDate ??
        '';
    final resolvedDate = _cleanDate(rawDate) ?? rawDate;
    final result = CashierDailySettleResult(
      statDate: resolvedDate,
      totalAmount: safeMoney(
        stat['total_amount'] ??
            stat['totalAmount'] ??
            (snapshot['net_sales_fen'] != null
                ? (safeMoney(snapshot['net_sales_fen']) / 100.0)
                : 0),
      ),
      discountAmount: safeMoney(
        stat['discount_amount'] ??
            stat['discountAmount'] ??
            (snapshot['discount_amount_fen'] != null
                ? (safeMoney(snapshot['discount_amount_fen']) / 100.0)
                : 0),
      ),
      refundAmount: safeMoney(
        stat['refund_amount'] ??
            stat['refundAmount'] ??
            (snapshot['refund_amount_fen'] != null
                ? (safeMoney(snapshot['refund_amount_fen']) / 100.0)
                : 0),
      ),
      settledAt: settledAt ?? DateTime.now(),
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shift',
        action: 'daily_close',
        result: 'success',
        shopId: shopId,
        targetType: 'shift',
        targetId: resolvedDate.isNotEmpty ? resolvedDate : 'current_shift',
      ),
    );
    return result;
  }

  static final Map<String, Future<DailyPrecheckResult>> _dailyContextInFlight = {};

  @override
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) {
    final cleanDate = _cleanDate(statDate);
    final key = '$shopId:$cleanDate:$minutes';
    final existing = _dailyContextInFlight[key];
    if (existing != null) {
      return existing;
    }
    final future = () async {
      try {
        final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
            .get(
              dailyContextEndpoint,
              query: {
                if (cleanDate != null && cleanDate.isNotEmpty)
                  'stat_date': cleanDate,
                if (minutes != null && minutes > 0) 'minutes': minutes,
              },
            );
        return DailyPrecheckResult.fromJson(_map(response));
      } finally {
        _dailyContextInFlight.remove(key);
      }
    }();
    _dailyContextInFlight[key] = future;
    return future;
  }

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => loadDailyContext(statDate: statDate, shopId: shopId, minutes: minutes);

  @override
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int? shopId,
    int? minutes,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .post(
          dailyVoidStaleTakeoutEndpoint,
          body: {
            if (cleanDate != null && cleanDate.isNotEmpty)
              'stat_date': cleanDate,
            if (minutes != null && minutes > 0) 'minutes': minutes,
          },
        );
    final map = _map(response);
    final data = map['data'] is Map ? _map(map['data']) : map;
    final result = VoidStaleTakeoutResult.fromJson(data);

    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'daily',
        action: 'void_stale_takeout',
        result: 'success',
        shopId: shopId,
        targetType: 'daily',
        targetId: statDate ?? '',
        detail: {
          'voided_count': result.voidedCount,
          'voided_amount': result.voidedAmount,
          'threshold_minutes': result.thresholdMinutes,
          'voided_order_nos': result.voidedOrderNos,
        },
      ),
    );
    return result;
  }

  @override
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId}) async {
    final cleanDate = _cleanDate(statDate);
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(
          dailyZReportEndpoint,
          query: {
            if (cleanDate != null && cleanDate.isNotEmpty)
              'stat_date': cleanDate,
          },
        );
    final map = _map(response);
    final zReport = _map(map['zReport']);
    var report = CommercialZReport.fromJson(zReport.isNotEmpty ? zReport : map);

    // If report doesn't already have dailyDetail, attempt to fetch from reportDailyEndpoint
    if (report.dailyDetail == null && (cleanDate != null || report.businessDay.isNotEmpty)) {
      try {
        final queryDate = cleanDate ?? report.businessDay;
        final dailyResp = await (shopId != null ? client.copyWith(shopId: shopId) : client)
            .get(
              reportDailyEndpoint,
              query: {
                'date': queryDate,
                'detail': 'true',
              },
            );
        final dailyMap = _map(dailyResp);
        final reportPayload = dailyMap['report'] ?? dailyMap['data'] ?? dailyMap;
        if (reportPayload is Map) {
          final detail = DailyReport.fromJson(reportPayload.cast<String, Object?>());
          report = report.copyWith(
            dailyDetail: detail,
            printableText: (report.printableText.isEmpty && detail.printableText != null)
                ? detail.printableText!
                : report.printableText,
          );
        }
      } catch (_) {
        // Fallback silently if reportDailyEndpoint is unavailable
      }
    }
    return report;
  }

  @override
  Future<CashierZReportHistoryPage> loadZReports({
    int? shopId,
    String? dateFrom,
    String? dateTo,
    Object? cursor,
    int limit = 20,
  }) async {
    final response = await (shopId != null ? client.copyWith(shopId: shopId) : client)
        .get(
          dailyZReportsEndpoint,
          query: {
            if (_cleanDate(dateFrom) case final value?) 'date_from': value,
            if (_cleanDate(dateTo) case final value?) 'date_to': value,
            if (cursor != null) 'cursor': cursor.toString(),
            'limit': limit.clamp(1, 100),
          },
        );
    return CashierZReportHistoryPage.fromJson(_map(response));
  }

  @override
  Future<Map<String, Object?>> reopenDaily({
    String? statDate,
    int? shopId,
    required String password,
    required String reason,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.post(
      dailyReopenEndpoint,
      body: {
        if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate,
        if (shopId != null) 'shop_id': shopId,
        'password': password,
        'reason': reason,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shift',
        action: 'daily_reopen',
        result: 'success',
        shopId: shopId,
        targetType: 'shift',
        targetId: statDate ?? '',
      ),
    );
    return _map(response);
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    final account = username.trim();
    await client.post(
      adminLoginEndpoint,
      body: {
        'workNo': account,
        'userName': account,
        'password': password,
      },
    );
  }

  @override
  Future<void> reprintShiftTicket(int shiftId) async {
    if (shiftId <= 0) {
      throw ArgumentError('补打交班小票需要有效班次ID');
    }
    await client.post(
      cashierPrintDispatchEndpoint,
      body: {
        'scenario': 'shift',
        'shift_id': shiftId,
        'is_reprint': true,
      },
    );
  }
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value'.trim().replaceFirst(' ', 'T'));
}

String? _cleanDate(String? dateStr) {
  if (dateStr == null) return null;
  final trimmed = dateStr.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length >= 10 && trimmed[4] == '-' && trimmed[7] == '-') {
    return trimmed.substring(0, 10);
  }
  return trimmed;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};
