package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 支付记录，对应 t_payment
 */
@Data
@TableName("t_payment")
public class Payment {
    private Long id;
    private String order_no;
    private String payment_method;
    private BigDecimal amount;
    private String transaction_id;
    private Date pay_time;
    private Integer operator_id;
    private Integer shop_id;
    private Date created_at;
}
