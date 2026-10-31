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
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

/**
 * 门店菜单排序的单一业务所有者。
 * 分类按门店覆盖；菜品按当前门店及生效分类重排。
 */
@Service
public class ShopMenuSortService {

    @Autowired
    private ShopMapper shopMapper;
    @Autowired
    private CategoryMapper categoryMapper;
    @Autowired
    private CategoryShopMapper categoryShopMapper;
    @Autowired
    private DishMapper dishMapper;
    @Autowired
    private DishShopMapper dishShopMapper;

    @Transactional(rollbackFor = Exception.class)
    public Category sortCategories(Integer shopId, Integer categoryId, int targetIndex) {
        lockShop(shopId);
        Category target = categoryMapper.selectById(categoryId);
        if (target == null) {
            throw new MenuSortException(500, "类目不存在");
        }

        List<Category> categories = categoryMapper.selectList(new QueryWrapper<Category>()
                .orderByAsc("sorting").orderByAsc("id"));
        Map<Integer, Integer> overrides = categoryOverrides(shopId);
        sortCategories(categories, overrides, false);
        int oldIndex = indexOfCategory(categories, categoryId);
        if (oldIndex < 0) {
            throw new MenuSortException(500, "类目不存在");
        }
        move(categories, oldIndex, targetIndex);

        for (int i = 0; i < categories.size(); i++) {
            Integer id = categories.get(i).getId();
            int sorting = i + 1;
            if (!Integer.valueOf(sorting).equals(overrides.get(id))
                    && categoryShopMapper.upsertSorting(shopId, id, sorting) <= 0) {
                throw new MenuSortException(500, "类目排序更新未生效");
            }
        }
        return target;
    }

    @Transactional(rollbackFor = Exception.class)
    public Dish sortDishes(Integer shopId, Integer dishId, int targetIndex) {
        lockShop(shopId);
        Dish targetDish = dishMapper.selectById(dishId);
        if (targetDish == null) {
            throw new MenuSortException(500, "菜品不存在");
        }

        List<DishShop> shopLinks = dishShopMapper.selectList(
                new QueryWrapper<DishShop>().eq("shop_id", shopId));
        if (shopLinks == null || shopLinks.isEmpty()) {
            throw new MenuSortException(500, "当前门店未挂载任何菜品");
        }
        Map<Integer, Dish> dishes = dishesById(shopLinks);
        DishShop targetLink = null;
        for (DishShop link : shopLinks) {
            if (dishId.equals(link.getDish_id())) {
                targetLink = link;
                break;
            }
        }
        if (targetLink == null) {
            throw new MenuSortException(500, "菜品未挂载到当前门店");
        }
        Integer targetCategoryId = effectiveCategoryId(targetLink, targetDish);
        if (targetCategoryId == null) {
            throw new MenuSortException(500, "菜品未绑定有效分类");
        }

        List<DishShop> categoryLinks = shopLinks.stream()
                .filter(link -> Objects.equals(targetCategoryId,
                        effectiveCategoryId(link, dishes.get(link.getDish_id()))))
                .sorted(Comparator
                        .comparingInt((DishShop link) -> effectiveDishSorting(link, dishes.get(link.getDish_id())))
                        .thenComparingInt(link -> link.getDish_id() != null ? link.getDish_id() : Integer.MAX_VALUE))
                .collect(Collectors.toCollection(ArrayList::new));
        int oldIndex = indexOfDish(categoryLinks, dishId);
        if (oldIndex < 0) {
            throw new MenuSortException(500, "菜品未挂载到当前门店分类");
        }
        move(categoryLinks, oldIndex, targetIndex);

        for (int i = 0; i < categoryLinks.size(); i++) {
            DishShop link = categoryLinks.get(i);
            int sorting = i + 1;
            if (!Integer.valueOf(sorting).equals(link.getSorting_override())
                    && dishShopMapper.updateSortingOverride(shopId, link.getDish_id(), sorting) != 1) {
                throw new MenuSortException(500, "菜品排序更新未生效");
            }
        }
        return targetDish;
    }

