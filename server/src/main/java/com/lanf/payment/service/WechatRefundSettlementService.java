package com.lanf.payment.service;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.audit.diff.OrderRefundDiffProvider;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.service.IOrderService;
import com.lanf.service.InviteService;
import com.lanf.service.PaymentLedgerService;
import com.lanf.entity.PaymentLedger;
import com.lanf.util.OrderPayChannelAmounts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

/**
 * 微信退款成功入账服务：微信退款回调（{@code OrderController#handleRefundNotify}）与
 * 退款补偿定时任务（{@code WechatRefundQueryScheduler}）共用同一套「台账幂等 + 订单行锁 +
 * 剩余可退截断 + 渠道列扣减」入账逻辑，保证 refund_amount 只累计一次。
 *
 * <p>幂等基准为 {@code t_payment_refund_request} 台账：{@code beginCallback} 按 out_refund_no
 * 行锁并拒绝已 SUCCESS 的记录，入账完成后 {@code markSuccess} 落 SUCCESS；即使微信重复回调或
 * 回调与补偿任务并发，同一退款单也只会入账一次。</p>
 */
@Service
public class WechatRefundSettlementService {

    private static final Logger log = LoggerFactory.getLogger(WechatRefundSettlementService.class);

    private final IOrderService orderService;
    private final PaymentRefundLedger paymentRefundLedger;
    private final InviteService inviteService;

    @org.springframework.beans.factory.annotation.Autowired
    private PaymentLedgerService paymentLedgerService;
    @org.springframework.beans.factory.annotation.Autowired(required = false)
    private com.lanf.service.IShopService shopService;

    public WechatRefundSettlementService(
            IOrderService orderService,
            PaymentRefundLedger paymentRefundLedger,
            InviteService inviteService) {
        this.orderService = orderService;
        this.paymentRefundLedger = paymentRefundLedger;
        this.inviteService = inviteService;
    }

