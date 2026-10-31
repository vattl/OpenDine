package com.lanf.dto;

import lombok.Data;

/**
 * POST 兑换码领取（与 {@code GET /coupon/redeem} 参数等价）。
 */
@Data
public class CouponRedeemPostDTO {
    private String openid;
    private String phone;
    private String redeem_code;
}
