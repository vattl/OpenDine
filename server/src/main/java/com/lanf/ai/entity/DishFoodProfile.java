package com.lanf.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 菜品食材、营养与风味画像扩展表实体，对应 t_dish_food_profile
 */
@Data
@TableName("t_dish_food_profile")
public class DishFoodProfile {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer dish_id;

    private Integer shop_id;

    private String ingredients;

    private String seasonings;

    /** 后厨是否支持做不辣：1 支持，0 无法做不辣 */
    private Integer non_spicy_available;

    /** 可用辣度选项JSON，如 ["不辣","微辣","中辣"] */
    private String spice_options;

    /** 已核验过敏原JSON，如 ["PEANUT","SEAFOOD"] */
    private String verified_allergens;

    /** 是否存在后厨交叉接触风险：0 无/未知，1 明确存在 */
    private Integer cross_contact_risk;

    /** 是否适合健身/减脂：1 是，0 否 */
    private Integer is_suitable_fitness;

    /** 每份卡路里(千卡)，未知则 null */
    private BigDecimal calories_kcal;

    /** 每份蛋白质(克)，未知则 null */
    private BigDecimal protein_g;

    /** 每份脂肪(克)，未知则 null */
    private BigDecimal fat_g;

    /** 可食部位净重(克)，未知则 null */
    private Integer edible_weight_g;

    /** 数据来源：UNVERIFIED, LAB_TEST, ESTIMATED */
    private String nutrition_source;

    private Date verified_at;

    private Date created_at;

    private Date updated_at;
}
