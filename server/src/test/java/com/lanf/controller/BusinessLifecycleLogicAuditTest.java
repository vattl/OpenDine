package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.controller.cashier.CashierOrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.DailyCloseSnapshot;
import com.lanf.entity.DailyStat;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.DailyCloseSnapshotMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IDailyStatService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShiftService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class BusinessLifecycleLogicAuditTest {

    private OrderController orderController;
    private CashierOrderController cashierOrderController;
    private IShopService shopService;
    private IOrderService orderService;
    private IShiftService shiftService;
    private IDailyStatService dailyStatService;
    private DailyCloseSnapshotMapper dailyCloseSnapshotMapper;
    private IAdminPermissionService adminPermissionService;

    @BeforeEach
    void setUp() {
        orderController = new OrderController();
        cashierOrderController = new CashierOrderController();

        shopService = mock(IShopService.class);
        orderService = mock(IOrderService.class);
        shiftService = mock(IShiftService.class);
        dailyStatService = mock(IDailyStatService.class);
        dailyCloseSnapshotMapper = mock(DailyCloseSnapshotMapper.class);
        adminPermissionService = mock(IAdminPermissionService.class);

        ReflectionTestUtils.setField(orderController, "shopService", shopService);
        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "shiftService", shiftService);
        ReflectionTestUtils.setField(orderController, "dailyStatService", dailyStatService);
        ReflectionTestUtils.setField(orderController, "dailyCloseSnapshotMapper", dailyCloseSnapshotMapper);
        ReflectionTestUtils.setField(orderController, "adminPermissionService", adminPermissionService);

        ReflectionTestUtils.setField(cashierOrderController, "shopService", shopService);
        ReflectionTestUtils.setField(cashierOrderController, "orderService", orderService);
        ReflectionTestUtils.setField(cashierOrderController, "orderController", orderController);
        ReflectionTestUtils.setField(cashierOrderController, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(cashierOrderController, "dailyCloseSnapshotMapper", dailyCloseSnapshotMapper);
        ReflectionTestUtils.setField(cashierOrderController, "dailyStatService", dailyStatService);
    }

    @Test
    void cEndCreateOrder_whenStoreClosed_shouldRejectWith4003() {
        Shop closedShop = new Shop();
        closedShop.setId(1);
        closedShop.setStatus(1);
        closedShop.setOrdering_open(0);
        when(shopService.getById(1)).thenReturn(closedShop);

        OrderDTO dto = new OrderDTO();
        dto.setShop_id(1);
        dto.setDineInOrTakeOut("堂食");
        dto.setTable_number("01");

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Shop-Id", "1");

        R r = orderController.create(dto, request);
        assertEquals(4003, r.get("code"));
        assertEquals("门店已打烊，暂不接单", r.get("msg"));
    }

    @Test
    void cashierQuickOrder_whenStoreClosed_shouldRejectWith4003() {
        Shop closedShop = new Shop();
        closedShop.setId(1);
        closedShop.setStatus(1);
        closedShop.setOrdering_open(0);
        when(shopService.getById(1)).thenReturn(closedShop);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        Map<String, Object> body = new HashMap<>();
        body.put("order_no", "CASHIER_001");
        body.put("table_number", "01");
        body.put("dining_type", "堂食");
        body.put("goods_list", Collections.emptyList());

        ReflectionTestUtils.setField(cashierOrderController, "request", request);
        R r = cashierOrderController.quickOrder(body);

        assertEquals(4003, r.get("code"));
        assertEquals("门店暂未营业，请先开启营业", r.get("msg"));
    }

    @Test
    void changeBusinessCore_closeStore_decoupledFromDailyClose_shouldSucceed() {
        Shop openShop = new Shop();
        openShop.setId(1);
        openShop.setStatus(1);
        openShop.setOrdering_open(1);
        openShop.setSettle_required(1);
        openShop.setShift_required(0);
        openShop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(openShop);
        when(shopService.update(any(Wrapper.class))).thenReturn(true);

        MockHttpServletRequest request = new MockHttpServletRequest();
        Map<String, String> body = new HashMap<>();
        body.put("bus", "0"); // 打烊

        com.lanf.service.DishMenuPushService pushService = mock(com.lanf.service.DishMenuPushService.class);
        ReflectionTestUtils.setField(orderController, "dishMenuPushService", pushService);

        R r = orderController.changeBusinessCore(1, body, request);
        assertEquals(0, r.get("code"));
        assertEquals(false, r.get("business"));
    }

    @Test
    void changeBusinessCore_openStore_whenPrevBizDayNotSettled_shouldRejectWith4001() {
        Shop shop = new Shop();
        shop.setId(1);
        shop.setStatus(1);
        shop.setOrdering_open(0);
        shop.setSettle_required(1);
        shop.setShift_required(0);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        when(dailyCloseSnapshotMapper.selectCount(any(Wrapper.class))).thenReturn(0);
        when(dailyStatService.count(any(Wrapper.class))).thenReturn(0);
        // 前一日有订单
        when(orderService.count(any(Wrapper.class))).thenReturn(5);

        MockHttpServletRequest request = new MockHttpServletRequest();
        Map<String, String> body = new HashMap<>();
        body.put("bus", "1"); // 开业

        R r = orderController.changeBusinessCore(1, body, request);
        assertEquals(4001, r.get("code"));
        org.junit.jupiter.api.Assertions.assertTrue(r.get("msg").toString().contains("尚未日结"));
    }

    @Test
    void cashierUpdateDiners_whenOrderUnsettled_shouldSucceed() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD20261016001");
        order.setShop_id(1);
        order.setTransac_status("unsettled");
        order.setNumber_of_diners("2");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD20261016001");
        body.put("number_of_diners", 4);

        R r = cashierOrderController.updateDiners(body);
        assertEquals(0, r.get("code"));
        assertEquals("4", order.getNumber_of_diners());
        assertEquals("2", r.get("previous_diners"));
        assertEquals(4, r.get("number_of_diners"));
    }

    @Test
    void cashierUpdateDiners_whenInvalidDinersCount_shouldRejectWith400() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD20261016001");
        body.put("number_of_diners", 0);

        R r = cashierOrderController.updateDiners(body);
        assertEquals(400, r.get("code"));
        assertEquals("用餐人数必须在 1 到 999 之间", r.get("msg"));

        body.put("number_of_diners", "abc");
        r = cashierOrderController.updateDiners(body);
        assertEquals(400, r.get("code"));
        assertEquals("用餐人数格式错误，必须为正整数", r.get("msg"));
    }

    @Test
    void cashierUpdateDiners_whenOrderCancelledOrClosed_shouldRejectWith4003() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        Order order = new Order();
        order.setId(102);
        order.setOrder_no("ORD20261016002");
        order.setShop_id(1);
        order.setTransac_status("cancelled");
        order.setNumber_of_diners("2");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD20261016002");
        body.put("number_of_diners", 3);

        R r = cashierOrderController.updateDiners(body);
        assertEquals(4003, r.get("code"));
        assertEquals("已作废或已关闭订单不允许修改用餐人数", r.get("msg"));
    }

    @Test
    void cashierUpdateDiners_whenOrderSettledAndDayClosed_shouldRejectWith40936() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        Order order = new Order();
        order.setId(103);
        order.setOrder_no("ORD20261016003");
        order.setShop_id(1);
        order.setTransac_status("success");
        order.setOrder_time(new java.util.Date());
        order.setPay_time(new java.util.Date());
        order.setNumber_of_diners("2");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        // 已日结
        when(dailyCloseSnapshotMapper.selectCount(any(Wrapper.class))).thenReturn(1);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD20261016003");
        body.put("number_of_diners", 5);

        R r = cashierOrderController.updateDiners(body);
        assertEquals(40936, r.get("code"));
        org.junit.jupiter.api.Assertions.assertTrue(r.get("msg").toString().contains("已完成日结封账，禁止修改用餐人数"));
    }

    @Test
    void cashierUpdateDiners_whenOrderSettledAndDayNotClosed_shouldSucceed() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        Order order = new Order();
        order.setId(104);
        order.setOrder_no("ORD20261016004");
        order.setShop_id(1);
        order.setTransac_status("success");
        order.setOrder_time(new java.util.Date());
        order.setPay_time(new java.util.Date());
        order.setNumber_of_diners("2");
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(any(Order.class))).thenReturn(true);

        // 未日结
        when(dailyCloseSnapshotMapper.selectCount(any(Wrapper.class))).thenReturn(0);
        when(dailyStatService.count(any(Wrapper.class))).thenReturn(0);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD20261016004");
        body.put("number_of_diners", 6);

        R r = cashierOrderController.updateDiners(body);
        assertEquals(0, r.get("code"));
        assertEquals("6", order.getNumber_of_diners());
        assertEquals("2", r.get("previous_diners"));
        assertEquals(6, r.get("number_of_diners"));
    }
}
