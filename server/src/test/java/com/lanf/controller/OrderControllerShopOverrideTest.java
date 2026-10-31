package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.lanf.entity.Category;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.ICategoryService;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 方案 A 门店隔离回归：下单/加菜名称解析（P0-①）、AI 菜单门店维度（P2-⑧）。
 */
class OrderControllerShopOverrideTest {

    private OrderController controller;
    private IDishService dishService;
    private DishShopMapper dishShopMapper;
    private ICategoryService categoryService;

    private void newController() {
        controller = new OrderController();
        dishService = mock(IDishService.class);
        dishShopMapper = mock(DishShopMapper.class);
        categoryService = mock(ICategoryService.class);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(controller, "categoryService", categoryService);
        ReflectionTestUtils.setField(controller, "aiOnSaleMenuCache",
                Caffeine.newBuilder().expireAfterWrite(60, TimeUnit.SECONDS).maximumSize(8).build());
    }

    @Test
    void resolveDishByMenuName_matchesShopNameOverride_whenHqNameAbsent() throws Exception {
        newController();
        // 总部按名/去空白名都查不到 → 门店覆盖名（t_dish_shop.name_override）命中
        when(dishService.getOne(any(Wrapper.class))).thenReturn(null);
        DishShop link = new DishShop();
        link.setDish_id(42);
        link.setName_override("门店烤羊排");
        when(dishShopMapper.selectOne(any(Wrapper.class))).thenReturn(link);
        Dish hq = new Dish();
        hq.setId(42);
        hq.setName("法式烤羊排");
        when(dishService.getById(42)).thenReturn(hq);

        Method m = OrderController.class.getDeclaredMethod("resolveDishByMenuName", String.class, Integer.class);
        m.setAccessible(true);
        Dish result = (Dish) m.invoke(controller, "门店烤羊排", 7);

        assertNotNull(result);
        assertEquals(42, result.getId());
    }

    @Test
    void getOnSaleMenuForAi_shopDimension_appliesOverridesAndGroupsByOverrideType() throws Exception {
        newController();

        DishShop link1 = new DishShop();
        link1.setDish_id(1);
        link1.setName_override("门店手撕鸡");
        link1.setType_id_override(10);
        link1.setOnsale_override(1);
        DishShop link2 = new DishShop();
        link2.setDish_id(2);
        link2.setOnsale_override(0); // 门店下架
        when(dishShopMapper.selectList(any(Wrapper.class))).thenReturn(Arrays.asList(link1, link2));

        Dish d1 = new Dish();
        d1.setId(1);
        d1.setName("总部手撕鸡");
        d1.setTypeId(20);
        d1.setOnsale(true);
        Dish d2 = new Dish();
        d2.setId(2);
        d2.setName("下架菜");
        d2.setTypeId(20);
        d2.setOnsale(true);
        when(dishService.list(any(Wrapper.class))).thenReturn(Arrays.asList(d1, d2));

        Category cat10 = new Category();
        cat10.setId(10);
        Category cat20 = new Category();
        cat20.setId(20);
        when(categoryService.list(any(Wrapper.class))).thenReturn(new ArrayList<>(Arrays.asList(cat10, cat20)));

        Method m = OrderController.class.getDeclaredMethod("getOnSaleMenuForAi", Integer.class);
        m.setAccessible(true);
        @SuppressWarnings("unchecked")
        List<Category> result = (List<Category>) m.invoke(controller, 7);

        // 门店下架的 d2 被过滤；d1 按覆盖分类 10 归组且名称已覆盖
        assertEquals(1, result.size());
        assertEquals(10, result.get(0).getId());
        assertEquals(1, result.get(0).getDishList().size());
        assertEquals("门店手撕鸡", result.get(0).getDishList().get(0).getName());
    }

    @Test
    void getOnSaleMenuForAi_noArg_readsShopFromAiSession() throws Exception {
        newController();
        // 无参版本：从 AI 会话 ThreadLocal 读门店 → 走门店菜单分支
        Class<?> sessCls = Class.forName("com.lanf.controller.OrderController$AiSuggestSession");
        java.lang.reflect.Constructor<?> ctor = sessCls.getDeclaredConstructor();
        ctor.setAccessible(true);
        Object sess = ctor.newInstance();
        Field shopIdF = sessCls.getDeclaredField("shopId");
        shopIdF.setAccessible(true);
        shopIdF.set(sess, 7);
        Field tls = OrderController.class.getDeclaredField("AI_SUGGEST_SESSION");
        tls.setAccessible(true);
        @SuppressWarnings("unchecked")
        ThreadLocal<Object> tl = (ThreadLocal<Object>) tls.get(null);
        tl.set(sess);
        try {
            DishShop link = new DishShop();
            link.setDish_id(1);
            link.setName_override("会话门店菜");
            link.setType_id_override(10);
            link.setOnsale_override(1);
            when(dishShopMapper.selectList(any(Wrapper.class))).thenReturn(Arrays.asList(link));

            Dish d1 = new Dish();
            d1.setId(1);
            d1.setName("总部菜");
            d1.setTypeId(99);
            d1.setOnsale(true);
            when(dishService.list(any(Wrapper.class))).thenReturn(Arrays.asList(d1));

            Category cat10 = new Category();
            cat10.setId(10);
            when(categoryService.list(any(Wrapper.class))).thenReturn(new ArrayList<>(Arrays.asList(cat10)));

            Method m = OrderController.class.getDeclaredMethod("getOnSaleMenuForAi");
            m.setAccessible(true);
            @SuppressWarnings("unchecked")
            List<Category> result = (List<Category>) m.invoke(controller);

            assertEquals(1, result.size());
            assertEquals("会话门店菜", result.get(0).getDishList().get(0).getName());
        } finally {
            tl.remove();
        }
    }
}
