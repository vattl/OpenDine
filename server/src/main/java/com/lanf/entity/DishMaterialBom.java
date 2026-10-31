package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 菜品-原材料 BOM，对应 t_dish_material_bom
 */
@Data
@TableName("t_dish_material_bom")
public class DishMaterialBom {
    private Long id;
    private Integer shop_id;
    private Integer dish_id;
    private Integer material_id;
    private BigDecimal dosage;
    private String unit;
    private BigDecimal loss_rate;
    private Integer is_enabled;
    private Date created_at;
    private Date updated_at;
}
