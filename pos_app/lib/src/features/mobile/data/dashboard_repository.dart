import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';

/// 首页仪表盘数据门面：**单一数据源** `GET /admin/report/dashboard`。
///
/// 服务端聚合口径（server/docs/openapi.yaml `/admin/report/dashboard`）：
/// 最近已完成结算日窗口的营收/订单/退款/优惠/未收/渠道实收/会员充值，
/// 以及周·月·新客复购率与注册人数，一次请求全部返回；首页不再调用其它分析端点。
class MobileDashboardRepository {
  const MobileDashboardRepository(this.client);

  final AdminApiClient client;

  /// 首页仪表盘：`GET /admin/report/dashboard`（携带当前门店 X-Shop-Id）。
  Future<DashboardSummary> loadDashboardSummary() async {
    final data = await client.get(reportDashboardEndpoint);
    return DashboardSummary.fromJson(data);
  }

  /// 员工工作台概览（PRD F02，不暴露营收净额）：并行拉取今日订单数、
  /// 待结金额/单数、桌台待清台数。三个子请求相互独立，任一失败不阻断其它。
  Future<StaffSummary> loadStaffSummary() async {
    final results = await Future.wait<Object?>([
      client.get(orderTodayCountEndpoint),
      client.get(orderTodayUnsettledAmountEndpoint),
      client.get(tableStatusEndpoint),
    ]);
    final rows = objectList(results[2]);
    var pendingClear = 0;
    for (final row in rows) {
      final raw = '${row['status'] ?? row['table_status'] ?? row['tableStatus'] ?? row['transac_status'] ?? row['transacStatus'] ?? ''}'.toLowerCase();
      if (raw == '2' || raw == 'success' || raw == 'settled' || raw == 'paid') {
        pendingClear++;
      }
    }
    return StaffSummary.fromJson(
      todayCountData: results[0],
      unsettledData: results[1],
      pendingClearCount: pendingClear,
    );
  }
}

/// 渠道实收（revenueByPayChannel 固定五类之一）。
class PayChannel {
  const PayChannel({
    required this.code,
    required this.label,
    required this.amount,
  });

  final String code;
  final String label;
  final double amount;

  factory PayChannel.fromJson(Map<String, Object?> map) {
    final a = map['amount'];
    return PayChannel(
      code: '${map['channelCode'] ?? map['channel_code'] ?? ''}',
      label: '${map['channelLabel'] ?? map['channel_label'] ?? ''}',
      amount: a is num ? a.toDouble() : double.tryParse('$a') ?? 0,
    );
  }
}

/// 首页仪表盘汇总：结算数据在 `data.businessDay`，复购率/注册人数在 `data` 顶层。
class DashboardSummary {
  const DashboardSummary({
    required this.revenue,
    required this.orderCount,
    required this.paidOrderCount,
    required this.avgOrderAmount,
    required this.refundAmount,
    required this.discountAmount,
    required this.unpaidAmount,
    required this.memberRechargeAmount,
    required this.memberRechargePrincipal,
    required this.memberRechargeGift,
    required this.memberRechargeCount,
    required this.bizStart,
    required this.bizEnd,
    required this.payChannels,
    required this.weeklyRepurchase,
    required this.monthlyRepurchase,
    required this.newCustomerRepurchase,
    required this.register,
  });

  /// 营业收入（实付净额）= todayRevenue。
  final double revenue;

  /// 当天订单数（含未结/已结）= todayOrderCount。
  final int orderCount;

  /// 已结 success 单数 = todayPaidOrderCount。
  final int paidOrderCount;

  /// 客单价 = 营业额 / 已结单数（无已结单时为 0）。
  final double avgOrderAmount;

  /// 退款合计 = totalRefundAmount。
  final double refundAmount;

  /// 优惠合计 = totalDiscountAmount。
  final double discountAmount;

  /// 未结账金额 = todayUnpaidAmount。
  final double unpaidAmount;

  /// 会员充值入账（本金+赠送）= todayMemberRechargeAmount。
  final double memberRechargeAmount;

  /// 充值本金 = todayMemberRechargePrincipal。
  final double memberRechargePrincipal;

  /// 充值赠送 = todayMemberRechargeGift。
  final double memberRechargeGift;

  /// 成功充值笔数 = todayMemberRechargeSuccessCount。
  final int memberRechargeCount;

  /// 结算窗口起点（服务端 Date → epoch 毫秒或字符串）。
  final DateTime? bizStart;

  /// 结算窗口终点，即结算日日期来源。
  final DateTime? bizEnd;

  /// 渠道实收（微信/支付宝/余额/现金/赠送）。
  final List<PayChannel> payChannels;

  /// 周复购率（默认本周周一～周日）。
  final RepurchaseReport weeklyRepurchase;

  /// 月复购率（默认本月）。
  final RepurchaseReport monthlyRepurchase;

  /// 新客复购率（本月 1 日～今日，窗口 N 天）。
  final NewCustomerRepurchase newCustomerRepurchase;

  /// 注册人数（近7天/本月/上月）。
  final RegisterStats register;

