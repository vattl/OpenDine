package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.realtime.CashierEventWebSocketHub;
import com.lanf.service.CashierClientRequestService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import com.lanf.service.impl.CashierTableOperationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class CashierTableCoordinationTest {

    private CashierTableController tableController;
    private CashierOrderController orderController;
    private ITableService tableService;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private CashierTableOperationService tableOperationService;
    private CashierEventWebSocketHub webSocketHub;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        tableController = new CashierTableController();
        orderController = new CashierOrderController();
        tableService = mock(ITableService.class);
        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        tableOperationService = mock(CashierTableOperationService.class);
        webSocketHub = mock(CashierEventWebSocketHub.class);
        request = new MockHttpServletRequest();

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 88);

        ReflectionTestUtils.setField(tableController, "tableService", tableService);
        ReflectionTestUtils.setField(tableController, "tableOperationService", tableOperationService);
        ReflectionTestUtils.setField(tableController, "request", request);

        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(orderController, "tableService", tableService);
        ReflectionTestUtils.setField(orderController, "cashierEventWebSocketHub", webSocketHub);
        ReflectionTestUtils.setField(orderController, "clientRequestService", mock(CashierClientRequestService.class));
        ReflectionTestUtils.setField(orderController, "request", request);
    }

    @Test
    void tableAreas_shouldReturnStandardAreas() {
        R r = tableController.tableAreas();
        assertEquals(200, r.get("code"));
        List<?> data = (List<?>) r.get("data");
        assertNotNull(data);
        assertEquals(3, data.size());
        Map<?, ?> first = (Map<?, ?>) data.get(0);
        assertEquals("hall", first.get("code"));
        assertEquals("大厅散座", first.get("name"));
    }

    @Test
    void pulse_shouldCalculateCorrectMetrics() {
        Table t1 = new Table();
        t1.setId(1);
        t1.setNumber("A01");
        t1.setStatus(1); // 就餐中
        t1.setAmount(120.5);

        Table t2 = new Table();
        t2.setId(2);
        t2.setNumber("A02");
        t2.setStatus(2); // 待翻台
        t2.setAmount(0.0);

        Table t3 = new Table();
        t3.setId(3);
        t3.setNumber("A03");
        t3.setStatus(0); // 空闲
        t3.setAmount(0.0);

        Table t4 = new Table();
        t4.setId(4);
        t4.setNumber("A04");
        t4.setStatus(1); // 就餐中
        t4.setAmount(80.0);

        when(tableService.list(any(Wrapper.class))).thenReturn(Arrays.asList(t1, t2, t3, t4));

        R r = tableController.pulse();
        assertEquals(200, r.get("code"));
        Map<?, ?> data = (Map<?, ?>) r.get("data");
        assertNotNull(data);
        assertEquals(4, data.get("total_tables"));
        assertEquals(2, data.get("active_dining_count"));
        assertEquals(1, data.get("pending_clear_count"));
        assertEquals(200.5, data.get("total_seated_amount"));
        assertEquals(50.0, data.get("occupancy_rate_percent"));
    }

    @Test
    void batchClear_shouldDelegateToOperationService() {
        Table t1 = new Table();
        t1.setId(101);
        t1.setNumber("A01");

        Table t2 = new Table();
        t2.setId(102);
        t2.setNumber("A02");

        when(tableService.list(any(Wrapper.class))).thenReturn(Arrays.asList(t1, t2));
        Map<String, Object> opResult = new HashMap<>();
        opResult.put("success_count", 2);
        opResult.put("failed_table_numbers", Collections.emptyList());
        when(tableOperationService.batchClear(eq(1), anyList(), any(), any(), any())).thenReturn(opResult);

        Map<String, Object> body = new HashMap<>();
        body.put("table_ids", Arrays.asList(101, 102));
        body.put("operator_account", "cashier_01");

        R r = tableController.batchClear(body);
        assertEquals(200, r.get("code"));
        Map<?, ?> data = (Map<?, ?>) r.get("data");
        assertNotNull(data);
        assertEquals(2, data.get("success_count"));
    }

    @Test
    void updateDiners_shouldAdjustTeaFeeAndBroadcastWebSocket() {
        Order order = new Order();
        order.setId(10);
        order.setOrder_no("ORD-20261023-001");
        order.setShop_id(1);
        order.setTable_number("A01");
        order.setNumber_of_diners("4");
        order.setTransac_status("unsettled");
        order.setSett_amount(100.0);

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        OrderDetail teaDetail = new OrderDetail();
        teaDetail.setId(55);
        teaDetail.setMId(10);
        teaDetail.setName("餐位茶位费");
        teaDetail.setQuantity("4");
        teaDetail.setTotal_price(8.0);
        teaDetail.setLine_status("normal");

        when(orderDetailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(teaDetail));
        when(orderDetailService.updateById(any(OrderDetail.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-20261023-001");
        body.put("diners", 6);
        body.put("operator_account", "cashier_01");

        R r = (R) ReflectionTestUtils.invokeMethod(orderController, "updateDinersInternal", body);
        assertNotNull(r);
        assertEquals(200, r.get("code"));
        assertEquals(6, r.get("number_of_diners"));

        // Verify tea fee increased from 4 to 6 (delta = 2, unitPrice = 2 -> +4.0)
        verify(orderDetailService).updateById(teaDetail);
        assertEquals("6", teaDetail.getQuantity());
        assertEquals(12.0, teaDetail.getTotal_price());

        // Verify order amount updated to 104.0
        assertEquals(104.0, order.getSett_amount());

        // Verify WebSocket broadcast called
        verify(webSocketHub).broadcastTableOrderChanged(eq(1), eq("A01"), eq("ORD-20261023-001"), eq(6));
    }
}
