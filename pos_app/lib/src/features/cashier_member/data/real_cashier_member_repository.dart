import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/cashier_operation_audit.dart';
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
    final result = MemberRechargeResult.fromJson(data);
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'member',
      action: 'recharge',
      result: 'success',
      targetType: 'member',
      targetId: phone,
      amountFen: ((amount + giftAmount) * 100).round(),
      detail: {'amount': amount, 'gift_amount': giftAmount},
    ));
    return result;
  }

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {
    await client.post(
      orderReassignOpenidByPhoneEndpoint,
      body: {'id': orderId, 'phone': phone},
    );
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'member',
      action: 'bind',
      result: 'success',
      targetType: 'order',
      targetId: '$orderId',
      detail: {'phone': phone},
    ));
  }

  @override
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  }) async {
    final data = await client.post(
      getUserInfoEndpoint,
      body: {
        'pageNum': page,
        'pageSize': pageSize,
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
    final rows = objectList(
      data,
    ).map(CashierMemberRow.fromJson).toList(growable: false);
    final total = totalFrom(data, rows.length);
    return PagedCashierMembers(rows: rows, total: total);
  }

  @override
  Future<CashierMemberStats> loadStats() async {
    final data = await client.get(memberStatsEndpoint);
    if (data is! Map) return const CashierMemberStats();
    return CashierMemberStats.fromJson(data.cast<String, Object?>());
  }

  @override
  Future<PagedRechargeLogs> loadRechargeLogs({
    int page = 1,
    int pageSize = 20,
    String phone = '',
    String startTime = '',
    String endTime = '',
  }) async {
    final query = <String, Object?>{
      'page': page,
      'pageSize': pageSize,
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (startTime.trim().isNotEmpty) 'startTime': startTime.trim(),
      if (endTime.trim().isNotEmpty) 'endTime': endTime.trim(),
    };
    final data = await client.get(memberRechargeListEndpoint, query: query);
    final rows = objectList(data)
        .map(RechargeLogRow.fromJson)
        .toList(growable: false);
    final total = totalFrom(data, rows.length);
    return PagedRechargeLogs(rows: rows, total: total);
  }

  @override
  Future<List<CashierCoupon>> loadCoupons() async {
    final data = await client.get(couponListEndpoint);
    return objectList(
      data,
    ).map(CashierCoupon.fromJson).toList(growable: false);
  }

  @override
  Future<int> batchSendCoupon({required int couponId}) async {
    final data = await client.post(
      couponBatchSendEndpoint,
      body: {'couponId': couponId},
    );
    if (data is! Map) return 0;
    final granted = data['grantedCount'] ?? data['granted_count'] ?? 0;
    return granted is num ? granted.toInt() : int.tryParse(granted.toString()) ?? 0;
  }

  @override
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  }) async {
    final query = <String, Object?>{
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (memberId != null) 'memberId': memberId,
    };
    try {
      final response = await client.get(memberPersonaTagsEndpoint, query: query);
      if (response is Map) {
        final data = response['data'] is Map ? response['data'] as Map : response;
        final rawTags = data['tags'];
        if (rawTags is Iterable) {
          return rawTags
              .whereType<Map>()
              .map((t) => CashierPersonaTag.fromJson(t.cast<String, Object?>()))
              .toList(growable: false);
        }
      }
    } catch (_) {}
    return const [];
  }
}

bool _looksMissing(String message) {
  final text = message.toLowerCase();
  return text.contains('不存在') ||
      text.contains('未找到') ||
      text.contains('not found');
}
