package com.lanf.service.impl;

import com.lanf.common.ApiException;
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

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

/**
 * 默认时间窗口：以当前已完成结算日 settle_time 为终点往前推 24 小时；
 * 严格校验 settle_time，未配置抛出 ApiException。
 */
@ExtendWith(MockitoExtension.class)
class AnalyticsDefaultWindowTest {

    @Mock
    private AnalyticsMapper analyticsMapper;
    @Mock
    private IMemberRechargeService memberRechargeService;
    @Mock
    private IShopService shopService;
    @InjectMocks
    private AnalyticsServiceImpl service;

    private static String day(int offset) {
        return LocalDate.now().plusDays(offset).format(DateTimeFormatter.ISO_LOCAL_DATE);
    }

    @Test
    @DisplayName("无门店配置：严格抛出 ApiException(SETTLE_TIME_NOT_CONFIGURED)")
    void defaultWindowWithoutShopConfig() {
        when(shopService.getById(5)).thenReturn(null);
        ApiException ex = assertThrows(ApiException.class, () -> service.defaultWindow(5));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex.getErrorCode());
    }

    @Test
    @DisplayName("门店 settle=05:00：返回 24 小时已结算窗口")
    void defaultWindowWithShopSettle() {
        Shop shop = new Shop();
        shop.setSettle_time("05:00");
        when(shopService.getById(5)).thenReturn(shop);
        String[] w = service.defaultWindow(5);
        boolean beforeSettle = LocalTime.now().isBefore(LocalTime.of(5, 0));
        int endOffset = beforeSettle ? -1 : 0;
        int startOffset = endOffset - 1;
        assertEquals(day(startOffset) + " 05:00:00", w[0]);
        assertEquals(day(endOffset) + " 05:00:00", w[1]);
    }

    @Test
    @DisplayName("settle 为空：严格抛出 ApiException，无 close 兜底")
    void defaultWindowThrowsWhenSettleEmpty() {
        Shop shop = new Shop();
        shop.setSettle_time("  ");
        shop.setClose_time("03:00");
        when(shopService.getById(5)).thenReturn(shop);
        ApiException ex = assertThrows(ApiException.class, () -> service.defaultWindow(5));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex.getErrorCode());
    }

    @Test
    @DisplayName("settle 为 null：严格抛出 ApiException，无默认兜底")
    void defaultWindowThrowsWhenSettleNull() {
        Shop shop = new Shop();
        when(shopService.getById(5)).thenReturn(shop);
        ApiException ex = assertThrows(ApiException.class, () -> service.defaultWindow(5));
        assertEquals("SETTLE_TIME_NOT_CONFIGURED", ex.getErrorCode());
    }
}
