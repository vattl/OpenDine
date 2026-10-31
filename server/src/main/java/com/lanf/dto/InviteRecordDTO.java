// 邀请记录DTO
package com.lanf.dto;

import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;


@Data
public class InviteRecordDTO {
    /** t_invite_record.id，用于前端详情定位 */
    private Long id;
    /**
     * 仅 {@code /invite/getReward} 列表：同一 {@link #id} 可能拆成注册礼行与首单返现两行，
     * 格式为 {@code {id}-full} | {@code {id}-reg} | {@code {id}-cash}，作列表项唯一键。
     */
    private String reward_row_uid;
    private String invitee_openid; // 被邀请者openid
    private String phone;     // 被邀请者手机号
    private String name;      // 被邀请者名称
    private String avatar;      // 被邀请者头像
    private Date reward_time; // 奖励发放时间
    private Integer status; // 状态：0-未发放 1-已发放
    private Date create_time; // 邀请时间
    /** 奖励类型：coupon、point；首单余额返现独立成行时为 {@code first_order_balance} */
    private String reward_type;
    /** 奖励关联 ID：coupon 时为 t_coupon.id；与 {@link #id}（邀请记录行 id）不同 */
    private Long reward_id; // 奖励优惠券ID（reward_type=coupon时）/积分值（reward_type=point时）
    /** reward_type=coupon 时由 t_coupon 表填充 */
    private String coupon_name; // 优惠券名称
    private String coupon_type; // 优惠券类型：full_reduction-满减 discount-折扣 direct_reduction-立减
    private BigDecimal discount_value; // 优惠值（金额/折扣）
    /** 优惠券使用门槛（元），reward_type=coupon 时由 t_coupon 填充 */
    private BigDecimal min_amount;

    /** 首单余额返现金额（元，整数），与 first_order_reward_time 同时有值表示已发放 */
    private Double first_order_reward_amount;
    /** 首单余额返现发放时间 */
    private Date first_order_reward_time;
    /** 触发首单返现的订单号 */
    private String first_order_no;
}