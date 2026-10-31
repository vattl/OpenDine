package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;
import java.util.Map;

/**
 * 菜品实体
 */
@TableName("t_dish")
@Data
public class Dish {

    private Integer id; // 编号

    private String name; // 菜品名称

    private String image; // 菜品图片

    private Integer typeId; // 类别ID

    @TableField(select = false)
    private Category type; // 类别

    private Integer monthlysale;  // 商品销售量

    private Integer sorting;  // 商品排序

    private Float unitprice; // 商品单价

    /**
     * 成本价（元），可选。
     * 未执行 {@code docs/db_migration_dish_cost_price.sql} 前库表无此列，须标记 exist=false；迁移后去掉 exist=false，并把 AnalyticsMapper.selectDishSalesAgg 中 ref_cost_price 改为 {@code MAX(d.cost_price)}。
     */
    @TableField(value = "cost_price", exist = false)
    private BigDecimal cost_price;

    private String unit; // 商品单位

    /** 商品数量（历史字段，与可售库存无关） */
    private Integer quantity;

    /** 可售库存份数；null 或负数表示不限量；0 且在售表示未启用库存（兼容）；下单扣减与取消回退仅改本字段 */
    private Integer stock;

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date time; // 上架时间

    private boolean onsale; // true：上架 false：下架

    /** 是否已售罄：0 否 1 是（与 onsale 独立；库存扣减会同步本字段，不自动改 onsale） */
    private Integer sold_out;

    @TableField(select = false, exist = false)
    private Map<String, Object> comboDefinition;

    private String specification;

    /** 预计出餐时长（分钟），用于 KDS 单品超时判断；历史与新增默认 10 分钟。 */
    private Integer serving_duration_minutes;


}
