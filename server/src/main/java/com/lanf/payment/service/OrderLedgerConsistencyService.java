package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.PaymentLedgerService;
import com.lanf.util.OrderNetRevenue;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.LinkedHashSet;

/**
 * Compares the order payment projection with the immutable, authoritative payment ledger.
 */
@Service
public class OrderLedgerConsistencyService {

    private final PaymentLedgerService paymentLedgerService;

    public OrderLedgerConsistencyService(PaymentLedgerService paymentLedgerService) {
        this.paymentLedgerService = paymentLedgerService;
    }

    public List<Issue> audit(List<Order> orders) {
        if (orders == null || orders.isEmpty()) {
            return Collections.emptyList();
        }
        Map<String, List<PaymentLedger>> ledgersByOrder = loadLedgersByOrder(orders);
        List<Issue> issues = new ArrayList<>();
        for (Order order : orders) {
            if (order == null || !"success".equals(order.getTransac_status())
                    || ReceivableService.PAYMENT_METHOD_RECEIVABLE.equals(order.getPayment_method())) {
                continue;
            }
            Map<String, Integer> expected = expectedByChannel(order);
            Map<String, Integer> actual = actualByChannel(
                    ledgersByOrder.getOrDefault(key(order.getShop_id(), order.getOrder_no()), Collections.emptyList()));
            if (!expected.equals(actual)) {
                issues.add(new Issue(order.getId(), order.getShop_id(), order.getOrder_no(),
                        order.getPayment_method(), expected, actual));
            }
        }
        return issues;
    }

    private Map<String, List<PaymentLedger>> loadLedgersByOrder(List<Order> orders) {
        Map<Integer, Set<String>> orderNosByShop = new LinkedHashMap<>();
        for (Order order : orders) {
            if (order != null && order.getShop_id() != null && order.getOrder_no() != null
                    && !ReceivableService.PAYMENT_METHOD_RECEIVABLE.equals(order.getPayment_method())) {
                orderNosByShop.computeIfAbsent(order.getShop_id(), ignored -> new LinkedHashSet<>())
                        .add(order.getOrder_no());
            }
        }
        Map<String, List<PaymentLedger>> result = new LinkedHashMap<>();
        for (Map.Entry<Integer, Set<String>> shopEntry : orderNosByShop.entrySet()) {
            List<String> orderNos = new ArrayList<>(shopEntry.getValue());
            for (int from = 0; from < orderNos.size(); from += 500) {
                List<String> chunk = orderNos.subList(from, Math.min(from + 500, orderNos.size()));
                List<PaymentLedger> ledgers = paymentLedgerService.list(new QueryWrapper<PaymentLedger>()
                        .eq("shop_id", shopEntry.getKey())
                        .eq("status", PaymentLedger.STATUS_SUCCEEDED)
                        .in("order_no", chunk)
                        .orderByAsc("id"));
                if (ledgers == null) {
                    continue;
                }
                for (PaymentLedger ledger : ledgers) {
                    result.computeIfAbsent(key(ledger.getShop_id(), ledger.getOrder_no()), ignored -> new ArrayList<>())
                            .add(ledger);
                }
            }
        }
        return result;
    }

    private Map<String, Integer> expectedByChannel(Order order) {
        Map<String, Integer> expected = new LinkedHashMap<>();
        add(expected, PaymentChannelCatalog.ledgerChannel(order.getPayment_method(), PaymentLedger.CHANNEL_WECHAT),
                toFen(order.getPay_amount_wechat()));
        add(expected, PaymentChannelCatalog.ledgerChannel(order.getPayment_method(), PaymentLedger.CHANNEL_ALIPAY),
                toFen(order.getPay_amount_alipay()));
        add(expected, PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, toFen(order.getPay_amount_balance()));
        add(expected, PaymentLedger.CHANNEL_CASH, toFen(order.getPay_amount_cash()));
        add(expected, PaymentLedger.CHANNEL_GIFT, toFen(order.getPay_amount_gift()));

        if (expected.isEmpty()) {
            int fallbackFen = Math.max(0, OrderNetRevenue.netRevenueFen(order));
            add(expected, inferredLedgerChannel(order.getPayment_method()), fallbackFen);
        }
        return expected;
    }

