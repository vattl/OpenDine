import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/cashier_member.dart';
import 'cashier_member_repository.dart';

class RealCashierMemberRepository implements CashierMemberRepository {
  const RealCashierMemberRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierMemberProfile> loadProfile(String phone) async {
    try {
      final data = await client.get(
        memberProfileEndpoint,
        query: {'phone': phone},
      );
      if (data is! Map) throw const MemberNotFoundException();
      return CashierMemberProfile.fromJson(data.cast<String, Object?>());
    } on ApiException catch (error) {
      if (_looksMissing(error.message))
        throw MemberNotFoundException(error.message);
      rethrow;
    } on FormatException {
      throw const MemberNotFoundException();
    }
  }

  @override
  Future<List<MemberConsumptionRecord>> loadConsumption(String phone) async {
    final data = await client.get(
      memberConsumptionEndpoint,
      query: {'phone': phone},
    );
    return objectList(
      data,
    ).map(MemberConsumptionRecord.fromJson).toList(growable: false);
  }

  @override
  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  ) async {
    final data = await client.get(
      orderDetailEndpoint,
      query: {'id': record.id},
    );
    final lines = objectList(
      data,
    ).map(MemberConsumptionLine.fromJson).toList(growable: false);
    return MemberConsumptionDetail(record: record, lines: lines);
  }

  @override
  Future<List<MemberRechargeRecord>> loadRecharges(String phone) async {
    final data = await client.get(
      memberRechargeListEndpoint,
      query: {'phone': phone, 'page': 1, 'pageSize': 100},
    );
    return objectList(
      data,
    ).map(MemberRechargeRecord.fromJson).toList(growable: false);
  }

  @override
  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  }) async {
    if (amount < 50) {
      throw ArgumentError.value(amount, 'amount', '充值本金不得低于 50 元');
    }
    if (giftAmount < 0) {
      throw ArgumentError.value(giftAmount, 'giftAmount', '赠送金额不得小于 0');
    }
    final data = await client.post(
      memberRechargeCreateEndpoint,
      body: {'phone': phone, 'amount': amount, 'gift_amount': giftAmount},
    );
    return MemberRechargeResult.fromJson(data);
  }

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {
    await client.post(
      orderReassignOpenidByPhoneEndpoint,
      body: {'id': orderId, 'phone': phone},
    );
  }
}

bool _looksMissing(String message) {
  final text = message.toLowerCase();
  return text.contains('不存在') ||
      text.contains('未找到') ||
      text.contains('not found');
}
