package com.lanf.kds.service;

import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsDishAvailabilityServiceTest {
    @Test
    void createsAndUpdatesOnlyTheAuthenticatedShopOverride() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(contains("onsale_override"), eq(Boolean.class), eq(7), eq(101)))
                .thenReturn(Boolean.TRUE);
        KdsDishAvailabilityService service = new KdsDishAvailabilityService(
                jdbc, mock(IDishService.class), mock(DishMenuPushService.class));

        service.applySnapshot(7, 101, 0, 1, "lack_item");

        verify(jdbc).update(contains("INSERT IGNORE INTO t_dish_shop"), eq(7), eq(101), eq(0), eq(1), eq(1));
        verify(jdbc).update(contains("WHERE shop_id=? AND dish_id=?"), eq(0), eq(1), eq(1), eq(7), eq(101));
        verify(jdbc).queryForObject(contains("onsale_override"), eq(Boolean.class), eq(7), eq(101));
    }


    @Test
    void explicitSoldOutClearsPositiveSnapshotStock() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(contains("onsale_override"), eq(Boolean.class), eq(7), eq(101)))
                .thenReturn(Boolean.TRUE);
        KdsDishAvailabilityService service = new KdsDishAvailabilityService(
                jdbc, mock(IDishService.class), mock(DishMenuPushService.class));

        service.applySnapshot(7, 101, 3, 1, "refund_item");

        verify(jdbc).update(contains("WHERE shop_id=? AND dish_id=?"), eq(0), eq(1), eq(1), eq(7), eq(101));
    }

    @Test
    void unlimitedStockSentinelClearsSoldOutAndDisablesTracking() {
        // stock=-1（不限量哨兵）：不得误判售罄，且不启用库存跟踪
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(contains("onsale_override"), eq(Boolean.class), eq(7), eq(101)))
                .thenReturn(Boolean.TRUE);
        KdsDishAvailabilityService service = new KdsDishAvailabilityService(
                jdbc, mock(IDishService.class), mock(DishMenuPushService.class));

        service.applySnapshot(7, 101, -1, null, "refund_item");

        verify(jdbc).update(contains("INSERT IGNORE INTO t_dish_shop"), eq(7), eq(101), eq(-1), eq(0), eq(0));
        verify(jdbc).update(contains("WHERE shop_id=? AND dish_id=?"), eq(-1), eq(0), eq(0), eq(7), eq(101));
    }

    @Test
    void availableWithoutStockRemainsDerivedFromStoredStock() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(contains("onsale_override"), eq(Boolean.class), eq(7), eq(101)))
                .thenReturn(Boolean.TRUE);
        KdsDishAvailabilityService service = new KdsDishAvailabilityService(
                jdbc, mock(IDishService.class), mock(DishMenuPushService.class));

        service.applySnapshot(7, 101, null, 0, "availability");

        verify(jdbc).update(contains("sold_out=CASE WHEN stock=0 THEN 1 ELSE 0 END"), eq(7), eq(101));
    }
}
