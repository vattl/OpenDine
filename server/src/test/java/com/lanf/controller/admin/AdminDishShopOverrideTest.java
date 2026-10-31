package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.Combo;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.ICategoryService;
import com.lanf.service.IDishService;
import com.lanf.service.IShopService;
import com.lanf.service.IComboMealService;
import com.lanf.service.ShopMenuSortService;
import com.lanf.controller.DishController;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 方案 A 回归：门店菜品完整覆盖（价格/规格/名称/图片/单位/分类/排序/出餐时长）。
 * - 门店上下文编辑只写 t_dish_shop 覆盖列，不写 t_dish（避免跨店联动）。
 * - 门店上下文排序只写 t_dish_shop.sorting_override。
 * - C 端菜单应用全量覆盖并按覆盖后分类分组。
 */
class AdminDishShopOverrideTest {

    private AdminDishController adminController;
    private DishController customerController;
    private IDishService dishService;
    private ICategoryService categoryService;
    private IShopService shopService;
    private IComboMealService comboMealService;
    private DishShopMapper dishShopMapper;
    private HttpServletRequest request;
    private ShopMenuSortService shopMenuSortService;

    @BeforeEach
    void setUp() {
        adminController = new AdminDishController();
        customerController = new DishController();
        dishService = mock(IDishService.class);
        categoryService = mock(ICategoryService.class);
        shopService = mock(IShopService.class);
        comboMealService = mock(IComboMealService.class);
        dishShopMapper = mock(DishShopMapper.class);
        request = mock(HttpServletRequest.class);
        shopMenuSortService = mock(ShopMenuSortService.class);
        DishMenuPushService pushService = mock(DishMenuPushService.class);

        ReflectionTestUtils.setField(adminController, "dishService", dishService);
        ReflectionTestUtils.setField(adminController, "categoryService", categoryService);
        ReflectionTestUtils.setField(adminController, "dishMenuPushService", pushService);
        ReflectionTestUtils.setField(adminController, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(adminController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminController, "shopMenuSortService", shopMenuSortService);

        ReflectionTestUtils.setField(customerController, "dishService", dishService);
        ReflectionTestUtils.setField(customerController, "categoryService", categoryService);
        ReflectionTestUtils.setField(customerController, "shopService", shopService);
        ReflectionTestUtils.setField(customerController, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(customerController, "comboMealService", comboMealService);
        ReflectionTestUtils.setField(customerController, "shopMenuSortService", shopMenuSortService);
    }

    private void mockShopContext(Integer shopId) {
        when(request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)).thenReturn(shopId);
    }

    private Dish hqDish(Integer id, String name, float price, Integer typeId, Integer sorting) {
        Dish d = new Dish();
        d.setId(id);
        d.setName(name);
        d.setUnitprice(price);
        d.setTypeId(typeId);
        d.setSorting(sorting);
        d.setOnsale(true);
        return d;
    }

    // ------------------------------------------------------------------
    // save：门店上下文编辑 → 覆盖列写 t_dish_shop，总部字段不动
    // ------------------------------------------------------------------

    @Test
    void saveShopUpdateWritesOverridesToDishShopNotHq() {
        mockShopContext(5);
        Dish existing = hqDish(1, "牛肉面", 10f, 1, 5);
        existing.setOnsale(true);
        when(dishService.getById(1)).thenReturn(existing);
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);

        Dish req = new Dish();
        req.setId(1);
        req.setName("门店招牌牛肉面");
        req.setUnitprice(12.5f);
        req.setSpecification("{\"份量\":[\"大\",\"小\"]}");
        req.setUnit("碗");
        req.setImage("shop.png");
        req.setTypeId(3);
        req.setSorting(2);
        req.setServing_duration_minutes(20);
        req.setStock(10);
        req.setSold_out(0);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        // 总部字段必须未被修改（避免跨店联动）
        ArgumentCaptor<Dish> hqSaved = ArgumentCaptor.forClass(Dish.class);
        verify(dishService).updateById(hqSaved.capture());
        Dish hq = hqSaved.getValue();
        assertNull(hq.getName());
        assertNull(hq.getUnitprice());
        assertNull(hq.getSpecification());
        assertNull(hq.getUnit());
        assertNull(hq.getImage());
        assertNull(hq.getTypeId());
        assertNull(hq.getSorting());
        assertNull(hq.getServing_duration_minutes());
        // 门店覆盖列已写入
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertEquals("门店招牌牛肉面", link.getName_override());
        assertEquals(new BigDecimal("12.50").compareTo(link.getUnitprice()) == 0, true);
        assertEquals("{\"份量\":[\"大\",\"小\"]}", link.getSpecification_override());
        assertEquals("碗", link.getUnit_override());
        assertEquals("shop.png", link.getImage_override());
        assertEquals(Integer.valueOf(3), link.getType_id_override());
        assertEquals(Integer.valueOf(2), link.getSorting_override());
        assertEquals(Integer.valueOf(20), link.getServing_duration_override());
        assertEquals(Integer.valueOf(10), link.getStock());
    }

