package com.lanf.order;

import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsLegacySyncService;
import com.lanf.mapper.CashierTableAuditMapper;
import com.lanf.mapper.CashierTableOperationMapper;
import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.dto.CashierTableOperationResult;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.impl.CashierTableOperationTransactionalService;
import com.lanf.service.impl.TakeoutDeliveryServiceImpl;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

public class OrderOffTimeAuditTest {

    @Test
    void testOrderEntityHasOffTime() {
        Order order = new Order();
        Date now = new Date();
        order.setOff_time(now);
        assertEquals(now, order.getOff_time());
    }

    @Test
    void testKdsCompletionSetsOffTime() {
        KdsLegacySyncService service = new KdsLegacySyncService();
        KdsConfigService configService = mock(KdsConfigService.class);
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(service, "configService", configService);
        ReflectionTestUtils.setField(service, "orderDetailService", mock(IOrderDetailService.class));
        ReflectionTestUtils.setField(service, "orderService", orderService);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("NO101");
        order.setOrder_receiving("rec_order");
        order.setTransac_status("unsettled");
        assertNull(order.getOff_time());

        KdsShopConfig config = new KdsShopConfig();
        config.setSync_legacy_rece(0);
        config.setAuto_off_order_on_kds_done(1);
        when(configService.getOrDefault(1)).thenReturn(config);
        when(orderService.getById(101)).thenReturn(order);

        service.afterOrderKdsStatus(1, 101, KdsOrderStatus.ALL_DONE);

        assertEquals("off_order", order.getOrder_receiving());
        assertNotNull(order.getOff_time());
        verify(orderService).updateById(order);
    }

    @Test
    void testAdminReceivingOffOrderSetsOffTime() {
        AdminOrderController controller = new AdminOrderController();
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(controller, "orderService", orderService);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("admin_shop_id", 1);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        Order existing = new Order();
        existing.setId(201);
        existing.setShop_id(1);
        existing.setOrder_no("NO201");
        existing.setOrder_receiving("rec_order");
        assertNull(existing.getOff_time());
        when(orderService.getById(201)).thenReturn(existing);

        Order param = new Order();
        param.setId(201);
        param.setOrder_receiving("off_order");

        R r = controller.receiving(param);
        assertEquals(0, r.get("code"));
        assertEquals("off_order", existing.getOrder_receiving());
        assertNotNull(existing.getOff_time());
        verify(orderService).updateById(existing);
    }

    @Test
    void testCashierClearTableFinishesSettledOrders() {
        CashierTableOperationMapper operationMapper = mock(CashierTableOperationMapper.class);
        CashierTableAuditMapper auditMapper = mock(CashierTableAuditMapper.class);
        ObjectMapper objectMapper = new ObjectMapper();

        CashierTableOperationTransactionalService service =
                new CashierTableOperationTransactionalService(operationMapper, auditMapper, objectMapper);

        Table table = new Table();
        table.setId(10);
        table.setShop_id(1);
        table.setNumber("A01");
        table.setStatus(2); // 待清台

        when(operationMapper.lockTable(1, "A01")).thenReturn(table);
        when(operationMapper.lockUnsettledOrders(1, "A01")).thenReturn(Collections.emptyList());
        when(operationMapper.clearTable(eq(10), eq(1), eq(2), any(Date.class))).thenReturn(1);

        CashierTableOperationRequest req = new CashierTableOperationRequest();
        req.setAction("CLEAR");
        req.setShopId(1);
        req.setSourceTable("A01");
        req.setRequestKey("req-clear-1");

        CashierTableOperationResult result = service.execute(req);
        assertTrue(result.isSuccess());
        verify(operationMapper).finishSettledOrdersOnTable(eq(1), eq("A01"), any(Date.class));
    }

    @Test
    void testTakeoutDeliveryCompletionSetsOffTime() {
        TakeoutDeliveryServiceImpl service = spy(new TakeoutDeliveryServiceImpl());
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(service, "orderService", orderService);

        Order order = new Order();
        order.setId(301);
        order.setShop_id(1);
        order.setDineInOrTakeOut("外卖");
        order.setOrder_receiving("rec_order");
        assertNull(order.getOff_time());

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setId(1L);
        delivery.setOrder_id(301);
        delivery.setDispatch_status("delivering");

        when(orderService.getById(301)).thenReturn(order);
        doReturn(delivery).when(service).getByOrderId(301);
        doReturn(true).when(service).updateById(delivery);

        boolean updated = service.updateDispatchStatus(301, "completed", 1);
        assertTrue(updated);
        assertEquals("off_order", order.getOrder_receiving());
        assertNotNull(order.getOff_time());
        verify(orderService).updateById(order);
    }
}
