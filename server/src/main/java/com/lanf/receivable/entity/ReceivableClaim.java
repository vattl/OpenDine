package com.lanf.receivable.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_receivable_claim")
public class ReceivableClaim {
    public static final String STATUS_OPEN = "OPEN";
    public static final String STATUS_PARTIAL = "PARTIAL";
    public static final String STATUS_SETTLED = "SETTLED";
    public static final String STATUS_OVERDUE = "OVERDUE";
    public static final String STATUS_WRITTEN_OFF = "WRITTEN_OFF";
    public static final String STATUS_REVERSED = "REVERSED";

    @TableId(type = IdType.AUTO)
    private Long id;
    @TableField("claim_no")
    private String claimNo;
    @TableField("request_id")
    private String requestId;
    @TableField("active_key")
    private String activeKey;
    @TableField("merchant_id")
    private String merchantId;
    @TableField("shop_id")
    private Integer shopId;
    @TableField("account_id")
    private Long accountId;
    @TableField("order_id")
    private Long orderId;
    @TableField("order_no")
    private String orderNo;
    @TableField("original_amount_fen")
    private Long originalAmountFen;
    @TableField("outstanding_fen")
    private Long outstandingFen;
    @TableField("due_date")
    private Date dueDate;
    private String status;
    private String note;
    private Integer version;
    @TableField("charged_by")
    private Integer chargedBy;
    @TableField("charged_at")
    private Date chargedAt;
    @TableField("settled_at")
    private Date settledAt;
    @TableField("updated_at")
    private Date updatedAt;
}
