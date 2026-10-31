package com.lanf.dto;

import lombok.Data;

/**
 * 优惠券规则预校验结果。
 */
@Data
public class CouponRuleValidateResult {
    /** 是否满足当前券规则 */
    private boolean valid;
    /** 用户券记录 ID（t_user_coupon.id） */
    private Long coupon_id;
    /** 券模板 ID（t_coupon.id） */
    private Long coupon_template_id;
    /** 券类型 */
    private String coupon_type;
    /** 参与规则计算的金额 */
    private Double eligible_amount;
    /** 订单原价（未优惠前） */
    private Double total_amount;
    /** 门槛金额 */
    private Double min_amount;
    /** 计算得到的优惠金额 */
    private Double discount_amount;
    /** 计算后的应付金额 */
    private Double payable_amount;
    /** 校验说明（通过/失败原因） */
    private String reason;
}