    /**
     * 将一笔微信退款成功金额回写到订单 refund_amount。
     *
     * @param orderNo     订单号（t_order.order_no）
     * @param outRefundNo 微信商户退款单号（out_refund_no，台账幂等键）
     * @param refundFen   微信侧退款金额（分）
     * @param source      入账来源：notify（微信回调）/ compensate（补偿查询）
     * @return true 表示本次实际入账；false 表示已处理过（幂等跳过）或无可入账金额
     */
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "refund", action = "refund_settle", target = "#p0", diff = OrderRefundDiffProvider.class)
    public boolean settle(String orderNo, String outRefundNo, int refundFen, String source) {
        return settleInternal(null, orderNo, outRefundNo, refundFen, source, null);
    }

    /** 微信退款回调入口：以已登记退款申请为权威来源，不信任回调提供的订单归属。 */
    @Transactional(rollbackFor = Exception.class)
    public boolean settleNotification(String outRefundNo, int refundFen,
                                      String transactionId, String mchId) {
        PaymentRefundLedger.Entry entry = paymentRefundLedger.beginVerifiedCallback(
                outRefundNo, refundFen, transactionId, mchId);
        if (entry.isSuccessful()) {
            return false;
        }
        return settleInternal(entry.shopId, entry.orderNo, outRefundNo, refundFen, "notify", entry);
    }

    private boolean settleInternal(Integer expectedShopId, String orderNo, String outRefundNo,
                                   int refundFen, String source, PaymentRefundLedger.Entry expected) {
        if (!StringUtils.hasText(orderNo)
                || !StringUtils.hasText(outRefundNo)
                || refundFen <= 0) {
            log.warn("退款入账参数无效: orderNo={} outRefundNo={} refundFen={} source={}",
                    orderNo, outRefundNo, refundFen, source);
            return false;
        }
        String orderNoTrim = orderNo.trim();
        String outRefundNoTrim = outRefundNo.trim();
        QueryWrapper<Order> orderQuery = new QueryWrapper<Order>().eq("order_no", orderNoTrim);
        if (expectedShopId != null) {
            orderQuery.eq("shop_id", expectedShopId);
        }
        Order order = orderService.getOne(orderQuery.last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            log.error("退款入账订单不存在: orderNo={} outRefundNo={}", orderNoTrim, outRefundNoTrim);
            if (expected != null) {
                throw new IllegalStateException("退款申请绑定的订单不存在");
            }
            return false;
        }
        int shopId = order.getShop_id() != null ? order.getShop_id() : 0;
        if (expected != null) {
            if (!expected.expectedTransactionId.equals(order.getTransaction_id())) {
                throw new IllegalStateException("退款申请绑定的微信交易号与订单不一致");
            }
            if (!expected.merchantConfigId.equals(order.getMerchant_config_id())
                    || !expected.merchantConfigVersion.equals(order.getMerchant_config_version())) {
                throw new IllegalStateException("退款申请绑定的商户凭据与订单不一致");
            }
        }
        if (!paymentRefundLedger.beginCallback(shopId, order.getOrder_no(), outRefundNoTrim, refundFen)) {
            log.info("退款单已入账（台账幂等跳过）: outRefundNo={} source={}", outRefundNoTrim, source);
            return false;
        }

        double paidYuan = nz(order.getSett_amount())
                + nz(order.getService_fee())
                - nz(order.getDiscount_amount());
        int totalPaidFen = com.lanf.util.UserWalletSplitUtil.yuanToFen(paidYuan);
        int previousRefundedFen = fen(order.getRefund_amount());
        int remainingFen = Math.max(0, totalPaidFen - previousRefundedFen);
        int channelFen = OrderPayChannelAmounts.totalPayChannelAmountFen(order);
        int applyFen = Math.min(refundFen, remainingFen);
        if (channelFen > 0) {
            applyFen = Math.min(applyFen, channelFen);
        }

        if (applyFen <= 0) {
            log.warn("退款入账无剩余可退额度，标记台账成功避免重复补偿: orderNo={} outRefundNo={} refundFen={}",
                    orderNoTrim, outRefundNoTrim, refundFen);
            paymentRefundLedger.markSuccess(outRefundNoTrim, 0);
            return false;
        }

        double deltaYuan = yuan(applyFen);
        double newRefundTotalYuan = yuan(previousRefundedFen + applyFen);
        boolean fullRefund = previousRefundedFen + applyFen >= totalPaidFen;
        String oldRemark = order.getRemark() != null ? order.getRemark() : "";
        String refundTag = (fullRefund ? "【退款到账·全额】" : "【退款到账·部分】") + deltaYuan + "元";
        if (!oldRemark.contains(refundTag)) {
            order.setRemark(oldRemark + (StringUtils.hasText(oldRemark) ? "；" : "") + refundTag);
        }

        String bDay = null;
        try {
            com.lanf.entity.Shop shop = shopService != null && order.getShop_id() != null ? shopService.getById(order.getShop_id()) : null;
            if (shop != null) {
                bDay = com.lanf.util.ShopBusinessWindowResolver.operationalBusinessDay(shop).toString();
            }
        } catch (Exception ignored) {
        }
        Long originalLedgerId = findOriginalWechatPaymentId(order);
        paymentLedgerService.recordRefund(
                order, PaymentLedger.CHANNEL_WECHAT, applyFen, null,
                "REF_" + outRefundNoTrim, bDay, originalLedgerId, outRefundNoTrim);

        order.setRefund_amount(newRefundTotalYuan);
        OrderPayChannelAmounts.applyRefundDeltaProportional(order, deltaYuan);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("退款入账订单更新失败: " + orderNoTrim);
        }
        paymentRefundLedger.markSuccess(outRefundNoTrim, applyFen);
        log.info("退款成功已入账: orderNo={} refund_fen={} refunded_total_yuan={} full={} source={}",
                orderNoTrim, applyFen, newRefundTotalYuan, fullRefund, source);
        try {
            inviteService.reconcileFirstOrderInviteRewardOnRefund(order);
        } catch (Exception ex) {
            log.warn("邀请首单返现退款冲正异常（退款已入账）: orderNo={}, err={}", orderNoTrim, ex.getMessage(), ex);
        }
        return true;
    }

    private Long findOriginalWechatPaymentId(Order order) {
        java.util.List<PaymentLedger> ledgers = paymentLedgerService.listByOrder(
                order.getShop_id(), order.getOrder_no());
        PaymentLedger best = null;
        if (ledgers != null) {
            for (PaymentLedger ledger : ledgers) {
                if (!PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())
                        || !PaymentLedger.STATUS_SUCCEEDED.equals(ledger.getStatus())
                        || !PaymentLedger.CHANNEL_WECHAT.equals(ledger.getChannel())) {
                    continue;
                }
                if (StringUtils.hasText(order.getTransaction_id())
                        && order.getTransaction_id().equals(ledger.getProvider_transaction_id())) {
                    return ledger.getId();
                }
                if (best == null || (ledger.getId() != null
                        && (best.getId() == null || ledger.getId() > best.getId()))) {
                    best = ledger;
                }
            }
        }
        return best != null ? best.getId() : null;
    }

    private static double nz(Double value) {
        return value != null ? value : 0d;
    }

    private static int fen(Double value) {
        return com.lanf.util.UserWalletSplitUtil.yuanToFen(com.lanf.util.UserWalletSplitUtil.decimal(value));
    }

    private static double yuan(int fen) {
        return fen / 100.0;
    }
}
