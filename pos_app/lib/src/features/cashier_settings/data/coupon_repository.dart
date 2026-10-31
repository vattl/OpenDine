import '../domain/coupon_models.dart';

/// 优惠券仓库（M-J 优惠券管理）。
/// 覆盖券模板增删改查、兑换码查询/生成/批量删除、用户券明细/解绑/作废、Excel 批量发券、定向发券。
abstract interface class CouponRepository {
  Future<List<CouponTemplate>> loadCoupons({int? status});

  Future<CouponTemplate> loadCouponDetail(int id);

  /// 新增券模板，返回服务端分配的 id。
  Future<int> addCoupon(CouponTemplate template);

  Future<void> updateCoupon(CouponTemplate template);

  Future<void> deleteCoupon(int id);

  Future<List<CouponRedeemCode>> loadRedeemCodes({
    int? couponId,
    int? status,
  });

  /// 批量生成兑换码（count 1~500），返回生成的券码记录（仅含 id/redeemCode）。
  Future<List<CouponRedeemCode>> createRedeemCodes({
    required int couponId,
    required int count,
  });

  Future<int> deleteRedeemCodes(List<int> ids);

  Future<List<UserCoupon>> loadUserCoupons({
    int? couponId,
    String? openid,
    int? status,
  });

  /// 定向发券（openid 与 phone 二选一）。
  Future<void> grantCoupon({
    required int couponId,
    String? openid,
    String? phone,
  });

  Future<CouponGrantExcelResult> grantByExcel({
    required int couponId,
    required List<int> bytes,
    required String fileName,
  });

  Future<void> voidUserCoupon(int userCouponId);

  Future<void> unbindUserCoupon(int userCouponId);

  /// 校验兑换码小程序码服务可用性（HTTP 200）；收银端展示以本地二维码兜底。
  Future<bool> verifyRedeemCodeQrcode(String redeemCode);
}
