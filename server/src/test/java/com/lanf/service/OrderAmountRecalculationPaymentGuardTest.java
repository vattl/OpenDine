package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.WechatJsapiPaymentService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderAmountRecalculationPaymentGuardTest {

    @Test
    void paymentGuardRunsBeforeAmountRecalculationWrites() {
        OrderAmountRecalculationService service = new OrderAmountRecalculationService();
        WechatJsapiPaymentService guard = mock(WechatJsapiPaymentService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        IOrderService orderService = mock(IOrderService.class);
        Order order = order();
        when(guard.prepareForAmountMutation(order)).thenReturn(order);
        when(detailService.list(any(QueryWrapper.class))).thenReturn(Collections.<OrderDetail>emptyList());
        when(orderService.updateById(order)).thenReturn(true);
        inject(service, guard, detailService, orderService);

        service.recalcFromActiveDetails(order);

        verify(guard).prepareForAmountMutation(order);
        verify(orderService).updateById(order);
    }

    @Test
    void uncertainPaymentStateStopsRecalculationBeforeAnyAmountWrite() {
        OrderAmountRecalculationService service = new OrderAmountRecalculationService();
        WechatJsapiPaymentService guard = mock(WechatJsapiPaymentService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        IOrderService orderService = mock(IOrderService.class);
        Order order = order();
        when(guard.prepareForAmountMutation(order))
                .thenThrow(new IllegalStateException("微信支付状态暂不确定"));
        inject(service, guard, detailService, orderService);

        assertThrows(IllegalStateException.class, () -> service.recalcFromActiveDetails(order));

        verify(detailService, never()).list(any(QueryWrapper.class));
        verify(orderService, never()).updateById(any(Order.class));
    }

    private static void inject(OrderAmountRecalculationService service, WechatJsapiPaymentService guard,
                               IOrderDetailService detailService, IOrderService orderService) {
        ReflectionTestUtils.setField(service, "wechatJsapiPaymentService", guard);
        ReflectionTestUtils.setField(service, "orderDetailService", detailService);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "serviceFeeConfig", mock(ServiceFeeConfig.class));
        ReflectionTestUtils.setField(service, "userCouponMapper", mock(UserCouponMapper.class));
        ReflectionTestUtils.setField(service, "takeoutDeliveryService", mock(ITakeoutDeliveryService.class));
        ReflectionTestUtils.setField(service, "tableService", mock(ITableService.class));
        ReflectionTestUtils.setField(service, "couponService", mock(ICouponService.class));
    }

    private static Order order() {
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORDER-1");
        order.setShop_id(7);
        order.setDineInOrTakeOut("打包");
        order.setTransac_status("unsettled");
        return order;
    }
}
