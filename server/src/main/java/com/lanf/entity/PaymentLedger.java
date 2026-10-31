package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Date;

/**
 * 不可变支付账本实体，对应 t_payment_ledger (POS-SDC-101)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_payment_ledger")
public class PaymentLedger {

    public static final String ENTRY_TYPE_PAYMENT = "PAYMENT";
    public static final String ENTRY_TYPE_REFUND = "REFUND";
    public static final String ENTRY_TYPE_REVERSAL = "REVERSAL";
    public static final String ENTRY_TYPE_ADJUSTMENT = "ADJUSTMENT";

    public static final String CHANNEL_CASH = "CASH";
    public static final String CHANNEL_WECHAT = "WECHAT";
    public static final String CHANNEL_ALIPAY = "ALIPAY";
    public static final String CHANNEL_WECHAT_QR = "WECHAT_QR";
    public static final String CHANNEL_ALIPAY_QR = "ALIPAY_QR";
    public static final String CHANNEL_BALANCE_PRINCIPAL = "BALANCE_PRINCIPAL";
    public static final String CHANNEL_GIFT = "GIFT";
    public static final String CHANNEL_OTHER = "OTHER";

    public static final String STATUS_SUCCEEDED = "SUCCEEDED";
    public static final String STATUS_FAILED = "FAILED";
    public static final String STATUS_PENDING = "PENDING";

    public static final String SOURCE_NATIVE = "NATIVE";
    public static final String SOURCE_BACKFILLED_ORDER = "BACKFILLED_ORDER";
    public static final String SOURCE_MANUAL = "MANUAL";

    public static final String TRUST_HIGH = "TRUST_HIGH";
    public static final String TRUST_MEDIUM = "TRUST_MEDIUM";
    public static final String TRUST_SUSPECT = "TRUST_SUSPECT";

    @TableId(type = IdType.AUTO)
    private Long id;

    private String ledger_no;
    private String request_id;
    private Integer shop_id;
    private Long order_id;
    private String order_no;
    private String terminal_id;
    private Long drawer_session_id;
    private Long employee_shift_id;
    private Integer operator_id;
    private String entry_type;
    private String channel;
    private Integer amount_fen;
    private String status;
    private String source;
    private String trust_level;
    private String provider_transaction_id;
    private Long original_ledger_id;
    private Date occurred_at;
    private String business_day;
    private Date created_at;
}
