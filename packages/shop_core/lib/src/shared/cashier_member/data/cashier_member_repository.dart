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
}

class MemberNotFoundException implements Exception {
  const MemberNotFoundException([this.message = '未找到该手机号对应的会员']);

  final String message;

  @override
  String toString() => message;
}
