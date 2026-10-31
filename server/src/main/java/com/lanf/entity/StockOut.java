package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 出库记录，对应 t_stock_out
 */
@Data
@TableName("t_stock_out")
public class StockOut {
    private Long id;
    private Integer shop_id;
    private Integer material_id;
    private BigDecimal quantity;
    private String reason;
    private String remark;
    private Integer operator_id;
    private Date created_at;
}
