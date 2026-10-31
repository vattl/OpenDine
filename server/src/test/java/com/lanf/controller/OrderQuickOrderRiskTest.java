package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Table;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderQuickOrderRiskTest {

    @Test
    void processingKeyIsStablePerShopAndTable() {
        assertEquals("processing:7:A01", OrderController.generateOrderKey(7, "A01"));
        assertEquals(OrderController.generateOrderKey(7, "A01"),
                OrderController.generateOrderKey(7, "A01"));
    }

    @Test
    void awaitingClearTableCannotCreateAnotherOrder() {
        Table table = new Table();
        table.setStatus(2);

        RuntimeException error = assertThrows(RuntimeException.class,
                () -> OrderController.ensureTableAvailableForNewOrder(table));

        assertEquals("该桌台已结账待清台，请先清台后再下单", error.getMessage());
    }

    @Test
    void orderPriceValidationUsesShopOverridePrice() {
        OrderController controller = new OrderController();
        IDishService dishService = mock(IDishService.class);
        DishShopMapper dishShopMapper = mock(DishShopMapper.class);
        IDishShopStockService stockService = mock(IDishShopStockService.class);
        Dish dish = new Dish();
        dish.setId(10);
        dish.setName("门店菜");
        dish.setUnitprice(10f);
        dish.setOnsale(true);
        DishShop link = new DishShop();
        link.setShop_id(7);
        link.setDish_id(10);
        link.setUnitprice(new BigDecimal("15.00"));
        link.setStock(-1);
        link.setSold_out(0);
        link.setOnsale_override(1);
        when(dishService.getById(10)).thenReturn(dish);
        when(dishShopMapper.selectOne(any(Wrapper.class))).thenReturn(link);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(controller, "dishShopStockService", stockService);
        OrderDetail line = new OrderDetail();
        line.setDish_id(10);
        line.setName("门店菜");
        line.setUnit("份");
        line.setCid("1");
        line.setQuantity("1");
        line.setTotal_price(15d);

        assertDoesNotThrow(() -> ReflectionTestUtils.invokeMethod(controller,
                "validateOrderDetailsOnSale", Collections.singletonList(line), 7));
    }
}
