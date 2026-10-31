package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;


@Data
@TableName("t_user_coupon")
public class UserCoupon {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String user_openid; // 用户openid
    private Long coupon_id; // 优惠券ID
    private Date get_time; // 领取时间
    private Date use_time; // 使用时间
    private String order_no; // 关联订单号
    private Integer status; // 0-未使用 1-已使用 2-已失效
    private Date expire_time; // 失效时间
}