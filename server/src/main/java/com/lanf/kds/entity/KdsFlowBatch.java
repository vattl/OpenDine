package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_flow_batch")
public class KdsFlowBatch {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Long ticket_id;

    private Integer detail_id;

    private Integer order_id;

    private Integer quantity;

    /** dine_in / pack / takeout */
    private String dining_channel;

    private String queue_status;

    private Date order_time;

    private Date prep_at;

    private Date cooked_at;

    private Date served_at;

    private String void_reason;

    private Date created_at;

    private Date updated_at;
}
