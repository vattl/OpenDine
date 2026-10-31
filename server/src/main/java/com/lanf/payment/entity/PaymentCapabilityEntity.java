package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_payment_capability")
public class PaymentCapabilityEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Integer online_pay_enabled;

    private Integer wechat_enabled;

    private Integer alipay_enabled;

    private Integer balance_enabled;

    private Integer combined_enabled;

    private Integer cashier_pay_enabled;

    private Integer cashier_wechat_enabled;

    private Integer cashier_alipay_enabled;

    private Integer cashier_balance_enabled;

    private Integer cashier_combined_enabled;

    private Integer mini_program_pay_enabled;

    private Integer mini_program_wechat_enabled;

    private Integer mini_program_balance_enabled;
    private Integer mini_program_alipay_enabled;

    private Integer offline_collect_enabled;

    private String offline_collect_channels;
    private Integer cashier_wechat_qr_enabled;
    private Integer cashier_alipay_qr_enabled;

    private String disabled_message;

    private Date updated_at;
}
