package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 支付渠道测试交易记录，对应 t_payment_test_txn（幂等键唯一）。
 */
@TableName("t_payment_test_txn")
@Data
public class PaymentTestTxnEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private String channel_code;
    private BigDecimal amount;
    private String terminal;
    private String idempotency_key;
    private String status;
    private String charge_status;
    private String refund_status;
    private String error;
    private Integer created_by;
    private LocalDateTime created_at;
    private LocalDateTime updated_at;
}
