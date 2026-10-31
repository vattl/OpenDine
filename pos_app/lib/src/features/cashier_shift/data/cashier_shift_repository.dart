import '../domain/cashier_shift.dart';

abstract interface class CashierShiftRepository {
  Future<CashierShift?> loadCurrentShift();

  /// 当班工作台聚合（GET /cashier/shift/workbench）。
  Future<CashierShiftWorkbenchData> loadWorkbench({int? shopId});

  Future<CashierTodayReport> loadTodayReport({int? shopId});

  Future<CashierShift> startShift({
    required double startCash,
    int? shopId,
    String? idempotencyKey,
  });

  Future<CashierHandoverResult> handover({
    required double endCash,
    double? countedCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    int? shopId,
    String? idempotencyKey,
  });

  /// 钱箱人工现金事件（加钞 CASH_IN、支出 CASH_OUT、投库 CASH_DROP）。
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String? reasonCode,
    String? remark,
    int? approverId,
    int? shopId,
    String? idempotencyKey,
  });

  /// 钱箱班次综合报表（GET /cashier/shift/report/{sessionId}）。
  Future<ShiftSummaryReport> loadShiftReport(int sessionId, {int? shopId});

  /// 历史交班报告（GET /cashier/shift/reports）。
  Future<CashierShiftReportPage> loadShiftReports({
    int? shopId,
    int? cursor,
    int limit = 20,
  });

  /// 已关闭班次现金流水（GET /cashier/shift/{sessionId}/cash-events）。
  Future<CashierCashEventPage> loadCashEvents(
    int sessionId, {
    int? shopId,
    int? cursor,
    int limit = 20,
  });

  /// 结算日汇总查询（GET /admin/daily/summary）。
  /// 遵循 OpenAPI 时间窗口统一标准：[statDate] 可选，不传时由服务端自动查询当前活动营业班次；
  /// 传入显式日期时查询指定历史结算日。
  Future<CashierDailySummary> loadDailySummary({String? statDate, int? shopId});

  /// 支付渠道对账（GET /admin/daily/byChannel）。
  /// [statDate] 可选，不传时查询当前活动营业班次；传入显式日期时查询指定历史结算日。
  Future<Map<String, double>> loadDailyChannels({
    String? statDate,
    int? shopId,
  });

  /// 门店日结（POST /admin/daily/settle）。
  /// [statDate] 可选，不传时服务端日结当前活动营业班次；传入显式日期时日结指定历史结算日。
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
    String? idempotencyKey,
  });

  /// 日结全量聚合上下文（GET /admin/daily/context）。
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => precheckDaily(statDate: statDate, shopId: shopId, minutes: minutes);

  /// 日结预检（GET /admin/daily/pre-check）。
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  });

  /// 一键作废超时未支付打包外卖单（POST /admin/daily/void-stale-takeout-orders，v1.2.289 / WI-014）。
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int? shopId,
    int? minutes,
  });

  /// 商用 Z 报表（GET /admin/daily/z-report）。
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId});

  /// 历史 Z 报表（GET /admin/daily/z-reports）。
  Future<CashierZReportHistoryPage> loadZReports({
    int? shopId,
    String? dateFrom,
    String? dateTo,
    Object? cursor,
    int limit = 20,
  });

  /// 重开日结（POST /admin/daily/reopen）。
  Future<Map<String, Object?>> reopenDaily({
    String? statDate,
    int? shopId,
    required String password,
    required String reason,
  });

  /// 校验管理账号密码（调用 POST /adminLogin），用于日结防误触等高危操作的二次验证。
  Future<void> verifyPassword({
    required String username,
    required String password,
  });

  /// 补打交接班小票（POST /cashier/print/dispatch，scenario=shift）
  Future<void> reprintShiftTicket(int shiftId);
}
