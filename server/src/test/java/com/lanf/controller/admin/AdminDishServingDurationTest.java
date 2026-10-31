package com.lanf.controller.admin;

import com.lanf.entity.Dish;
import com.lanf.entity.R;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

class AdminDishServingDurationTest {

    private AdminDishController controller;
    private IDishService dishService;

    @BeforeEach
    void setUp() {
        controller = new AdminDishController();
        dishService = mock(IDishService.class);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "dishMenuPushService", mock(DishMenuPushService.class));
        ReflectionTestUtils.setField(controller, "dishShopMapper", mock(DishShopMapper.class));
        ReflectionTestUtils.setField(controller, "httpServletRequest", mock(HttpServletRequest.class));
    }

    @Test
    void createDefaultsServingDurationToTenMinutes() {
        Dish dish = new Dish();
        dish.setName("测试菜");

        R result = controller.save(dish);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<Dish> saved = ArgumentCaptor.forClass(Dish.class);
        verify(dishService).save(saved.capture());
        assertEquals(10, saved.getValue().getServing_duration_minutes());
    }

    @Test
    void updatePersistsExplicitServingDuration() {
        Dish dish = new Dish();
        dish.setId(9);
        dish.setServing_duration_minutes(18);

        R result = controller.save(dish);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<Dish> updated = ArgumentCaptor.forClass(Dish.class);
        verify(dishService).updateById(updated.capture());
        assertEquals(18, updated.getValue().getServing_duration_minutes());
    }

    @Test
    void rejectsNonPositiveServingDuration() {
        Dish dish = new Dish();
        dish.setServing_duration_minutes(0);

        R result = controller.save(dish);

        assertEquals(500, result.get("code"));
        verify(dishService, never()).save(any(Dish.class));
        verify(dishService, never()).updateById(any(Dish.class));
    }
}