    @Test
    void saveShopUpdateWithoutOverrideFieldsKeepsLinkUnchanged() {
        mockShopContext(5);
        Dish existing = hqDish(2, "凉菜", 8f, 2, 1);
        existing.setOnsale(true);
        when(dishService.getById(2)).thenReturn(existing);
        DishShop existingLink = new DishShop();
        existingLink.setId(99L);
        existingLink.setShop_id(5);
        existingLink.setDish_id(2);
        existingLink.setName_override("门店凉菜");
        existingLink.setUnitprice(new BigDecimal("9.00"));
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(existingLink);

        Dish req = new Dish();
        req.setId(2);
        req.setStock(20); // 只改库存

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        // 未传覆盖字段 → 保持既有覆盖，不覆盖为 NULL
        assertEquals("门店凉菜", link.getName_override());
        assertEquals(new BigDecimal("9.00"), link.getUnitprice());
        assertEquals(Integer.valueOf(20), link.getStock());
    }

    // ------------------------------------------------------------------
    // sort：门店上下文 → 只写 t_dish_shop.sorting_override，不动总部
    // ------------------------------------------------------------------

    @Test
    void sortShopContextWritesOnlySortingOverride() {
        mockShopContext(5);
        when(shopMenuSortService.sortDishes(5, 2, 3))
                .thenReturn(hqDish(2, "B", 1f, 1, 2));

        Map<String, Integer> body = new HashMap<>();
        body.put("id", 2);
        body.put("targetIndex", 3);
        R result = adminController.sort(body);

        assertEquals(0, result.get("code"));
        verify(shopMenuSortService).sortDishes(5, 2, 3);
        verify(dishService, never()).update(any());
    }

    @Test
    void sortWithoutShopContextReturnsErrorInsteadOfChangingHqSorting() {
        when(request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)).thenReturn(null);
        when(shopMenuSortService.sortDishes(null, 2, 1)).thenThrow(
                new ShopMenuSortService.MenuSortException(4001,
                        "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code"));

        Map<String, Integer> body = new HashMap<>();
        body.put("id", 2);
        body.put("targetIndex", 1);
        R result = adminController.sort(body);

