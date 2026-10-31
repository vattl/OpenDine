package com.lanf.util;

import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * 门店菜品覆盖统一应用器（方案 A）。
 *
 * <p>将 t_dish_shop 上的门店覆盖列应用到 t_dish 对象；覆盖列为 NULL 时回退总部值。
 * C 端菜单（DishController.listAll）、KDS、AI 推荐菜单等所有「按门店出菜」的入口共用，
 * 保证同一门店在任何入口看到一致的名称/图片/单位/规格/分类/排序/出餐时长/价格/库存/上下架。</p>
 */
public final class DishShopOverrides {

    private DishShopOverrides() {
    }

    /**
     * 对菜品列表应用门店覆盖。dishes 为空或 shopDishMeta 为空时直接返回（总部语义）。
     *
     * @param dishes       总部菜品列表（将被就地覆盖）
     * @param shopDishMeta dishId -> 门店挂载/覆盖记录
     */
    public static void apply(List<Dish> dishes, Map<Integer, DishShop> shopDishMeta) {
        if (dishes == null || dishes.isEmpty() || shopDishMeta == null || shopDishMeta.isEmpty()) {
            return;
        }
        for (Dish d : dishes) {
            if (d == null || d.getId() == null) {
                continue;
            }
            DishShop link = shopDishMeta.get(d.getId());
            if (link == null) {
                continue;
            }
            if (link.getOnsale_override() != null) {
                d.setOnsale(link.getOnsale_override() == 1);
            }
            BigDecimal up = link.getUnitprice();
            if (up != null) {
                d.setUnitprice(up.floatValue());
            }
            if (link.getStock() != null) {
                d.setStock(link.getStock());
            }
            if (link.getSold_out() != null) {
                d.setSold_out(link.getSold_out());
            } else if (link.getStock() != null) {
                DishSoldOutSync.applyFromStock(d);
            }
            if (StringUtils.hasText(link.getName_override())) {
                d.setName(link.getName_override());
            }
            if (StringUtils.hasText(link.getImage_override())) {
                d.setImage(link.getImage_override());
            }
            if (StringUtils.hasText(link.getUnit_override())) {
                d.setUnit(link.getUnit_override());
            }
            if (StringUtils.hasText(link.getSpecification_override())) {
                d.setSpecification(link.getSpecification_override());
            }
            if (link.getType_id_override() != null) {
                d.setTypeId(link.getType_id_override());
            }
            if (link.getSorting_override() != null) {
                d.setSorting(link.getSorting_override());
            }
            if (link.getServing_duration_override() != null) {
                d.setServing_duration_minutes(link.getServing_duration_override());
            }
        }
    }
}
