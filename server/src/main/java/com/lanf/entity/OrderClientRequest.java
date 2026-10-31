package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** Durable response snapshot for mobile cashier request idempotency. */
@TableName("t_order_client_request")
@Data
public class OrderClientRequest {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Integer admin_id;
    private String client_request_id;
    private String request_path;
    private String request_fingerprint;
    private String status;
    private String response_snapshot;
    private Date expires_at;
    private Date created_at;
    private Date updated_at;
}
