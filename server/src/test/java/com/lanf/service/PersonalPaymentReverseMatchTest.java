package com.lanf.service;

import com.lanf.entity.Order;
import com.lanf.entity.PersonalPaymentEvent;
import com.lanf.mapper.PersonalPaymentEventMapper;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.success.PaymentSuccessHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 出码补偿（客人先付款、后出码）：反向匹配近期到账记录并自动结账。
 */
class PersonalPaymentReverseMatchTest {

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

    private static PersonalPaymentEvent evt(String eventId) {
        PersonalPaymentEvent e = new PersonalPaymentEvent();
        e.setEvent_id(eventId);
        e.setChannel("wechat");
        e.setAmount_fen(3000L);
        e.setStatus("UNMATCHED");
        e.setMatched_shop_id(1);
        return e;
    }

    private static Order unsettledOrder() {
        Order o = new Order();
        o.setId(100);
        o.setOrder_no("TESTCOLLECT001");
        o.setShop_id(1);
        o.setTransac_status("unsettled");
        o.setSett_amount(30.0);
        return o;
    }

    @Test
    void unknownShopCannotBeConsumedByAnotherShop() {
        PersonalPaymentEvent event = evt("UNKNOWN");
        event.setMatched_shop_id(null);
        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.singletonList(event));
        assertFalse(service.settleByRecentPaid(1,"TESTCOLLECT001","wechat",3000,"s"));
        verify(cashierCheckoutService, never()).checkout(anyInt(), anyMap());
    }

    @Test
    void singleRecentUnmatchedEvent_settlesOrderAndMarksEventUsed() {
        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.singletonList(evt("EVT_001")));
        Order order = unsettledOrder();
        when(orderService.getOne(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(order);
        when(cashierCheckoutService.checkoutKeepMerchantId(eq(1), anyMap())).thenReturn(com.lanf.entity.R.ok());

        boolean settled = service.settleByRecentPaid(1, "TESTCOLLECT001", "wechat", 3000, "sess_001");

        assertTrue(settled);
        verify(intentService).confirmDirect(1, "TESTCOLLECT001", "sess_001", "wechat", 3000);
        verify(cashierCheckoutService).checkoutKeepMerchantId(eq(1), argThat(map ->
                "TESTCOLLECT001".equals(map.get("order_no"))
                        && "微信收款码自动".equals(map.get("payment_method"))
                        && "sess_001".equals(map.get("collection_session_id"))
        ));

        ArgumentCaptor<PersonalPaymentEvent> captor = ArgumentCaptor.forClass(PersonalPaymentEvent.class);
        verify(mapper).updateById(captor.capture());
        assertEquals("MATCHED_SETTLED", captor.getValue().getStatus());
        assertEquals("TESTCOLLECT001", captor.getValue().getMatched_order_no());
        assertEquals(1, captor.getValue().getMatched_shop_id());
        verify(mapper, never()).insert(any(PersonalPaymentEvent.class));
    }

    @Test
    void multipleRecentEvents_rejectsAutoSettle() {
        List<PersonalPaymentEvent> two = Arrays.asList(evt("EVT_A"), evt("EVT_B"));
        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(two);

        boolean settled = service.settleByRecentPaid(1, "TESTCOLLECT001", "wechat", 3000, "sess_001");

        assertFalse(settled);
        verify(cashierCheckoutService, never()).checkout(anyInt(), anyMap());
        verify(mapper, never()).updateById(any());
    }

    @Test
    void noRecentEvent_skipsSettlement() {
        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());

        boolean settled = service.settleByRecentPaid(1, "TESTCOLLECT001", "wechat", 3000, "sess_001");

        assertFalse(settled);
        verify(cashierCheckoutService, never()).checkout(anyInt(), anyMap());
        verify(mapper, never()).updateById(any());
    }

    @Test
    void orderAlreadyPaid_doesNotMarkEventUsed() {
        when(mapper.selectList(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.singletonList(evt("EVT_PAID")));
        Order paid = unsettledOrder();
        paid.setTransac_status("success");
        when(orderService.getOne(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(paid);

        boolean settled = service.settleByRecentPaid(1, "TESTCOLLECT001", "wechat", 3000, "sess_001");

        assertFalse(settled);
        verify(mapper, never()).updateById(any());
        verify(cashierCheckoutService, never()).checkout(anyInt(), anyMap());
    }
}
