package com.lanf.dto;

import lombok.Data;
import java.util.Date;

@Data // Lombok 自动生成 getter、setter、toString，简化代码
public class UserCouponDTO {
    // 1. 用户优惠券表（t_user_coupon）字段（需要返回给前端的）
    private Long id; // 用户优惠券记录ID
    private String user_openid; // 用户openid（建议用驼峰命名，符合Java规范）
    private Long coupon_id; // 关联优惠券ID
    private Date get_time; // 领取时间
    private Date use_time; // 使用时间
    private String order_no; // 关联订单号
    private Integer status; // 状态：0-未使用 1-已使用 2-已失效
    private Date expire_time; // 失效时间

    // 2. 优惠券表（t_coupon）字段（需要返回给前端的详情）
    private String coupon_name; // 优惠券名称
    private Double discount_value; // 折扣值（如90.00=9折）
    private Double min_amount; // 门槛
    private String coupon_type; // 优惠券类型（如discount=折扣券）
    private Date start_time; // 优惠券有效期开始时间
    private Date end_time; // 优惠券有效期结束时间
    private String description; // 优惠券描述
    private String apply_dining_type;//'适用用餐方式：all=全部，dine_in=仅限堂食，take_out=仅限打包'
    /** 适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3] */
    private String apply_dish_ids;
    /** 适用门店ID数组（JSON字符串），为空表示不限门店，如 [1,2] */
    private String apply_shop_ids;
}