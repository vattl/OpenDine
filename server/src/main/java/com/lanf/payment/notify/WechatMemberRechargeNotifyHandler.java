package com.lanf.payment.notify;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.User;
import com.lanf.payment.support.PaymentDateUtil;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IUserService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.PrintWriter;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Date;
import java.util.Map;

@Component
public class WechatMemberRechargeNotifyHandler {

    private static final Logger log = LoggerFactory.getLogger(WechatMemberRechargeNotifyHandler.class);

    @Autowired
    private PaymentNotifyState paymentNotifyState;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private IUserService userService;
    @Autowired
    private com.lanf.payment.channel.wechat.WechatMerchantKeyStore merchantKeyStore;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;

    public void handle(PrintWriter out, String notifyId, String rechargeNo, String outTradeNo,
                       Map<String, Object> paymentResult) throws IOException {
        Boolean alreadyProcessed = paymentNotifyState.getProcessed(notifyId);
        if (Boolean.TRUE.equals(alreadyProcessed)) {
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
            return;
        }
        String tradeStatus = (String) paymentResult.get("trade_state");
        if (!"SUCCESS".equals(tradeStatus)) {
            paymentNotifyState.markProcessed(notifyId);
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
            return;
        }
        Object lock = paymentNotifyState.lockFor(rechargeNo);
        synchronized (lock) {
            MemberRecharge latest = memberRechargeService.getOne(
                    new QueryWrapper<MemberRecharge>()
                            .eq("order_no", rechargeNo)
                            .eq("channel", "wechat")
                            .last("LIMIT 1"));
            if (latest == null) {
                log.error("微信充值流水不存在: {}", rechargeNo);
                out.write("{\"code\":\"FAIL\",\"message\":\"记录不存在\"}");
                return;
            }
            if ("success".equals(latest.getStatus())) {
                log.info("微信充值已入账，跳过重复回调: {}", rechargeNo);
                paymentNotifyState.markProcessed(notifyId);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }
            if (!"pending".equals(latest.getStatus())) {
                log.error("微信充值流水状态异常: {} status={}", rechargeNo, latest.getStatus());
                out.write("{\"code\":\"FAIL\",\"message\":\"状态异常\"}");
                return;
            }

            if (merchantKeyStore != null) {
                com.lanf.payment.channel.wechat.WechatMerchantKeyStore.ResolvedMerchant resolved =
                        merchantKeyStore.resolveForPay(latest.getShop_id(), "1", null);
                if (resolved == null) {
                    log.error("微信充值商户凭据不存在: shopId={}", latest.getShop_id());
                    out.write("{\"code\":\"FAIL\",\"message\":\"商户凭据不存在\"}");
                    return;
                }
                int rechargeShopId = latest.getShop_id() != null ? latest.getShop_id() : 0;
                if (resolved.dbShopId == null
                        || (resolved.dbShopId != com.lanf.payment.config.PaymentConfigCache.GLOBAL_SHOP_ID
                        && resolved.dbShopId != rechargeShopId)) {
                    log.error("微信充值商户不属于当前门店: shopId={} dbShopId={}", rechargeShopId, resolved.dbShopId);
                    out.write("{\"code\":\"FAIL\",\"message\":\"商户不属于当前门店\"}");
                    return;
                }
                String callbackMchId = paymentResult.get("mchid") != null ? paymentResult.get("mchid").toString().trim() : "";
                String callbackAppId = paymentResult.get("appid") != null ? paymentResult.get("appid").toString().trim() : "";
                if (!org.springframework.util.StringUtils.hasText(callbackMchId) || !callbackMchId.equals(resolved.mchId)) {
                    log.error("微信充值商户号不匹配: expect={} actual={}", resolved.mchId, callbackMchId);
                    out.write("{\"code\":\"FAIL\",\"message\":\"商户号不匹配\"}");
                    return;
                }
                if (!org.springframework.util.StringUtils.hasText(callbackAppId) || !callbackAppId.equals(resolved.appId)) {
                    log.error("微信充值AppID不匹配: expect={} actual={}", resolved.appId, callbackAppId);
                    out.write("{\"code\":\"FAIL\",\"message\":\"AppID不匹配\"}");
                    return;
                }
            }

            String transactionId = (String) paymentResult.get("transaction_id");
            String successTime = (String) paymentResult.get("success_time");
            @SuppressWarnings("unchecked")
            Map<String, Object> amount = (Map<String, Object>) paymentResult.get("amount");
            Integer total = amount != null ? (Integer) amount.get("total") : 0;

            double expectYuan = latest.getRecharge_amount() != null ? latest.getRecharge_amount().doubleValue() : 0d;
            int expectFen = com.lanf.util.UserWalletSplitUtil.yuanToFen(expectYuan);
            if (total == null || total <= 0 || !total.equals(expectFen)) {
                log.error("微信充值金额异常(分): 期望={}, 实付={}", expectFen, total);
                out.write("{\"code\":\"FAIL\",\"message\":\"金额不匹配\"}");
                return;
            }
            double paidYuan = (total != null ? total : 0) / 100.0;
            Date payTime = PaymentDateUtil.parseWechatSuccessTime(successTime);
            User u = userService.getUserByOpenid(latest.getOpenid());
            if (u == null || u.getId() == null) {
                log.error("微信充值回调未找到用户: openid={}", latest.getOpenid());
                out.write("{\"code\":\"FAIL\",\"message\":\"用户不存在\"}");
                return;
            }
            BigDecimal paidBd = BigDecimal.valueOf(paidYuan).setScale(2, RoundingMode.HALF_UP);
            BigDecimal giftBd = latest.getGift_amount() != null
                    ? latest.getGift_amount().setScale(2, RoundingMode.HALF_UP)
                    : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
            if (!userService.addBalanceAndGift(u.getId(), paidBd, giftBd)) {
                BigDecimal totalTry = paidBd.add(giftBd).setScale(2, RoundingMode.HALF_UP);
                log.error("微信充值回调入账失败: userId={}, principal={}, gift={}, total={}",
                        u.getId(), paidBd, giftBd, totalTry);
                out.write("{\"code\":\"FAIL\",\"message\":\"入账失败\"}");
                return;
            }
            if (shopMemberWalletService != null) {
                shopMemberWalletService.addBalance(u.getId(), latest.getShop_id(), paidBd, giftBd);
            }
            log.info("微信充值入账: rechargeNo={} out_trade_no={} paidYuan={} giftYuan={} totalCredit={}",
                    rechargeNo, outTradeNo, paidYuan, giftBd, paidBd.add(giftBd).setScale(2, RoundingMode.HALF_UP));
            memberRechargeService.markSuccessWechat(rechargeNo, transactionId, payTime);
        }
        paymentNotifyState.markProcessed(notifyId);
        out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
    }
}
