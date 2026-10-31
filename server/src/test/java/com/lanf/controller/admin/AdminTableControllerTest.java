package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.User;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AdminTableControllerTest {

    @Test
    void status_shouldReturnAndSumEveryUnsettledOrderAfterMerge() {
        AdminTableController controller = new AdminTableController();
        ITableService tableService = mock(ITableService.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IUserService userService = mock(IUserService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Table table = new Table();
        table.setId(1);
        table.setShop_id(7);
        table.setNumber("A02");
        table.setStatus(1);
        table.setOrder_no("O-1");
        Order first = order(10, "O-1");
        first.setSett_amount(12.5d);
        first.setOpenid("member-openid");
        Order second = order(11, "O-2");
        second.setSett_amount(20d);
        User member = new User();
        member.setOpenid("member-openid");
        member.setPhone("13800000000");
        when(tableService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(table));
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(first, second));
        when(detailService.list(any(QueryWrapper.class))).thenReturn(
                Collections.singletonList(detail(10, 12.5)),
                Collections.singletonList(detail(11, 20d)));
        when(userService.list(any(QueryWrapper.class)))
                .thenReturn(Collections.singletonList(member));

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        R response = controller.status("A02");

        List<?> orders = (List<?>) response.get("orderList");
        List<?> audits = (List<?>) response.get("amountAudits");
        List<Table> tables = (List<Table>) response.get("tableList");
        Map<?, ?> aggregate = (Map<?, ?>) response.get("amountAudit");
        assertEquals(2, orders.size());
        assertEquals(2, audits.size());
        assertEquals(32.5d, tables.get(0).getAmount());
        assertEquals(2, aggregate.get("order_count"));
        assertEquals(32.5d, aggregate.get("payable_amount"));
        assertEquals("13800000000", first.getMember_phone());
    }

    @Test
    void status_shouldResolveTableAndMergedOrdersByOrderNo() {
        AdminTableController controller = new AdminTableController();
        ITableService tableService = mock(ITableService.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IUserService userService = mock(IUserService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Table table = new Table();
        table.setId(2);
        table.setShop_id(7);
        table.setNumber("B06");
        table.setStatus(1);
        Order requested = order(20, "O-20");
        requested.setSett_amount(18d);
        requested.setTable_number("B06");
        Order merged = order(21, "O-21");
        merged.setSett_amount(22d);
        merged.setTable_number("B06");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(requested);
        when(tableService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(table));
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(requested, merged));
        when(detailService.list(any(QueryWrapper.class))).thenReturn(
                Collections.singletonList(detail(20, 18d)),
                Collections.singletonList(detail(21, 22d)));

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        R response = controller.status(null, "O-20", null);

        List<?> orders = (List<?>) response.get("orderList");
        List<Table> tables = (List<Table>) response.get("tableList");
        assertEquals(2, orders.size());
        assertEquals("B06", tables.get(0).getNumber());
        assertEquals(40d, tables.get(0).getAmount());
    }

    @Test
    void status_shouldReturnOnlyHistoricalOrderWhenTableHasBeenReused() {
        AdminTableController controller = new AdminTableController();
        ITableService tableService = mock(ITableService.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IUserService userService = mock(IUserService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Table reusedTable = new Table();
        reusedTable.setId(3);
        reusedTable.setShop_id(7);
        reusedTable.setNumber("C08");
        reusedTable.setStatus(1);
        reusedTable.setOrder_no("O-NEW");
        reusedTable.setAmount(88d);
        Order historical = order(30, "O-OLD");
        historical.setSett_amount(35d);
        historical.setTable_number("C08");
        historical.setTransac_status("success");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(historical);
        when(tableService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(reusedTable));
        when(detailService.list(any(QueryWrapper.class)))
                .thenReturn(Collections.singletonList(detail(30, 35d)));

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        R response = controller.status(null, null, "O-OLD");

        List<Order> orders = (List<Order>) response.get("orderList");
        List<Table> tables = (List<Table>) response.get("tableList");
        assertEquals(1, orders.size());
        assertEquals("O-OLD", orders.get(0).getOrder_no());
        assertEquals(88d, tables.get(0).getAmount());
    }

    @Test
    void add_shouldValidateTableNumberAndTolerateMissingWechatToken() {
        AdminTableController controller = new AdminTableController();
        ITableService tableService = mock(ITableService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        when(tableService.count(any(QueryWrapper.class))).thenReturn(0);
        when(tableService.save(any(Table.class))).thenReturn(true);

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        // Test empty number validation
        Table emptyTable = new Table();
        R errResponse = controller.add(emptyTable);
        assertEquals(500, errResponse.get("code"));

        // Test normal table creation (tolerating wechat token absence)
        Table table = new Table();
        table.setNumber("A88");
        R successResponse = controller.add(table);
        assertEquals(0, successResponse.get("code"));
    }

    @Test
    void delete_shouldRejectOccupiedTableAndAllowEmptyTable() {
        AdminTableController controller = new AdminTableController();
        ITableService tableService = mock(ITableService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Table occupied = new Table();
        occupied.setId(10);
        occupied.setShop_id(7);
        occupied.setNumber("T10");
        occupied.setStatus(1); // occupied

        Table empty = new Table();
        empty.setId(11);
        empty.setShop_id(7);
        empty.setNumber("T11");
        empty.setStatus(0); // empty

        when(tableService.getById(10)).thenReturn(occupied);
        when(tableService.getById(11)).thenReturn(empty);
        when(tableService.removeById(11)).thenReturn(true);

        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        // Reject occupied
        R occupiedRes = controller.delete(10);
        assertEquals(500, occupiedRes.get("code"));

        // Allow empty
        R emptyRes = controller.delete(11);
        assertEquals(0, emptyRes.get("code"));
    }

    private static Order order(int id, String orderNo) {
        Order order = new Order();
        order.setId(id);
        order.setShop_id(7);
        order.setOrder_no(orderNo);
        order.setTable_number("A02");
        order.setTransac_status("unsettled");
        return order;
    }

    private static OrderDetail detail(int orderId, double totalPrice) {
        OrderDetail detail = new OrderDetail();
        detail.setMId(orderId);
        detail.setQuantity("1");
        detail.setTotal_price(totalPrice);
        detail.setLine_status("normal");
        return detail;
    }
}