    /** 按当前门店覆盖顺序排序并将响应中的 sorting 替换为生效值。 */
    public List<Category> orderCategories(Integer shopId, List<Category> categories) {
        if (categories == null || categories.isEmpty()) {
            return categories == null ? Collections.emptyList() : categories;
        }
        if (shopId == null) {
            categories.sort(categoryComparator(Collections.emptyMap()));
            return categories;
        }
        Map<Integer, Integer> overrides = categoryOverrides(shopId);
        sortCategories(categories, overrides, true);
        return categories;
    }

    private void lockShop(Integer shopId) {
        if (shopId == null) {
            throw new MenuSortException(4001, "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code");
        }
        if (shopMapper.selectIdForUpdate(shopId) == null) {
            throw new MenuSortException(4003, "门店不存在或不可用");
        }
    }

    private Map<Integer, Integer> categoryOverrides(Integer shopId) {
        List<CategoryShop> rows = categoryShopMapper.selectList(
                new QueryWrapper<CategoryShop>().eq("shop_id", shopId));
        Map<Integer, Integer> overrides = new HashMap<>();
        if (rows != null) {
            for (CategoryShop row : rows) {
                if (row.getCategory_id() != null && row.getSorting_override() != null) {
                    overrides.put(row.getCategory_id(), row.getSorting_override());
                }
            }
        }
        return overrides;
    }

    private static void sortCategories(List<Category> categories, Map<Integer, Integer> overrides,
                                       boolean exposeEffectiveSorting) {
        categories.sort(categoryComparator(overrides));
        if (exposeEffectiveSorting) {
            for (Category category : categories) {
                Integer override = overrides.get(category.getId());
                if (override != null) {
                    category.setSorting(override);
                }
            }
        }
    }

    private static Comparator<Category> categoryComparator(Map<Integer, Integer> overrides) {
        return Comparator.comparingInt((Category category) -> {
            Integer override = overrides.get(category.getId());
            Integer effective = override != null ? override : category.getSorting();
            return effective != null ? effective : Integer.MAX_VALUE;
        }).thenComparingInt(category -> category.getId() != null ? category.getId() : Integer.MAX_VALUE);
    }

    private Map<Integer, Dish> dishesById(List<DishShop> links) {
        Collection<Integer> ids = links.stream().map(DishShop::getDish_id)
                .filter(Objects::nonNull).collect(Collectors.toList());
        if (ids.isEmpty()) {
            return Collections.emptyMap();
        }
        List<Dish> rows = dishMapper.selectBatchIds(ids);
        Map<Integer, Dish> result = new HashMap<>();
        if (rows != null) {
            for (Dish row : rows) {
                if (row != null && row.getId() != null) {
                    result.put(row.getId(), row);
                }
            }
        }
        return result;
    }

    private static Integer effectiveCategoryId(DishShop link, Dish dish) {
        return link.getType_id_override() != null
                ? link.getType_id_override()
                : dish != null ? dish.getTypeId() : null;
    }

    private static int effectiveDishSorting(DishShop link, Dish dish) {
        Integer sorting = link.getSorting_override() != null
                ? link.getSorting_override()
                : dish != null ? dish.getSorting() : null;
        return sorting != null ? sorting : Integer.MAX_VALUE;
    }

    private static int indexOfCategory(List<Category> rows, Integer id) {
        for (int i = 0; i < rows.size(); i++) {
            if (Objects.equals(id, rows.get(i).getId())) {
                return i;
            }
        }
        return -1;
    }

    private static int indexOfDish(List<DishShop> rows, Integer id) {
        for (int i = 0; i < rows.size(); i++) {
            if (Objects.equals(id, rows.get(i).getDish_id())) {
                return i;
            }
        }
        return -1;
    }

    private static <T> void move(List<T> rows, int oldIndex, int targetIndex) {
        int target = Math.max(0, Math.min(targetIndex - 1, rows.size() - 1));
        if (target != oldIndex) {
            T moving = rows.remove(oldIndex);
            rows.add(target, moving);
        }
    }

    public static final class MenuSortException extends RuntimeException {
        private final int code;

        public MenuSortException(int code, String message) {
            super(message);
            this.code = code;
        }

        public int getCode() {
            return code;
        }
    }
}

