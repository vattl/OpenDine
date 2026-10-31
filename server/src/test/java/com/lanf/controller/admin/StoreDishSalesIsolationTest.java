package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.User;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IDailyCloseService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class StoreDishSalesIsolationTest {

    private AdminReportController reportController;
    private AdminOrderController orderController;
    private IOrderService orderService;
    private IShopService shopService;
    private IDailyCloseService dailyCloseService;
    private IMemberRechargeService memberRechargeService;
    private IUserService userService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        reportController = new AdminReportController();
        orderController = new AdminOrderController();
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        dailyCloseService = mock(IDailyCloseService.class);
        memberRechargeService = mock(IMemberRechargeService.class);
        userService = mock(IUserService.class);

        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 2);

        Shop shop2 = new Shop();
        shop2.setId(2);
        shop2.setName("西二旗分店");
        shop2.setSettle_time("04:00");
        when(shopService.getById(2)).thenReturn(shop2);

        ReflectionTestUtils.setField(reportController, "orderService", orderService);
        ReflectionTestUtils.setField(reportController, "shopService", shopService);
        ReflectionTestUtils.setField(reportController, "dailyCloseService", dailyCloseService);
        ReflectionTestUtils.setField(reportController, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(reportController, "userService", userService);
        ReflectionTestUtils.setField(reportController, "httpServletRequest", request);
        ReflectionTestUtils.setField(reportController, "adminOrderController", orderController);

        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "shopService", shopService);
        ReflectionTestUtils.setField(orderController, "httpServletRequest", request);
    }

    @Test
    void testDailyReportTopDishesIsolationParameterInjection() {
        DishSalesDTO dishA = new DishSalesDTO();
        dishA.setDish_name("西二旗招牌烤五花");
        dishA.setTotal_quantity(50L);
        dishA.setTotal_sales("200.00");
        when(orderService.statisticsDishSales(any())).thenReturn(Collections.singletonList(dishA));
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());

        R response = reportController.daily("2026-10-18", null, null, null, true);
        assertEquals(0, response.get("code"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsDishSales(captor.capture());

        Map<String, Object> params = captor.getValue();
        assertNotNull(params);
        // Verify shopId is present in both shopId and shop_id formats
        assertEquals(2, params.get("shopId"), "shopId should match store context");
        assertEquals(2, params.get("shop_id"), "shop_id should match store context");
    }

    @Test
    void testDishRankingDirectCallCarriesShopContext() {
        DishSalesDTO dish = new DishSalesDTO();
        dish.setDish_name("精品羊排");
        dish.setTotal_quantity(10L);
        dish.setTotal_sales("180.00");
        when(orderService.statisticsDishSales(any())).thenReturn(Collections.singletonList(dish));

        R response = reportController.dishRanking("2026-10-18", "2026-10-18", null);
        assertEquals(0, response.get("code"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsDishSales(captor.capture());

        Map<String, Object> params = captor.getValue();
        assertEquals(2, params.get("shopId"));
    }

    @Test
    void testStatisticsCategorySalesCarriesShopContext() {
        when(orderService.statisticsCategorySales(any())).thenReturn(Collections.emptyList());
        when(orderService.statisticsOrderSummary(any())).thenReturn(Collections.emptyMap());

        R response = orderController.statisticsCategorySales("2026-10-18", "2026-10-18", null, null, null, null, null);
        assertEquals(0, response.get("code"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(orderService).statisticsCategorySales(captor.capture());

        Map<String, Object> params = captor.getValue();
        assertEquals(2, params.get("shopId"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testDailyReportNewMembersFilteredByShop() {
        when(orderService.statisticsDishSales(any())).thenReturn(Collections.emptyList());
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());
        when(userService.count(any())).thenReturn(3);

        R response = reportController.daily("2026-10-18", null, null, null, true);
        assertEquals(0, response.get("code"));

        ArgumentCaptor<QueryWrapper<User>> userCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(userService).count(userCaptor.capture());

        QueryWrapper<User> wrapper = userCaptor.getValue();
        assertNotNull(wrapper);
        String sql = wrapper.getCustomSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("phone IS NOT NULL"), "Should filter phone IS NOT NULL");
        assertTrue(sql.contains("TRIM(phone)"), "Should filter non-empty phone");
        assertTrue(sql.contains("t_order"), "Should subquery t_order");
        assertTrue(sql.contains("t_member_recharge"), "Should subquery t_member_recharge");
        assertTrue(sql.contains("t_shop_member_wallet"), "Should subquery t_shop_member_wallet");
        assertTrue(sql.contains("shop_id = 2"), "Should isolate by shop_id = 2");
    }

    @Test
    @SuppressWarnings("unchecked")
    void testDailyReportNewMembersShop1Compatibility() {
        Shop shop1 = new Shop();
        shop1.setId(1);
        shop1.setName("老斐烤肉总店");
        shop1.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop1);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        when(orderService.statisticsDishSales(any())).thenReturn(Collections.emptyList());
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());
        when(userService.count(any())).thenReturn(7);

        R response = reportController.daily("2026-10-18", null, null, null, true);
        assertEquals(0, response.get("code"));

        ArgumentCaptor<QueryWrapper<User>> userCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(userService).count(userCaptor.capture());

        QueryWrapper<User> wrapper = userCaptor.getValue();
        assertNotNull(wrapper);
        String sql = wrapper.getCustomSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("(shop_id = 1 OR shop_id IS NULL)"), "Shop 1 must support legacy unassigned records");
    }

    @Test
    @SuppressWarnings("unchecked")
    void testDailyReportNewMembersHeadquartersNoShopFilter() {
        Date start = new Date(1700000000000L);
        Date end = new Date(1700086400000L);

        when(userService.count(any())).thenReturn(10);

        long count = ReflectionTestUtils.invokeMethod(reportController, "countShopNewMembers", null, start, end);
        assertEquals(10L, count);

        ArgumentCaptor<QueryWrapper<User>> userCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(userService).count(userCaptor.capture());

        QueryWrapper<User> wrapper = userCaptor.getValue();
        assertNotNull(wrapper);
        String sql = wrapper.getCustomSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("phone IS NOT NULL"));
        assertTrue(sql.contains("TRIM(phone)"));
        assertFalse(sql.contains("t_shop_member_wallet"), "Headquarters global count must not restrict to a specific shop");
    }
}
