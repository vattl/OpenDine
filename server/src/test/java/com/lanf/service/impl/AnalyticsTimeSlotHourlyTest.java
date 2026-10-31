package com.lanf.service.impl;

import com.lanf.entity.Shop;
import com.lanf.mapper.AnalyticsMapper;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D027 分时段营收细分：time_slots_hourly（墙钟小时）与 time_slots_business_hourly（营业日小时）
 * 组装、avg_ticket/start/end 补全、resolveOpenTime/resolveSettleTime 传参。
 */
@ExtendWith(MockitoExtension.class)
class AnalyticsTimeSlotHourlyTest {

    @Mock
    private AnalyticsMapper analyticsMapper;
    @Mock
    private IMemberRechargeService memberRechargeService;
    @Mock
    private IShopService shopService;
    @InjectMocks
    private AnalyticsServiceImpl service;

    private static Map<String, Object> row(String hourKey, double net, long count) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("hour_key", hourKey);
        m.put("net_revenue", net);
        m.put("order_count", count);
        return m;
    }

    @Test
    @DisplayName("门店配置 settle_time：两套小时序列组装并补 avg_ticket/start/end")
    void hourlySlotsAssembledWithDefaultWindow() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");
        when(shopService.getById(5)).thenReturn(shop);
        when(analyticsMapper.selectTimeSlotHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(new ArrayList<>(Arrays.asList(
                        row("18", 1526.5, 18),
                        row("23", 300.0, 3))));
        when(analyticsMapper.selectTimeSlotBusinessHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(new ArrayList<>(Arrays.asList(
                        row("bd_hour_14", 1526.5, 18),
                        row("bd_hour_23", 88.0, 1))));

        Map<String, Object> data = service.businessOverview("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> hourly = (List<Map<String, Object>>) data.get("time_slots_hourly");
        assertNotNull(hourly);
        assertEquals(2, hourly.size());
        Map<String, Object> h18 = hourly.get(0);
        assertEquals("18", h18.get("hour_key"));
        assertEquals("18:00", h18.get("start"));
        assertEquals("19:00", h18.get("end"));
        assertEquals(1526.5, h18.get("net_revenue"));
        assertEquals(18L, h18.get("order_count"));
        assertEquals(84.81, h18.get("avg_ticket"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> bizHourly = (List<Map<String, Object>>) data.get("time_slots_business_hourly");
        assertNotNull(bizHourly);
        Map<String, Object> b14 = bizHourly.get(0);
        assertEquals("bd_hour_14", b14.get("hour_key"));
        assertEquals("18:00", b14.get("start"));
        assertEquals("19:00", b14.get("end"));
        assertEquals(88.0, bizHourly.get(1).get("net_revenue"));

        verify(analyticsMapper).selectTimeSlotHourly(eq("2026-09-10 00:00:00"), eq("2026-09-10 23:59:59"), eq(5),
                eq("04:00"), eq("04:00"));
        verify(analyticsMapper).selectTimeSlotBusinessHourly(eq("2026-09-10 00:00:00"), eq("2026-09-10 23:59:59"), eq(5),
                eq("04:00"), eq("04:00"));
    }

    @Test
    @DisplayName("门店配置优先：settle_time=05:00 传入小时查询")
    void hourlySlotsUseShopConfiguredWindow() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");
        when(shopService.getById(5)).thenReturn(shop);
        when(analyticsMapper.selectTimeSlotHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "05:00", "05:00"))
                .thenReturn(new ArrayList<>());
        when(analyticsMapper.selectTimeSlotBusinessHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "05:00", "05:00"))
                .thenReturn(new ArrayList<>());

        service.businessOverview("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5);

        verify(analyticsMapper).selectTimeSlotHourly(eq("2026-09-10 00:00:00"), eq("2026-09-10 23:59:59"), eq(5),
                eq("05:00"), eq("05:00"));
    }

    @Test
    @DisplayName("小时查询返回 null：不 NPE，组装为空列表")
    void hourlySlotsNullSafe() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");
        when(shopService.getById(5)).thenReturn(shop);
        when(analyticsMapper.selectTimeSlotHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(null);
        when(analyticsMapper.selectTimeSlotBusinessHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(null);

        Map<String, Object> data = service.businessOverview("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> hourly = (List<Map<String, Object>>) data.get("time_slots_hourly");
        assertNotNull(hourly);
        assertTrue(hourly.isEmpty());
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> bizHourly = (List<Map<String, Object>>) data.get("time_slots_business_hourly");
        assertNotNull(bizHourly);
        assertTrue(bizHourly.isEmpty());
    }

    @Test
    @DisplayName("跨天归属：bd_hour 从 0 点订单映射到前一日营业日尾段")
    void businessHourOffsetAcrossMidnight() {
        Shop shop = new Shop();
        shop.setSettle_time("04:00");
        when(shopService.getById(5)).thenReturn(shop);
        when(analyticsMapper.selectTimeSlotBusinessHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(new ArrayList<>(Arrays.asList(row("bd_hour_20", 300.0, 3))));
        when(analyticsMapper.selectTimeSlotHourly("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5, "04:00", "04:00"))
                .thenReturn(new ArrayList<>());

        Map<String, Object> data = service.businessOverview("2026-09-10 00:00:00", "2026-09-10 23:59:59", 5);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> bizHourly = (List<Map<String, Object>>) data.get("time_slots_business_hourly");
        // bd_hour_20（open=04:00 → 墙钟 00:00-01:00）
        assertEquals("00:00", bizHourly.get(0).get("start"));
        assertEquals("01:00", bizHourly.get(0).get("end"));
        assertEquals(100.0, bizHourly.get(0).get("avg_ticket"));
    }
}
