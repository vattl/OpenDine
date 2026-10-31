package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 收银员班次，对应 t_shift
 */
@Data
@TableName("t_shift")
public class Shift {
    private Long id;
    private Integer admin_id;
    @TableField(exist = false)
    private String admin_name;
    private Integer shop_id;
    private Date start_time;
    private Date end_time;
    private BigDecimal start_cash;
    private BigDecimal end_cash;
    private Integer order_count;
    private BigDecimal total_amount;
    private Long drawer_session_id;
    private String terminal_id;
    private String state;
    private String business_day;
    private Integer version;
    private Date created_at;
}