  /// 最近已完成结算日的窗口文案，数据缺失时为 null。
  String? get settlementWindowLabel {
    final s = bizStart;
    final e = bizEnd;
    if (s == null || e == null) return null;
    final crossDay = e.day != s.day;
    final fmt = (DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return crossDay
        ? '最近已完成结算日 · ${fmt(s)}～次日 ${fmt(e)}'
        : '最近已完成结算日 · ${fmt(s)}～${fmt(e)}';
  }

  factory DashboardSummary.fromJson(Object? data) {
    final map = data is Map ? data.cast<String, Object?>() : const <String, Object?>{};
    final bizRaw = map['businessDay'];
    final biz =
        bizRaw is Map ? bizRaw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    DateTime? t(Object? v) {
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v.trim().replaceFirst(' ', 'T'));
      }
      return null;
    }

    final revenue = d(biz['todayRevenue'] ?? biz['businessRevenueNet']);
    final paid = i(biz['todayPaidOrderCount']);
    final channelsRaw = biz['revenueByPayChannel'];
    return DashboardSummary(
      revenue: revenue,
      orderCount: i(biz['todayOrderCount']),
      paidOrderCount: paid,
      avgOrderAmount: paid > 0 ? revenue / paid : 0,
      refundAmount: d(biz['totalRefundAmount']),
      discountAmount: d(biz['totalDiscountAmount']),
      unpaidAmount: d(biz['todayUnpaidAmount']),
      memberRechargeAmount: d(biz['todayMemberRechargeAmount']),
      memberRechargePrincipal: d(biz['todayMemberRechargePrincipal']),
      memberRechargeGift: d(biz['todayMemberRechargeGift']),
      memberRechargeCount: i(biz['todayMemberRechargeSuccessCount']),
      bizStart: t(biz['startTime']),
      bizEnd: t(biz['endTime']),
      payChannels: channelsRaw is List
          ? channelsRaw
              .whereType<Map>()
              .map((e) => PayChannel.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
      weeklyRepurchase: RepurchaseReport.fromJson(map['weeklyRepurchase']),
      monthlyRepurchase: RepurchaseReport.fromJson(map['monthlyRepurchase']),
      newCustomerRepurchase:
          NewCustomerRepurchase.fromJson(map['newCustomerRepurchase']),
      register: RegisterStats.fromJson(map['register']),
    );
  }
}

/// 复购率报告（周/月共用结构）。
class RepurchaseReport {
  const RepurchaseReport({
    required this.buyers,
    required this.repurchasedBuyers,
    required this.repurchaseRate,
  });

  /// 统计期消费人数。
  final int buyers;

  /// 其中复购人数。
  final int repurchasedBuyers;

  /// 复购率（0～1）。
  final double repurchaseRate;

  factory RepurchaseReport.fromJson(Object? raw) {
    final m =
        raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final r = m['repurchaseRate'];
    return RepurchaseReport(
      buyers: i(m['buyers']),
      repurchasedBuyers: i(m['repurchasedBuyers']),
      repurchaseRate: r is num ? r.toDouble() : double.tryParse('$r') ?? 0,
    );
  }
}

/// 新客复购率。
class NewCustomerRepurchase {
  const NewCustomerRepurchase({
    required this.windowDays,
    required this.newBuyers,
    required this.repurchasedNewBuyers,
    required this.repurchaseRate,
  });

  /// 观察窗口天数 N（默认 30）。
  final int windowDays;

  /// 新客数。
  final int newBuyers;

  /// 窗口内回流的新客数。
  final int repurchasedNewBuyers;

  /// 复购率（0～1）。
  final double repurchaseRate;

  factory NewCustomerRepurchase.fromJson(Object? raw) {
    final m =
        raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final r = m['repurchaseRate'];
    return NewCustomerRepurchase(
      windowDays: i(m['windowDays']),
      newBuyers: i(m['newBuyers']),
      repurchasedNewBuyers: i(m['repurchasedNewBuyers']),
      repurchaseRate: r is num ? r.toDouble() : double.tryParse('$r') ?? 0,
    );
  }
}

/// 注册人数统计。
class RegisterStats {
  const RegisterStats({
    required this.sevenDays,
    required this.thisMonth,
    required this.lastMonth,
  });

  final int sevenDays;
  final int thisMonth;
  final int lastMonth;

  factory RegisterStats.fromJson(Object? raw) {
    final m =
        raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return RegisterStats(
      sevenDays: i(m['sevenDaysRegisterCount']),
      thisMonth: i(m['thisMonthRegisterCount']),
      lastMonth: i(m['lastMonthRegisterCount']),
    );
  }
}


/// 员工工作台概览（PRD F02）：结算日订单数 / 待结金额与单数 / 待清台数。
/// todayCount 与 todayUnsettledAmount 未传 date 时均由后端取最近已完成结算日。
class StaffSummary {
  const StaffSummary({
    required this.todayOrderCount,
    required this.unsettledAmount,
    required this.unsettledCount,
    required this.pendingClearCount,
  });

  final int todayOrderCount;
  final double unsettledAmount;
  final int unsettledCount;
  final int pendingClearCount;

  factory StaffSummary.fromJson({
    required Object? todayCountData,
    required Object? unsettledData,
    required int pendingClearCount,
  }) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('') ?? 0;
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('') ?? 0;
    final countMap = todayCountData is Map
        ? todayCountData.cast<String, Object?>()
        : const <String, Object?>{};
    final unsettledMap = unsettledData is Map
        ? unsettledData.cast<String, Object?>()
        : const <String, Object?>{};
    return StaffSummary(
      todayOrderCount: i(countMap['todayCount']),
      unsettledAmount: d(unsettledMap['todayUnsettledAmount']),
      unsettledCount: i(unsettledMap['todayUnsettledCount']),
      pendingClearCount: pendingClearCount,
    );
  }
}
