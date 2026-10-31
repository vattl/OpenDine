package com.lanf.service;

import com.lanf.entity.Order;
import com.lanf.entity.PersonalPaymentEvent;
import com.lanf.entity.R;
import com.lanf.mapper.PersonalPaymentEventMapper;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.success.PaymentSuccessHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PersonalPaymentWebhookServiceTest {

    private PersonalPaymentWebhookService service;
    private PersonalPaymentEventMapper mapper;
    private CashierCollectionIntentService intentService;
    private IOrderService orderService;
    private PaymentSuccessHandler successHandler;
    private JdbcTemplate jdbcTemplate;
    private CashierCheckoutService cashierCheckoutService;

    @BeforeEach
    void setUp() {
        mapper = mock(PersonalPaymentEventMapper.class);
        intentService = mock(CashierCollectionIntentService.class);
        orderService = mock(IOrderService.class);
        successHandler = mock(PaymentSuccessHandler.class);
        jdbcTemplate = mock(JdbcTemplate.class);
        cashierCheckoutService = mock(CashierCheckoutService.class);

        service = new PersonalPaymentWebhookService(
                mapper, intentService, orderService, successHandler, jdbcTemplate, cashierCheckoutService);
    }

    @Test
    void ambiguousPaymentIsNotEligibleForReverseMatching() {
        when(intentService.matchAndConfirmByWebhook(any(), any(), anyInt(), any(Date.class)))
                .thenThrow(new CashierCollectionIntentService.AmbiguousCollectionException());
        service.processPayment("ambiguous", "wechat", 100, "1724458800000", "", 1, null);
        verify(mapper).insert(argThat((PersonalPaymentEvent e) -> "NEEDS_REVIEW".equals(e.getStatus())));
        verify(cashierCheckoutService, never()).checkoutKeepMerchantId(anyInt(), anyMap());
    }

    @Test
    void testProcessPaymentMatchesIntentAndSettlesOrder() {
        String eventId = "evt_wx_001";
        String channel = "wechat";
        long amountFen = 1800L;
        String timestamp = "1724458800000";
        String rawText = "微信支付收款 18.00 元";
        Integer shopId = 1;

        CashierCollectionIntentService.MatchedIntent matched =
                new CashierCollectionIntentService.MatchedIntent(10L, 1, "ORD_20260824001", "sess_001", new Date());

        when(intentService.matchAndConfirmByWebhook(eq(shopId), eq(channel), eq(1800), any(Date.class)))
                .thenReturn(matched);

        Order order = new Order();
        order.setId(100);
        order.setOrder_no("ORD_20260824001");
        order.setShop_id(1);
        order.setTransac_status("unsettled");
        order.setSett_amount(18.0);

        when(orderService.getOne(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(order);
        when(cashierCheckoutService.checkoutKeepMerchantId(eq(1), anyMap())).thenReturn(R.ok());

        service.processPayment(eventId, channel, amountFen, timestamp, rawText, shopId, null);

        verify(cashierCheckoutService).checkoutKeepMerchantId(eq(1), argThat(map ->
                "ORD_20260824001".equals(map.get("order_no"))
                        && "微信收款码自动".equals(map.get("payment_method"))
                        && "sess_001".equals(map.get("collection_session_id"))
        ));
        verify(mapper).insert(argThat((PersonalPaymentEvent e) -> "MATCHED_SETTLED".equals(e.getStatus())));
    }

    @Test
    void testProcessPaymentUnmatchedDoesNotSettleOrder() {
        String eventId = "evt_unmatched_002";
        String channel = "alipay";
        long amountFen = 500L;
        String timestamp = "1724458800000";

        when(intentService.matchAndConfirmByWebhook(any(), any(), anyInt(), any(Date.class)))
                .thenReturn(null);
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());

        service.processPayment(eventId, channel, amountFen, timestamp, "无匹配", null, null);

        verify(cashierCheckoutService, never()).checkoutKeepMerchantId(anyInt(), anyMap());
        verify(mapper).insert(argThat((PersonalPaymentEvent e) -> "UNMATCHED".equals(e.getStatus())));
    }

    @Test
    void testSettleByRecentPaidHitsUnmatchedEventAndSettles() {
        int shopId = 1;
        String orderNo = "ORD_20260830_300";
        String channel = "wechat";
        int amountFen = 3000;
        String sessionId = "sess_300";

        PersonalPaymentEvent event = new PersonalPaymentEvent();
        event.setId(99L);
        event.setEvent_id("evt_wx_recent_01");
        event.setChannel("wechat");
        event.setAmount_fen(3000L);
        event.setStatus("UNMATCHED");
        event.setMatched_shop_id(1);
        event.setCreated_at(new Date(System.currentTimeMillis() - 20_000L)); // 20秒前到账

        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.singletonList(event));

        Order order = new Order();
        order.setId(200);
        order.setOrder_no(orderNo);
        order.setShop_id(shopId);
        order.setTransac_status("unsettled");
        order.setSett_amount(30.0);

        when(orderService.getOne(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(order);
        when(cashierCheckoutService.checkoutKeepMerchantId(eq(shopId), anyMap())).thenReturn(R.ok());

        boolean settled = service.settleByRecentPaid(shopId, orderNo, channel, amountFen, sessionId);

        assertTrue(settled);
        verify(intentService).confirmDirect(shopId, orderNo, sessionId, channel, amountFen);
        verify(cashierCheckoutService).checkoutKeepMerchantId(eq(shopId), argThat(map ->
                orderNo.equals(map.get("order_no"))
                        && "微信收款码自动".equals(map.get("payment_method"))
                        && sessionId.equals(map.get("collection_session_id"))
        ));
        assertEquals("MATCHED_SETTLED", event.getStatus());
        assertEquals(orderNo, event.getMatched_order_no());
        assertEquals(shopId, event.getMatched_shop_id());
        verify(mapper).updateById(event);
    }

    @Test
    void testSettleByRecentPaidNoCandidateReturnsFalse() {
        int shopId = 1;
        String orderNo = "ORD_20260830_301";
        String channel = "alipay";
        int amountFen = 2000;
        String sessionId = "sess_301";

        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());

        boolean settled = service.settleByRecentPaid(shopId, orderNo, channel, amountFen, sessionId);

        assertFalse(settled);
        verify(cashierCheckoutService, never()).checkoutKeepMerchantId(anyInt(), anyMap());
    }

    @Test
    void testSettleByRecentPaidMultipleCandidatesRejectsAutoSettling() {
        int shopId = 1;
        String orderNo = "ORD_20260830_302";
        String channel = "wechat";
        int amountFen = 3000;
        String sessionId = "sess_302";

        PersonalPaymentEvent e1 = new PersonalPaymentEvent();
        e1.setId(1L);
        PersonalPaymentEvent e2 = new PersonalPaymentEvent();
        e2.setId(2L);

        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(java.util.Arrays.asList(e1, e2));

        boolean settled = service.settleByRecentPaid(shopId, orderNo, channel, amountFen, sessionId);

        assertFalse(settled);
        verify(cashierCheckoutService, never()).checkoutKeepMerchantId(anyInt(), anyMap());
    }
}
