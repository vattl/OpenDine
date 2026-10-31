package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.dto.InviteCodeDTO;
import com.lanf.dto.InviteRecordDTO;
import com.lanf.dto.R;
import com.lanf.entity.InviteRecord;
import com.lanf.entity.Order;
import com.lanf.entity.User;

import java.util.List;

/**
 * 邀请服务接口（定义业务规范）
 */
public interface InviteService extends IService<InviteRecord> {

    /**
     * 生成/获取用户专属邀请码
     * @param openid 用户唯一标识
     * @return 包含邀请码的响应结果
     */
    R<InviteCodeDTO> getInviteCode(String openid);

    /**
     * 获取用户邀请记录
     * @param openid 用户唯一标识
     * @return 包含邀请记录列表的响应结果
     */
    R<List<InviteRecordDTO>> getInviteRecords(String openid);

    /**
     * 获取用户奖励记录：已发注册礼（{@code reward_time}）或已处理首单返现（{@code first_order_reward_time}）；
     * 同一条邀请若两者皆有，拆成两行，返现行 {@code reward_type=first_order_balance}，见 {@link InviteRecordDTO#getReward_row_uid()}。
     * @param openid 邀请者 openid
     * @return 奖励记录列表
     */
    R<List<InviteRecordDTO>> getRewardRecords(String openid);

    /**
     * 被邀请者注册成功后，发放奖励（邀请者+被邀请者）
     * @param inviteCode 邀请码
     * @param inviteeOpenid 被邀请者openid
     */
    void giveReward(String inviteCode, String inviteeOpenid);

    /**
     * 被邀请好友「首笔」点餐订单支付成功后，按配置将实付的一定比例以余额形式发给邀请人（返现金额按元整数四舍五入；幂等见 {@code t_invite_record.first_order_reward_time}）。
     * 应在支付成功落库后调用；内部失败应记录日志，不应影响支付主流程（由调用方 try/catch 包裹）。
     *
     * @param paidOrder 已置为 {@code transac_status=success} 的订单
     * @param paidYuan  本次实付金额（元）
     */
    void tryGrantInviterBalanceForInviteeFirstPaidOrder(Order paidOrder, double paidYuan);

    /**
     * 订单退款入账后（{@code t_order.refund_amount} 已更新）：若该单曾触发首单返现（{@code t_invite_record.first_order_no} = 订单号），
     * 按当前剩余实付重算应返现整数元，差额调整邀请人余额；若剩余实付为 0（全退），收回已发返现并清空 {@code first_order_no}/{@code first_order_reward_amount}，
     * 保留 {@code first_order_reward_time} 非空使被邀请人不再具备首单返现资格。
     */
    void reconcileFirstOrderInviteRewardOnRefund(Order orderAfterRefundUpdate);
}