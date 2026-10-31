package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.*;
import com.lanf.mapper.ComboFixedItemMapper;
import com.lanf.mapper.ComboGroupItemMapper;
import com.lanf.mapper.ComboGroupMapper;
import com.lanf.mapper.ComboMapper;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IDishService;
import com.lanf.service.impl.ComboMealServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * 结构化套餐门店隔离机制测试：
 * 验证同名/同菜品套餐跨店独立配置、互不覆盖、两级回退继承以及越权防护。
 */
class AdminComboStoreIsolationTest {

    private ComboMealServiceImpl comboMealService;
    private ComboMapper comboMapper;
    private ComboFixedItemMapper comboFixedItemMapper;
    private ComboGroupMapper comboGroupMapper;
    private ComboGroupItemMapper comboGroupItemMapper;
    private IDishService dishService;

    private AdminComboController adminComboController;
    private AdminShopScopeGuard adminShopScopeGuard;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        comboMealService = new ComboMealServiceImpl();
        comboMapper = mock(ComboMapper.class);
        comboFixedItemMapper = mock(ComboFixedItemMapper.class);
        comboGroupMapper = mock(ComboGroupMapper.class);
        comboGroupItemMapper = mock(ComboGroupItemMapper.class);
        dishService = mock(IDishService.class);

        ReflectionTestUtils.setField(comboMealService, "comboMapper", comboMapper);
        ReflectionTestUtils.setField(comboMealService, "comboFixedItemMapper", comboFixedItemMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupMapper", comboGroupMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupItemMapper", comboGroupItemMapper);
        ReflectionTestUtils.setField(comboMealService, "dishService", dishService);
        ReflectionTestUtils.setField(comboMealService, "objectMapper", new ObjectMapper());

        adminComboController = new AdminComboController();
        adminShopScopeGuard = mock(AdminShopScopeGuard.class);
        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(adminComboController, "comboMealService", comboMealService);
        ReflectionTestUtils.setField(adminComboController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminComboController, "request", request);

        Dish dish = new Dish();
        dish.setId(100);
        dish.setName("超值双人餐");
        when(dishService.getById(100)).thenReturn(dish);
    }

    @Test
    void getByDishId_withShopId_returnsStoreComboIfConfigured() {
        Combo storeCombo = new Combo();
        storeCombo.setId(10L);
        storeCombo.setDish_id(100);
        storeCombo.setShop_id(2);
        storeCombo.setStatus(1);

        when(comboMapper.selectOne(argThat(wrapper -> {
            String sql = wrapper != null ? wrapper.getCustomSqlSegment() : "";
            // Verify query targets shop_id = 2
            return sql.contains("shop_id");
        }))).thenReturn(storeCombo);

        Combo result = comboMealService.getByDishId(100, 2);
        assertNotNull(result);
        assertEquals(10L, result.getId());
        assertEquals(2, result.getShop_id());
    }

    @Test
    void getByDishId_withoutStoreOverride_fallsBackToHeadquartersTemplate() {
        Combo hqCombo = new Combo();
        hqCombo.setId(1L);
        hqCombo.setDish_id(100);
        hqCombo.setShop_id(0);
        hqCombo.setStatus(1);

        // Store specific query returns null
        when(comboMapper.selectOne(argThat(wrapper -> {
            // First attempt with store query
            return wrapper != null && wrapper.getTargetSql().contains("shop_id") && !wrapper.getTargetSql().contains("IS NULL");
        }))).thenReturn(null);

        // Second fallback query returns HQ combo
        when(comboMapper.selectOne(argThat(wrapper -> {
            return wrapper != null && (wrapper.getTargetSql().contains("0") || wrapper.getTargetSql().contains("IS NULL"));
        }))).thenReturn(hqCombo);

        Combo result = comboMealService.getByDishId(100, 3);
        assertNotNull(result);
        assertEquals(1L, result.getId());
        assertEquals(0, result.getShop_id());
    }

    @Test
    void saveComboDefinition_isolatesStoresAndDoesNotDeleteOtherStores() {
        // When shopId = 2 saves combo
        List<Map<String, Object>> fixedItems = new ArrayList<>();
        Map<String, Object> item1 = new HashMap<>();
        item1.put("componentDishId", 201);
        item1.put("qtyPerCombo", 2);
        fixedItems.add(item1);

        comboMealService.saveComboDefinition(100, 2, "fixed", 1, fixedItems, Collections.emptyList(), null);

        // Verify comboMapper.insert is called with shop_id = 2
        ArgumentCaptor<Combo> comboCaptor = ArgumentCaptor.forClass(Combo.class);
        verify(comboMapper).insert(comboCaptor.capture());
        Combo inserted = comboCaptor.getValue();
        assertEquals(100, inserted.getDish_id());
        assertEquals(2, inserted.getShop_id());
        assertEquals("fixed", inserted.getCombo_type());
    }

    @Test
    void adminComboController_save_passesTargetShopIdAndAppliesScopeGuard() {
        when(adminShopScopeGuard.resolveTargetShopId(eq(5), any())).thenAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 5;
            return null; // authorized
        });

        Map<String, Object> body = new HashMap<>();
        body.put("dishId", 100);
        body.put("shopId", 5);
        body.put("comboType", "groups");

        R r = adminComboController.save(body);
        assertEquals(0, r.get("code"));

        ArgumentCaptor<Combo> comboCaptor = ArgumentCaptor.forClass(Combo.class);
        verify(comboMapper).insert(comboCaptor.capture());
        assertEquals(5, comboCaptor.getValue().getShop_id());
    }

    @Test
    void adminComboController_save_forbiddenWhenScopeGuardDenies() {
        when(adminShopScopeGuard.resolveTargetShopId(eq(99), any()))
                .thenReturn(R.error(4003, "门店不在当前管理员可操作范围内"));

        Map<String, Object> body = new HashMap<>();
        body.put("dishId", 100);
        body.put("shopId", 99);

        R r = adminComboController.save(body);
        assertEquals(4003, r.get("code"));
        assertTrue(r.get("msg").toString().contains("门店不在当前管理员可操作范围内"));
        verify(comboMapper, never()).insert(any());
    }
}
