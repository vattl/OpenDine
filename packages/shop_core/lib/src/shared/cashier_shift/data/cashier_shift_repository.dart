import '../domain/cashier_shift.dart';

abstract interface class CashierShiftRepository {
  Future<CashierShift?> loadCurrentShift();

  Future<CashierTodayReport> loadTodayReport({int? shopId});

  Future<CashierShift> startShift({required double startCash, int? shopId});

  /// 盲盘交班：提交实点现金；差额超 50 元时必须传 [varianceReasonCode]/[varianceNote]
  /// 与 [approvedBy]（店长授权），否则服务端拒绝。
  Future<CashierHandoverResult> handover({
    required double endCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    String? idempotencyKey,
    int? shopId,
  });

  /// 钱箱班次综合报表（GET /cashier/shift/report/{sessionId}）。
  Future<ShiftSummaryReport> loadShiftReport(int sessionId, {int? shopId});

  /// 日结预检（GET /admin/daily/pre-check）：阻断项 / 警告 / precheck_token。
  Future<DailyPrecheckResult> precheckDaily({String? statDate, int? shopId});

  /// 门店日结（POST /admin/daily/settle）：携带预检 token；有警告时传 [password] 并 [force]。
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
  });

  /// 商用 Z 报表（GET /admin/daily/z-report）。
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId});

  /// 校验管理账号密码（POST /adminLogin，优先工号匹配），
  /// 用于交班长短款/日结等高危操作的二次验证。
  Future<void> verifyPassword({required String account, required String password});

  /// 日结工作台统一上下文聚合（GET /admin/daily/context）：单请求返回
  /// 营业日时序、汇总、渠道、预检阻断与超时外卖单。
  Future<DailyContext> loadDailyContext({String? statDate, int? shopId});

  /// 作废目标营业日内超时未支付的打包/外卖单
  /// （POST /admin/daily/void-stale-takeout-orders）。
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int minutes = 30,
    int? shopId,
  });

  /// 历史 Z 报表时序列表（GET /admin/daily/z-reports）。
  Future<DailyZReportsPage> loadDailyZReports({
    String? dateFrom,
    String? dateTo,
    int? cursor,
    int limit = 20,
    int? shopId,
  });

  /// 记录钱箱人工现金事件（POST /cashier/shift/cash-movement）：
  /// CASH_IN 加钞 / CASH_OUT 支出 / CASH_DROP 投库。
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String reasonCode = '',
    String remark = '',
    int? approverId,
    String idempotencyKey = '',
    int? shopId,
  });

  /// 已交班班次现金流水（GET /cashier/shift/{sessionId}/cash-events）。
  Future<CashEventsPage> loadCashEvents(
    int sessionId, {
    int? cursor,
    int limit = 20,
    int? shopId,
  });
}
