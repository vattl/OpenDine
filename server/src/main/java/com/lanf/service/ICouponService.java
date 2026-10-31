package com.lanf.service;

import com.lanf.dto.CouponDTO;
import com.lanf.dto.CouponRuleValidateRequest;
import com.lanf.dto.CouponRuleValidateResult;
import com.lanf.dto.R;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.Coupon;

import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 优惠券服务接口（定义业务规范）
 */
public interface ICouponService {

    /**
     * 获取可领取的优惠券列表
     * @param openid 用户唯一标识
     * @return 包含可领取优惠券DTO列表的响应结果
     */
    R<List<CouponDTO>> getAvailableCoupons(String openid);

    /**
     * 领取优惠券（原子操作，含库存扣减）
     * @param openid 用户唯一标识
     * @param couponId 优惠券ID
     * @return 领取结果响应（成功/失败信息）
     */
    R<Void> receiveCoupon(String openid, Long couponId);

    /**
     * 通过兑换码领取优惠券
     * @param openid 用户唯一标识
     * @param redeemCode 兑换码
     */
    R<Map<String, Object>> receiveCouponByRedeemCode(String openid, String redeemCode);

    /**
     * 获取用户优惠券列表（按状态筛选）
     * @param openid 用户唯一标识
     * @param status 状态筛选（usable-未使用、used-已使用、expired-已失效）
     * @return 包含用户优惠券DTO列表的响应结果
     */
    R<List<UserCouponDTO>> getUserCoupons(String openid, String status);

    R<List<UserCouponDTO>> getUserCoupons(String openid, String status, Integer shopId);

    R<List<UserCouponDTO>> getUserAvailableCoupons(String openid, Integer shopId);

    /**
     * 获取用户可用（未使用）优惠券数量（status=0）
     * @param openid 用户唯一标识
     * @return 数量，>=0
     */
    int getAvailableCouponCount(String openid);

    /**
     * 获取用户在指定门店可用的优惠券数量（apply_shop_ids 包含 shopId）。
     */
    int getAvailableCouponCount(String openid, Integer shopId);

    /**
     * 使用优惠券（订单支付时调用）
     * @param openid 用户唯一标识
     * @param couponId 优惠券ID
     * @param orderNo 关联订单号
     * @return 使用结果响应（成功/失败信息）
     */
    R<Void> useCoupon(String openid, Long couponId, String orderNo);

    Coupon selectByCouponById(Long couponId);

    /**
     * 按券类型计算优惠金额（与 OrderController 结算逻辑一致，供删除菜品等重算使用）
     * @param totalRaw 参与计算的金额（如烧烤类目原价合计）
     * @param coupon 优惠券，可为 null
     * @return 优惠金额（元），无券或无法计算时返回 0
     */
    double calcDiscountAmount(double totalRaw, Coupon coupon);

    /**
     * 预校验优惠券规则（不占用/不核销），供前端在下单前实时验券。
     */
    R<CouponRuleValidateResult> validateCouponRule(CouponRuleValidateRequest req);

    /** C 端：券模板详情（可选 openid 返回是否已领过；可选 shopId 严格校验适用门店）。 */
    R<CouponDTO> getCouponTemplateDetail(String openid, Long templateId, Integer shopId);

    /** C 端：用户券记录详情（{@code userCouponRecordId} 为 {@code t_user_coupon.id}）。 */
    R<UserCouponDTO> getUserCouponDetail(String openid, Long userCouponRecordId);

    /** C 端：用户券分页；{@code shopId} 非空时与当前门店可用列表过滤规则一致。 */
    R<Map<String, Object>> getUserCouponsPage(String openid, String status, Integer shopId, Integer page, Integer pageSize);

    /** C 端：可领券模板分页（可选门店严格匹配）。 */
    R<Map<String, Object>> getAvailableCouponsPage(String openid, Integer shopId, Integer page, Integer pageSize);

    /** C 端：未支付/非成功订单解除用户券与订单号的占用绑定。 */
    R<Void> unbindUserCouponFromOrder(String openid, String orderNo);
}