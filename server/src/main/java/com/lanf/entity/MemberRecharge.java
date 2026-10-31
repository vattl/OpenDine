package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 会员充值流水，对应 t_member_recharge。
 */
@Data
@TableName("t_member_recharge")
public class MemberRecharge {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer user_id;

    private String openid;

    /** 微信充值商户单号（与 t_order.order_no 无关）；后台充值可为 null */
    private String order_no;

    private Integer shop_id;

    /** 后台人工充值操作员；C 端微信充值及历史记录可为空。 */
    private Integer operator_id;

    /** 后台人工充值发生的钱箱会话；无活动班次时为空。 */
    private Long drawer_session_id;

    /** wechat | admin */
    private String channel;

    /** pending | success | cancelled */
    private String status;

    private BigDecimal recharge_amount;

    private BigDecimal gift_amount;

    private BigDecimal total_amount;

    private String transaction_id;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date pay_time;

    private String remark;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date created_at;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date updated_at;

    /**
     * 会员手机号（非 t_member_recharge 物理列，由关联 t_user 补全返回）
     */
    @TableField(exist = false)
    private String phone;
}
