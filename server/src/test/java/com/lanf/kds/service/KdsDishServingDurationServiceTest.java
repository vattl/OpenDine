package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class KdsDishServingDurationServiceTest {

    private KdsDishServingDurationService service;
    private IDishService dishService;
    private IOrderDetailService orderDetailService;

    @BeforeEach
    void setUp() {
        service = new KdsDishServingDurationService();
        dishService = mock(IDishService.class);
        orderDetailService = mock(IOrderDetailService.class);
        ReflectionTestUtils.setField(service, "dishService", dishService);
        ReflectionTestUtils.setField(service, "orderDetailService", orderDetailService);
    }

    @Test
    void dishDurationOverridesShopSlaAndMissingDishFallsBack() {
        OrderDetail custom = detail(101, 11);
        OrderDetail missing = detail(102, 12);
        Dish dish = new Dish();
        dish.setId(11);
        dish.setServing_duration_minutes(18);
        when(dishService.listByIds(anyCollection())).thenReturn(Collections.singletonList(dish));

        Map<Integer, Integer> seconds = service.resolveSecondsByDetails(Arrays.asList(custom, missing), 600);

        assertEquals(1080, seconds.get(101));
        assertEquals(600, seconds.get(102));
    }

    @Test
    void resolvesDurationsFromTicketDetailIdsForScheduler() {
        OrderDetail detail = detail(201, 21);
        Dish dish = new Dish();
        dish.setId(21);
        dish.setServing_duration_minutes(7);
        when(orderDetailService.listByIds(anyCollection())).thenReturn(Collections.singletonList(detail));
        when(dishService.listByIds(anyCollection())).thenReturn(Collections.singletonList(dish));

        Map<Integer, Integer> seconds = service.resolveSecondsByDetailIds(Collections.singletonList(201), 600);

        assertEquals(420, seconds.get(201));
    }

    @Test
    void shopServingDurationOverrideTakesPrecedenceOverHq() {
        DishShopMapper shopMapper = mock(DishShopMapper.class);
        ReflectionTestUtils.setField(service, "dishShopMapper", shopMapper);
        OrderDetail detail = detail(301, 31);
        Dish dish = new Dish();
        dish.setId(31);
        dish.setServing_duration_minutes(8);
        when(dishService.listByIds(anyCollection())).thenReturn(Collections.singletonList(dish));
        DishShop link = new DishShop();
        link.setDish_id(31);
        link.setServing_duration_override(25);
        when(shopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(link));

        Map<Integer, Integer> seconds = service.resolveSecondsByDetails(
                Collections.singletonList(detail), 600, 7);

        // 门店覆盖 25 分钟 > 总部 8 分钟
        assertEquals(1500, seconds.get(301));
    }

    private static OrderDetail detail(int id, int dishId) {
        OrderDetail detail = new OrderDetail();
        detail.setId(id);
        detail.setDish_id(dishId);
        return detail;
    }
}
