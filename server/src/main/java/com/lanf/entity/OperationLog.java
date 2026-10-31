package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 关键操作日志，对应 t_operation_log
 */
@Data
@TableName("t_operation_log")
public class OperationLog {
    private Long id;
    private Integer shop_id;
    private String module;
    private String action;
    private String target_id;
    private Integer admin_id;
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String admin_name;
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String operator_name;
    private String ip;
    private String request_snapshot;
    private String source_table;
    private String target_table;
    private String order_nos;
    private String before_state;
    private String after_state;
    private String result_status;
    private Integer result_code;
    private String reason;
    private String request_key;
    private String request_fingerprint;
    private String trace_id;
    private Date created_at;
}
