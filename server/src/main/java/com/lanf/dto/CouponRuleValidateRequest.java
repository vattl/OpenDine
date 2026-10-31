package com.lanf.dto;

import com.lanf.entity.OrderDetail;
import lombok.Data;

import java.util.List;

/**
 * 优惠券规则预校验请求（仅校验，不占用券）。
 */
@Data
public class CouponRuleValidateRequest {
    /** 用户 openid */
    private String openid;
    /** 用户券记录 ID（t_user_coupon.id） */
    private Long coupon_id;
    /** 当前订单号；后端支付链路用于幂等复检已被本订单占用的券。 */
    private String order_no;
    /** 连锁门店 ID（t_shop.id，可选） */
    private Integer shop_id;
    /** 就餐方式：堂食/打包（可选） */
    private String dineInOrTakeOut;
    /** 订单明细（至少需 name 与 total_price） */
    private List<OrderDetail> goods_list;
    /**
     * 客户端传入的优惠金额（可选）。
     * 非空时将与服务端按券规则计算结果比对；C 端/旧版小程序建议不传，由服务端计算并写回订单。
     */
    private Double discount_amount;
}
