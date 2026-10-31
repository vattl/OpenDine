package com.lanf.receivable.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_receivable_ledger")
public class ReceivableLedger {
    public static final String TYPE_CHARGE = "CHARGE";
    public static final String TYPE_COLLECTION = "COLLECTION";
    public static final String TYPE_REVERSAL = "REVERSAL";
    public static final String TYPE_WRITE_OFF = "WRITE_OFF";

    @TableId(type = IdType.AUTO)
    private Long id;
    @TableField("ledger_no")
    private String ledgerNo;
    @TableField("request_id")
    private String requestId;
    @TableField("merchant_id")
    private String merchantId;
    @TableField("shop_id")
    private Integer shopId;
    @TableField("account_id")
    private Long accountId;
    @TableField("claim_id")
    private Long claimId;
    @TableField("order_id")
    private Long orderId;
    @TableField("order_no")
    private String orderNo;
    @TableField("entry_type")
    private String entryType;
    /** CHARGE 为正；COLLECTION、REVERSAL、WRITE_OFF 为负。 */
    @TableField("amount_fen")
    private Long amountFen;
    private String channel;
    @TableField("drawer_session_id")
    private Long drawerSessionId;
    @TableField("operator_id")
    private Integer operatorId;
    @TableField("business_day")
    private String businessDay;
    private String note;
    @TableField("original_ledger_id")
    private Long originalLedgerId;
    @TableField("occurred_at")
    private Date occurredAt;
    @TableField("created_at")
    private Date createdAt;
}
