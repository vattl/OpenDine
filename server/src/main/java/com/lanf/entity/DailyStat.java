package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 日结对账，对应 t_daily_stat
 */
@Data
@TableName("t_daily_stat")
public class DailyStat {
    private Long id;
    private Date stat_date;
    private Integer shop_id;
    private BigDecimal total_amount;
    private BigDecimal discount_amount;
    private BigDecimal refund_amount;
    private BigDecimal material_cost;
    private Date settled_at;
    private Integer operator_id;
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String operator_name;
    private Long snapshot_id;
    private Date created_at;
}
