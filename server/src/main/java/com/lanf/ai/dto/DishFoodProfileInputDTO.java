package com.lanf.ai.dto;

import lombok.Data;

import java.math.BigDecimal;
import java.util.List;

/**
 * 菜品食材、营养与风味画像输入DTO（支持前端单项或批量编辑）
 */
@Data
public class DishFoodProfileInputDTO {

    /** 菜品ID (t_dish.id) */
    private Integer dish_id;

    /** 门店ID (默认 1) */
    private Integer shop_id = 1;

    /** 门店ID别名，等同于 shop_id */
    private Integer store_id;

    /** 主要原料（如 "羊腿肉,孜然,辣椒面"） */
    private String ingredients;

    /** 调味料清单 */
    private String seasonings;

    /** 后厨是否支持免辣制作：1 支持，0 无法做免辣 */
    private Integer non_spicy_available = 1;

    /** 可选辣度数组，如 ["不辣", "微辣", "中辣"] */
    private List<String> spice_options;

    /** 已核验过敏原数组，如 ["PEANUT", "SEAFOOD", "GLUTEN"] */
    private List<String> verified_allergens;

    /** 是否存在后厨交叉接触风险：0 无/未知，1 明确存在 */
    private Integer cross_contact_risk = 0;

    /** 是否适合健身控重/高蛋白：1 是，0 否 */
    private Integer is_suitable_fitness = 0;

    /** 每份卡路里(kcal) */
    private BigDecimal calories_kcal;

    /** 每份蛋白质(g) */
    private BigDecimal protein_g;

    /** 每份脂肪(g) */
    private BigDecimal fat_g;

    /** 可食部位净重/单份克重(g) */
    private Integer edible_weight_g;

    /** 数据核验来源：UNVERIFIED, LAB_TEST, ESTIMATED */
    private String nutrition_source = "ESTIMATED";
}