    private Map<String, Integer> actualByChannel(List<PaymentLedger> ledgers) {
        Map<String, Integer> actual = new LinkedHashMap<>();
        if (ledgers == null) {
            return actual;
        }
        for (PaymentLedger ledger : ledgers) {
            if (ledger == null || !PaymentLedger.STATUS_SUCCEEDED.equals(ledger.getStatus())
                    || !isSettlementEntry(ledger.getEntry_type())) {
                continue;
            }
            add(actual, ledger.getChannel(), ledger.getAmount_fen() != null ? ledger.getAmount_fen() : 0);
        }
        return actual;
    }

    private static String key(Integer shopId, String orderNo) {
        return String.valueOf(shopId) + "|" + String.valueOf(orderNo);
    }

    private static boolean isSettlementEntry(String type) {
        return PaymentLedger.ENTRY_TYPE_PAYMENT.equals(type)
                || PaymentLedger.ENTRY_TYPE_REFUND.equals(type)
                || PaymentLedger.ENTRY_TYPE_REVERSAL.equals(type)
                || PaymentLedger.ENTRY_TYPE_ADJUSTMENT.equals(type);
    }

    private static String inferredLedgerChannel(String paymentMethod) {
        String code = PaymentChannelCatalog.codeFromPaymentMethod(paymentMethod);
        if (PaymentChannelCatalog.ONLINE_WECHAT.equals(code)) {
            return PaymentLedger.CHANNEL_WECHAT;
        }
        if (PaymentChannelCatalog.ONLINE_ALIPAY.equals(code)) {
            return PaymentLedger.CHANNEL_ALIPAY;
        }
        if (PaymentChannelCatalog.ONLINE_BALANCE.equals(code)) {
            return PaymentLedger.CHANNEL_BALANCE_PRINCIPAL;
        }
        if (PaymentChannelCatalog.OFFLINE_WECHAT_QR.equals(code)) {
            return PaymentLedger.CHANNEL_WECHAT_QR;
        }
        if (PaymentChannelCatalog.OFFLINE_ALIPAY_QR.equals(code)) {
            return PaymentLedger.CHANNEL_ALIPAY_QR;
        }
        return PaymentLedger.CHANNEL_CASH;
    }

    private static int toFen(Double yuan) {
        return yuan == null ? 0 : (int) Math.round(yuan * 100d);
    }

    private static void add(Map<String, Integer> amounts, String channel, int amountFen) {
        if (channel == null || amountFen == 0) {
            return;
        }
        amounts.merge(channel, amountFen, Integer::sum);
        if (amounts.get(channel) == 0) {
            amounts.remove(channel);
        }
    }

    public static final class Issue {
        private final Integer orderId;
        private final Integer shopId;
        private final String orderNo;
        private final String paymentMethod;
        private final Map<String, Integer> expectedByChannel;
        private final Map<String, Integer> actualByChannel;
        private final List<String> reasonCodes;
        private final List<String> reasons;
        private final List<Map<String, Object>> channelDifferences;

        public Issue(String orderNo, Map<String, Integer> expectedByChannel,
                     Map<String, Integer> actualByChannel) {
            this(null, null, orderNo, null, expectedByChannel, actualByChannel);
        }

        public Issue(Integer orderId, Integer shopId, String orderNo, String paymentMethod,
                     Map<String, Integer> expectedByChannel, Map<String, Integer> actualByChannel) {
            this.orderId = orderId;
            this.shopId = shopId;
            this.orderNo = orderNo;
            this.paymentMethod = paymentMethod;
            this.expectedByChannel = immutableCopy(expectedByChannel);
            this.actualByChannel = immutableCopy(actualByChannel);
            Explanation explanation = explain(this.expectedByChannel, this.actualByChannel);
            this.reasonCodes = explanation.reasonCodes;
            this.reasons = explanation.reasons;
            this.channelDifferences = explanation.channelDifferences;
        }

        public String getOrderNo() {
            return orderNo;
        }

        public Map<String, Integer> getExpectedByChannel() {
            return expectedByChannel;
        }

        public Map<String, Integer> getActualByChannel() {
            return actualByChannel;
        }

        public List<String> getReasonCodes() {
            return reasonCodes;
        }

