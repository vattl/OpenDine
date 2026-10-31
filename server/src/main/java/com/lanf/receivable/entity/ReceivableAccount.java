package com.lanf.receivable.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_receivable_account")
public class ReceivableAccount {
    public static final String SCOPE_SHOP = "SHOP";
    public static final String SCOPE_MERCHANT = "MERCHANT";
    public static final String STATUS_ACTIVE = "ACTIVE";
    public static final String STATUS_SUSPENDED = "SUSPENDED";
    public static final String STATUS_CLOSED = "CLOSED";

    @TableId(type = IdType.AUTO)
    private Long id;
    @TableField("account_no")
    private String accountNo;
    @TableField("merchant_id")
    private String merchantId;
    @TableField("scope_type")
    private String scopeType;
    @TableField("shop_id")
    private Integer shopId;
    @TableField("customer_type")
    private String customerType;
    @TableField("customer_name")
    private String customerName;
    @TableField("contact_name")
    private String contactName;
    @TableField("contact_phone")
    private String contactPhone;
    @TableField("tax_no")
    private String taxNo;
    @TableField("credit_limit_fen")
    private Long creditLimitFen;
    @TableField("outstanding_fen")
    private Long outstandingFen;
    @TableField(exist = false)
    private Long availableLimitFen;

    public Long getAvailableLimitFen() {
        if (availableLimitFen != null) {
            return availableLimitFen;
        }
        if (creditLimitFen == null) {
            return 0L;
        }
        long outstanding = outstandingFen != null ? outstandingFen : 0L;
        return Math.max(0L, creditLimitFen - outstanding);
    }

    public void setAvailableLimitFen(Long availableLimitFen) {
        this.availableLimitFen = availableLimitFen;
    }

    @TableField("payment_terms_days")
    private Integer paymentTermsDays;
    private String status;
    private String notes;
    private Integer version;
    @TableField("created_by")
    private Integer createdBy;
    @TableField("updated_by")
    private Integer updatedBy;
    @TableField("created_at")
    private Date createdAt;
    @TableField("updated_at")
    private Date updatedAt;
    @TableField("closed_at")
    private Date closedAt;
}
