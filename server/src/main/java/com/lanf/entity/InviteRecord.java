package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;


@Data
@TableName("t_invite_record")
public class InviteRecord {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String inviter_openid; // 邀请者openid
    private String invitee_openid; // 被邀请者openid
    private String invite_code; // 邀请码
    private Date create_time; // 邀请时间
    private Integer status; // 0-未注册 1-已注册
    private String reward_type; // coupon-优惠券 point-积分
    private Long reward_id; // 奖励ID
    private Date reward_time; // 奖励发放时间

    /** 首单余额奖励金额(元)，整数四舍五入，与 first_order_reward_time 同时写入 */
    private Double first_order_reward_amount;
    /** 首单余额奖励发放时间；非空表示该邀请关系已处理过首单返利 */
    private Date first_order_reward_time;
    /** 触发首单余额奖励的订单号 */
    private String first_order_no;
}