        public Map<String, Object> toMap() {
            Map<String, Object> detail = new LinkedHashMap<>();
            detail.put("order_no", orderNo);
            if (orderId != null) {
                detail.put("order_id", orderId);
            }
            if (shopId != null) {
                detail.put("shop_id", shopId);
            }
            if (paymentMethod != null) {
                detail.put("payment_method", paymentMethod);
            }
            detail.put("reason_codes", reasonCodes);
            detail.put("reason", String.join("；", reasons));
            detail.put("expected_total_fen", total(expectedByChannel));
            detail.put("ledger_total_fen", total(actualByChannel));
            detail.put("difference_fen", total(actualByChannel) - total(expectedByChannel));
            detail.put("expected_by_channel_fen", expectedByChannel);
            detail.put("ledger_by_channel_fen", actualByChannel);
            detail.put("channel_differences", channelDifferences);
            return detail;
        }

        private static Explanation explain(Map<String, Integer> expected, Map<String, Integer> actual) {
            LinkedHashSet<String> codeSet = new LinkedHashSet<>();
            List<String> reasonList = new ArrayList<>();
            List<Map<String, Object>> differences = new ArrayList<>();
            int expectedTotal = total(expected);
            int actualTotal = total(actual);

            if (expectedTotal != 0 && actual.isEmpty()) {
                addReason(codeSet, reasonList, "LEDGER_MISSING", "订单存在实收投影，但缺少成功资金流水");
            } else if (expected.isEmpty() && actualTotal != 0) {
                addReason(codeSet, reasonList, "ORDER_PROJECTION_MISSING", "资金流水存在净额，但订单实收投影为空");
            }
            if (actualTotal < expectedTotal) {
                addReason(codeSet, reasonList, "TOTAL_AMOUNT_SHORT", "资金流水净额少于订单实收投影");
            } else if (actualTotal > expectedTotal) {
                addReason(codeSet, reasonList, "TOTAL_AMOUNT_EXCESS", "资金流水净额多于订单实收投影");
            }

            LinkedHashSet<String> channels = new LinkedHashSet<>();
            channels.addAll(expected.keySet());
            channels.addAll(actual.keySet());
            for (String channel : channels) {
                int expectedFen = expected.getOrDefault(channel, 0);
                int actualFen = actual.getOrDefault(channel, 0);
                if (expectedFen == actualFen) {
                    continue;
                }
                String code;
                String reason;
                if (expectedFen != 0 && actualFen == 0) {
                    code = "CHANNEL_LEDGER_MISSING";
                    reason = "渠道 " + channel + " 缺少成功资金流水";
                } else if (expectedFen == 0 && actualFen != 0) {
                    code = "UNEXPECTED_LEDGER_CHANNEL";
                    reason = "流水存在订单未记录的渠道 " + channel;
                } else if (actualFen < expectedFen) {
                    code = "CHANNEL_AMOUNT_SHORT";
                    reason = "渠道 " + channel + " 流水净额不足";
                } else {
                    code = "CHANNEL_AMOUNT_EXCESS";
                    reason = "渠道 " + channel + " 流水净额超额";
                }
                addReason(codeSet, reasonList, code, reason);
                Map<String, Object> difference = new LinkedHashMap<>();
                difference.put("channel", channel);
                difference.put("reason_code", code);
                difference.put("reason", reason);
                difference.put("expected_fen", expectedFen);
                difference.put("ledger_fen", actualFen);
                difference.put("difference_fen", actualFen - expectedFen);
                differences.add(Collections.unmodifiableMap(difference));
            }
            return new Explanation(
                    Collections.unmodifiableList(new ArrayList<>(codeSet)),
                    Collections.unmodifiableList(reasonList),
                    Collections.unmodifiableList(differences));
        }

        private static void addReason(Set<String> codes, List<String> reasons, String code, String reason) {
            if (codes.add(code)) {
                reasons.add(reason);
            }
        }

        private static int total(Map<String, Integer> amounts) {
            int total = 0;
            for (Integer amount : amounts.values()) {
                total += amount != null ? amount : 0;
            }
            return total;
        }

        private static Map<String, Integer> immutableCopy(Map<String, Integer> source) {
            return Collections.unmodifiableMap(new LinkedHashMap<>(
                    source != null ? source : Collections.emptyMap()));
        }

        private static final class Explanation {
            private final List<String> reasonCodes;
            private final List<String> reasons;
            private final List<Map<String, Object>> channelDifferences;

            private Explanation(List<String> reasonCodes, List<String> reasons,
                                List<Map<String, Object>> channelDifferences) {
                this.reasonCodes = reasonCodes;
                this.reasons = reasons;
                this.channelDifferences = channelDifferences;
            }
        }
    }
}
