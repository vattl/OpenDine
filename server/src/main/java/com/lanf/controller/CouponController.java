package com.lanf.controller;

import com.lanf.annotation.NoAuth;
import com.lanf.dto.CouponDTO;
import com.lanf.dto.CouponRedeemPostDTO;
import com.lanf.dto.CouponRuleValidateRequest;
import com.lanf.dto.CouponRuleValidateResult;
import com.lanf.dto.R;
import com.lanf.dto.ReceiveCouponDTO;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.User;
import com.lanf.service.ICouponService;
import com.lanf.service.IUserService;
import com.lanf.util.ShopChainSupport;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import com.lanf.interceptor.UserIdentityInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.validation.Valid;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/coupon")
@RequiredArgsConstructor
public class CouponController {
    private final ICouponService couponService;
    private final IUserService userService;
    private static final Logger log = LoggerFactory.getLogger(CouponController.class);

    // 获取可领取优惠券列表
    @NoAuth
    @PostMapping("/getAvailable")
    public R<List<CouponDTO>> getAvailableCoupons(@RequestBody Map<String, String> params) {
        String openid = params.get("openid");
        if(openid == null || openid.isEmpty() ) {
            return R.fail("参数不完整");
        }
        return couponService.getAvailableCoupons(openid);
    }

