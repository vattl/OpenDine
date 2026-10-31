package com.lanf.marketing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 首单核销/恢复记录，对应 t_first_order_redemption。
 */
@TableName("t_first_order_redemption")
@Data
public class FirstOrderRedemption {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Long campaign_id;
    private String customer_id;
    private String order_no;
    private Integer order_id;
    private BigDecimal amount;
    private String status;
    private String restored_reason;
    private LocalDateTime restored_at;
    private LocalDateTime created_at;
    private LocalDateTime updated_at;
}
