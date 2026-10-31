package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 入库记录，对应 t_stock_in
 */
@Data
@TableName("t_stock_in")
public class StockIn {
    private Long id;
    private Integer shop_id;
    private Integer material_id;
    private BigDecimal quantity;
    private BigDecimal price;
    private BigDecimal total_amount;
    private String remark;
    private Integer operator_id;
    private Date created_at;
}