        assertEquals(4001, result.get("code"));
        verify(dishService, never()).update(any());
    }

    // ------------------------------------------------------------------
    // listAll：C 端菜单应用全量覆盖 + 按覆盖后分类分组
    // ------------------------------------------------------------------

    @Test
    @SuppressWarnings("unchecked")
    void listAllAppliesFullShopOverridesAndRegroupsByType() {
        DishShop link = new DishShop();
        link.setShop_id(5);
        link.setDish_id(1);
        link.setName_override("门店招牌牛肉面");
        link.setUnitprice(new BigDecimal("12.50"));
        link.setSpecification_override("{\"辣度\":[\"微辣\"]}");
        link.setType_id_override(3);
        link.setSorting_override(1);
        link.setServing_duration_override(25);
        link.setOnsale_override(1);
        link.setStock(50);
        link.setSold_out(0);
        when(dishShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(link));

        Dish hq = hqDish(1, "牛肉面", 10f, 1, 5);
        hq.setSpecification("{\"份量\":[\"大\",\"小\"]}");
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(hq));

        Category c1 = new Category();
        c1.setId(1);
        c1.setLabel("面食");
        Category c3 = new Category();
        c3.setId(3);
        c3.setLabel("招牌");
        when(categoryService.list(any(QueryWrapper.class))).thenReturn(new java.util.ArrayList<>(Arrays.asList(c1, c3)));
        when(comboMealService.getByDishId(1)).thenReturn(null);

        R result = customerController.listAll(5, null, request);

        assertEquals(0, result.get("code"));
        List<Category> categories = (List<Category>) result.get("allDish");
        assertEquals(1, categories.size(), "覆盖分类后应只留下有菜品的类目");
        assertEquals("招牌", categories.get(0).getLabel());
        List<Dish> dishes = categories.get(0).getDishList();
        assertEquals(1, dishes.size());
        Dish viewed = dishes.get(0);
        assertEquals("门店招牌牛肉面", viewed.getName());
        assertEquals(12.5f, viewed.getUnitprice());
        assertEquals("{\"辣度\":[\"微辣\"]}", viewed.getSpecification());
        assertEquals(Integer.valueOf(3), viewed.getTypeId());
        assertEquals(Integer.valueOf(1), viewed.getSorting());
        assertEquals(Integer.valueOf(25), viewed.getServing_duration_minutes());
        assertEquals(Integer.valueOf(50), viewed.getStock());
    }

    @Test
    void listAllWithoutOverridesFallsBackToHqFields() {
        DishShop link = new DishShop();
        link.setShop_id(5);
        link.setDish_id(1);
        link.setStock(-1);
        link.setSold_out(0);
        link.setOnsale_override(1);
        when(dishShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(link));

        Dish hq = hqDish(1, "牛肉面", 10f, 1, 5);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(hq));

        Category c1 = new Category();
        c1.setId(1);
        c1.setLabel("面食");
        when(categoryService.list(any(QueryWrapper.class))).thenReturn(new java.util.ArrayList<>(Collections.singletonList(c1)));
        when(comboMealService.getByDishId(1)).thenReturn(null);

        R result = customerController.listAll(5, null, request);

        List<Category> categories = (List<Category>) result.get("allDish");
        assertEquals(1, categories.size());
        Dish viewed = categories.get(0).getDishList().get(0);
        assertEquals("牛肉面", viewed.getName());
        assertEquals(10f, viewed.getUnitprice());
        assertEquals(Integer.valueOf(1), viewed.getTypeId());
        assertNull(viewed.getSpecification());
        assertTrue(viewed.getServing_duration_minutes() == null
                || viewed.getServing_duration_minutes() == 0
                || viewed.getServing_duration_minutes() == 10);
    }

    // ------------------------------------------------------------------
    // save：门店新建菜品自动关联总库已有菜品
    // ------------------------------------------------------------------

    @Test
    void saveShopCreateWithExistingHqDishAutoLinksAndOverrides() {
        mockShopContext(5);
        Dish existingHq = hqDish(10, "羊肉串", 5f, 1, 1);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(existingHq));
        when(dishShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        when(dishService.getById(10)).thenReturn(existingHq);

        Dish req = new Dish();
        req.setName("  羊肉串  ");
        req.setUnitprice(6.5f);
        req.setTypeId(2);
        req.setStock(50);
        req.setSold_out(0);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        // 关键断言：总库未插入重复菜品
        verify(dishService, never()).save(any(Dish.class));
        // 门店关联行已写入并强制上架与覆盖
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertEquals(Integer.valueOf(10), link.getDish_id());
        assertEquals(Integer.valueOf(5), link.getShop_id());
        assertEquals(Integer.valueOf(1), link.getOnsale_override());
        assertEquals(Integer.valueOf(50), link.getStock());
        assertEquals(Integer.valueOf(2), link.getType_id_override());
        assertEquals(0, new BigDecimal("6.50").compareTo(link.getUnitprice()));
    }

    @Test
    void saveShopCreateWithExistingLinkedDishRestoresOnSale() {
        mockShopContext(5);
        Dish existingHq = hqDish(10, "羊肉串", 5f, 1, 1);
        DishShop oldLink = linkOf(101L, 5, 10, 1);
        oldLink.setOnsale_override(0); // 历史已下架

        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(existingHq));
        when(dishShopMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(oldLink));
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(oldLink);
        when(dishService.getById(10)).thenReturn(existingHq);

        Dish req = new Dish();
        req.setName("羊肉串");
        req.setStock(30);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        verify(dishService, never()).save(any(Dish.class));
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertEquals(Integer.valueOf(10), link.getDish_id());
        assertEquals(Integer.valueOf(1), link.getOnsale_override()); // 强制恢复上架
        assertEquals(Integer.valueOf(30), link.getStock());
    }

    @Test
    void saveShopCreateWithNewDishSavesToHqAndLinks() {
        mockShopContext(5);
        when(dishService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);

        Dish req = new Dish();
        req.setName("全新原创菜品");
        req.setUnitprice(18f);
        req.setStock(20);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        // 关键断言：总库真正保存新菜
        verify(dishService).save(any(Dish.class));
    }

    // ------------------------------------------------------------------
    // 门店菜品分类显式绑定：新建挂载/存量行在分类为空时自动回填有效总部分类
    // ------------------------------------------------------------------

    @Test
    void newLinkBindsValidHqCategoryAutomatically() {
        mockShopContext(5);
        Dish existing = hqDish(1, "牛肉面", 10f, 1, 5);
        existing.setOnsale(true);
        when(dishService.getById(1)).thenReturn(existing);
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        when(categoryService.count(any(QueryWrapper.class))).thenReturn(1); // 分类 1 有效

        Dish req = new Dish();
        req.setId(1);
        req.setStock(10);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertEquals(Integer.valueOf(1), link.getType_id_override(), "新建挂载行未传分类时应自动绑定总部分类");
    }

    @Test
    void newLinkDoesNotBindInvalidHqCategory() {
        mockShopContext(5);
        Dish existing = hqDish(1, "牛肉面", 10f, 99, 5); // 总部 typeId=99 不存在
        existing.setOnsale(true);
        when(dishService.getById(1)).thenReturn(existing);
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(null);
        when(categoryService.count(any(QueryWrapper.class))).thenReturn(0);

        Dish req = new Dish();
        req.setId(1);
        req.setStock(10);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertNull(link.getType_id_override(), "总部分类无效时不绑定，等待人工补分类");
    }

    @Test
    void existingLinkWithNullCategoryBackfillsFromHq() {
        mockShopContext(5);
        Dish existing = hqDish(2, "凉菜", 8f, 2, 1);
        existing.setOnsale(true);
        when(dishService.getById(2)).thenReturn(existing);
        DishShop existingLink = linkOf(99L, 5, 2, null); // type_id_override 为 null 的存量行
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(existingLink);
        when(categoryService.count(any(QueryWrapper.class))).thenReturn(1);

        Dish req = new Dish();
        req.setId(2);
        req.setStock(20);

        R result = adminController.save(req);

        assertEquals(0, result.get("code"));
        ArgumentCaptor<DishShop> linkCaptor = ArgumentCaptor.forClass(DishShop.class);
        verify(dishShopMapper, atLeastOnce()).updateById(linkCaptor.capture());
        DishShop link = linkCaptor.getValue();
        assertEquals(Integer.valueOf(2), link.getType_id_override(), "存量行分类为空时应回填总部分类");
    }

    private static DishShop linkOf(Long id, Integer shopId, Integer dishId, Integer sortingOverride) {
        DishShop l = new DishShop();
        l.setId(id);
        l.setShop_id(shopId);
        l.setDish_id(dishId);
        l.setSorting_override(sortingOverride);
        l.setStock(-1);
        l.setSold_out(0);
        return l;
    }
}
