package com.lanf.schedule;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatJsapiChannel;
import com.lanf.payment.service.PaymentRefundLedger;
import com.lanf.payment.service.WechatRefundSettlementService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.List;

/**
 * 微信退款补偿对账任务：扫描 {@code t_payment_refund_request} 中仍处于 REQUESTED 状态的退款申请
 * （即微信退款发起后回调缺失/丢失、refund_amount 未回写），调用微信「查询退款单」接口
 * （GET /v3/refund/domestic/refunds/{out_refund_no}）核对实际结果：
 *
 * <ul>
 *   <li>SUCCESS → 复用 {@link WechatRefundSettlementService#settle}（台账幂等）补写 refund_amount；</li>
 *   <li>CLOSED / ABNORMAL → 台账标记 FAILED 并释放幂等键（允许后续重试发起）；</li>
 *   <li>PROCESSING / 其他 → 保持 REQUESTED，等待下一轮轮询。</li>
 * </ul>
 *
 * <p>幂等保证：settle 内部以台账 beginCallback/markSuccess 为基准，补偿任务与微信回调并发
 * 时同一退款单只会入账一次。</p>
 */
@Component
public class WechatRefundQueryScheduler {

    private static final Logger log = LoggerFactory.getLogger(WechatRefundQueryScheduler.class);

    private final PaymentRefundLedger paymentRefundLedger;
    private final IOrderService orderService;
    private final WechatJsapiChannel wechatJsapiChannel;
    private final WechatRefundSettlementService refundSettlementService;

    public WechatRefundQueryScheduler(
            PaymentRefundLedger paymentRefundLedger,
            IOrderService orderService,
            WechatJsapiChannel wechatJsapiChannel,
            WechatRefundSettlementService refundSettlementService) {
        this.paymentRefundLedger = paymentRefundLedger;
        this.orderService = orderService;
        this.wechatJsapiChannel = wechatJsapiChannel;
        this.refundSettlementService = refundSettlementService;
    }

    @Scheduled(fixedDelayString = "${wx.refund-query-ms:300000}")
    public void reconcilePendingWechatRefunds() {
        try {
            List<PaymentRefundLedger.Entry> pending = paymentRefundLedger.findPending(50);
            if (pending.isEmpty()) {
                return;
            }
            log.info("微信退款补偿对账：本轮待跟进退款单 {} 笔", pending.size());
            for (PaymentRefundLedger.Entry entry : pending) {
                try {
                    reconcileOne(entry);
                } catch (Exception ex) {
                    log.error("退款补偿单处理异常（下轮重试）: outRefundNo={} err={}",
                            entry.outRefundNo, ex.getMessage(), ex);
                }
            }
        } catch (Exception ex) {
            log.error("微信退款补偿对账任务执行失败", ex);
        }
    }

    private static int shopIdOf(Order order) {
        return order.getShop_id() != null ? order.getShop_id() : 0;
    }

    private void reconcileOne(PaymentRefundLedger.Entry entry) {
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", entry.orderNo).last("LIMIT 1"));
        if (order == null) {
            log.warn("退款补偿：订单不存在，跳过（保持 REQUESTED 待人工核对）: orderNo={}", entry.orderNo);
            return;
        }
        if (!StringUtils.hasText(order.getTransaction_id())) {
            log.warn("退款补偿：订单无微信交易单号（非微信支付渠道），标记失败释放幂等键: orderNo={}", entry.orderNo);
            paymentRefundLedger.markRequestFailed(shopIdOf(order), entry.idempotencyKey);
            return;
        }
        R query = wechatJsapiChannel.queryDomesticRefund(order, entry.outRefundNo);
        if (query == null) {
            log.warn("退款补偿查询返回空（下轮重试）: outRefundNo={}", entry.outRefundNo);
            return;
        }
        Object codeObj = query.get("code");
        if (codeObj instanceof Number && ((Number) codeObj).intValue() != 0) {
            log.warn("退款补偿查询失败（下轮重试）: outRefundNo={} msg={}",
                    entry.outRefundNo, query.get("msg"));
            return;
        }
        String status = query.get("status") != null ? query.get("status").toString() : "";
        int refundedFen = query.get("amount_refund_fen") instanceof Number
                ? ((Number) query.get("amount_refund_fen")).intValue() : 0;
        if ("SUCCESS".equals(status)) {
            refundSettlementService.settle(entry.orderNo, entry.outRefundNo, refundedFen, "compensate");
        } else if ("CLOSED".equals(status) || "ABNORMAL".equals(status)) {
            log.warn("退款补偿：微信退款单终态非成功，标记失败释放幂等键: outRefundNo={} status={}",
                    entry.outRefundNo, status);
            paymentRefundLedger.markRequestFailed(shopIdOf(order), entry.idempotencyKey);
        } else {
            log.info("退款补偿：微信退款处理中，保持 REQUESTED 等待下轮: outRefundNo={} status={}",
                    entry.outRefundNo, status);
        }
    }
}
