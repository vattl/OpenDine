package com.lanf.service.impl;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.OrderAmountRecalculationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class OrderDetailRefundServiceTest {

    private OrderDetailRefundService service;
    private IOrderDetailService details;
    private IDishShopStockService stock;
    private WechatJsapiPaymentService paymentGuard;

    @BeforeEach
    void setUp() {
        service = new OrderDetailRefundService();
        details = mock(IOrderDetailService.class);
        stock = mock(IDishShopStockService.class);
        paymentGuard = mock(WechatJsapiPaymentService.class);
        when(paymentGuard.prepareForAmountMutation(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        ReflectionTestUtils.setField(service, "orderDetailService", details);
        ReflectionTestUtils.setField(service, "dishShopStockService", stock);
        ReflectionTestUtils.setField(service, "kdsOrderHook", mock(KdsOrderHook.class));
        ReflectionTestUtils.setField(service, "orderAmountRecalculationService",
                mock(OrderAmountRecalculationService.class));
        ReflectionTestUtils.setField(service, "wechatJsapiPaymentService", paymentGuard);
    }

    @Test
    void partialRefundAccumulatesRefundedQuantityAndKeepsRemainingQuantity() {
        Order order = order();
        OrderDetail detail = detail(5, 1);

        service.refundPartial(detail, order, 2);

        assertEquals("3", detail.getQuantity());
        assertEquals(3, detail.getRefunded_quantity());
        verify(stock).handleRefundStock(detail, 7, 2, com.lanf.order.RefundStockAction.RESTORE, null, null);
        verify(details).updateById(detail);
    }

    @Test
    void finalRefundAddsCurrentRemainingQuantityToCumulativeValue() {
        Order order = order();
        OrderDetail detail = detail(3, 2);

        service.refundFullLine(detail, order);

        assertEquals(5, detail.getRefunded_quantity());
        assertEquals("refunded", detail.getLine_status());
        verify(stock).handleRefundStock(detail, 7, 3, com.lanf.order.RefundStockAction.RESTORE, null, null);
        verify(details).updateById(detail);
    }

    @Test
    void closesOrConvergesWechatPaymentBeforeAnyRefundSideEffect() {
        Order order = order();
        OrderDetail detail = detail(3, 0);
        KdsOrderHook kds = mock(KdsOrderHook.class);
        ReflectionTestUtils.setField(service, "kdsOrderHook", kds);
        when(paymentGuard.prepareForAmountMutation(order)).thenReturn(order);

        service.refundFullLine(detail, order);

        org.mockito.InOrder sequence = inOrder(paymentGuard, stock, details, kds);
        sequence.verify(paymentGuard).prepareForAmountMutation(order);
        sequence.verify(stock).handleRefundStock(detail, 7, 3,
                com.lanf.order.RefundStockAction.RESTORE, null, null);
        sequence.verify(details).updateById(detail);
        sequence.verify(kds).afterRefundDetails(7, java.util.Collections.singletonList(9901));
    }

    @Test
    void paymentWinningTheRaceLeavesDishStockAndKdsUntouched() {
        Order order = order();
        OrderDetail detail = detail(3, 0);
        KdsOrderHook kds = mock(KdsOrderHook.class);
        OrderAmountRecalculationService recalculation = mock(OrderAmountRecalculationService.class);
        ReflectionTestUtils.setField(service, "kdsOrderHook", kds);
        ReflectionTestUtils.setField(service, "orderAmountRecalculationService", recalculation);
        when(paymentGuard.prepareForAmountMutation(order))
                .thenThrow(new IllegalStateException("订单已被微信支付"));

        assertThrows(IllegalStateException.class, () -> service.refundFullLine(detail, order));

        verifyNoInteractions(stock, details, kds, recalculation);
        assertEquals("3", detail.getQuantity());
        assertEquals("normal", detail.getLine_status());
    }

    @Test
    void comboHeaderRefundCascadesToComponentsAndVoidsKds() {
        Order order = order();
        OrderDetail header = detail(1, 0);
        header.setId(1001);
        header.setLine_type("combo_header");
        header.setCombo_instance_id("inst-abc-123");

        OrderDetail comp1 = detail(2, 0);
        comp1.setId(1002);
        comp1.setLine_type("combo_component");
        comp1.setCombo_instance_id("inst-abc-123");

        OrderDetail comp2 = detail(1, 0);
        comp2.setId(1003);
        comp2.setLine_type("combo_component");
        comp2.setCombo_instance_id("inst-abc-123");

        KdsOrderHook kds = mock(KdsOrderHook.class);
        ReflectionTestUtils.setField(service, "kdsOrderHook", kds);

        when(details.list(any())).thenReturn(java.util.Arrays.asList(comp1, comp2));

        service.refundFullLine(header, order);

        assertEquals("refunded", header.getLine_status());
        assertEquals("refunded", comp1.getLine_status());
        assertEquals(2, comp1.getRefunded_quantity());
        assertEquals("refunded", comp2.getLine_status());
        assertEquals(1, comp2.getRefunded_quantity());

        verify(stock).handleRefundStock(header, 7, 1, com.lanf.order.RefundStockAction.RESTORE, null, null);
        verify(stock).handleRefundStock(comp1, 7, 2, com.lanf.order.RefundStockAction.RESTORE, null, null);
        verify(stock).handleRefundStock(comp2, 7, 1, com.lanf.order.RefundStockAction.RESTORE, null, null);
        verify(details).updateById(header);
        verify(details).updateById(comp1);
        verify(details).updateById(comp2);

        verify(kds).afterRefundDetails(7, java.util.Collections.singletonList(1001));
        verify(kds).afterRefundDetails(7, java.util.Collections.singletonList(1002));
        verify(kds).afterRefundDetails(7, java.util.Collections.singletonList(1003));
    }

    private static Order order() {
        Order order = new Order();
        order.setId(9001);
        order.setShop_id(7);
        order.setTransac_status("unsettled");
        return order;
    }

    private static OrderDetail detail(int quantity, int refunded) {
        OrderDetail detail = new OrderDetail();
        detail.setId(9901);
        detail.setQuantity(String.valueOf(quantity));
        detail.setRefunded_quantity(refunded);
        detail.setTotal_price(50d);
        detail.setLine_status("normal");
        return detail;
    }
}

