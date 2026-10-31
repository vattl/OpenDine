package com.lanf.util;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.Dish;

import java.util.List;

/**
 * C 端菜单：仅按上架状态过滤（{@code onsale = true}）。售罄标记 {@code sold_out} 由下单接口单独校验。
 */
public final class DishCustomerMenuFilters {

    private DishCustomerMenuFilters() {}

    /**
     * 在已有条件上追加：{@code onsale = true}（对应库内上架态）。
     */
    public static void applyTo(QueryWrapper<Dish> q) {
        if (q == null) {
            return;
        }
        q.eq("onsale", true);
    }

    /**
     * 去掉 {@code dishList} 为空或 null 的分类（与 {@link #applyTo} 联用后，无在售菜的分类不返回）。
     */
    public static void dropCategoriesWithNoDishes(List<Category> categories) {
        if (categories == null) {
            return;
        }
        categories.removeIf(c -> c.getDishList() == null || c.getDishList().isEmpty());
    }
}
