import '../domain/cashier_member.dart';

abstract class CashierMemberRepository {
  Future<CashierMemberProfile> loadProfile(String phone);

  Future<List<MemberConsumptionRecord>> loadConsumption(String phone);

  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  );

  Future<List<MemberRechargeRecord>> loadRecharges(String phone);

  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  });

  Future<void> bindOrder({required int orderId, required String phone});

  /// 会员列表分页（POST /admin/order/getUserInfo，query 按姓名/手机号模糊，phone 精确筛选）。
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  });

  /// 会员看板统计（GET /admin/member/stats，当月口径）。
  Future<CashierMemberStats> loadStats();

  /// 运营端充值记录分页（GET /admin/member/recharge/list）。
  /// phone 为空 = 按时间查全部；phone 非空 = 单查该会员。
  /// startTime/endTime 格式 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss，均可空。
  Future<PagedRechargeLogs> loadRechargeLogs({
    int page = 1,
    int pageSize = 20,
    String phone = '',
    String startTime = '',
    String endTime = '',
  });

  /// 优惠券模板列表（GET /admin/coupon/list，供一键发券选择）。
  Future<List<CashierCoupon>> loadCoupons();

  /// 一键发券（POST /admin/coupon/batch-send），返回实际发放张数。
  Future<int> batchSendCoupon({required int couponId});

  /// UI061: 会员大数据画像智能标签推荐（GET /admin/member/persona-tags）
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  });
}

class MemberNotFoundException implements Exception {
  const MemberNotFoundException([this.message = '未找到该手机号对应的会员']);

  final String message;

  @override
  String toString() => message;
}
