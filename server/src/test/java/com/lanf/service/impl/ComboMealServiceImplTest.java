package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Combo;
import com.lanf.entity.ComboFixedItem;
import com.lanf.entity.ComboGroup;
import com.lanf.entity.ComboGroupItem;
import com.lanf.entity.Dish;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.ComboFixedItemMapper;
import com.lanf.mapper.ComboGroupItemMapper;
import com.lanf.mapper.ComboGroupMapper;
import com.lanf.mapper.ComboMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ComboMealServiceImplTest {

    private ComboMealServiceImpl comboMealService;
    private ComboMapper comboMapper;
    private ComboFixedItemMapper comboFixedItemMapper;
    private ComboGroupMapper comboGroupMapper;
    private ComboGroupItemMapper comboGroupItemMapper;
    private IDishService dishService;
    private DishShopMapper dishShopMapper;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        comboMealService = new ComboMealServiceImpl();
        comboMapper = mock(ComboMapper.class);
        comboFixedItemMapper = mock(ComboFixedItemMapper.class);
        comboGroupMapper = mock(ComboGroupMapper.class);
        comboGroupItemMapper = mock(ComboGroupItemMapper.class);
        dishService = mock(IDishService.class);
        dishShopMapper = mock(DishShopMapper.class);
        objectMapper = new ObjectMapper();

        ReflectionTestUtils.setField(comboMealService, "comboMapper", comboMapper);
        ReflectionTestUtils.setField(comboMealService, "comboFixedItemMapper", comboFixedItemMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupMapper", comboGroupMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupItemMapper", comboGroupItemMapper);
        ReflectionTestUtils.setField(comboMealService, "dishService", dishService);
        ReflectionTestUtils.setField(comboMealService, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(comboMealService, "objectMapper", objectMapper);
    }

    @Test
    void normalizeCartLines_shouldExpandFixedComboSuccessfully() {
        Combo combo = new Combo();
        combo.setId(8L);
        combo.setDish_id(139);
        combo.setCombo_type("fixed");
        combo.setStatus(1);

        Dish headerDish = new Dish();
        headerDish.setId(139);
        headerDish.setName("单人油边套餐");
        headerDish.setUnit("份");
        headerDish.setTypeId(10);
        headerDish.setUnitprice(68.0f);
        headerDish.setOnsale(true);

        Dish compDish1 = new Dish();
        compDish1.setId(201);
        compDish1.setName("烤油边");
        compDish1.setUnit("串");
        compDish1.setTypeId(1);
        compDish1.setUnitprice(15.0f);

        ComboFixedItem fixedItem = new ComboFixedItem();
        fixedItem.setId(1L);
        fixedItem.setCombo_id(8L);
        fixedItem.setComponent_dish_id(201);
        fixedItem.setQty_per_combo(2);
        fixedItem.setSort_order(1);

        when(comboMapper.selectById(8L)).thenReturn(combo);
        when(dishService.getById(139)).thenReturn(headerDish);
        when(dishService.getById(201)).thenReturn(compDish1);
        when(comboFixedItemMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(fixedItem));
        when(comboGroupMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        OrderDetail req = new OrderDetail();
        req.setDish_id(139);
        req.setName("单人油边套餐");
        req.setQuantity("1");
        req.setUnit("份");
        req.setTotal_price(68.0);
        req.setLine_type("combo");
        req.setCombo_id(8L);
        req.setComboSelections(Collections.emptyMap());
        req.setClient_line_id("line-1");

        List<OrderDetail> list = new ArrayList<>();
        list.add(req);

        comboMealService.normalizeCartLines(list, 1);

        assertEquals(2, list.size());
        OrderDetail header = list.get(0);
        assertEquals("combo_header", header.getLine_type());
        assertEquals("单人油边套餐", header.getName());
        assertEquals(68.0, header.getTotal_price());
        assertEquals(139, header.getDish_id());
        assertNotNull(header.getCombo_instance_id());
        assertEquals("line-1", header.getClient_line_id());

        OrderDetail comp = list.get(1);
        assertEquals("combo_component", comp.getLine_type());
        assertEquals("烤油边", comp.getName());
        assertEquals("2", comp.getQuantity());
        assertEquals(0.0, comp.getTotal_price());
        assertEquals(201, comp.getDish_id());
        assertEquals(header.getCombo_instance_id(), comp.getCombo_instance_id());
        assertNull(comp.getClient_line_id());
    }

    @Test
    void normalizeCartLines_shouldValidateRequiredGroupSelections() {
        Combo combo = new Combo();
        combo.setId(9L);
        combo.setDish_id(140);
        combo.setCombo_type("groups");
        combo.setStatus(1);

        Dish headerDish = new Dish();
        headerDish.setId(140);
        headerDish.setName("双人自选套餐");
        headerDish.setUnit("份");
        headerDish.setTypeId(10);
        headerDish.setUnitprice(98.0f);
        headerDish.setOnsale(true);

        ComboGroup group = new ComboGroup();
        group.setId(101L);
        group.setCombo_id(9L);
        group.setGroup_key("drink");
        group.setTitle("饮品任选一");
        group.setMin_pick(1);
        group.setMax_pick(1);

        when(comboMapper.selectById(9L)).thenReturn(combo);
        when(dishService.getById(140)).thenReturn(headerDish);
        when(comboFixedItemMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(comboGroupMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(group));

        OrderDetail req = new OrderDetail();
        req.setDish_id(140);
        req.setName("双人自选套餐");
        req.setQuantity("1");
        req.setUnit("份");
        req.setTotal_price(98.0);
        req.setLine_type("combo");
        req.setCombo_id(9L);
        req.setComboSelections(Collections.emptyMap());

        List<OrderDetail> list = new ArrayList<>();
        list.add(req);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> comboMealService.normalizeCartLines(list, 1));
        assertTrue(ex.getMessage().contains("饮品任选一") && ex.getMessage().contains("须选 1~1 项"));
    }

    @Test
    void normalizeCartLines_shouldFillFallbackUnitAndCid() {
        Combo combo = new Combo();
        combo.setId(10L);
        combo.setDish_id(141);
        combo.setCombo_type("fixed");
        combo.setStatus(1);

        Dish headerDish = new Dish();
        headerDish.setId(141);
        headerDish.setName("特色套餐");
        headerDish.setUnit(null); // missing unit
        headerDish.setTypeId(null); // missing typeId
        headerDish.setUnitprice(50.0f);
        headerDish.setOnsale(true);

        Dish compDish = new Dish();
        compDish.setId(202);
        compDish.setName("特色配菜");
        compDish.setUnit(null);
        compDish.setTypeId(null);

        ComboFixedItem fixedItem = new ComboFixedItem();
        fixedItem.setId(2L);
        fixedItem.setCombo_id(10L);
        fixedItem.setComponent_dish_id(202);
        fixedItem.setQty_per_combo(1);

        when(comboMapper.selectById(10L)).thenReturn(combo);
        when(dishService.getById(141)).thenReturn(headerDish);
        when(dishService.getById(202)).thenReturn(compDish);
        when(comboFixedItemMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(fixedItem));
        when(comboGroupMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        OrderDetail req = new OrderDetail();
        req.setDish_id(141);
        req.setName("特色套餐");
        req.setQuantity("1");
        req.setUnit("套");
        req.setCid("custom-cid");
        req.setTotal_price(50.0);
        req.setLine_type("combo");
        req.setCombo_id(10L);

        List<OrderDetail> list = new ArrayList<>();
        list.add(req);

        comboMealService.normalizeCartLines(list, 1);

        assertEquals(2, list.size());
        assertEquals("套", list.get(0).getUnit());
        assertEquals("custom-cid", list.get(0).getCid());
        assertEquals("份", list.get(1).getUnit());
        assertEquals("0", list.get(1).getCid());
    }
}
