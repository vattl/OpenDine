package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_payment_merchant_policy")
public class PaymentMerchantPolicyEntity {
    @TableId
    private Integer shop_id;
    private Integer allow_global_fallback;
    private Date created_at;
    private Date updated_at;
}
