package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.FieldStrategy;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_wechat_jsapi_payment_attempt")
public class WechatJsapiPaymentAttemptEntity {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Integer order_id;
    private String order_no;
    private String out_trade_no;
    private String merchant_id;
    private Long merchant_config_id;
    private String merchant_key;
    private Integer merchant_config_version;
    private Integer amount_fen;
    private String payer_openid;
    private String prepay_id;
    private String status;
    private String trade_state;
    private String transaction_id;
    @TableField(updateStrategy = FieldStrategy.IGNORED)
    private String active_key;
    private Date expires_at;
    private Date success_time;
    private Date last_queried_at;
    private Date created_at;
    private Date updated_at;
}
