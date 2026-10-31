package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.Admin;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.kds.service.KdsOrderEnrichService;
import com.lanf.util.AdminNameResolver;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CashierOrderCashierIdentityTest {

    private CashierOrderController cashierOrderController;
    private AdminOrderController adminOrderController;

    private IOrderService orderService;
    private IAdminService adminService;
    private IShopService shopService;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private KdsOrderEnrichService kdsOrderEnrichService;
    private IAdminPermissionService adminPermissionService;

    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        cashierOrderController = new CashierOrderController();
        adminOrderController = new AdminOrderController();

        orderService = mock(IOrderService.class);
        adminService = mock(IAdminService.class);
        shopService = mock(IShopService.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        kdsOrderEnrichService = mock(KdsOrderEnrichService.class);
        adminPermissionService = mock(IAdminPermissionService.class);

        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 5);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 88);

        when(adminPermissionService.getPermissionCodesByAdminId(88))
                .thenReturn(Collections.singleton("admin:super"));

        ReflectionTestUtils.setField(cashierOrderController, "orderService", orderService);
        ReflectionTestUtils.setField(cashierOrderController, "adminService", adminService);
        ReflectionTestUtils.setField(cashierOrderController, "shopService", shopService);
        ReflectionTestUtils.setField(cashierOrderController, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(cashierOrderController, "request", request);

        ReflectionTestUtils.setField(adminOrderController, "orderService", orderService);
        ReflectionTestUtils.setField(adminOrderController, "adminService", adminService);
        ReflectionTestUtils.setField(adminOrderController, "shopService", shopService);
        ReflectionTestUtils.setField(adminOrderController, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(adminOrderController, "kdsOrderEnrichService", kdsOrderEnrichService);
        ReflectionTestUtils.setField(adminOrderController, "httpServletRequest", request);

        Shop shop = new Shop();
        shop.setId(5);
        shop.setName("老肥油边总店");
        shop.setSettle_time("04:30");
        when(shopService.getById(5)).thenReturn(shop);
    }

    @Test
    void enrichOrdersCashierInfo_returnsBothNameAndWorkNo() {
        Admin cashier = new Admin();
        cashier.setId(88);
        cashier.setRealName("张晓峰");
        cashier.setWorkNo("0801");
        cashier.setUserName("zhangxf");

        when(adminService.listByIds(Collections.singleton(88))).thenReturn(Collections.singletonList(cashier));

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD20261025001");
        order.setCashier_id(88);

        AdminNameResolver.enrichOrdersCashierInfo(Collections.singletonList(order), adminService);

        assertEquals(88, order.getCashier_id());
        assertEquals("张晓峰", order.getCashier_name());
        assertEquals("0801", order.getCashier_work_no());
        assertEquals("张晓峰 (0801)", order.getCashier_display_name());
        assertEquals("张晓峰 (0801)", order.getDisplay_name());
    }

    @Test
    void enrichOrdersCashierInfo_fallsBackToOrderAdminIdWhenCashierIdNull() {
        Admin cashier = new Admin();
        cashier.setId(99);
        cashier.setRealName("李红梅");
        cashier.setWorkNo("0802");
        cashier.setUserName("lihm");

        when(adminService.listByIds(Collections.singleton(99))).thenReturn(Collections.singletonList(cashier));

        Order order = new Order();
        order.setId(102);
        order.setOrder_no("ORD20261025002");
        order.setOrder_admin_id(99);
        order.setCashier_id(null);

        AdminNameResolver.enrichOrdersCashierInfo(Collections.singletonList(order), adminService);

        assertEquals(99, order.getCashier_id());
        assertEquals("李红梅", order.getCashier_name());
        assertEquals("0802", order.getCashier_work_no());
        assertEquals("李红梅 (0802)", order.getCashier_display_name());
        assertEquals("李红梅", order.getOrder_admin_name());
    }

    @Test
    void cashierTodayOrders_enrichesBothNameAndWorkNo() {
        Admin cashier = new Admin();
        cashier.setId(88);
        cashier.setRealName("张晓峰");
        cashier.setWorkNo("0801");

        when(adminService.listByIds(Collections.singleton(88))).thenReturn(Collections.singletonList(cashier));

        Order order = new Order();
        order.setId(201);
        order.setOrder_no("ORD20261025003");
        order.setCashier_id(88);
        order.setSett_amount(128.0);

        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));

        R res = cashierOrderController.today(5, null, null, null, null);
        assertEquals(0, res.get("code"));

        @SuppressWarnings("unchecked")
        List<Order> list = (List<Order>) res.get("list");
        assertNotNull(list);
        assertEquals(1, list.size());
        Order resOrder = list.get(0);
        assertEquals("张晓峰", resOrder.getCashier_name());
        assertEquals("0801", resOrder.getCashier_work_no());
        assertEquals("张晓峰 (0801)", resOrder.getCashier_display_name());
    }

    @Test
    void cashierSearchOrders_enrichesBothNameAndWorkNo() {
        Admin cashier = new Admin();
        cashier.setId(88);
        cashier.setRealName("张晓峰");
        cashier.setWorkNo("0801");

        when(adminService.listByIds(Collections.singleton(88))).thenReturn(Collections.singletonList(cashier));

        Order order = new Order();
        order.setId(202);
        order.setOrder_no("ORD20261025004");
        order.setCashier_id(88);

        Page<Order> page = new Page<>(1, 10);
        page.setRecords(Collections.singletonList(order));
        page.setTotal(1);

        when(orderService.page(any(Page.class), any(Wrapper.class))).thenReturn(page);

        R res = cashierOrderController.search(null, null, null, 88, 1, 10);
        assertEquals(0, res.get("code"));

        @SuppressWarnings("unchecked")
        List<Order> list = (List<Order>) res.get("list");
        assertNotNull(list);
        assertEquals(1, list.size());
        Order resOrder = list.get(0);
        assertEquals("张晓峰", resOrder.getCashier_name());
        assertEquals("0801", resOrder.getCashier_work_no());
        assertEquals("张晓峰 (0801)", resOrder.getCashier_display_name());
    }

    @Test
    void cashierToday_supportsSlashDateFormatWithShopSettleTime() {
        AtomicReference<QueryWrapper<Order>> captured = new AtomicReference<>();
        when(orderService.list(any(Wrapper.class))).thenAnswer(invocation -> {
            captured.set((QueryWrapper<Order>) invocation.getArgument(0));
            return Collections.emptyList();
        });

        // 真实线上请求示例：GET /cashier/order/today?shopId=5&startTime=2026%2F10%2F24&endTime=2026%2F10%2F24
        R res = cashierOrderController.today(5, null, null, "2026/10/24", "2026/10/24");
        assertEquals(0, res.get("code"));

        QueryWrapper<Order> q = captured.get();
        assertNotNull(q);
        String sql = q.getSqlSegment();
        assertTrue(sql.contains("order_time"));
        assertTrue(sql.contains(">="));
        assertTrue(sql.contains("<"));

        // 验证门店 settle_time 04:30 自动补全
        ZoneId zone = ZoneId.of("Asia/Shanghai");
        Date expectedStart = Date.from(LocalDateTime.of(2026, 10, 24, 4, 30, 0).atZone(zone).toInstant());
        Date expectedEnd = Date.from(LocalDateTime.of(2026, 10, 25, 4, 30, 0).atZone(zone).toInstant());

        assertTrue(q.getParamNameValuePairs().containsValue(expectedStart));
        assertTrue(q.getParamNameValuePairs().containsValue(expectedEnd));
    }

    @Test
    void cashierSearch_supportsSlashDateFormatWithShopSettleTime() {
        AtomicReference<QueryWrapper<Order>> captured = new AtomicReference<>();
        Page<Order> emptyPage = new Page<>(1, 20);
        when(orderService.page(any(Page.class), any(Wrapper.class))).thenAnswer(invocation -> {
            captured.set((QueryWrapper<Order>) invocation.getArgument(1));
            return emptyPage;
        });

        R res = cashierOrderController.search(null, "2026/10/24", "2026/10/24", null, 1, 20);
        assertEquals(0, res.get("code"));

        QueryWrapper<Order> q = captured.get();
        assertNotNull(q);
        assertNotNull(q.getSqlSegment());
        ZoneId zone = ZoneId.of("Asia/Shanghai");
        Date expectedStart = Date.from(LocalDateTime.of(2026, 10, 24, 4, 30, 0).atZone(zone).toInstant());
        Date expectedEnd = Date.from(LocalDateTime.of(2026, 10, 25, 4, 30, 0).atZone(zone).toInstant());

        assertTrue(q.getParamNameValuePairs().containsValue(expectedStart));
        assertTrue(q.getParamNameValuePairs().containsValue(expectedEnd));
    }
}
