package com.lanf.controller.admin;

import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AdminDishAvailabilityInvariantTest {

    @Test
    void manualSoldOutClearsShopStock() {
        Fixture fixture = fixture(link(5, 0, 1));
        Dish request = new Dish();
        request.setId(10);
        request.setSold_out(1);

        fixture.controller.updateSaleStatus(request);

        assertEquals(1, fixture.link.getSold_out());
        assertEquals(0, fixture.link.getStock());
        assertEquals(1, fixture.link.getStock_enabled());
    }

    @Test
    void partialDishSavePreservesOmittedAvailabilityFields() {
        Fixture fixture = fixture(link(8, 1, 1));
        Dish request = new Dish();
        request.setId(10);
        request.setName("改名不应恢复库存");

        fixture.controller.save(request);

        assertEquals(1, fixture.link.getSold_out());
        assertEquals(0, fixture.link.getStock());
        assertEquals(1, fixture.link.getStock_enabled());
    }

    private static Fixture fixture(DishShop link) {
        AdminDishController controller = new AdminDishController();
        IDishService dishService = mock(IDishService.class);
        DishShopMapper dishShopMapper = mock(DishShopMapper.class);
        DishMenuPushService pushService = mock(DishMenuPushService.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        Dish existing = new Dish();
        existing.setId(10);
        existing.setName("测试菜品");
        existing.setOnsale(true);
        when(dishService.getById(10)).thenReturn(existing);
        when(dishShopMapper.selectOne(any())).thenReturn(link);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(controller, "dishMenuPushService", pushService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
        return new Fixture(controller, link);
    }

    private static DishShop link(int stock, int soldOut, int stockEnabled) {
        DishShop link = new DishShop();
        link.setId(99L);
        link.setShop_id(7);
        link.setDish_id(10);
        link.setStock(stock);
        link.setSold_out(soldOut);
        link.setStock_enabled(stockEnabled);
        link.setOnsale_override(1);
        return link;
    }

    private static final class Fixture {
        final AdminDishController controller;
        final DishShop link;

        Fixture(AdminDishController controller, DishShop link) {
            this.controller = controller;
            this.link = link;
        }
    }
}
