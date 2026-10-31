package com.lanf.service.impl;

import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import org.mockito.ArgumentCaptor;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 库存回退缺陷回归：库存被扣到 0 后退菜必须回补；回退与扣减同样优先按 dish_id 匹配。
 */
class DishShopStockServiceImplTest {

    private DishShopStockServiceImpl service;
    private IDishService dishService;
    private DishShopMapper dishShopMapper;

    @BeforeEach
    void setUp() {
        service = new DishShopStockServiceImpl();
        dishService = mock(IDishService.class);
        dishShopMapper = mock(DishShopMapper.class);
        ReflectionTestUtils.setField(service, "dishService", dishService);
        ReflectionTestUtils.setField(service, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(service, "dishMenuPushService", mock(DishMenuPushService.class));
    }

    @Test
    void restoresStockEvenWhenDeductedToZero() {
        // 有限库存被扣到 0（sold_out=1，菜品仍在售）：旧逻辑会误判「未启用库存」而跳过回退
        Dish dish = dish(10, true);
        DishShop link = link(0, 1, 1);
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any())).thenReturn(link);

        service.restoreForDetail(detail(10, "2"), 7);

        verify(dishShopMapper).update(isNull(), any());
    }

    @Test
    void refundRestoresSoldOutDishStockAndMakesItAvailable() {
        Dish dish = dish(10, true);
        DishShop link = link(0, 1, 1);
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any())).thenReturn(link);

        service.restoreForDetail(detail(10, "2"), 7);

        ArgumentCaptor<Wrapper<DishShop>> update = ArgumentCaptor.forClass(Wrapper.class);
        verify(dishShopMapper).update(isNull(), update.capture());
        String sql = update.getValue().getSqlSet();
        org.junit.jupiter.api.Assertions.assertTrue(sql.contains("stock = stock + 2"));
        org.junit.jupiter.api.Assertions.assertTrue(sql.contains(
                "sold_out = CASE WHEN stock + 2 > 0 THEN 0 ELSE sold_out END"));
    }

    @Test
    void restorePrefersDishIdOverNameLookup() {
        // 明细带 dish_id 但名称与库内不一致：回退必须命中 dish_id，而不是按 name 反查失败后静默跳过
        Dish dish = dish(10, true);
        DishShop link = link(3, 0, 1);
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any())).thenReturn(link);
        // 名称反查查不到任何菜品
        when(dishService.getOne(any())).thenReturn(null);

        OrderDetail detail = detail(10, "2");
        detail.setName("已改名的菜品");
        service.restoreForDetail(detail, 7);

        verify(dishShopMapper).update(isNull(), any());
    }

    @Test
    void skipsRestoreWhenTrackingDisabled() {
        Dish dish = dish(10, true);
        DishShop link = link(-1, 0, 0); // 不限量
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any())).thenReturn(link);

        service.restoreForDetail(detail(10, "2"), 7);

        verify(dishShopMapper, never()).update(isNull(), any());
    }

    @Test
    void skipsRestoreGracefullyWhenDishUnlinkedFromShop() {
        // 菜品已被解绑（t_dish_shop 无记录）：回退跳过并留痕，退菜事务不应整体回滚
        Dish dish = dish(10, true);
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any())).thenReturn(null);

        assertDoesNotThrow(() -> service.restoreForDetail(detail(10, "2"), 7));
        verify(dishShopMapper, never()).update(isNull(), any());
    }

    private static Dish dish(int id, boolean onsale) {
        Dish dish = new Dish();
        dish.setId(id);
        dish.setName("烤鸡翅");
        dish.setOnsale(onsale);
        return dish;
    }

    private static DishShop link(int stock, int soldOut, int stockEnabled) {
        DishShop link = new DishShop();
        link.setShop_id(7);
        link.setDish_id(10);
        link.setStock(stock);
        link.setSold_out(soldOut);
        link.setStock_enabled(stockEnabled);
        return link;
    }

    private static OrderDetail detail(int dishId, String quantity) {
        OrderDetail detail = new OrderDetail();
        detail.setId(9901);
        detail.setDish_id(dishId);
        detail.setName("烤鸡翅");
        detail.setQuantity(quantity);
        detail.setLine_status("normal");
        return detail;
    }
}