    /**
     * 获取用户可用（未使用）优惠券数量（契约：body 含 openid，成功 body 含 code、count）
     */
    @NoAuth
    @PostMapping("/availableCount")
    public com.lanf.entity.R getAvailableCouponCount(@RequestBody Map<String, String> params, HttpServletRequest request) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return com.lanf.entity.R.error(2, "openid不能为空");
        }
        try {
            Integer shopId = ShopChainSupport.parseHeaderShopId(request);
            if (shopId == null) {
                return com.lanf.entity.R.error(2, "请求头X-Shop-Id不能为空");
            }
            int count = couponService.getAvailableCouponCount(openid.trim(), shopId);
            return com.lanf.entity.R.ok().put("count", count);
        } catch (Exception e) {
            return com.lanf.entity.R.error(2, e.getMessage() != null ? e.getMessage() : "门店信息异常");
        }
    }

    // 领取优惠券
    @NoAuth
    @PostMapping("/receive")
    public R<Void> receiveCoupon(
            @Valid @RequestBody ReceiveCouponDTO params
    ) {

        return couponService.receiveCoupon(params.getOpenid(), params.getCoupon_id());
    }

    /**
     * 通过兑换码领取优惠券（GET）
     */
    @NoAuth
    @GetMapping("/redeem")
    public R<Map<String, Object>> redeemByCode(@RequestParam(required = false) String openid,
                                               @RequestParam(required = false) String phone,
                                               @RequestParam("redeem_code") String redeemCode,
                                               HttpServletRequest request) {
        try {
            if (!StringUtils.hasText(redeemCode)) {
                return R.fail("redeem_code不能为空");
            }
            String resolvedOpenid = authenticatedOpenid(request);
            return couponService.receiveCouponByRedeemCode(resolvedOpenid, redeemCode.trim());
        } catch (Exception e) {
            log.error("兑换码领取失败", e);
            return R.fail("兑换失败：" + (e.getMessage() != null ? e.getMessage() : "系统异常"));
        }
    }

    // 获取用户优惠券列表
    @NoAuth
    @PostMapping("/getUserCoupons")
    public R<List<UserCouponDTO>> getUserCoupons(@RequestBody Map<String, String> params) {

        String openid = params.get("openid");
        String status = params.get("status");
        if(openid == null || openid.isEmpty() || status == null || status.isEmpty()) {
            return R.fail("参数不完整");
        }
        return couponService.getUserCoupons(openid, status);
    }

    // 获取用户当前门店可用优惠券列表（按门店过滤）
    @NoAuth
    @PostMapping("/getUserAvailableCoupons")
    public R<List<UserCouponDTO>> getUserAvailableCoupons(@RequestBody Map<String, String> params, HttpServletRequest request) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.fail("openid不能为空");
        }
        try {
            Integer shopId = ShopChainSupport.parseHeaderShopId(request);
            if (shopId == null) {
                return R.fail("请求头X-Shop-Id不能为空");
            }
            return couponService.getUserAvailableCoupons(openid.trim(), shopId);
        } catch (Exception e) {
            return R.fail(e.getMessage() != null ? e.getMessage() : "门店信息异常");
        }
    }

    /**
     * 优惠券规则预校验（仅校验，不占用券/不核销），便于前端在下单前实时验券。
     */
    @NoAuth
    @PostMapping("/validateRule")
    public R<CouponRuleValidateResult> validateRule(@RequestBody CouponRuleValidateRequest req) {
        return couponService.validateCouponRule(req);
    }

    // 订单使用优惠券
    @PostMapping("/useCoupon")
    public R<Void> useCoupon(
            @RequestParam String openid,
            @RequestParam Long coupon_id,
            @RequestParam String order_no
    ) {
        return couponService.useCoupon(openid, coupon_id, order_no);
    }

    /**
     * 券模板详情（{@code template_id} 为 {@code t_coupon.id}）；可选 {@code openid} 返回是否已领过；可选 {@code X-Shop-Id}/body {@code shop_id} 严格校验适用门店。
     */
    @NoAuth
    @PostMapping("/getTemplate")
    public R<CouponDTO> getTemplate(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        if (body == null) {
            return R.paramError("参数不能为空");
        }
        Object tid = body.get("template_id") != null ? body.get("template_id") : body.get("coupon_id");
        Long templateId = null;
        if (tid instanceof Number) {
            templateId = ((Number) tid).longValue();
        } else if (tid != null && org.springframework.util.StringUtils.hasText(tid.toString())) {
            try {
                templateId = Long.parseLong(tid.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }
        if (templateId == null || templateId <= 0) {
            return R.paramError("template_id（或 coupon_id）不能为空");
        }
        String openid = body.get("openid") != null ? body.get("openid").toString() : null;
        Integer shopId = null;
        Object sidBody = body.get("shop_id");
        if (sidBody instanceof Number && ((Number) sidBody).intValue() > 0) {
            shopId = ((Number) sidBody).intValue();
        } else {
            try {
                shopId = ShopChainSupport.parseHeaderShopId(request);
            } catch (Exception ignored) {
                shopId = null;
            }
        }
        return couponService.getCouponTemplateDetail(
                org.springframework.util.StringUtils.hasText(openid) ? openid.trim() : null,
                templateId,
                shopId);
    }

    /**
     * 用户单张券详情（{@code user_coupon_id} 为 {@code t_user_coupon.id}）。
     */
    @NoAuth
    @PostMapping("/getUserCoupon")
    public R<UserCouponDTO> getUserCouponDetail(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.paramError("参数不能为空");
        }
        String openid = body.get("openid") != null ? body.get("openid").toString() : null;
        if (!org.springframework.util.StringUtils.hasText(openid)) {
            return R.paramError("openid不能为空");
        }
        Object rid = body.get("user_coupon_id");
        Long userCouponRecordId = null;
        if (rid instanceof Number) {
            userCouponRecordId = ((Number) rid).longValue();
        } else if (rid != null && org.springframework.util.StringUtils.hasText(rid.toString())) {
            try {
                userCouponRecordId = Long.parseLong(rid.toString().trim());
            } catch (NumberFormatException ignored) {
            }
        }
        if (userCouponRecordId == null || userCouponRecordId <= 0) {
            return R.paramError("user_coupon_id不能为空");
        }
        return couponService.getUserCouponDetail(openid.trim(), userCouponRecordId);
    }

    /**
     * 兑换码领取（POST，语义同 {@link #redeemByCode}）。
     */
    @NoAuth
    @PostMapping("/redeemByCode")
    public R<Map<String, Object>> redeemByCodePost(@Valid @RequestBody CouponRedeemPostDTO dto,
                                                    HttpServletRequest request) {
        try {
            if (!StringUtils.hasText(dto.getRedeem_code())) {
                return R.fail("redeem_code不能为空");
            }
            String resolvedOpenid = authenticatedOpenid(request);
            return couponService.receiveCouponByRedeemCode(resolvedOpenid, dto.getRedeem_code().trim());
        } catch (Exception e) {
            log.error("兑换码领取失败", e);
            return R.fail("兑换失败：" + (e.getMessage() != null ? e.getMessage() : "系统异常"));
        }
    }

    private String authenticatedOpenid(HttpServletRequest request) {
        Object value = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (value == null || !StringUtils.hasText(value.toString())) {
            throw new IllegalStateException("用户身份缺失");
        }
        return value.toString().trim();
    }

    /**
     * 用户优惠券分页（{@code status}：usable/used/expired）；可选 {@code shop_id} 或 {@code X-Shop-Id} 按门店过滤。
     */
    @NoAuth
    @PostMapping("/getUserCouponsPage")
    public R<Map<String, Object>> getUserCouponsPage(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        if (body == null) {
            return R.paramError("参数不能为空");
        }
        String openid = body.get("openid") != null ? body.get("openid").toString() : null;
        if (!StringUtils.hasText(openid)) {
            return R.paramError("openid不能为空");
        }
        String status = body.get("status") != null ? body.get("status").toString() : null;
        Integer page = body.get("page") instanceof Number ? ((Number) body.get("page")).intValue() : null;
        Integer pageSize = body.get("pageSize") instanceof Number ? ((Number) body.get("pageSize")).intValue() : null;
        Integer shopId = null;
        if (body.get("shop_id") instanceof Number && ((Number) body.get("shop_id")).intValue() > 0) {
            shopId = ((Number) body.get("shop_id")).intValue();
        } else {
            try {
                shopId = ShopChainSupport.parseHeaderShopId(request);
            } catch (Exception ignored) {
                shopId = null;
            }
        }
        return couponService.getUserCouponsPage(openid.trim(), status, shopId, page, pageSize);
    }

    /**
     * 可领取优惠券分页；可选 {@code shop_id} 或 {@code X-Shop-Id}（严格匹配 {@code apply_shop_ids}）。
     */
    @NoAuth
    @PostMapping("/getAvailablePage")
    public R<Map<String, Object>> getAvailablePage(@RequestBody(required = false) Map<String, Object> body, HttpServletRequest request) {
        String openid = null;
        Integer page = null;
        Integer pageSize = null;
        if (body != null) {
            if (body.get("openid") != null) {
                openid = body.get("openid").toString();
            }
            if (body.get("page") instanceof Number) {
                page = ((Number) body.get("page")).intValue();
            }
            if (body.get("pageSize") instanceof Number) {
                pageSize = ((Number) body.get("pageSize")).intValue();
            }
        }
        Integer shopId = null;
        if (body != null && body.get("shop_id") instanceof Number && ((Number) body.get("shop_id")).intValue() > 0) {
            shopId = ((Number) body.get("shop_id")).intValue();
        } else {
            try {
                shopId = ShopChainSupport.parseHeaderShopId(request);
            } catch (Exception ignored) {
                shopId = null;
            }
        }
        return couponService.getAvailableCouponsPage(
                StringUtils.hasText(openid) ? openid.trim() : null,
                shopId,
                page,
                pageSize);
    }

    /**
     * 解除未支付/非成功订单对用户券的占用（清空 {@code t_user_coupon.order_no}）。
     */
    @NoAuth
    @PostMapping("/unbindFromOrder")
    public R<Void> unbindFromOrder(@RequestBody Map<String, String> body) {
        if (body == null) {
            return R.paramError("参数不能为空");
        }
        String openid = body.get("openid");
        String orderNo = body.get("order_no");
        return couponService.unbindUserCouponFromOrder(openid, orderNo);
    }
}
