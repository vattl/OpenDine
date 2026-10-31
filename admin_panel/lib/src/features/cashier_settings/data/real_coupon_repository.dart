import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/coupon_models.dart';
import 'coupon_repository.dart';

/// 优惠券仓库实现（X-Shop-Id 由 client 注入）。
class RealCouponRepository implements CouponRepository {
  const RealCouponRepository(this.client);

  final AdminApiClient client;

  @override
  Future<List<CouponTemplate>> loadCoupons({int? status}) async {
    final response = await client.get(
      couponListEndpoint,
      query: {if (status != null) 'status': status},
    );
    return _extractList(response, 'list')
        .map(CouponTemplate.fromJson)
        .toList(growable: false);
  }

  @override
  Future<CouponTemplate> loadCouponDetail(int id) async {
    final response = await client.get(
      couponGetEndpoint,
      query: {'id': id},
    );
    final map = _object(response);
    final raw = map['coupon'] ?? map;
    return CouponTemplate.fromJson(_object(raw));
  }

  @override
  Future<int> addCoupon(CouponTemplate template) async {
    if (template.name.trim().isEmpty) {
      throw ArgumentError('coupon name must not be empty');
    }
    final response = await client.post(
      couponAddEndpoint,
      body: template.toSaveJson(),
    );
    final map = _object(response);
    return _int(map['id']) ?? 0;
  }

  @override
  Future<void> updateCoupon(CouponTemplate template) async {
    if (template.id == 0) throw ArgumentError('coupon id required');
    await client.post(
      couponUpdateEndpoint,
      body: template.toSaveJson(),
    );
  }

  @override
  Future<void> deleteCoupon(int id) async {
    await client.get(couponDeleteEndpoint, query: {'id': id});
  }

  @override
  Future<List<CouponRedeemCode>> loadRedeemCodes({
    int? couponId,
    int? status,
  }) async {
    final response = await client.get(
      couponRedeemCodeListEndpoint,
      query: {
        if (couponId != null) 'couponId': couponId,
        if (status != null) 'status': status,
      },
    );
    return _extractList(response, 'list')
        .map(CouponRedeemCode.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<CouponRedeemCode>> createRedeemCodes({
    required int couponId,
    required int count,
  }) async {
    if (count < 1 || count > 500) {
      throw ArgumentError('count must be 1..500');
    }
    final response = await client.post(
      couponRedeemCodeCreateEndpoint,
      body: {'couponId': couponId, 'count': count},
    );
    final map = _object(response);
    final raw = map['codes'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => CouponRedeemCode.fromJson(row.cast<String, Object?>()))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<int> deleteRedeemCodes(List<int> ids) async {
    if (ids.isEmpty) throw ArgumentError('ids must not be empty');
    final response = await client.post(
      couponRedeemCodeDeleteEndpoint,
      body: {'ids': ids},
    );
    final map = _object(response);
    return _int(map['deleted']) ?? 0;
  }

  @override
  Future<List<UserCoupon>> loadUserCoupons({
    int? couponId,
    String? openid,
    int? status,
  }) async {
    final response = await client.get(
      couponUserCouponListEndpoint,
      query: {
        if (couponId != null) 'couponId': couponId,
        if (openid != null && openid.trim().isNotEmpty) 'openid': openid.trim(),
        if (status != null) 'status': status,
      },
    );
    return _extractList(response, 'list')
        .map(UserCoupon.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> grantCoupon({
    required int couponId,
    String? openid,
    String? phone,
  }) async {
    final openidValue = openid?.trim() ?? '';
    final phoneValue = phone?.trim() ?? '';
    if (openidValue.isEmpty && phoneValue.isEmpty) {
      throw ArgumentError('openid or phone required');
    }
    await client.post(
      couponUserCouponGrantEndpoint,
      body: {
        'couponId': couponId,
        if (openidValue.isNotEmpty) 'openid': openidValue,
        if (phoneValue.isNotEmpty) 'phone': phoneValue,
      },
    );
  }

  @override
  Future<CouponGrantExcelResult> grantByExcel({
    required int couponId,
    required List<int> bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('file bytes must not be empty');
    final response = await client.postMultipart(
      couponUserCouponBatchGrantExcelEndpoint,
      fields: {'couponId': '$couponId'},
      files: {
        'file': (
          bytes: bytes,
          filename: fileName,
          contentType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      },
    );
    return CouponGrantExcelResult.fromJson(_object(response));
  }

  @override
  Future<void> voidUserCoupon(int userCouponId) async {
    await client.post(
      couponUserCouponVoidEndpoint,
      body: {'userCouponId': userCouponId},
    );
  }

  @override
  Future<void> unbindUserCoupon(int userCouponId) async {
    await client.post(
      couponUserCouponUnbindEndpoint,
      body: {'userCouponId': userCouponId},
    );
  }

  @override
  Future<bool> verifyRedeemCodeQrcode(String redeemCode) async {
    if (redeemCode.trim().isEmpty) throw ArgumentError('redeemCode required');
    final response = await client.requestRaw(
      couponRedeemCodeQrcodeEndpoint,
      query: {'redeem_code': redeemCode.trim()},
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Map<String, Object?>> _extractList(Object? response, String key) {
  if (response is List) {
    return response
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }
  if (response is Map) {
    final map = response.cast<String, Object?>();
    final raw = map[key] ?? map['items'] ?? map['data'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => row.cast<String, Object?>())
          .toList(growable: false);
    }
  }
  return const [];
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
