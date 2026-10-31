package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 外卖配送扩展，与 dineInOrTakeOut=外卖 的 t_order 一对一，对应 t_takeout_delivery。
 */
@Data
@TableName("t_takeout_delivery")
public class TakeoutDelivery {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer order_id;

    private String order_no;

    private Integer shop_id;

    private Long user_address_id;

    private String receiver_name;

    private String receiver_phone;

    private String address_full;

    private BigDecimal lng;

    private BigDecimal lat;

    private BigDecimal delivery_fee;

    /**
     * submitted=已下单待支付；paid=已支付；accepted=商家已接单；delivering=配送中；
     * completed=已完成；cancelled=已取消；dispatch_failed=配送异常（如骑手取消，可重发）
     */
    private String dispatch_status;

    private String merchant_remark;

    /** 真省钱 openOrderId */
    private Long zsq_open_order_id;

    private String zsq_order_id;

    private String zsq_shop_number;

    private String zsq_parent_order_no;

    private String zsq_delivery_codes_json;

    private String zsq_quote_json;

    private String zsq_dispatch_json;

    private Integer zsq_delivery_send_status;

    private String zsq_phase;

    /** none|pending|dispatched|failed|rider_cancelled|order_missing|completed */
    private String zsq_dispatch_status;

    private String zsq_rider_name;

    private String zsq_rider_phone;

    private BigDecimal zsq_rider_lat;

    private BigDecimal zsq_rider_lng;

    private Date zsq_rider_updated_at;

    private String zsq_last_error;

    private Integer zsq_dispatch_attempts;

    /** 真省钱取消责任扣费（元），从用户退款金额中扣除 */
    private BigDecimal zsq_liability_fee;

    /** 真省钱实际跑腿费用（元），来自 shopActualCost/discountLastMoney */
    private BigDecimal zsq_actual_fee;

    /** 真省钱实际配送运力渠道（如京东特惠、美团等），来自 deliverySupplierName */
    private String zsq_delivery_supplier_name;

    private String zsq_cancel_prompt;

    private String zsq_cancel_json;

    private Date created_at;

    private Date updated_at;

    /**
     * 实际配送费（语义别名，取自 zsq_actual_fee），非表字段，方便接口统一返回 actual_delivery_fee
     */
    @TableField(exist = false)
    private BigDecimal actual_delivery_fee;

    public BigDecimal getActual_delivery_fee() {
        if (this.actual_delivery_fee != null) {
            return this.actual_delivery_fee;
        }
        return this.zsq_actual_fee;
    }

    public void setActual_delivery_fee(BigDecimal actual_delivery_fee) {
        this.actual_delivery_fee = actual_delivery_fee;
    }
}
