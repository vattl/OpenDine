package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
import java.math.BigDecimal;
import java.util.Date;


@Data
@TableName("t_coupon")
public class Coupon {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String coupon_name; // 优惠券名称
    private String coupon_type; // full_reduction-满减 discount-折扣 direct_reduction-立减
    private BigDecimal discount_value; // 优惠值（金额/百分比）
    private BigDecimal min_amount; // 使用门槛
    private Date start_time; // 生效时间
    private Date end_time; // 失效时间
    private Integer status; // 0-未启用 1-可用 2-已下架
    private Integer stock; // 库存（-1无限）
    /** 已向用户发放的张数（对应 t_user_coupon 成功写入条数累计） */
    private Integer granted_count;
    private String description; // 描述
    /** 历史字段兼容：兑换码已迁移到 t_coupon_redeem_code，此字段不参与 t_coupon SQL */
    @TableField(exist = false)
    private String redeem_code;
    private Date create_time; // 创建时间
    private Date update_time; // 更新时间
    private String apply_dining_type;//'适用用餐方式：all=全部，dine_in=仅限堂食，take_out=仅限打包'
    /** 适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3] */
    private String apply_dish_ids;
    /** 适用门店 ID 数组（JSON 字符串），空/NULL 表示全部门店，如 [1,2] */
    private String apply_shop_ids;
    private Integer validity_time; //有效期，单位小时
}