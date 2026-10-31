package com.lanf.marketing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 首单活动，对应 t_first_order_campaign。
 */
@TableName("t_first_order_campaign")
@Data
public class FirstOrderCampaign {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private String name;
    private String campaign_type;
    private BigDecimal threshold_amount;
    private BigDecimal discount_value;
    private String discount_desc;
    private LocalDateTime start_time;
    private LocalDateTime end_time;
    private String status;
    private Integer version;
    private LocalDateTime created_at;
    private LocalDateTime updated_at;
}
