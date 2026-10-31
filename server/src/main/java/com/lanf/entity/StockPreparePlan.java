package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 原材料备货计划，对应 t_stock_prepare_plan
 */
@Data
@TableName("t_stock_prepare_plan")
public class StockPreparePlan {
    private Long id;
    private Integer shop_id;
    private Long run_id;
    private Date prepare_date;
    private Integer material_id;
    private BigDecimal current_stock;
    private BigDecimal forecast_consume;
    private BigDecimal safe_stock;
    private BigDecimal suggest_qty;
    private BigDecimal manual_adjust;
    private BigDecimal final_qty;
    private Integer status;
    private Integer operator_id;
    private Date created_at;
    private Date updated_at;
}
