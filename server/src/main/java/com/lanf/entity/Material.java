package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 原材料，对应 t_material
 */
@Data
@TableName("t_material")
public class Material {
    private Integer id;
    /** 门店 ID，对应 t_material.shop_id；NULL 为迁移前未分门店数据 */
    private Integer shop_id;
    private String name;
    private String unit;
    private BigDecimal stock;
    private BigDecimal alert_threshold;
    private Date created_at;
    private Date updated_at;
}
