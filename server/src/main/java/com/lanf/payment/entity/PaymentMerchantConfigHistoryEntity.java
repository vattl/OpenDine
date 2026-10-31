package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_payment_merchant_config_history")
public class PaymentMerchantConfigHistoryEntity {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long merchant_config_id;
    private Integer credential_version;
    private Integer shop_id;
    private String channel;
    private String merchant_key;
    private String app_id;
    private String mch_id;
    private String notify_url;
    private String refund_notify_url;
    private String api_v3_key_enc;
    private String api_v2_key_enc;
    private String serial_no;
    private String platform_pub_key_id;
    private String platform_pub_key_ref;
    private String private_key_ref;
    private String client_cert_p12_ref;
    private Date created_at;
}
