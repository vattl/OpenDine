package com.lanf.controller;


import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.Combo;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.R;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.ICategoryService;
import com.lanf.service.IDishService;
import com.lanf.service.IShopService;
import com.lanf.service.ShopMenuSortService;
import com.lanf.util.DishCustomerMenuFilters;
import com.lanf.util.DishShopOverrides;
import com.lanf.util.DishSoldOutSync;
import com.lanf.util.ShopChainSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.lanf.service.IComboMealService;


/**
 * 菜品控制器
 */
@RestController
@RequestMapping("/dish")
public class DishController {

    /** C 端未传门店（无 X-Shop-Id / shop_id 等）时默认总店，兼容旧版小程序 */
    private static final int DEFAULT_C_SHOP_ID = 1;

    @Autowired
    private IDishService dishService;

    @Autowired
    private ICategoryService categoryService;

    @Autowired
    private IShopService shopService;

    @Autowired
    private DishShopMapper dishShopMapper;

    @Autowired
    private IComboMealService comboMealService;
    @Autowired
    private ShopMenuSortService shopMenuSortService;

    /**
     * 查询所有菜单分类
     * @return
     */
    @RequestMapping("/listAll")
    public R listAll(@RequestParam(name = "shop_id", required = false) Integer shopId,
                     @RequestParam(name = "shop_code", required = false) String shopCode,
                     HttpServletRequest request) {
        Integer resolved;
        try {
            resolved = ShopChainSupport.resolveShopChain(request, shopId,
                    shopCode != null ? shopCode.trim() : null,
                    shopService::requireActiveShopIdByCode);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        if (resolved == null) {
            resolved = DEFAULT_C_SHOP_ID;
        }
        List<DishShop> shopLinks = dishShopMapper.selectList(
                new QueryWrapper<DishShop>().eq("shop_id", resolved));
        if (shopLinks == null || shopLinks.isEmpty()) {
            Map<String, Object> empty = new HashMap<>();
            empty.put("allDish", java.util.Collections.emptyList());
            return R.ok(empty);
        }
        Map<Integer, DishShop> shopDishMeta = shopLinks.stream()
                .filter(l -> l.getDish_id() != null)
                .collect(Collectors.toMap(DishShop::getDish_id, l -> l, (a, b) -> a));
        final Set<Integer> shopDishIds = shopDishMeta.keySet();

        // 一次取全部挂店菜 → 应用门店覆盖（含分类/名称/规格/排序等）→ 按生效 typeId 分组
        List<Dish> allDishes = dishService.list(new QueryWrapper<Dish>().in("id", shopDishIds));
        applyShopOverrides(allDishes, shopDishMeta);
        Map<Integer, List<Dish>> dishesByType = new HashMap<>();
        for (Dish d : allDishes) {
            if (d == null || !d.isOnsale()) {
                continue;
            }
            Integer tid = d.getTypeId();
            dishesByType.computeIfAbsent(tid, k -> new ArrayList<>()).add(d);
        }
        // 类目先按 sorting 排序；每个类目内按（门店覆盖后）菜品 sorting 排序
        List<Category> categoryList = categoryService.list(new QueryWrapper<Category>()
                .orderByAsc("sorting").orderByAsc("id"));
        shopMenuSortService.orderCategories(resolved, categoryList);
        for (Category category : categoryList) {
            List<Dish> dishList = dishesByType.getOrDefault(category.getId(), Collections.emptyList());
            dishList.sort(Comparator.comparingInt((Dish d) -> d.getSorting() != null ? d.getSorting() : Integer.MAX_VALUE)
                    .thenComparingInt(d -> d.getId() != null ? d.getId() : 0));
            attachComboDefinitions(dishList, resolved);
            category.setDishList(dishList);
        }
        DishCustomerMenuFilters.dropCategoriesWithNoDishes(categoryList);
        Map<String, Object> map = new HashMap<>();
        map.put("allDish", categoryList);
        return R.ok(map);
    }

    /**
     * 仅展示已挂到当前门店的菜品；对门店维度单价/库存/上下架/售罄及
     * 名称/图片/单位/规格模板/分类/排序/出餐时长做覆盖（若有）。
     */
    private static void applyShopOverrides(List<Dish> dishes, Map<Integer, DishShop> shopDishMeta) {
        // 门店覆盖统一由公共工具应用（C 端/KDS/AI 共用，见 com.lanf.util.DishShopOverrides）
        DishShopOverrides.apply(dishes, shopDishMeta);
    }

    private void attachComboDefinitions(List<Dish> dishes, Integer shopId) {
        if (dishes == null || dishes.isEmpty()) {
            return;
        }
        for (Dish d : dishes) {
            if (d == null || d.getId() == null) {
                continue;
            }
            Combo c = comboMealService.getByDishId(d.getId(), shopId);
            if (c != null && (c.getStatus() == null || c.getStatus() == 1)) {
                d.setComboDefinition(comboMealService.buildComboMenuPayload(c.getId()));
            }
        }
    }

}
