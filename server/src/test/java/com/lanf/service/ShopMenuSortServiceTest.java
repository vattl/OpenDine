package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.CategoryShop;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.mapper.CategoryMapper;
import com.lanf.mapper.CategoryShopMapper;
import com.lanf.mapper.DishMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.ShopMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ShopMenuSortServiceTest {

    private ShopMenuSortService service;
    private ShopMapper shopMapper;
    private CategoryMapper categoryMapper;
    private CategoryShopMapper categoryShopMapper;
    private DishMapper dishMapper;
    private DishShopMapper dishShopMapper;

    @BeforeEach
    void setUp() {
        service = new ShopMenuSortService();
        shopMapper = mock(ShopMapper.class);
        categoryMapper = mock(CategoryMapper.class);
        categoryShopMapper = mock(CategoryShopMapper.class);
        dishMapper = mock(DishMapper.class);
        dishShopMapper = mock(DishShopMapper.class);
        ReflectionTestUtils.setField(service, "shopMapper", shopMapper);
        ReflectionTestUtils.setField(service, "categoryMapper", categoryMapper);
        ReflectionTestUtils.setField(service, "categoryShopMapper", categoryShopMapper);
        ReflectionTestUtils.setField(service, "dishMapper", dishMapper);
        ReflectionTestUtils.setField(service, "dishShopMapper", dishShopMapper);
        when(shopMapper.selectIdForUpdate(5)).thenReturn(5);
    }

    @Test
    void sortDishesReordersOnlyWithinEffectiveCategory() {
        Dish d1 = dish(1, 1, 1);
        Dish d2 = dish(2, 1, 2);
        Dish d3 = dish(3, 2, 1);
        when(dishMapper.selectById(2)).thenReturn(d2);
        when(dishMapper.selectBatchIds(any())).thenReturn(Arrays.asList(d1, d2, d3));
        when(dishShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Arrays.asList(
                link(5, 1, 1, 1), link(5, 2, 1, 2), link(5, 3, 2, 1)));
        when(dishShopMapper.updateSortingOverride(anyInt(), anyInt(), anyInt())).thenReturn(1);

        service.sortDishes(5, 2, 1);

        verify(dishShopMapper).updateSortingOverride(5, 2, 1);
        verify(dishShopMapper).updateSortingOverride(5, 1, 2);
        verify(dishShopMapper, never()).updateSortingOverride(eq(5), eq(3), anyInt());
    }

    @Test
    void sortCategoriesWritesOnlyCurrentShopContinuousOverrides() {
        when(categoryMapper.selectById(3)).thenReturn(category(3, 2));
        when(categoryMapper.selectList(any(QueryWrapper.class))).thenReturn(new ArrayList<>(Arrays.asList(
                category(1, 1), category(2, 2), category(3, 2))));
        when(categoryShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(categoryShopMapper.upsertSorting(anyInt(), anyInt(), anyInt())).thenReturn(1);

        service.sortCategories(5, 3, 1);

        verify(categoryShopMapper).upsertSorting(5, 3, 1);
        verify(categoryShopMapper).upsertSorting(5, 1, 2);
        verify(categoryShopMapper).upsertSorting(5, 2, 3);
    }

    @Test
    void orderCategoriesUsesRequestedShopOverridesAndStableIdTieBreak() {
        when(categoryShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Arrays.asList(
                categoryShop(5, 2, 1), categoryShop(5, 1, 2)));
        List<Category> categories = new ArrayList<>(Arrays.asList(
                category(3, 1), category(1, 1), category(2, 1)));

        service.orderCategories(5, categories);

        assertEquals(Arrays.asList(2, 3, 1), Arrays.asList(
                categories.get(0).getId(), categories.get(1).getId(), categories.get(2).getId()));
        assertEquals(Integer.valueOf(1), categories.get(0).getSorting());
        assertEquals(Integer.valueOf(1), categories.get(1).getSorting());
        assertEquals(Integer.valueOf(2), categories.get(2).getSorting());
    }

    @Test
    void missingShopContextFailsClosed() {
        ShopMenuSortService.MenuSortException error = assertThrows(
                ShopMenuSortService.MenuSortException.class,
                () -> service.sortCategories(null, 1, 1));

        assertEquals(4001, error.getCode());
        verify(categoryShopMapper, never()).upsertSorting(anyInt(), anyInt(), anyInt());
    }

    private static Category category(int id, Integer sorting) {
        Category row = new Category();
        row.setId(id);
        row.setSorting(sorting);
        return row;
    }

    private static CategoryShop categoryShop(int shopId, int categoryId, int sorting) {
        CategoryShop row = new CategoryShop();
        row.setShop_id(shopId);
        row.setCategory_id(categoryId);
        row.setSorting_override(sorting);
        return row;
    }

    private static Dish dish(int id, int typeId, int sorting) {
        Dish row = new Dish();
        row.setId(id);
        row.setName("D" + id);
        row.setTypeId(typeId);
        row.setSorting(sorting);
        return row;
    }

    private static DishShop link(int shopId, int dishId, int typeId, int sorting) {
        DishShop row = new DishShop();
        row.setShop_id(shopId);
        row.setDish_id(dishId);
        row.setType_id_override(typeId);
        row.setSorting_override(sorting);
        return row;
    }
}
