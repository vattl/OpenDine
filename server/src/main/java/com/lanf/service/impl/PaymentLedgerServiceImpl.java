package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.mapper.PaymentLedgerMapper;
import com.lanf.service.PaymentLedgerService;
import com.lanf.util.OrderNetRevenue;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

@Service
public class PaymentLedgerServiceImpl extends ServiceImpl<PaymentLedgerMapper, PaymentLedger>
        implements PaymentLedgerService {

    @Override
    @Transactional(rollbackFor = Exception.class)
    public List<PaymentLedger> recordSettlement(
            Order order,
            Integer operatorId,
            String requestId,
            String terminalId,
            Long drawerSessionId,
            Long employeeShiftId,
            String businessDay,
            Map<String, Integer> channelAmountsFen,
            String providerTransactionId) {

        if (order == null || order.getId() == null) {
            throw new IllegalArgumentException("订单不能为空");
        }
        if (channelAmountsFen == null || channelAmountsFen.isEmpty()) {
            throw new IllegalArgumentException("结算支付渠道分项不能为空");
        }
        String reqId = StringUtils.hasText(requestId) ? requestId.trim() : UUID.randomUUID().toString().replace("-", "");
        String bDay = StringUtils.hasText(businessDay) ? businessDay.trim() : java.time.LocalDate.now().toString();

        int sumFen = 0;
        for (Map.Entry<String, Integer> entry : channelAmountsFen.entrySet()) {
            Integer fen = entry.getValue();
            if (fen == null || fen < 0) {
                throw new IllegalArgumentException("支付渠道分项金额不能为负数: " + entry.getKey());
            }
            sumFen += fen;
        }

        int payableFen = OrderNetRevenue.netRevenueFen(order);
        Integer giftFen = channelAmountsFen.get(PaymentLedger.CHANNEL_GIFT);
        int expectedSum = (giftFen != null && giftFen > 0) ? (payableFen + giftFen) : payableFen;
        if (sumFen != payableFen && sumFen != expectedSum) {
            throw new IllegalStateException("支付分项合计(" + sumFen + "分)与订单应付金额(" + payableFen + "分)不相等");
        }

        // 调用方必须先持有订单行锁。同一订单已有成功 PAYMENT 时，只允许完全相同的幂等重放；
        // 收银手动结账不得覆盖微信回调等已经确立的权威资金事实。
        List<PaymentLedger> orderLifecycle = list(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", order.getShop_id())
                .eq("order_no", order.getOrder_no())
                .eq("status", PaymentLedger.STATUS_SUCCEEDED)
                .orderByAsc("id"));
        List<PaymentLedger> existingOrderPayments = activePayments(orderLifecycle);
        if (existingOrderPayments != null && !existingOrderPayments.isEmpty()) {
            validateExistingSettlement(order, reqId, channelAmountsFen,
                    providerTransactionId, existingOrderPayments);
            return existingOrderPayments;
        }

        List<PaymentLedger> result = new ArrayList<>();
        int seq = 1;
        Date occurredAt = order.getPay_time() != null ? order.getPay_time() : new Date();

        for (Map.Entry<String, Integer> entry : channelAmountsFen.entrySet()) {
            String channel = entry.getKey();
            int amountFen = entry.getValue();
            if (amountFen <= 0) {
                continue;
            }

            // 幂等防重检查：(shop_id, request_id, entry_type, channel)
            PaymentLedger existing = getOne(new QueryWrapper<PaymentLedger>()
                    .eq("shop_id", order.getShop_id())
                    .eq("request_id", reqId)
                    .eq("entry_type", PaymentLedger.ENTRY_TYPE_PAYMENT)
                    .eq("channel", channel)
                    .last("LIMIT 1"));
            if (existing != null) {
                validateExistingLedger(order, reqId, channel, amountFen,
                        providerTransactionId, existing);
                result.add(existing);
                continue;
            }

            String ledgerNo = "PL_" + order.getShop_id() + "_" + order.getOrder_no() + "_" + channel + "_" + System.currentTimeMillis() + "_" + (seq++);
            PaymentLedger ledger = PaymentLedger.builder()
                    .ledger_no(ledgerNo)
                    .request_id(reqId)
                    .shop_id(order.getShop_id())
                    .order_id(order.getId() != null ? order.getId().longValue() : null)
                    .order_no(order.getOrder_no())
                    .terminal_id(terminalId)
                    .drawer_session_id(drawerSessionId)
                    .employee_shift_id(employeeShiftId)
                    .operator_id(operatorId)
                    .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                    .channel(channel)
                    .amount_fen(amountFen)
                    .status(PaymentLedger.STATUS_SUCCEEDED)
                    .source(PaymentLedger.SOURCE_NATIVE)
                    .trust_level(PaymentLedger.TRUST_HIGH)
                    .provider_transaction_id(providerTransactionId)
                    .original_ledger_id(null)
                    .occurred_at(occurredAt)
                    .business_day(bDay)
                    .created_at(new Date())
                    .build();

            if (!save(ledger)) {
                throw new IllegalStateException("权威资金流水写入失败");
            }
            result.add(ledger);
        }

        return result;
    }

    private static void validateExistingSettlement(
            Order order, String requestId, Map<String, Integer> expectedChannels,
            String providerTransactionId, List<PaymentLedger> existing) {
        Map<String, Integer> actualChannels = new LinkedHashMap<>();
        for (PaymentLedger ledger : existing) {
            int existingAmountFen = ledger.getAmount_fen() != null ? ledger.getAmount_fen() : 0;
            validateExistingLedger(order, requestId, ledger.getChannel(),
                    existingAmountFen,
                    providerTransactionId, ledger);
            actualChannels.merge(ledger.getChannel(), existingAmountFen, Integer::sum);
        }
        Map<String, Integer> normalizedExpected = new LinkedHashMap<>();
        for (Map.Entry<String, Integer> entry : expectedChannels.entrySet()) {
            if (entry.getValue() != null && entry.getValue() > 0) {
                normalizedExpected.put(entry.getKey(), entry.getValue());
            }
        }
        if (!actualChannels.equals(normalizedExpected)) {
            throw new IllegalStateException("订单已存在另一笔权威支付流水，禁止重复结账");
        }
    }

    private static void validateExistingLedger(
            Order order, String requestId, String channel, int amountFen,
            String providerTransactionId, PaymentLedger existing) {
        if (!Objects.equals(order.getShop_id(), existing.getShop_id())
                || !Objects.equals(order.getOrder_no(), existing.getOrder_no())
                || !Objects.equals(order.getId().longValue(), existing.getOrder_id())
                || !Objects.equals(requestId, existing.getRequest_id())
                || !Objects.equals(channel, existing.getChannel())
                || !Objects.equals(amountFen, existing.getAmount_fen())
                || !Objects.equals(providerTransactionId, existing.getProvider_transaction_id())) {
            throw new IllegalStateException("订单已存在另一笔权威支付流水，禁止重复结账");
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public List<PaymentLedger> recordReversal(
            Order order,
            Integer operatorId,
            String requestId,
            String businessDay,
            String reason) {

        if (order == null || order.getId() == null) {
            throw new IllegalArgumentException("订单不能为空");
        }
        String reqId = StringUtils.hasText(requestId) ? requestId.trim() : "REV_" + UUID.randomUUID().toString().replace("-", "");
        String bDay = StringUtils.hasText(businessDay) ? businessDay.trim() : java.time.LocalDate.now().toString();

        List<PaymentLedger> lifecycle = list(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", order.getShop_id())
                .eq("order_no", order.getOrder_no())
                .eq("status", PaymentLedger.STATUS_SUCCEEDED));
        List<PaymentLedger> payments = new ArrayList<>();
        for (PaymentLedger ledger : lifecycle) {
            if (PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())) {
                payments.add(ledger);
            }
        }

        if (payments.isEmpty()) {
            return Collections.emptyList();
        }

        List<PaymentLedger> reversals = new ArrayList<>();
        int seq = 1;
        Date occurredAt = new Date();

        for (PaymentLedger original : payments) {
            int remainingFen = remainingReversibleFen(original, lifecycle);
            if (remainingFen <= 0) {
                continue;
            }
            // 幂等防重：同一 request_id 下同一 channel 的冲正
            PaymentLedger existingRev = getOne(new QueryWrapper<PaymentLedger>()
                    .eq("shop_id", order.getShop_id())
                    .eq("request_id", reqId)
                    .eq("entry_type", PaymentLedger.ENTRY_TYPE_REVERSAL)
                    .eq("channel", original.getChannel())
                    .last("LIMIT 1"));
            if (existingRev != null) {
                reversals.add(existingRev);
                continue;
            }

            String revLedgerNo = "REV_" + order.getShop_id() + "_" + order.getOrder_no() + "_" + original.getChannel() + "_" + System.currentTimeMillis() + "_" + (seq++);
            PaymentLedger rev = PaymentLedger.builder()
                    .ledger_no(revLedgerNo)
                    .request_id(reqId)
                    .shop_id(order.getShop_id())
                    .order_id(order.getId() != null ? order.getId().longValue() : null)
                    .order_no(order.getOrder_no())
                    .terminal_id(original.getTerminal_id())
                    .drawer_session_id(original.getDrawer_session_id())
                    .employee_shift_id(original.getEmployee_shift_id())
                    .operator_id(operatorId)
                    .entry_type(PaymentLedger.ENTRY_TYPE_REVERSAL)
                    .channel(original.getChannel())
                    .amount_fen(-remainingFen)
                    .status(PaymentLedger.STATUS_SUCCEEDED)
                    .source(PaymentLedger.SOURCE_NATIVE)
                    .trust_level(PaymentLedger.TRUST_HIGH)
                    .provider_transaction_id(original.getProvider_transaction_id())
                    .original_ledger_id(original.getId())
                    .occurred_at(occurredAt)
                    .business_day(bDay)
                    .created_at(new Date())
                    .build();

            if (!save(rev)) {
                throw new IllegalStateException("权威冲正流水写入失败");
            }
            reversals.add(rev);
        }

        return reversals;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public PaymentLedger recordRefund(
            Order order,
            String channel,
            int refundFen,
            Integer operatorId,
            String requestId,
            String businessDay,
            Long originalLedgerId,
            String providerRefundId) {

        if (order == null || order.getId() == null) {
            throw new IllegalArgumentException("订单不能为空");
        }
        if (refundFen <= 0) {
            throw new IllegalArgumentException("退款金额必须大于0");
        }
        String reqId = StringUtils.hasText(requestId) ? requestId.trim() : "REF_" + UUID.randomUUID().toString().replace("-", "");
        String bDay = StringUtils.hasText(businessDay) ? businessDay.trim() : java.time.LocalDate.now().toString();

        // 幂等防重
        PaymentLedger existing = getOne(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", order.getShop_id())
                .eq("request_id", reqId)
                .eq("entry_type", PaymentLedger.ENTRY_TYPE_REFUND)
                .eq("channel", channel)
                .last("LIMIT 1"));
        if (existing != null) {
            validateExistingRefund(order, channel, refundFen, originalLedgerId, providerRefundId, existing);
            return existing;
        }

        String refLedgerNo = "REF_" + order.getShop_id() + "_" + order.getOrder_no() + "_" + channel + "_" + System.currentTimeMillis();
        PaymentLedger refundLedger = PaymentLedger.builder()
                .ledger_no(refLedgerNo)
                .request_id(reqId)
                .shop_id(order.getShop_id())
                .order_id(order.getId() != null ? order.getId().longValue() : null)
                .order_no(order.getOrder_no())
                .terminal_id(null)
                .drawer_session_id(null)
                .employee_shift_id(null)
                .operator_id(operatorId)
                .entry_type(PaymentLedger.ENTRY_TYPE_REFUND)
                .channel(channel)
                .amount_fen(-Math.abs(refundFen))
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .source(PaymentLedger.SOURCE_NATIVE)
                .trust_level(PaymentLedger.TRUST_HIGH)
                .provider_transaction_id(providerRefundId)
                .original_ledger_id(originalLedgerId)
                .occurred_at(new Date())
                .business_day(bDay)
                .created_at(new Date())
                .build();

        if (!save(refundLedger)) {
            throw new IllegalStateException("权威退款流水写入失败");
        }
        return refundLedger;
    }

    private static List<PaymentLedger> activePayments(List<PaymentLedger> lifecycle) {
        if (lifecycle == null || lifecycle.isEmpty()) {
            return Collections.emptyList();
        }
        List<PaymentLedger> result = new ArrayList<>();
        for (PaymentLedger ledger : lifecycle) {
            if (PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())
                    && remainingReversibleFen(ledger, lifecycle) > 0) {
                result.add(ledger);
            }
        }
        return result;
    }

    private static int remainingReversibleFen(PaymentLedger payment, List<PaymentLedger> lifecycle) {
        int paidFen = payment.getAmount_fen() != null ? Math.max(0, payment.getAmount_fen()) : 0;
        long reversedFen = 0L;
        if (payment.getId() != null && lifecycle != null) {
            for (PaymentLedger ledger : lifecycle) {
                if (PaymentLedger.ENTRY_TYPE_REVERSAL.equals(ledger.getEntry_type())
                        && PaymentLedger.STATUS_SUCCEEDED.equals(ledger.getStatus())
                        && Objects.equals(payment.getId(), ledger.getOriginal_ledger_id())) {
                    reversedFen += Math.abs((long) (ledger.getAmount_fen() != null ? ledger.getAmount_fen() : 0));
                }
            }
        }
        return (int) Math.max(0L, paidFen - reversedFen);
    }

    private static void validateExistingRefund(
            Order order, String channel, int refundFen, Long originalLedgerId,
            String providerRefundId, PaymentLedger existing) {
        if (!Objects.equals(order.getShop_id(), existing.getShop_id())
                || !Objects.equals(order.getOrder_no(), existing.getOrder_no())
                || !Objects.equals(order.getId().longValue(), existing.getOrder_id())
                || !Objects.equals(channel, existing.getChannel())
                || !Objects.equals(-Math.abs(refundFen), existing.getAmount_fen())
                || !Objects.equals(originalLedgerId, existing.getOriginal_ledger_id())
                || !Objects.equals(providerRefundId, existing.getProvider_transaction_id())) {
            throw new IllegalStateException("退款请求幂等冲突，既有流水与本次事实不一致");
        }
    }

    @Override
    public List<PaymentLedger> listByOrder(Integer shopId, String orderNo) {
        if (shopId == null || !StringUtils.hasText(orderNo)) {
            return Collections.emptyList();
        }
        return list(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId)
                .eq("order_no", orderNo.trim())
                .orderByAsc("id"));
    }

    @Override
    public List<PaymentLedger> listByBusinessDay(Integer shopId, String businessDay) {
        if (shopId == null || !StringUtils.hasText(businessDay)) {
            return Collections.emptyList();
        }
        return list(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId)
                .eq("business_day", businessDay.trim())
                .orderByAsc("id"));
    }
}
