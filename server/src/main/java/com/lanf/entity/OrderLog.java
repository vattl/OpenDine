package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 订单操作日志，对应 t_order_log
 */
@Data
@TableName("t_order_log")
public class OrderLog {
    private Long id;
    private Integer shop_id;
    private String order_no;
    private String action;
    private String operator_type;
    private String operator_id;
    @TableField(exist = false)
    private String operator_name;
    private String remark;
    private Date created_at;
}
