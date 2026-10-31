package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IShopService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AdminTakeoutControllerDeliveryListTest {

    private AdminTakeoutController controller;
    private ITakeoutDeliveryService deliveryService;
    private IShopService shopService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminTakeoutController();
        deliveryService = mock(ITakeoutDeliveryService.class);
        shopService = mock(IShopService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void deliveryList_defaultsToCurrentOperationalBusinessDay() {
        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        TakeoutDelivery delivery = new TakeoutDelivery();
        delivery.setId(101L);
        delivery.setOrder_id(201);
        delivery.setZsq_actual_fee(new BigDecimal("7.50"));

        IPage<TakeoutDelivery> pageResult = new Page<>(1, 20);
        pageResult.setRecords(Collections.singletonList(delivery));
        pageResult.setTotal(1);

        ArgumentCaptor<Date> startCaptor = ArgumentCaptor.forClass(Date.class);
        ArgumentCaptor<Date> endCaptor = ArgumentCaptor.forClass(Date.class);

        when(deliveryService.pageByShop(eq(1), eq(1), eq(20), isNull(), startCaptor.capture(), endCaptor.capture()))
                .thenReturn(pageResult);

        Map<String, Object> body = new HashMap<>();
        R res = controller.deliveryList(body);

        assertEquals(0, res.get("code"));
        assertEquals(1L, res.get("total"));
        assertNotNull(res.get("startTime"));
        assertNotNull(res.get("endTime"));
        assertTrue(startCaptor.getValue().before(endCaptor.getValue()));

        @SuppressWarnings("unchecked")
        List<TakeoutDelivery> list = (List<TakeoutDelivery>) res.get("list");
        assertEquals(1, list.size());
        assertEquals(new BigDecimal("7.50"), list.get(0).getActual_delivery_fee());
    }

    @Test
    void deliveryList_customTimeRangeAndSnakeCaseParams() {
        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        IPage<TakeoutDelivery> pageResult = new Page<>(2, 10);
        pageResult.setRecords(Collections.emptyList());
        pageResult.setTotal(0);

        ArgumentCaptor<Date> startCaptor = ArgumentCaptor.forClass(Date.class);
        ArgumentCaptor<Date> endCaptor = ArgumentCaptor.forClass(Date.class);

        when(deliveryService.pageByShop(eq(1), eq(2), eq(10), eq("delivering"), startCaptor.capture(), endCaptor.capture()))
                .thenReturn(pageResult);

        Map<String, Object> body = new HashMap<>();
        body.put("pageNum", 2);
        body.put("pageSize", 10);
        body.put("dispatch_status", "delivering");
        body.put("start_time", "2026-10-01 08:00:00");
        body.put("end_time", "2026-10-01 20:00:00");

        R res = controller.deliveryList(body);

        assertEquals(0, res.get("code"));
        assertEquals("2026-10-01 08:00:00", res.get("startTime"));
        assertEquals("2026-10-01 20:00:00", res.get("endTime"));
        assertEquals(2L, res.get("pageNum"));
        assertEquals(10L, res.get("pageSize"));
    }

    @Test
    void deliveryList_returns400WhenEndTimeEarlierThanStartTime() {
        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        Map<String, Object> body = new HashMap<>();
        body.put("startTime", "2026-10-02 12:00:00");
        body.put("endTime", "2026-10-01 12:00:00");

        R res = controller.deliveryList(body);

        assertEquals(400, res.get("code"));
        assertTrue(res.get("msg").toString().contains("endTime cannot be earlier than startTime"));
    }

    @Test
    void deliveryList_returns400WhenShopIdMissing() {
        request.removeAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID);
        R res = controller.deliveryList(Collections.emptyMap());
        assertEquals(400, res.get("code"));
    }

    @Test
    void takeoutDelivery_actualDeliveryFeeFallbackAndOverride() {
        TakeoutDelivery d = new TakeoutDelivery();
        assertNull(d.getActual_delivery_fee());

        d.setZsq_actual_fee(new BigDecimal("6.80"));
        assertEquals(new BigDecimal("6.80"), d.getActual_delivery_fee());

        d.setActual_delivery_fee(new BigDecimal("5.50"));
        assertEquals(new BigDecimal("5.50"), d.getActual_delivery_fee());
    }

    @Test
    void enrichOrder_populatesActualDeliveryFee() {
        Order o = new Order();
        o.setId(100);

        TakeoutDelivery d = new TakeoutDelivery();
        d.setId(555L);
        d.setOrder_id(100);
        d.setDelivery_fee(new BigDecimal("5.00"));
        d.setZsq_actual_fee(new BigDecimal("6.20"));
        d.setDispatch_status("delivering");

        org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                com.lanf.service.impl.TakeoutDeliveryServiceImpl.class, "applyTakeoutToOrder", o, d);

        assertEquals(555L, o.getTakeout_delivery_id());
        assertEquals(5.0d, o.getDelivery_fee());
        assertEquals(6.2d, o.getActual_delivery_fee());
        assertEquals("delivering", o.getTakeout_dispatch_status());
    }
}
