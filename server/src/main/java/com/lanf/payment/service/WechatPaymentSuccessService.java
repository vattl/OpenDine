package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentDateUtil;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.support.PaymentSettlementLedgerHelper;
import com.lanf.service.IOrderService;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.OrderNetRevenue;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.Map;

/** 回调与主动查单共用的微信支付成功入账入口。 */
@Service
public class WechatPaymentSuccessService {
    @Autowired private IOrderService orderService;
    @Autowired private OrderPaymentBridge orderPaymentBridge;
    @Autowired private PaymentNotifyState paymentNotifyState;
    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private PaymentSettlementLedgerHelper paymentSettlementLedgerHelper;

    @Transactional
    public ApplyResult apply(String orderNo, String expectedOutTradeNo, Map<String, Object> payment,
                             String merchantId, Integer expectedAmountFen) {
        return apply(orderNo, expectedOutTradeNo, payment, merchantId, expectedAmountFen, null);
    }

    @Transactional
    public ApplyResult apply(String orderNo, String expectedOutTradeNo, Map<String, Object> payment,
                             String merchantId, Integer expectedAmountFen, Integer expectedShopId) {
        if (payment == null || !"SUCCESS".equals(text(payment.get("trade_state")))) {
            return ApplyResult.error("TRADE_NOT_SUCCESS", "微信交易未成功");
        }
        if (!expectedOutTradeNo.equals(text(payment.get("out_trade_no")))) {
            return ApplyResult.error("OUT_TRADE_NO_MISMATCH", "商户单号不匹配");
        }
        String tradeType = text(payment.get("trade_type"));
        if (StringUtils.hasText(tradeType) && !"NATIVE".equals(tradeType) && !"JSAPI".equals(tradeType)
                && !"MICROPAY".equals(tradeType)) {
            return ApplyResult.error("TRADE_TYPE_MISMATCH", "交易类型不匹配");
        }
        Integer total = amountTotal(payment);
        if (total == null || total <= 0 || (expectedAmountFen != null && !expectedAmountFen.equals(total))) {
            return ApplyResult.error("AMOUNT_MISMATCH", "金额不匹配");
        }
        synchronized (paymentNotifyState.lockFor(orderNo)) {
            QueryWrapper<Order> orderQuery = new QueryWrapper<Order>().eq("order_no", orderNo);
            if (expectedShopId != null) orderQuery.eq("shop_id", expectedShopId);
            Order order = orderService.getOne(orderQuery.last("LIMIT 1 FOR UPDATE"));
            if (order == null) return ApplyResult.error("ORDER_NOT_FOUND", "订单不存在");
            if (merchantKeyStore == null) {
                return ApplyResult.error("MERCHANT_VALIDATOR_UNAVAILABLE", "商户凭据校验器不可用");
            }
            String legacyOrderMerchantId = StringUtils.hasText(order.getMerchantId())
                    ? order.getMerchantId() : merchantId;
            WechatMerchantKeyStore.ResolvedMerchant resolved = order.getMerchant_config_id() != null
                    && order.getMerchant_config_version() != null
                    ? merchantKeyStore.resolveBound(
                            order.getMerchant_config_id(), order.getMerchant_config_version(), order.getShop_id())
                    : merchantKeyStore.resolveForPay(
                            order.getShop_id(), StringUtils.hasText(legacyOrderMerchantId) ? legacyOrderMerchantId : "1", null);
            if (resolved == null) return ApplyResult.error("MERCHANT_BINDING_MISSING", "订单绑定的商户凭据不存在");
            int orderShopId = order.getShop_id() != null ? order.getShop_id() : 0;
            if (resolved.dbShopId == null
                    || (resolved.dbShopId != PaymentConfigCache.GLOBAL_SHOP_ID
                    && resolved.dbShopId != orderShopId)) {
                return ApplyResult.error("MERCHANT_SHOP_MISMATCH", "订单绑定的商户不属于当前门店");
            }
            String callbackMchId = text(payment.get("mchid"));
            String callbackAppId = text(payment.get("appid"));
            if (!StringUtils.hasText(callbackMchId)) {
                return ApplyResult.error("MCH_ID_MISSING", "回调商户号缺失");
            }
            if (!callbackMchId.equals(resolved.mchId)) {
                return ApplyResult.error("MCH_ID_MISMATCH", "商户号不匹配");
            }
            if (!StringUtils.hasText(callbackAppId)) {
                return ApplyResult.error("APP_ID_MISSING", "回调AppID缺失");
            }
            if (!callbackAppId.equals(resolved.appId)) {
                return ApplyResult.error("APP_ID_MISMATCH", "AppID不匹配");
            }
            String transactionId = text(payment.get("transaction_id"));
            if (!StringUtils.hasText(transactionId)) return ApplyResult.error("TRANSACTION_ID_MISSING", "微信支付单号缺失");
            if ("success".equals(order.getTransac_status())) {
                return transactionId.equals(order.getTransaction_id())
                        ? ApplyResult.alreadyPaid()
                        : ApplyResult.error("DUPLICATE_PAYMENT", "检测到另一笔微信支付，请立即对账处理");
            }
            if (!"unsettled".equals(order.getTransac_status())) {
                return ApplyResult.error("ORDER_STATE_INVALID", "订单状态不允许支付");
            }
            int payableFen = OrderNetRevenue.netRevenueFen(order);
            if (total != payableFen || payableFen <= 0) {
                return ApplyResult.error("AMOUNT_MISMATCH", "支付金额与订单当前应付金额不匹配");
            }
            order.setTransac_status("success");
            order.setTransaction_id(transactionId);
            if (order.getMerchant_config_id() == null) {
                order.setMerchantId(StringUtils.hasText(merchantId) ? merchantId : "1");
            }
            order.setPayment_method("微信支付");
            order.setPay_time(PaymentDateUtil.parseWechatSuccessTime(text(payment.get("success_time"))));
            Object payerValue = payment.get("payer");
            if (payerValue instanceof Map) {
                String openid = text(((Map<?, ?>) payerValue).get("openid"));
                order.setPay_openid(openid);
                if (!StringUtils.hasText(order.getOpenid())) order.setOpenid(openid);
            }
            double paidYuan = total / 100d;
            OrderPayChannelAmounts.applySingleChannel(order, "wechat", paidYuan);
            // 权威资金流水必须先于订单成功状态持久化；二者处于同一事务，任一步失败全部回滚。
            paymentSettlementLedgerHelper.recordAuthoritativePayment(
                    order, null, null, "WECHAT_" + transactionId);
            if (!orderService.updateById(order)) {
                throw new IllegalStateException("订单入账失败，权威资金流水已回滚");
            }
            orderPaymentBridge.runPostPaymentSuccessSideEffects(order, paidYuan);
            return ApplyResult.applied();
        }
    }

    @SuppressWarnings("unchecked")
    private static Integer amountTotal(Map<String, Object> payment) {
        Object amount = payment.get("amount");
        if (!(amount instanceof Map)) return null;
        Object total = ((Map<String, Object>) amount).get("total");
        return total instanceof Number ? ((Number) total).intValue() : null;
    }
    private static String text(Object value) { return value == null ? null : String.valueOf(value); }

    public static class ApplyResult {
        public final boolean success;
        public final boolean alreadyPaid;
        public final String code;
        public final String message;
        private ApplyResult(boolean success, boolean alreadyPaid, String code, String message) {
            this.success = success; this.alreadyPaid = alreadyPaid; this.code = code; this.message = message;
        }
        public static ApplyResult applied() { return new ApplyResult(true, false, "APPLIED", "支付已入账"); }
        public static ApplyResult alreadyPaid() { return new ApplyResult(true, true, "ALREADY_PAID", "订单已支付"); }
        public static ApplyResult error(String code, String message) { return new ApplyResult(false, false, code, message); }
    }
}
