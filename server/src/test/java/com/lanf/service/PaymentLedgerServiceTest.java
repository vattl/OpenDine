package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.mapper.PaymentLedgerMapper;
import com.lanf.service.impl.PaymentLedgerServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentLedgerServiceTest {

    private PaymentLedgerServiceImpl service;
    private PaymentLedgerMapper mapper;

    @BeforeEach
    void setUp() {
        service = new PaymentLedgerServiceImpl();
        mapper = mock(PaymentLedgerMapper.class);
        ReflectionTestUtils.setField(service, "baseMapper", mapper);
    }

    private Order createOrder(Integer id, String orderNo, Integer shopId, double payableYuan) {
        Order order = new Order();
        order.setId(id);
        order.setOrder_no(orderNo);
        order.setShop_id(shopId);
        order.setTransac_status("success");
        order.setSett_amount(payableYuan);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        return order;
    }

    @Test
    void recordSettlement_singleCash_success() {
        Order order = createOrder(1, "ORD-001", 10, 50.00);
        when(mapper.insert(any(PaymentLedger.class))).thenReturn(1);
        when(mapper.selectOne(any())).thenReturn(null);

        Map<String, Integer> channels = Collections.singletonMap(PaymentLedger.CHANNEL_CASH, 5000);
        List<PaymentLedger> ledgers = service.recordSettlement(
                order, 99, "REQ-001", "TERM-01", 101L, 201L, "2026-10-03", channels, "TX-CASH-001"
        );

        assertEquals(1, ledgers.size());
        PaymentLedger ledger = ledgers.get(0);
        assertEquals("ORD-001", ledger.getOrder_no());
        assertEquals(10, ledger.getShop_id());
        assertEquals(PaymentLedger.ENTRY_TYPE_PAYMENT, ledger.getEntry_type());
        assertEquals(PaymentLedger.CHANNEL_CASH, ledger.getChannel());
        assertEquals(5000, ledger.getAmount_fen());
        assertEquals(PaymentLedger.STATUS_SUCCEEDED, ledger.getStatus());
        assertEquals("TX-CASH-001", ledger.getProvider_transaction_id());
        verify(mapper, times(1)).insert(any(PaymentLedger.class));
    }

    @Test
    void recordSettlement_combinedPayment_success() {
        Order order = createOrder(2, "ORD-002", 10, 100.00);
        when(mapper.insert(any(PaymentLedger.class))).thenReturn(1);
        when(mapper.selectOne(any())).thenReturn(null);

        Map<String, Integer> channels = new LinkedHashMap<>();
        channels.put(PaymentLedger.CHANNEL_CASH, 3000);
        channels.put(PaymentLedger.CHANNEL_WECHAT, 2000);
        channels.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, 5000);

        List<PaymentLedger> ledgers = service.recordSettlement(
                order, 99, "REQ-002", "TERM-01", 101L, 201L, "2026-10-03", channels, "CASHIER_COMBINED_ORD-002"
        );

        assertEquals(3, ledgers.size());
        int totalFen = ledgers.stream().mapToInt(PaymentLedger::getAmount_fen).sum();
        assertEquals(10000, totalFen);
        verify(mapper, times(3)).insert(any(PaymentLedger.class));
    }

    @Test
    void recordSettlement_invariantViolation_throwsIllegalStateException() {
        Order order = createOrder(3, "ORD-003", 10, 100.00); // 10000 fen payable

        Map<String, Integer> channels = new LinkedHashMap<>();
        channels.put(PaymentLedger.CHANNEL_CASH, 8000); // Only 8000 fen, mismatch!

        IllegalStateException ex = assertThrows(IllegalStateException.class, () ->
                service.recordSettlement(
                        order, 99, "REQ-003", "TERM-01", 101L, 201L, "2026-10-03", channels, null
                )
        );

        assertTrue(ex.getMessage().contains("不相等"));
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }

    @Test
    void recordSettlement_idempotency_returnsExistingLedgerWithoutDuplicateInsert() {
        Order order = createOrder(4, "ORD-004", 10, 50.00);
        PaymentLedger existing = PaymentLedger.builder()
                .id(999L)
                .ledger_no("PL_EXISTING")
                .request_id("REQ-004")
                .shop_id(10)
                .order_id(4L)
                .order_no("ORD-004")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(5000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .build();
        when(mapper.selectOne(any())).thenReturn(existing);

        Map<String, Integer> channels = Collections.singletonMap(PaymentLedger.CHANNEL_CASH, 5000);
        List<PaymentLedger> ledgers = service.recordSettlement(
                order, 99, "REQ-004", "TERM-01", 101L, 201L, "2026-10-03", channels, null
        );

        assertEquals(1, ledgers.size());
        assertEquals(999L, ledgers.get(0).getId());
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }

    @Test
    void recordSettlement_rejectsAnotherSuccessfulSettlementForSameOrder() {
        Order order = createOrder(9, "ORD-009", 10, 50.00);
        PaymentLedger callbackLedger = PaymentLedger.builder()
                .id(1001L)
                .request_id("WECHAT_WX-TX-9")
                .shop_id(10)
                .order_id(9L)
                .order_no("ORD-009")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(5000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .provider_transaction_id("WX-TX-9")
                .build();
        when(mapper.selectList(any())).thenReturn(Collections.singletonList(callbackLedger));

        IllegalStateException error = assertThrows(IllegalStateException.class, () ->
                service.recordSettlement(order, 99, "CASHIER-REQ-9", "TERM-01", 101L, 201L,
                        "2026-10-03", Collections.singletonMap(PaymentLedger.CHANNEL_CASH, 5000), null));

        assertTrue(error.getMessage().contains("另一笔权威支付流水"));
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }

    @Test
    void recordSettlement_whenHistoricalPaymentWasFullyReversed_allowsNewSettlementGeneration() {
        Order order = createOrder(10, "ORD-010", 10, 50.00);
        PaymentLedger historical = PaymentLedger.builder()
                .id(1101L).request_id("OLD-PAY").shop_id(10).order_id(10L).order_no("ORD-010")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT).channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(5000).status(PaymentLedger.STATUS_SUCCEEDED).build();
        PaymentLedger reversal = PaymentLedger.builder()
                .id(1102L).request_id("OLD-REV").shop_id(10).order_id(10L).order_no("ORD-010")
                .entry_type(PaymentLedger.ENTRY_TYPE_REVERSAL).channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(-5000).status(PaymentLedger.STATUS_SUCCEEDED)
                .original_ledger_id(1101L).build();
        when(mapper.selectList(any())).thenReturn(Arrays.asList(historical, reversal));
        when(mapper.selectOne(any())).thenReturn(null);
        when(mapper.insert(any(PaymentLedger.class))).thenReturn(1);

        List<PaymentLedger> ledgers = service.recordSettlement(
                order, 99, "NEW-PAY", "TERM-01", 101L, 201L,
                "2026-10-03", Collections.singletonMap(PaymentLedger.CHANNEL_CASH, 5000), null);

        assertEquals(1, ledgers.size());
        assertEquals("NEW-PAY", ledgers.get(0).getRequest_id());
        verify(mapper, times(1)).insert(any(PaymentLedger.class));
    }

    @Test
    void recordReversal_createsNegativeReversalEntries() {
        Order order = createOrder(5, "ORD-005", 10, 60.00);

        PaymentLedger p1 = PaymentLedger.builder()
                .id(101L)
                .shop_id(10)
                .order_id(5L)
                .order_no("ORD-005")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(2000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .business_day("2026-10-03")
                .build();
        PaymentLedger p2 = PaymentLedger.builder()
                .id(102L)
                .shop_id(10)
                .order_id(5L)
                .order_no("ORD-005")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL)
                .amount_fen(4000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .business_day("2026-10-03")
                .build();

        when(mapper.selectList(any())).thenReturn(Arrays.asList(p1, p2));
        when(mapper.selectOne(any())).thenReturn(null);
        when(mapper.insert(any(PaymentLedger.class))).thenReturn(1);

        List<PaymentLedger> reversals = service.recordReversal(
                order, 99, "REV-005", "2026-10-03", "全额反结账"
        );

        assertEquals(2, reversals.size());
        assertEquals(-2000, reversals.get(0).getAmount_fen());
        assertEquals(PaymentLedger.ENTRY_TYPE_REVERSAL, reversals.get(0).getEntry_type());
        assertEquals(101L, reversals.get(0).getOriginal_ledger_id());

        assertEquals(-4000, reversals.get(1).getAmount_fen());
        assertEquals(PaymentLedger.ENTRY_TYPE_REVERSAL, reversals.get(1).getEntry_type());
        assertEquals(102L, reversals.get(1).getOriginal_ledger_id());

        verify(mapper, times(2)).insert(any(PaymentLedger.class));
    }

    @Test
    void recordReversal_alreadyReversed_skipsDuplicate() {
        Order order = createOrder(6, "ORD-006", 10, 50.00);

        PaymentLedger p1 = PaymentLedger.builder()
                .id(201L)
                .shop_id(10)
                .order_id(6L)
                .order_no("ORD-006")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(5000)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .business_day("2026-10-03")
                .build();

        PaymentLedger revExisting = PaymentLedger.builder()
                .id(301L)
                .original_ledger_id(201L)
                .entry_type(PaymentLedger.ENTRY_TYPE_REVERSAL)
                .amount_fen(-5000)
                .build();

        when(mapper.selectList(any())).thenReturn(Collections.singletonList(p1));
        when(mapper.selectOne(any())).thenReturn(revExisting);

        List<PaymentLedger> reversals = service.recordReversal(
                order, 99, "REV-006", "2026-10-03", "已冲正测试"
        );

        assertEquals(1, reversals.size());
        assertEquals(301L, reversals.get(0).getId());
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }

    @Test
    void recordReversal_whenPaymentAlreadyFullyReversedByAnotherRequest_doesNotOverReverse() {
        Order order = createOrder(11, "ORD-011", 10, 50.00);
        PaymentLedger payment = PaymentLedger.builder()
                .id(1201L).shop_id(10).order_id(11L).order_no("ORD-011")
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT).channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(5000).status(PaymentLedger.STATUS_SUCCEEDED).build();
        PaymentLedger reversal = PaymentLedger.builder()
                .id(1202L).shop_id(10).order_id(11L).order_no("ORD-011")
                .request_id("FIRST-REV").entry_type(PaymentLedger.ENTRY_TYPE_REVERSAL)
                .channel(PaymentLedger.CHANNEL_CASH).amount_fen(-5000)
                .status(PaymentLedger.STATUS_SUCCEEDED).original_ledger_id(1201L).build();
        when(mapper.selectList(any())).thenReturn(Arrays.asList(payment, reversal));
        when(mapper.selectOne(any())).thenReturn(null);

        List<PaymentLedger> result = service.recordReversal(
                order, 99, "SECOND-REV", "2026-10-03", "重复反结账");

        assertTrue(result.isEmpty());
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }

    @Test
    void recordRefund_createsNegativeRefundEntry() {
        Order order = createOrder(7, "ORD-007", 10, 50.00);
        when(mapper.selectOne(any())).thenReturn(null);
        when(mapper.insert(any(PaymentLedger.class))).thenReturn(1);

        PaymentLedger refund = service.recordRefund(
                order, PaymentLedger.CHANNEL_WECHAT, 3000, 99, "REF-007", "2026-10-03", 501L, "WX-REF-001"
        );

        assertNotNull(refund);
        assertEquals(-3000, refund.getAmount_fen());
        assertEquals(PaymentLedger.ENTRY_TYPE_REFUND, refund.getEntry_type());
        assertEquals(PaymentLedger.CHANNEL_WECHAT, refund.getChannel());
        assertEquals(501L, refund.getOriginal_ledger_id());
        assertEquals("WX-REF-001", refund.getProvider_transaction_id());
        verify(mapper, times(1)).insert(any(PaymentLedger.class));
    }

    @Test
    void recordRefund_invalidAmount_throwsException() {
        Order order = createOrder(8, "ORD-008", 10, 50.00);

        assertThrows(IllegalArgumentException.class, () ->
                service.recordRefund(order, PaymentLedger.CHANNEL_WECHAT, 0, 99, "REF-008", "2026-10-03", null, null)
        );
        assertThrows(IllegalArgumentException.class, () ->
                service.recordRefund(order, PaymentLedger.CHANNEL_WECHAT, -100, 99, "REF-008", "2026-10-03", null, null)
        );
    }

    @Test
    void recordRefund_sameRequestWithDifferentFacts_rejectsIdempotencyConflict() {
        Order order = createOrder(12, "ORD-012", 10, 50.00);
        PaymentLedger existing = PaymentLedger.builder()
                .id(1301L).request_id("REF-012").shop_id(10).order_id(12L).order_no("ORD-012")
                .entry_type(PaymentLedger.ENTRY_TYPE_REFUND).channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(-1000).status(PaymentLedger.STATUS_SUCCEEDED)
                .original_ledger_id(501L).provider_transaction_id("WX-REF-012").build();
        when(mapper.selectOne(any())).thenReturn(existing);

        IllegalStateException error = assertThrows(IllegalStateException.class, () ->
                service.recordRefund(order, PaymentLedger.CHANNEL_WECHAT, 2000, 99,
                        "REF-012", "2026-10-03", 501L, "WX-REF-012"));

        assertTrue(error.getMessage().contains("幂等冲突"));
        verify(mapper, never()).insert(any(PaymentLedger.class));
    }
}
