package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

@Data
@TableName("t_payment_ninefold_config")
public class PaymentNinefoldEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Integer enabled;
    private BigDecimal pay_rate;
    private BigDecimal min_base_yuan;
    private String time_start;
    private String time_end;
    private String zone_id;
    private String eligible_dining_types;
    private Date updated_at;
}
