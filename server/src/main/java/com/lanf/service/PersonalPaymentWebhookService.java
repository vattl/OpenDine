package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.PersonalPaymentEvent;
import com.lanf.mapper.PersonalPaymentEventMapper;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.util.OrderPayChannelAmounts;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;


import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 个人支付宝/微信收款通知处理服务（出码 3 分钟有效窗口匹配、订单自动结账、幂等去重、持久化事件流水）
 */
@Service
@RequiredArgsConstructor
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class PersonalPaymentWebhookService {

    private static final Logger log = LoggerFactory.getLogger(PersonalPaymentWebhookService.class);

    private final PersonalPaymentEventMapper personalPaymentEventMapper;
    private final CashierCollectionIntentService collectionIntentService;
    private final IOrderService orderService;
    private final PaymentSuccessHandler paymentSuccessHandler;
    private final JdbcTemplate jdbcTemplate;
    private final CashierCheckoutService cashierCheckoutService;



    /**
     * 判断事件 ID 是否已经处理过（幂等去重）
     */
    public boolean isEventProcessed(String eventId) {
        if (!StringUtils.hasText(eventId)) {
            return false;
        }
        Integer count = personalPaymentEventMapper.selectCount(new QueryWrapper<PersonalPaymentEvent>()
                .eq("event_id", eventId.trim()));
        return count != null && count > 0;
    }

    /**
     * 处理个人收款通知并执行 3 分钟窗口匹配与官方对齐结账
     */
    @Transactional(rollbackFor = Exception.class)
    public void processPayment(String eventId, String channel, long amountFen,
                               String timestampRaw, String rawText, Integer shopId, Integer merchantId) {
        if (!StringUtils.hasText(eventId)) {
            return;
        }
        if (isEventProcessed(eventId)) {
            log.info("个人收款事件已处理过，跳过重复写入: eventId={}", eventId);
            return;
        }

        BigDecimal amountYuan = BigDecimal.valueOf(amountFen)
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        double paidYuan = amountFen / 100.0;
        Date arrivalTime = parseArrivalTime(timestampRaw);

        log.info("收到 {} 到账通知: {} 元 ({}分), arrivalTime={}, event_id={}",
                channel, amountYuan, amountFen, arrivalTime, eventId);

        // 匹配门店优先级：merchantId（回调显式指定）> shop_id（兼容旧回调）> 默认门店 1
        Integer matchShopId = (merchantId != null && merchantId > 0) ? merchantId
                : (shopId != null && shopId > 0 ? shopId : 1);

        // 1. 在 3 分钟（180秒）有效时间窗口内匹配出码意向
        CashierCollectionIntentService.MatchedIntent matchedIntent = null;
        boolean needsReview = false;
        try {
            if (amountFen > 0 && amountFen <= Integer.MAX_VALUE) {
                matchedIntent = collectionIntentService.matchAndConfirmByWebhook(
                        matchShopId, channel, (int) amountFen, arrivalTime);
            }
        } catch (CashierCollectionIntentService.AmbiguousCollectionException e) {
            needsReview = true;
        }

        String matchedOrderNo = null;
        Integer finalShopId = matchShopId;
        if (matchedIntent != null) {
            matchedOrderNo = matchedIntent.getOrderNo();
            finalShopId = matchedIntent.getShopId();
            log.info("在 3 分钟窗口内命中出码意向: orderNo={}, shopId={}, sessionId={}",
                    matchedOrderNo, finalShopId, matchedIntent.getSessionId());

        }

        String status = needsReview ? "NEEDS_REVIEW" : "UNMATCHED";
        String remark = "未在 3 分钟有效时间窗口内匹配到待结账出码记录";

        if (matchedOrderNo != null) {
            SettleResult settle = settleOrder(matchedOrderNo, channel, amountFen, arrivalTime, eventId,
                    matchedIntent != null ? matchedIntent.getSessionId() : null,
                    matchedIntent != null ? matchedIntent.getShopId() : finalShopId);
            if (settle != null) {
                status = settle.status;
                remark = settle.remark;
                if ("MATCHED_SETTLED".equals(settle.status)) {
                    log.info("订单自动结账成功: orderNo={}, shopId={}, paidYuan={}",
                            matchedOrderNo, finalShopId, paidYuan);
                }
            }
        }

        PersonalPaymentEvent event = new PersonalPaymentEvent();
        event.setEvent_id(eventId.trim());
        event.setChannel(channel != null ? channel.trim().toLowerCase() : "unknown");
        event.setAmount_fen(amountFen);
        event.setAmount_yuan(amountYuan);
        event.setTimestamp_raw(timestampRaw);
        event.setRaw_text(null); // Notification text is not needed for matching or reconciliation.
        event.setMatched_shop_id(finalShopId);
        event.setMatched_order_no(matchedOrderNo);
        event.setStatus(status);
        event.setRemark(remark);
        event.setCreated_at(new Date());

        personalPaymentEventMapper.insert(event);
    }

    /** 结账结果：状态 + 流水备注（供回调路径与出码补偿共用）。 */
    private static class SettleResult {
        final String status;
        final String remark;
        SettleResult(String status, String remark) {
            this.status = status;
            this.remark = remark;
        }
    }

    /**
     * 对指定订单执行收款码自动结账（回调与出码补偿全面复用 CashierCheckoutService 结账主流程）：
     * <ul>
     *   <li>订单不存在 → 返回 {@code null}</li>
     *   <li>未结账 → 走 CashierCheckoutService.checkout，完成结账、清台、小票打印、会员反积分，返回 {@code MATCHED_SETTLED}</li>
     *   <li>已结账 → {@code MATCHED_ALREADY_PAID}</li>
     *   <li>状态不支持 → {@code MATCHED_INVALID_STATUS}</li>
     * </ul>
     */
    private SettleResult settleOrder(String orderNo, String channel, long amountFen, Date arrivalTime,
                                     String eventId, String sessionId, Integer shopId) {
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo)
                .last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return null;
        }
        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            if ("success".equalsIgnoreCase(order.getTransac_status())) {
                return new SettleResult("MATCHED_ALREADY_PAID", "匹配订单但已处于已结账状态: " + orderNo);
            }
            return new SettleResult("MATCHED_INVALID_STATUS",
                    "订单状态不支持结账: " + order.getTransac_status());
        }

        int targetShopId = shopId != null && shopId > 0 ? shopId : (order.getShop_id() != null ? order.getShop_id() : 1);
        String normalizedChannel = channel != null ? channel.trim().toLowerCase() : "wechat";

        Map<String, Object> checkoutBody = new java.util.HashMap<>();
        checkoutBody.put("order_no", orderNo);
        checkoutBody.put("payment_method", "alipay".equals(normalizedChannel)
                ? PaymentChannelCatalog.NAME_ALIPAY_QR_AUTO
                : PaymentChannelCatalog.NAME_WECHAT_QR_AUTO);
        if (StringUtils.hasText(sessionId)) {
            checkoutBody.put("collection_session_id", sessionId.trim());
        }
        if ("alipay".equals(normalizedChannel)) {
            checkoutBody.put("pay_amount_alipay", amountFen / 100.0);
        } else {
            checkoutBody.put("pay_amount_wechat", amountFen / 100.0);
        }

        com.lanf.entity.R checkoutResult = cashierCheckoutService.checkoutKeepMerchantId(targetShopId, checkoutBody);
        if (checkoutResult == null || !Integer.valueOf(0).equals(checkoutResult.get("code"))) {
            String errorMsg = checkoutResult != null && checkoutResult.get("msg") != null
                    ? checkoutResult.get("msg").toString() : "未知错误";
            log.warn("[payment] 复用 CashierCheckoutService 结账返回失败: order={} err={}", orderNo, errorMsg);
            return new SettleResult("MATCHED_FAILED", "结账流程执行失败: " + errorMsg);
        }

        return new SettleResult("MATCHED_SETTLED",
                "已在 3 分钟有效窗口内匹配并完成订单结账与小票打印: " + orderNo);
    }

    /**
     * 出码补偿：客人<strong>先付款、收银员后出码</strong>时，回调早已过去、意向永远匹配不到。
     * 出码时往前 {@link #REVERSE_MATCH_WINDOW_MS}（1分钟）内查找同渠道、同金额、未使用（{@code UNMATCHED}）且未绑定订单的到账记录，
     * 恰好命中 1 条则复用 {@link #settleOrder}（及底层 {@link CashierCheckoutService}）完成自动结账，并把事件标记为已使用防重复。
     *
     * @return true 表示已自动结账
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean settleByRecentPaid(int shopId, String orderNo, String channel, int amountFen, String sessionId) {
        String normalizedChannel = channel != null ? channel.trim().toLowerCase() : channel;
        Date windowStart = new Date(System.currentTimeMillis() - REVERSE_MATCH_WINDOW_MS);
        List<PersonalPaymentEvent> candidates = personalPaymentEventMapper.selectList(new QueryWrapper<PersonalPaymentEvent>()
                .eq("channel", normalizedChannel)
                .eq("amount_fen", (long) amountFen)
                .eq("status", "UNMATCHED")
                .isNull("matched_order_no")
                .ge("created_at", windowStart)
                .eq("matched_shop_id", shopId)
                .orderByDesc("id")
                .last("LIMIT 2 FOR UPDATE"));
        if (candidates == null || candidates.isEmpty()) {
            return false;
        }
        if (candidates.size() > 1) {
            log.warn("[payment] 出码补偿匹配到多条未用收款记录，拒绝自动结账: shop={} channel={} amount={} count={}",
                    shopId, normalizedChannel, amountFen, candidates.size());
            return false;
        }
        PersonalPaymentEvent evt = candidates.get(0);
        if (!Integer.valueOf(shopId).equals(evt.getMatched_shop_id())) return false;

        // 1. 设置出码会话在 t_cashier_collection_intent 中置为 CONFIRMED
        collectionIntentService.confirmDirect(shopId, orderNo, sessionId, normalizedChannel, amountFen);

        // 2. 复用标准结账流程
        SettleResult settle = settleOrder(orderNo, normalizedChannel, amountFen,
                parseArrivalTime(evt.getTimestamp_raw()), evt.getEvent_id(), sessionId, shopId);
        if (settle == null || !"MATCHED_SETTLED".equals(settle.status)) {
            log.warn("[payment] 出码补偿结账未完成: order={} status={}", orderNo,
                    settle != null ? settle.status : "null");
            return false;
        }
        // 标记事件已使用，防止下次出码重复结账
        evt.setStatus("MATCHED_SETTLED");
        evt.setMatched_shop_id(shopId);
        evt.setMatched_order_no(orderNo);
        evt.setRemark("出码补偿自动结账: " + orderNo);
        personalPaymentEventMapper.updateById(evt);
        log.info("[payment] 出码补偿自动结账成功: orderNo={} shopId={} channel={} amountFen={}",
                orderNo, shopId, normalizedChannel, amountFen);
        return true;
    }

    /** 出码反向匹配到账记录的往前时间窗口（毫秒）。 */
    static final long REVERSE_MATCH_WINDOW_MS = 60_000L;

    private Date parseArrivalTime(String timestampRaw) {
        if (!StringUtils.hasText(timestampRaw)) {
            return new Date();
        }
        try {
            long ts = Long.parseLong(timestampRaw.trim());
            if (ts < 100000000000L) {
                ts = ts * 1000L;
            }
            Date date = new Date(ts);
            return date;
        } catch (Exception e) {
            return new Date();
        }
    }

}
