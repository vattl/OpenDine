package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.order.OrderRevisionService;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class OrderRevisionControllerContractTest {

    @Test
    void orderDtoAcceptsExpectedVersionAliases() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        assertEquals(7, mapper.readValue("{\"expectedVersion\":7}", OrderDTO.class).getExpectedVersion());
        assertEquals(8, mapper.readValue("{\"expected_version\":8}", OrderDTO.class).getExpectedVersion());
    }

    @Test
    void staleChangePriceStopsBeforeApprovalOrDetailMutation() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        OrderRevisionService revisionService = mock(OrderRevisionService.class);
        HighRiskActionAuthorizationService authorizationService = mock(HighRiskActionAuthorizationService.class);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 3);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderRevisionService", revisionService);
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorizationService);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD-REV-1");
        order.setShop_id(3);
        order.setRevision(8);
        order.setTransac_status("unsettled");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(revisionService.readExpectedVersion(any())).thenReturn(7);
        when(revisionService.assertExpected(order, 7)).thenThrow(
                new ApiException(409, "ORDER_VERSION_CONFLICT", "订单已被其他终端修改"));

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-REV-1");
        body.put("detail_id", 55);
        body.put("total_price", 8d);
        body.put("expectedVersion", 7);

        ApiException ex = assertThrows(ApiException.class, () -> controller.updatePrice(body));
        assertEquals("ORDER_VERSION_CONFLICT", ex.getErrorCode());
        verify(authorizationService, never()).authorize(any());
    }

    @Test
    void staleRefundDishStopsBeforeApprovalAndDetailLookup() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        OrderRevisionService revisionService = mock(OrderRevisionService.class);
        HighRiskActionAuthorizationService authorizationService = mock(HighRiskActionAuthorizationService.class);
        com.lanf.service.IOrderDetailService detailService = mock(com.lanf.service.IOrderDetailService.class);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 3);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "orderRevisionService", revisionService);
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorizationService);

        Order order = unsettledOrder();
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(revisionService.readExpectedVersion(any())).thenReturn(7);
        when(revisionService.assertExpected(order, 7)).thenThrow(versionConflict());

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-REV-1");
        body.put("detail_id", 55);
        body.put("quantity", 1);
        body.put("expectedVersion", 7);

        assertThrows(ApiException.class, () -> controller.refundDish(body));
        verifyNoInteractions(detailService, authorizationService);
    }

    @Test
    void staleDiscountStopsBeforePaymentPreparationAndApproval() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        OrderRevisionService revisionService = mock(OrderRevisionService.class);
        HighRiskActionAuthorizationService authorizationService = mock(HighRiskActionAuthorizationService.class);
        com.lanf.payment.service.WechatJsapiPaymentService paymentService =
                mock(com.lanf.payment.service.WechatJsapiPaymentService.class);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 3);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderRevisionService", revisionService);
        ReflectionTestUtils.setField(controller, "highRiskActionAuthorizationService", authorizationService);
        ReflectionTestUtils.setField(controller, "wechatJsapiPaymentService", paymentService);

        Order order = unsettledOrder();
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(revisionService.readExpectedVersion(any())).thenReturn(7);
        when(revisionService.assertExpected(order, 7)).thenThrow(versionConflict());

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-REV-1");
        body.put("payRate", 0.9d);
        body.put("expectedVersion", 7);

        assertThrows(ApiException.class, () -> controller.discount(body));
        verifyNoInteractions(paymentService, authorizationService);
    }

    @Test
    void cashierAddDishesPropagatesExpectedVersionToOrderCommand() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        IShopService shopService = mock(IShopService.class);
        IDishService dishService = mock(IDishService.class);
        OrderController orderController = mock(OrderController.class);
        OrderRevisionService revisionService = mock(OrderRevisionService.class);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 3);
        ReflectionTestUtils.setField(controller, "request", request);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderRevisionService", revisionService);

        Shop shop = new Shop();
        shop.setId(3);
        shop.setStatus(1);
        shop.setOrdering_open(1);
        when(shopService.getById(3)).thenReturn(shop);

        Order existing = new Order();
        existing.setId(101);
        existing.setOrder_no("ORD-REV-1");
        existing.setShop_id(3);
        existing.setTable_number("A01");
        existing.setOpenid("member-1");
        existing.setOrderNumber(1);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(existing);
        when(revisionService.readExpectedVersion(any())).thenReturn(7);
        when(orderController.addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class)))
                .thenReturn(R.ok().put("revision", 8));

        Map<String, Object> dish = new HashMap<>();
        dish.put("dish_id", 9);
        dish.put("name", "一串菇");
        dish.put("quantity", "1");
        dish.put("total_price", 8d);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-REV-1");
        body.put("table_number", "A01");
        body.put("goods_list", Arrays.asList(dish));
        body.put("expected_version", 7);

        controller.addDishes(body);

        ArgumentCaptor<OrderDTO> dto = ArgumentCaptor.forClass(OrderDTO.class);
        verify(orderController).addDishes(dto.capture(), nullable(HttpServletRequest.class));
        assertEquals(7, dto.getValue().getExpectedVersion());
    }

    private static Order unsettledOrder() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD-REV-1");
        order.setShop_id(3);
        order.setRevision(8);
        order.setTransac_status("unsettled");
        order.setSett_amount(108d);
        return order;
    }

    private static ApiException versionConflict() {
        return new ApiException(409, "ORDER_VERSION_CONFLICT", "订单已被其他终端修改");
    }
}
