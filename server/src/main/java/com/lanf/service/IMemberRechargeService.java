package com.lanf.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.MemberRecharge;

import java.math.BigDecimal;
import java.util.Date;
import java.util.List;

/**
 * 会员充值流水：微信预下单、支付回调、后台充值、C 端分页查询。
 */
public interface IMemberRechargeService extends IService<MemberRecharge> {

    /**
     * 创建微信渠道待支付充值流水。{@code giftAmountYuan} 为活动赠送（用户不付微信），支付成功时与实付一并入账余额。
     */
    Long createPendingWechat(Integer userId, String openid, String orderNo, Integer shopId,
                             BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan);

    void updateOrderNo(String oldOrderNo, String newOrderNo);

    boolean markSuccessWechat(String orderNo, String transactionId, Date payTime);

    void markCancelledById(Long id);

    void markCancelledByOrderNo(String orderNo);

    /**
     * 用户取消未支付的微信充值流水（与点餐取消共用参数名 order_no，实为充值商户单号）。
     */
    boolean cancelPendingWechat(String rechargeNo, String openid);

    void recordAdminSuccess(Integer userId, String openid, BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark);

    /**
     * 后台人工充值入账流水；{@code shopId} 为操作发生的门店（可为 null，表示历史跨店/总部操作）。
     */
    void recordAdminSuccess(Integer userId, String openid, Integer shopId,
                            BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark);

    /** 后台人工充值，并记录由服务端解析的操作员与钱箱班次归属。 */
    void recordAdminSuccess(Integer userId, String openid, Integer shopId, Integer operatorId, Long drawerSessionId,
                            BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark);

    /** 按门店营业窗口汇总成功充值，时间范围为左闭右开。 */
    MemberRechargeSummary summarizeSuccessfulByWindow(Integer shopId, Date startInclusive, Date endExclusive);

    /** 按显式钱箱会话归属汇总成功充值。 */
    MemberRechargeSummary summarizeSuccessfulByDrawerSession(Long drawerSessionId);

    IPage<MemberRecharge> pageByOpenid(String openid, int page, int pageSize, String statusFilter);

    /**
     * 批量补全充值流水关联的会员手机号（基于 user_id / openid 关联 t_user）
     */
    void attachMemberPhones(List<MemberRecharge> records);
}
