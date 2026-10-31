package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 优惠券兑换码（一条兑换码对应一张优惠券模板，可一次性领取）。
 */
@Data
@TableName("t_coupon_redeem_code")
public class CouponRedeemCode {
    @TableId(type = IdType.AUTO)
    private Long id;

    private Long coupon_id;

    private String redeem_code;

    /** 0-未使用 1-已使用 */
    private Integer status;

    private String used_openid;

    private Date used_time;

    private Date create_time;
}

