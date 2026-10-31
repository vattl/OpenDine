package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.Admin;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.order.OrderRevisionService;
import com.lanf.service.IDishService;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.CashierClientRequestService;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.impl.OrderDetailRefundService;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierOrderControllerTest {

    private static final String CASHIER_QUICK_ORDER_ATTRIBUTE =
            "com.lanf.order.cashierQuickOrder";

    private static void allowOrderRevision(CashierOrderController controller) {
        ReflectionTestUtils.setField(controller, "orderRevisionService", mock(OrderRevisionService.class));
    }

    @Test
    void today_shouldReturnUnsettledOrdersAndOrdersFromLastThreeHoursByDefault() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        AtomicReference<QueryWrapper<Order>> captured = new AtomicReference<>();
        when(orderService.list(any(QueryWrapper.class))).thenAnswer(invocation -> {
            captured.set(invocation.getArgument(0));
            return Collections.emptyList();
        });
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "request", request);
        com.lanf.service.IShopService shopService = mock(com.lanf.service.IShopService.class);
        Shop shop = new Shop();
        shop.setId(7);
        shop.setSettle_time("04:00");
        when(shopService.getById(7)).thenReturn(shop);
        ReflectionTestUtils.setField(controller, "shopService", shopService);

        R result = controller.today(7, null, null);

        assertEquals(0, result.get("code"));
        String sql = captured.get().getSqlSegment();
        assertTrue(sql.contains("shop_id"));
        assertTrue(sql.contains("transac_status"));
        assertTrue(sql.contains("OR"));
        assertTrue(sql.contains("order_time"));
        assertTrue(sql.contains(">="));
        assertTrue(captured.get().getParamNameValuePairs().containsValue(7));
        assertTrue(captured.get().getParamNameValuePairs().containsValue("unsettled"));
        Date cutoff = captured.get().getParamNameValuePairs().values().stream()
                .filter(Date.class::isInstance).map(Date.class::cast)
                .min(java.util.Comparator.naturalOrder()).orElse(null);
        assertNotNull(cutoff);
        assertEquals(2, captured.get().getParamNameValuePairs().values().stream()
                .filter(Date.class::isInstance).count());
        long expected = System.currentTimeMillis() - java.util.concurrent.TimeUnit.HOURS.toMillis(3);
        assertTrue(Math.abs(cutoff.getTime() - expected) < java.util.concurrent.TimeUnit.MINUTES.toMillis(1));
    }

    @Test
    void today_shouldRejectMissingShopContext() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "request", new MockHttpServletRequest());

        R result = controller.today(1, null, null);

        assertEquals(4001, result.get("code"));
        verify(orderService, never()).list(any(QueryWrapper.class));
    }

    @Test
    void today_shouldRejectShopIdDifferentFromResolvedShop() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.today(8, null, null);

        assertEquals(4003, result.get("code"));
        verify(orderService, never()).list(any(QueryWrapper.class));
    }

    @Test
    void today_shouldRejectCustomRangeWithoutAdminSuperPermission() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        when(permissionService.getPermissionCodesByAdminId(9)).thenReturn(Collections.singleton("cashier:operate"));
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.today(7, null, null,
                "2026-10-01 10:00:00", "2026-10-02 10:00:00");

        assertEquals(403, result.get("code"));
        verify(orderService, never()).list(any(QueryWrapper.class));
    }

    @Test
    void today_shouldAllowAdminSuperToQueryCustomRange() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        AtomicReference<QueryWrapper<Order>> captured = new AtomicReference<>();
        when(permissionService.getPermissionCodesByAdminId(9)).thenReturn(Collections.singleton("admin:super"));
        when(orderService.list(any(QueryWrapper.class))).thenAnswer(invocation -> {
            captured.set(invocation.getArgument(0));
            return Collections.emptyList();
        });
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.today(7, "success", null,
                "2026-10-01 10:00:00", "2026-10-02 10:00:00");

        assertEquals(0, result.get("code"));
        assertTrue(captured.get().getSqlSegment().contains("order_time"));
        assertTrue(captured.get().getSqlSegment().contains("<=") );
        assertTrue(captured.get().getParamNameValuePairs().containsValue("success"));
        assertTrue(captured.get().getParamNameValuePairs().containsValue(Date.from(
                LocalDateTime.of(2026, 10, 1, 10, 0).atZone(ZoneId.of("Asia/Shanghai")).toInstant())));
        assertTrue(captured.get().getParamNameValuePairs().containsValue(Date.from(
                LocalDateTime.of(2026, 10, 2, 10, 0).atZone(ZoneId.of("Asia/Shanghai")).toInstant())));
    }

    @Test
    void today_shouldRejectPartialOrOversizedCustomRangeBeforeQuery() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        when(permissionService.getPermissionCodesByAdminId(9)).thenReturn(Collections.singleton("admin:super"));
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "request", request);

        R partial = controller.today(7, null, null, "2026-10-01", null);
        R oversized = controller.today(7, null, null, "2026-08-01", "2026-10-01");
        R mixed = controller.today(7, null, "2026-10-01", "2026-10-01", "2026-10-02");

        assertEquals(4002, partial.get("code"));
        assertEquals(4002, oversized.get("code"));
        assertEquals(4002, mixed.get("code"));
        verify(orderService, never()).list(any(QueryWrapper.class));
    }

    @Test
    void today_shouldKeepDateCompatibilityForAdminSuperOnly() {
        CashierOrderController controller = new CashierOrderController();
        IOrderService orderService = mock(IOrderService.class);
        IAdminPermissionService permissionService = mock(IAdminPermissionService.class);
        com.lanf.service.IShopService shopService = mock(com.lanf.service.IShopService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        Shop shop = new Shop();
        shop.setId(7);
        shop.setSettle_time("04:00");
        when(permissionService.getPermissionCodesByAdminId(9)).thenReturn(Collections.singleton("admin:super"));
        when(shopService.getById(7)).thenReturn(shop);
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.today(7, null, "2026-10-01", null, null);

        assertEquals(0, result.get("code"));
        verify(orderService).list(any(QueryWrapper.class));
    }

    @Test
    void generatedOrderNumbers_shouldRemainUniqueWithinOneThousandCalls() {
        Set<String> values = new HashSet<>();
        for (int index = 0; index < 1000; index++) {
            String orderNo = CashierOrderController.generateCashierOrderNo();
            assertTrue(orderNo.matches("^ORD\\d{17}$"));
            assertTrue(values.add(orderNo), "重复订单号：" + orderNo);
        }
    }

    @Test
    void quickOrder_shouldMarkPreopenedTableAsTrustedCashierFlow() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            HttpServletRequest forwardedRequest = invocation.getArgument(1);
            capturedOrder.set(invocation.getArgument(0));
            assertSame(request, forwardedRequest);
            assertEquals(Boolean.TRUE,
                    forwardedRequest.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE));
            return R.ok().put("order_no", "C1001").put("id", 1);
        }).when(orderController).create(any(OrderDTO.class), nullable(HttpServletRequest.class));

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("name", "油边环");
        line.put("quantity", 1);
        line.put("unit", "份");
        line.put("total_price", 15.0);
        line.put("cid", "3");
        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "40");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.quickOrder(body);

        assertEquals(0, result.get("code"));
        assertNull(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE));
        assertTrue(capturedOrder.get().getOrder_no()
                .matches("^ORD\\d{17}$"));
        assertEquals("堂食", capturedOrder.get().getDineInOrTakeOut());
        assertEquals("mis_order", capturedOrder.get().getOrder_receiving());
    }

    @Test
    void quickOrder_shouldSafelyParseJsonScalarTypesAndDishId() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            capturedOrder.set(invocation.getArgument(0));
            return R.ok().put("order_no", "ORD-TYPES").put("id", 1);
        }).when(orderController).create(any(OrderDTO.class), nullable(HttpServletRequest.class));
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", "12");
        line.put("name", "油边环");
        line.put("quantity", "2");
        line.put("unit", "份");
        line.put("total_price", "30.00");
        line.put("cid", 3);
        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", 40);
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.quickOrder(body);

        assertEquals(0, result.get("code"));
        assertEquals("40", capturedOrder.get().getTable_number());
        assertEquals(12, capturedOrder.get().getGoods_list().get(0).getDish_id());
        assertEquals("3", capturedOrder.get().getGoods_list().get(0).getCid());
        assertEquals(30d, capturedOrder.get().getGoods_list().get(0).getTotal_price());
    }

    @Test
    @SuppressWarnings("unchecked")
    void quickOrder_shouldReturnReadyContractAndFormalDetailMapping() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            OrderDTO dto = invocation.getArgument(0);
            dto.setId(9001);
            return R.ok().put("order_no", "ORD-9001").put("id", 9001);
        }).when(orderController).create(any(OrderDTO.class), nullable(HttpServletRequest.class));
        Order committed = new Order();
        committed.setId(9001);
        committed.setOrder_receiving("mis_order");
        when(orderService.getById(9001)).thenReturn(committed);
        OrderDetail detail = new OrderDetail();
        detail.setId(9901);
        detail.setDish_id(101);
        detail.setQuantity("2");
        detail.setClient_line_id("line-1");
        when(detailService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(detail));
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", 101);
        line.put("name", "油边王");
        line.put("quantity", 2);
        line.put("total_price", 30d);
        line.put("client_line_id", "line-1");
        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "18");
        body.put("goods_list", Arrays.asList(line));

        R result = controller.quickOrder(body);

        assertEquals(true, result.get("accepted"));
        assertEquals("ready", result.get("fulfillment_status"));
        assertEquals("mis_order", result.get("cloud_acceptance_status"));
        Map<String, Object> mapping = ((java.util.List<Map<String, Object>>)
                result.get("order_details")).get(0);
        assertEquals(9901, mapping.get("detail_id"));
        assertEquals("line-1", mapping.get("client_line_id"));
    }

    @Test
    void quickOrder_shouldReturnParameterErrorForMalformedGoodsRow() {
        CashierOrderController controller = new CashierOrderController();
        ReflectionTestUtils.setField(controller, "request", new MockHttpServletRequest());
        Map<String, Object> body = new HashMap<>();
        body.put("tableNumber", "A01");
        body.put("goods_list", Collections.singletonList("not-an-object"));

        R result = controller.quickOrder(body);

        assertEquals(400, result.get("code"));
    }

    @Test
    void addDishes_shouldPreserveSelectedSpicyAndLineMetadata() {
        CashierOrderController controller = new CashierOrderController();
        allowOrderRevision(controller);
        markShopOrderingOpen(controller, 7);
        OrderController orderController = mock(OrderController.class);
        IOrderService orderService = mock(IOrderService.class);
        IDishService dishService = mock(IDishService.class);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();

        Order existing = new Order();
        existing.setOrder_no("ORD-ADD-1");
        existing.setOrderNumber(1);
        existing.setShop_id(7);
        existing.setTable_number("18");
        existing.setOpenid("cashier_system");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existing);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            capturedOrder.set(invocation.getArgument(0));
            return R.ok();
        }).when(orderController).addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class));

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", 101);
        line.put("name", "油边王");
        line.put("quantity", 2);
        line.put("unit", "份");
        line.put("total_price", 30d);
        line.put("cid", "3");
        line.put("selectedSpicy", "{\"辣度\":\"微辣\"}");
        line.put("remark", "少盐");
        line.put("client_line_id", "add-line-1");
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-ADD-1");
        body.put("table_number", "18");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.addDishes(body);

        assertEquals(0, result.get("code"));
        OrderDetail capturedLine = capturedOrder.get().getGoods_list().get(0);
        assertEquals(101, capturedLine.getDish_id());
        assertEquals("{\"辣度\":\"微辣\"}", capturedLine.getSelectedSpicy());
        assertEquals("少盐", capturedLine.getRemark());
        assertEquals("add-line-1", capturedLine.getClient_line_id());
    }

    @Test
    void addDishes_shouldBindOrderOwnerAfterResolvingAuthorizedShop() {
        CashierOrderController controller = new CashierOrderController();
        allowOrderRevision(controller);
        markShopOrderingOpen(controller, 7);
        OrderController orderController = mock(OrderController.class);
        IOrderService orderService = mock(IOrderService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        AtomicReference<QueryWrapper<Order>> capturedQuery = new AtomicReference<>();

        Order existing = new Order();
        existing.setOrder_no("ORD-ADD-OWNER");
        existing.setOrderNumber(1);
        existing.setShop_id(7);
        existing.setTable_number("18");
        existing.setOpenid("cashier_system");
        when(orderService.getOne(any(QueryWrapper.class))).thenAnswer(invocation -> {
            capturedQuery.set(invocation.getArgument(0));
            return existing;
        });
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            OrderDTO dto = invocation.getArgument(0);
            return "cashier_system".equals(dto.getOpenid())
                    ? R.ok()
                    : R.error(403, "无权给该订单加菜");
        }).when(orderController).addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class));

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", 101);
        line.put("name", "油边王");
        line.put("quantity", 1);
        line.put("unit", "份");
        line.put("total_price", 15d);
        line.put("cid", "3");
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-ADD-OWNER");
        body.put("table_number", "18");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.addDishes(body);

        assertEquals(0, result.get("code"));
        assertTrue(capturedQuery.get().getSqlSegment().contains("shop_id"));
        assertTrue(capturedQuery.get().getParamNameValuePairs().containsValue(7));
    }

    @Test
    void addDishes_shouldRejectTableNumberDifferentFromStoredOrder() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 7);
        OrderController orderController = mock(OrderController.class);
        IOrderService orderService = mock(IOrderService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        Order existing = new Order();
        existing.setOrder_no("ORD-ADD-TABLE");
        existing.setShop_id(7);
        existing.setTable_number("18");
        existing.setOpenid("cashier_system");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existing);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(orderController.addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class))).thenReturn(R.ok());

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", 101);
        line.put("name", "油边王");
        line.put("quantity", 1);
        line.put("unit", "份");
        line.put("total_price", 15d);
        line.put("cid", "3");
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-ADD-TABLE");
        body.put("table_number", "19");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.addDishes(body);

        assertEquals(4003, result.get("code"));
        verify(orderController, never()).addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class));
    }

    @Test
    void addDishes_shouldReturnParameterErrorForMalformedDishId() {
        CashierOrderController controller = new CashierOrderController();
        ReflectionTestUtils.setField(controller, "request", new MockHttpServletRequest());

        Map<String, Object> line = new HashMap<>();
        line.put("dish_id", "not-an-integer");
        line.put("name", "油边王");
        line.put("quantity", 1);
        line.put("total_price", 15d);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-ADD-1");
        body.put("table_number", "18");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.addDishes(body);

        assertEquals(400, result.get("code"));
        assertEquals("dish_id 必须是整数", result.get("msg"));
    }

    @Test
    void addDishes_shouldSupportComboFieldsAndPropagateErrors() {
        CashierOrderController controller = new CashierOrderController();
        allowOrderRevision(controller);
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderService orderService = mock(IOrderService.class);
        IDishService dishService = mock(IDishService.class);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();

        Order existing = new Order();
        existing.setOrder_no("ORD20260912154554756");
        existing.setOrderNumber(1);
        existing.setShop_id(1);
        existing.setTable_number("20");
        existing.setOpenid("cashier_system");
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existing);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            capturedOrder.set(invocation.getArgument(0));
            return R.error("套餐组「饮品」须选 1~1 项");
        }).when(orderController).addDishes(any(OrderDTO.class), nullable(HttpServletRequest.class));

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> comboLine = new HashMap<>();
        comboLine.put("dish_id", 139);
        comboLine.put("name", "单人油边套餐");
        comboLine.put("cid", "a20260517044607000000389");
        comboLine.put("quantity", "1");
        comboLine.put("unit", "份");
        comboLine.put("total_price", 68.0);
        comboLine.put("selectedSpicy", "{\"辣度\":\"不辣\"}");
        comboLine.put("line_type", "combo");
        comboLine.put("combo_id", 8);
        comboLine.put("combo_selections", new HashMap<>());

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD20260912154554756");
        body.put("table_number", "20");
        body.put("goods_list", Collections.singletonList(comboLine));

        R result = controller.addDishes(body);

        assertEquals(500, result.get("code"));
        assertEquals("套餐组「饮品」须选 1~1 项", result.get("msg"));
        assertNotNull(capturedOrder.get());
        OrderDetail capturedLine = capturedOrder.get().getGoods_list().get(0);
        assertEquals(139, capturedLine.getDish_id());
        assertEquals(8L, capturedLine.getCombo_id());
        assertEquals("combo", capturedLine.getLine_type());
        assertNotNull(capturedLine.getComboSelections());
    }

    @Test
    void checkout_shouldDelegateToTransactionalServiceWithResolvedShop() {
        CashierOrderController controller = new CashierOrderController();
        CashierCheckoutService checkoutService = mock(CashierCheckoutService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-COMBINED");
        body.put("payment_method", "online_combined");
        when(checkoutService.checkout(2, body)).thenReturn(
                R.ok().put("order_no", "ORD-COMBINED").put("idempotent", true));
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.checkout(body);

        assertEquals(0, result.get("code"));
        verify(checkoutService).checkout(2, body);
    }

    @Test
    void checkout_shouldForwardClientRequestIdToIdempotencyService() {
        CashierOrderController controller = new CashierOrderController();
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "mobile-checkout-1");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-1");
        when(clientRequestService.execute(eq(7), eq(9), eq("mobile-checkout-1"),
                eq("/cashier/order/checkout"), eq(body), any(Supplier.class)))
                .thenReturn(R.ok().put("order_no", "ORD-1"));
        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.checkout(body);

        assertEquals(0, result.get("code"));
        verify(clientRequestService).execute(eq(7), eq(9), eq("mobile-checkout-1"),
                eq("/cashier/order/checkout"), eq(body), any(Supplier.class));
    }

    @Test
    void refundDish_shouldBeIdempotentAndLockShopOwnedOrderBeforeDetail() {
        CashierOrderController controller = new CashierOrderController();
        allowOrderRevision(controller);
        allowSensitiveAuthorization(controller);
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        OrderDetailRefundService refundService = mock(OrderDetailRefundService.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "refund-1");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);

        Order order = new Order();
        order.setId(21);
        order.setOrder_no("ORD-REFUND-1");
        order.setShop_id(7);
        order.setTransac_status("unsettled");
        OrderDetail detail = new OrderDetail();
        detail.setId(31);
        detail.setMId(21);
        detail.setMorder_no("ORD-REFUND-1");
        detail.setQuantity("2");

        AtomicReference<QueryWrapper<Order>> orderQuery = new AtomicReference<>();
        AtomicReference<QueryWrapper<OrderDetail>> detailQuery = new AtomicReference<>();
        when(orderService.getOne(any(QueryWrapper.class))).thenAnswer(invocation -> {
            orderQuery.set(invocation.getArgument(0));
            return order;
        });
        when(detailService.getById(31)).thenReturn(detail);
        when(detailService.getOne(any(QueryWrapper.class))).thenAnswer(invocation -> {
            detailQuery.set(invocation.getArgument(0));
            return detail;
        });
        when(clientRequestService.execute(eq(7), eq(9), eq("refund-1"),
                eq("/cashier/order/refundDish"), any(), any(Supplier.class)))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());

        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "orderDetailRefundService", refundService);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-REFUND-1");
        body.put("detail_id", 31);
        body.put("quantity", 1);

        R result = controller.refundDish(body);

        assertEquals(0, result.get("code"));
        verify(clientRequestService).execute(eq(7), eq(9), eq("refund-1"),
                eq("/cashier/order/refundDish"), eq(body), any(Supplier.class));
        String orderSql = orderQuery.get().getSqlSegment();
        assertTrue(orderSql.contains("shop_id"));
        assertTrue(orderSql.contains("FOR UPDATE"));
        assertTrue(orderQuery.get().getParamNameValuePairs().containsValue(7));
        String detailSql = detailQuery.get().getSqlSegment();
        assertTrue(detailSql.contains("mId"));
        assertTrue(detailSql.contains("FOR UPDATE"));
        verify(refundService).refundPartial(detail, order, 1, com.lanf.order.RefundStockAction.RESTORE, "authorized_admin:22", null);
    }

    @Test
    void refund_shouldWriteRefundAmountAndDeductCashChannel() {
        CashierOrderController controller = new CashierOrderController();
        allowSensitiveAuthorization(controller);
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        IOrderService orderService = mock(IOrderService.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        ITakeoutDeliveryService takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        CashierCheckoutService checkoutService = mock(CashierCheckoutService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "refund-cash-1");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);

        Order order = new Order();
        order.setId(21);
        order.setOrder_no("ORD-CASH-1");
        order.setShop_id(7);
        order.setTransac_status("success");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        order.setDiscount_amount(0d);
        order.setPay_amount_cash(50d);
        order.setRefund_amount(0d);

        AtomicReference<Order> updated = new AtomicReference<>();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenAnswer(invocation -> {
            updated.set(invocation.getArgument(0));
            return true;
        });
        when(orderLogService.save(any())).thenReturn(true);
        when(takeoutDeliveryService.getRefundBlockReason(any(Order.class))).thenReturn(null);
        when(checkoutService.refundCashComponent(eq(7), any(Map.class))).thenReturn(R.ok()
                .put("refund_amount", 50d).put("refund_total", 50d).put("cash_remaining", 0d));
        when(clientRequestService.execute(eq(7), eq(9), eq("refund-cash-1"),
                eq("/cashier/order/refund"), any(), any(Supplier.class)))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());

        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-CASH-1");

        R result = controller.refund(body);

        assertEquals(0, result.get("code"));
        assertEquals(50d, result.get("refund_amount"));
        assertEquals(50d, result.get("refund_total"));
        assertEquals(0d, result.get("cash_remaining"));
        verify(checkoutService).refundCashComponent(7, body);
    }

    @Test
    void refund_shouldRejectWhenCashChannelCleared() {
        CashierOrderController controller = new CashierOrderController();
        allowSensitiveAuthorization(controller);
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        IOrderService orderService = mock(IOrderService.class);
        ITakeoutDeliveryService takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        CashierCheckoutService checkoutService = mock(CashierCheckoutService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "refund-cash-2");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);

        Order order = new Order();
        order.setId(22);
        order.setOrder_no("ORD-CASH-2");
        order.setShop_id(7);
        order.setTransac_status("success");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        order.setDiscount_amount(0d);
        order.setPay_amount_cash(0d);
        order.setRefund_amount(0d);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(takeoutDeliveryService.getRefundBlockReason(any(Order.class))).thenReturn(null);
        when(checkoutService.refundCashComponent(eq(7), any(Map.class))).thenReturn(R.error("订单无现金渠道可退"));
        when(clientRequestService.execute(eq(7), eq(9), eq("refund-cash-2"),
                eq("/cashier/order/refund"), any(), any(Supplier.class)))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());

        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-CASH-2");

        R result = controller.refund(body);

        assertTrue(((Number) result.get("code")).intValue() != 0);
        verify(orderService, never()).updateById(any());
    }

    @Test
    void refund_shouldRejectUnpaidOrder() {
        CashierOrderController controller = new CashierOrderController();
        allowSensitiveAuthorization(controller);
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        IOrderService orderService = mock(IOrderService.class);
        CashierCheckoutService checkoutService = mock(CashierCheckoutService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "refund-cash-3");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);

        Order order = new Order();
        order.setId(23);
        order.setOrder_no("ORD-CASH-3");
        order.setShop_id(7);
        order.setTransac_status("unsettled");
        order.setPay_amount_cash(50d);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(clientRequestService.execute(eq(7), eq(9), eq("refund-cash-3"),
                eq("/cashier/order/refund"), any(), any(Supplier.class)))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());

        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-CASH-3");

        R result = controller.refund(body);

        assertTrue(((Number) result.get("code")).intValue() != 0);
        verify(orderService, never()).updateById(any());
    }

    @Test
    void refund_shouldRejectAmountExceedingCashRemaining() {
        CashierOrderController controller = new CashierOrderController();
        allowSensitiveAuthorization(controller);
        CashierClientRequestService clientRequestService = mock(CashierClientRequestService.class);
        IOrderService orderService = mock(IOrderService.class);
        ITakeoutDeliveryService takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        CashierCheckoutService checkoutService = mock(CashierCheckoutService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Client-Request-Id", "refund-cash-4");
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);

        Order order = new Order();
        order.setId(24);
        order.setOrder_no("ORD-CASH-4");
        order.setShop_id(7);
        order.setTransac_status("success");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        order.setDiscount_amount(0d);
        order.setPay_amount_cash(50d);
        order.setRefund_amount(0d);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(takeoutDeliveryService.getRefundBlockReason(any(Order.class))).thenReturn(null);
        when(checkoutService.refundCashComponent(eq(7), any(Map.class))).thenReturn(R.error("退款金额超过订单现金渠道剩余"));
        when(clientRequestService.execute(eq(7), eq(9), eq("refund-cash-4"),
                eq("/cashier/order/refund"), any(), any(Supplier.class)))
                .thenAnswer(invocation -> ((Supplier<R>) invocation.getArgument(5)).get());

        ReflectionTestUtils.setField(controller, "clientRequestService", clientRequestService);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(controller, "cashierCheckoutService", checkoutService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-CASH-4");
        body.put("refundAmount", 60);

        R result = controller.refund(body);

        assertTrue(((Number) result.get("code")).intValue() != 0);
        verify(orderService, never()).updateById(any());
    }

    @Test
    void refundDish_shouldRejectOrderOutsideResolvedShop() {
        CashierOrderController controller = new CashierOrderController();
        allowSensitiveAuthorization(controller);
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        OrderDetailRefundService refundService = mock(OrderDetailRefundService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(null);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "orderDetailRefundService", refundService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "ORD-OTHER-SHOP");
        body.put("detail_id", 31);
        body.put("quantity", 1);

        R result = controller.refundDish(body);

        assertEquals(500, result.get("code"));
        verify(refundService, never()).refundPartial(any(), any(), any(Integer.class));
        verify(refundService, never()).refundFullLine(any(), any());
    }
    @Test
    void quickOrder_shouldCreatePickupOrderForFrontDeskPacking() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            capturedOrder.set(invocation.getArgument(0));
            return R.ok().put("order_no", "ORD20260723014058928").put("id", 1);
        }).when(orderController).create(any(OrderDTO.class), nullable(HttpServletRequest.class));

        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("name", "油边环");
        line.put("quantity", 1);
        line.put("unit", "份");
        line.put("total_price", 15.0);
        line.put("cid", "3");
        Map<String, Object> body = new HashMap<>();
        body.put("dineInOrTakeOut", "打包");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.quickOrder(body);

        assertEquals(0, result.get("code"));
        assertEquals("打包", capturedOrder.get().getDineInOrTakeOut());
        assertNull(capturedOrder.get().getTable_number());
        assertEquals(16.0d, capturedOrder.get().getSett_amount());
        assertEquals(1.0d, result.get("packaging_fee"));
        assertEquals(16.0d, result.get("sett_amount"));
    }

    @Test
    void quickOrder_shouldRecognizePackingAliasAndNotRequireExistingTable() {
        CashierOrderController controller = new CashierOrderController();
        markShopOrderingOpen(controller, 1);
        OrderController orderController = mock(OrderController.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        IDishService dishService = mock(IDishService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        AtomicReference<OrderDTO> capturedOrder = new AtomicReference<>();
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        doAnswer(invocation -> {
            capturedOrder.set(invocation.getArgument(0));
            return R.ok().put("order_no", "PACK-1").put("id", 1);
        }).when(orderController).create(any(OrderDTO.class), nullable(HttpServletRequest.class));
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> line = new HashMap<>();
        line.put("name", "油边环");
        line.put("quantity", 1);
        line.put("total_price", 15.0);
        Map<String, Object> body = new HashMap<>();
        body.put("diningType", "pickup");
        body.put("tableNumber", "NOT-EXISTS");
        body.put("goods_list", Collections.singletonList(line));

        R result = controller.quickOrder(body);

        assertEquals(0, result.get("code"));
        assertEquals("打包", capturedOrder.get().getDineInOrTakeOut());
        assertEquals("NOT-EXISTS", capturedOrder.get().getTable_number());
        assertEquals(16.0d, capturedOrder.get().getSett_amount());
        assertEquals(1.0d, result.get("packaging_fee"));
    }

    @Test
    void discount_shouldProvideMigratedManualDiscountContract() {
        CashierOrderController controller = new CashierOrderController();
        allowOrderRevision(controller);
        allowSensitiveAuthorization(controller);
        IOrderService orderService = mock(IOrderService.class);
        ITableService tableService = mock(ITableService.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        Order order = new Order();
        order.setId(10);
        order.setShop_id(7);
        order.setOrder_no("O-100");
        order.setTransac_status("unsettled");
        order.setDineInOrTakeOut("打包");
        order.setSett_amount(100d);
        order.setService_fee(0d);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(order);
        when(orderService.updateById(order)).thenReturn(true);
        com.lanf.payment.service.WechatJsapiPaymentService jsapiPaymentService =
                mock(com.lanf.payment.service.WechatJsapiPaymentService.class);
        when(jsapiPaymentService.prepareForAmountMutation(order)).thenReturn(order);
        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "wechatJsapiPaymentService", jsapiPaymentService);
        ReflectionTestUtils.setField(controller, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "O-100");
        body.put("payRate", 0.9d);
        body.put("reason", "会员九折");

        R result = controller.discount(body);

        assertEquals(0, result.get("code"));
        assertEquals(100d, result.get("grossYuan"));
        assertEquals(10d, result.get("discount_amount"));
        assertEquals(90d, result.get("payableYuan"));
        assertTrue(order.getRemark().contains("会员九折"));
        verify(orderService).updateById(order);
    }

    @Test
    void printContent_shouldDelegateWithResolvedShopAndKeepResponseContract() {
        CashierOrderController controller = new CashierOrderController();
        OrderController orderController = mock(OrderController.class);
        IOrderLogService orderLogService = mock(IOrderLogService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(orderController.printContentForCashier(10, false, 7)).thenReturn(
                R.ok().put("content", "ticket").put("printSuccess", true).put("order_no", "O-10"));
        ReflectionTestUtils.setField(controller, "orderController", orderController);
        ReflectionTestUtils.setField(controller, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(controller, "request", request);

        R result = controller.printContent(10, false);

        assertEquals(0, result.get("code"));
        assertEquals("ticket", result.get("content"));
        assertEquals(true, result.get("printSuccess"));
        verify(orderController).printContentForCashier(10, false, 7);
    }

    @Test
    void legacyOrderPrintContent_shouldReturnMigrationNotice() {
        R result = new OrderController().getPrintContent(10, false);

        assertEquals(410, result.get("code"));
        assertTrue(result.get("msg").toString().contains("/cashier/order/printContent"));
    }
    private static void allowSensitiveAuthorization(CashierOrderController controller) {
        HighRiskActionAuthorizationService authorizationService =
                mock(HighRiskActionAuthorizationService.class);
        HighRiskActionAuthorizationService.Result result =
                mock(HighRiskActionAuthorizationService.Result.class);
        when(result.isAllowed()).thenReturn(true);
        when(result.getAuthorizedAdminId()).thenReturn(22);
        when(authorizationService.authorize(any())).thenReturn(result);
        ReflectionTestUtils.setField(
                controller, "highRiskActionAuthorizationService", authorizationService);
    }

    private static void markShopOrderingOpen(CashierOrderController controller, int shopId) {
        com.lanf.service.IShopService shopService = mock(com.lanf.service.IShopService.class);
        Shop shop = new Shop();
        shop.setId(shopId);
        shop.setOrdering_open(1);
        when(shopService.getById(shopId)).thenReturn(shop);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
    }
}

