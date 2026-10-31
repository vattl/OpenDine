package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_combo")
public class Combo {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer dish_id;

    /** 门店ID：0表示总部通用默认模板，>0表示指定门店专属套餐 */
    private Integer shop_id;

    /** fixed | groups */
    private String combo_type;

    private Integer status;

    /** 单笔订单限购份数，NULL或<=0表示不限 */
    private Integer limit_per_order;

    /** 单用户限购份数，NULL或<=0表示不限 */
    private Integer limit_per_user;

    /** 用户限购周期：daily(每日)|lifetime(终生) */
    private String limit_cycle;

    /** 活动生效开始时间，NULL表示不限 */
    private Date start_time;

    /** 活动生效截止时间，NULL表示不限 */
    private Date end_time;

    /** 可用星期，逗号分隔，如 1,2,3,4,5 代表周一至周五，NULL表示不限 */
    private String available_days;

    /** 每日可用起始时间段，如 11:00 */
    private String time_range_start;

    /** 每日可用截止时间段，如 14:00 */
    private String time_range_end;

    /** 适用就餐方式：all(全部)|dine_in(仅限堂食)|take_out(仅限外卖打包) */
    private String apply_dining_type;

    /** 是否允许叠加优惠券：1允许 0禁止 */
    private Integer allow_coupon;

    /** 每日套餐配额，NULL表示不限 */
    private Integer daily_stock;

    private Date created_at;

    private Date updated_at;
}
