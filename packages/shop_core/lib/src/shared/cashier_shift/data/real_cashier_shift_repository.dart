import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
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
  Future<CashierTodayReport> loadTodayReport({int? shopId}) async {
    final response = await client
        .copyWith(shopId: shopId)
        .get(reportDashboardEndpoint);
    return CashierTodayReport.fromJson(_map(response));
  }

  @override
  Future<CashierShift> startShift({
    required double startCash,
    int? shopId,
  }) async {
    await client.post(
      cashierShiftStartEndpoint,
      body: {'start_cash': startCash, if (shopId != null) 'shop_id': shopId},
    );
    final shift = await loadCurrentShift();
    if (shift == null) {
      throw const FormatException('开班成功，但未能读取当前班次');
    }
    return shift;
  }

  @override
  Future<CashierHandoverResult> handover({
    required double endCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    String? idempotencyKey,
    int? shopId,
  }) async {
    final response = await client.post(
      cashierShiftHandoverEndpoint,
      body: {
        'end_cash': endCash,
        'counted_cash': endCash,
        if (varianceReasonCode != null) 'variance_reason_code': varianceReasonCode,
        if (varianceNote != null) 'variance_note': varianceNote,
        if (approvedBy != null) 'approved_by': approvedBy,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'idempotency_key': idempotencyKey,
        if (shopId != null) 'shop_id': shopId,
      },
    );
    return CashierHandoverResult.fromJson(_map(response));
  }

  @override
  Future<ShiftSummaryReport> loadShiftReport(
    int sessionId, {
    int? shopId,
  }) async {
    final targetClient = shopId != null ? client.copyWith(shopId: shopId) : client;
    final response = await targetClient.get(
      cashierShiftReportEndpoint(sessionId),
    );
    return ShiftSummaryReport.fromJson(_map(response));
  }

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.copyWith(shopId: shopId).get(
      dailyPrecheckEndpoint,
      query: {if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate},
    );
    return DailyPrecheckResult.fromJson(_map(response));
  }

  @override
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
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
      },
    );
    return CashierDailySettleResult.fromJson(_map(response));
  }

  @override
  Future<CommercialZReport> loadZReport({
    String? statDate,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.copyWith(shopId: shopId).get(
      dailyZReportEndpoint,
      query: {if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate},
    );
    final map = _map(response);
    final zReport = _map(map['zReport']);
    return CommercialZReport.fromJson(zReport.isNotEmpty ? zReport : map);
  }

  @override
  Future<void> verifyPassword({
    required String account,
    required String password,
  }) async {
    await client.post(
      adminLoginEndpoint,
      body: {'userName': account, 'workNo': account, 'password': password},
    );
  }

  @override
  Future<DailyContext> loadDailyContext({
    String? statDate,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.copyWith(shopId: shopId).get(
      dailyContextEndpoint,
      query: {
        if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate,
      },
    );
    return DailyContext.fromJson(_map(response));
  }

  @override
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int minutes = 30,
    int? shopId,
  }) async {
    final cleanDate = _cleanDate(statDate);
    final response = await client.copyWith(shopId: shopId).post(
      dailyVoidStaleTakeoutOrdersEndpoint,
      body: {
        if (cleanDate != null && cleanDate.isNotEmpty) 'stat_date': cleanDate,
        'minutes': minutes,
      },
    );
    return VoidStaleTakeoutResult.fromJson(_map(response));
  }

  @override
  Future<DailyZReportsPage> loadDailyZReports({
    String? dateFrom,
    String? dateTo,
    int? cursor,
    int limit = 20,
    int? shopId,
  }) async {
    final response = await client.copyWith(shopId: shopId).get(
      dailyZReportsEndpoint,
      query: {
        if (dateFrom != null && dateFrom.trim().isNotEmpty)
          'date_from': dateFrom.trim(),
        if (dateTo != null && dateTo.trim().isNotEmpty) 'date_to': dateTo.trim(),
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    return DailyZReportsPage.fromJson(_map(response));
  }

  @override
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String reasonCode = '',
    String remark = '',
    int? approverId,
    String idempotencyKey = '',
    int? shopId,
  }) async {
    await client.copyWith(shopId: shopId).post(
      cashierShiftCashMovementEndpoint,
      body: {
        'movement_type': movementType,
        'amount': amount,
        if (reasonCode.trim().isNotEmpty) 'reason_code': reasonCode.trim(),
        if (remark.trim().isNotEmpty) 'remark': remark.trim(),
        if (approverId != null) 'approver_id': approverId,
        if (idempotencyKey.trim().isNotEmpty)
          'idempotency_key': idempotencyKey.trim(),
      },
    );
  }

  @override
  Future<CashEventsPage> loadCashEvents(
    int sessionId, {
    int? cursor,
    int limit = 20,
    int? shopId,
  }) async {
    final response = await client.copyWith(shopId: shopId).get(
      cashierShiftCashEventsEndpoint(sessionId),
      query: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    return CashEventsPage.fromJson(_map(response));
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
