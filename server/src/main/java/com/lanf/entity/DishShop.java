package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 门店菜品关联，对应 t_dish_shop
 */
@Data
@TableName("t_dish_shop")
public class DishShop {
    private Long id;
    private Integer shop_id;
    private Integer dish_id;
    private BigDecimal unitprice;
    private Integer stock;
    /** 是否启用库存跟踪（持久标志，不随库存值变化）：1 跟踪（扣减/回退）；0 不限量或未启用。见 docs/db_migration_dish_shop_stock_enabled.sql */
    private Integer stock_enabled;
    private Integer sold_out;
    private Integer onsale_override;
    /** 门店规格模板 JSON；NULL 回退 t_dish.specification（见 docs/db_migration_dish_shop_full_overrides.sql） */
    private String specification_override;
    /** 门店本地化名称；NULL 回退 t_dish.name */
    private String name_override;
    /** 门店本地化图片；NULL 回退 t_dish.image */
    private String image_override;
    /** 门店单位；NULL 回退 t_dish.unit */
    private String unit_override;
    /** 门店分类(t_category.id)；NULL 回退 t_dish.typeId */
    private Integer type_id_override;
    /** 门店排序；NULL 回退 t_dish.sorting */
    private Integer sorting_override;
    /** 门店出餐时长(分钟)；NULL 回退 t_dish.serving_duration_minutes */
    private Integer serving_duration_override;
    private Date updated_at;
}
