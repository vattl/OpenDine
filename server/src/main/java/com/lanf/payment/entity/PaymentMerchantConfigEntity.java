package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_payment_merchant_config")
public class PaymentMerchantConfigEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private String channel;

    private String merchant_key;

    private Integer enabled;

    /** ACTIVE | RETIRED；退役保留历史交易所需凭据。 */
    private String status;

    /** 凭据版本，从 1 单调递增。 */
    private Integer credential_version;

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

    private String alipay_app_cert_ref;

    private String alipay_public_cert_ref;

    private String alipay_root_cert_ref;

    private String routing_rule_json;

    private Integer sort_order;

    private String remark;

    private Date created_at;

    private Date updated_at;
}
