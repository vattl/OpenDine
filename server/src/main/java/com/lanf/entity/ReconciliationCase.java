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
 * 对账差异处理单实体 (t_reconciliation_case)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_reconciliation_case")
public class ReconciliationCase {

    // 状态
    public static final String STATUS_OPEN = "OPEN";
    public static final String STATUS_INVESTIGATING = "INVESTIGATING";
    public static final String STATUS_ADJUSTED = "ADJUSTED";
    public static final String STATUS_WRITTEN_OFF = "WRITTEN_OFF";
    public static final String STATUS_CLOSED = "CLOSED";

    // 层级
    public static final int LAYER_ORDER_VS_LEDGER = 1;
    public static final int LAYER_LEDGER_VS_CHANNEL = 2;
    public static final int LAYER_CHANNEL_VS_SETTLEMENT = 3;

    // 差异类型
    public static final String TYPE_ORDER_LEDGER_MISMATCH = "ORDER_LEDGER_MISMATCH";
    public static final String TYPE_INTERNAL_MISSING = "INTERNAL_MISSING";
    public static final String TYPE_CHANNEL_MISSING = "CHANNEL_MISSING";
    public static final String TYPE_AMOUNT_MISMATCH = "AMOUNT_MISMATCH";
    public static final String TYPE_DUPLICATE_TRANSACTION = "DUPLICATE_TRANSACTION";
    public static final String TYPE_REFUND_STATUS_MISMATCH = "REFUND_STATUS_MISMATCH";
    public static final String TYPE_FEE_MISMATCH = "FEE_MISMATCH";
    public static final String TYPE_TIMING_DIFFERENCE = "TIMING_DIFFERENCE";

    @TableId(type = IdType.AUTO)
    private Long id;

    private String case_no;

    private Integer shop_id;

    private Date business_day;

    private String channel;

    private Integer layer;

    private String discrepancy_type;

    private String status;

    private Long order_id;

    private Long ledger_id;

    private Long statement_entry_id;

    private Integer internal_amount_fen;

    private Integer channel_amount_fen;

    private Integer difference_fen;

    private String reason;

    private String resolution_note;

    private String responsible_person;

    private Integer assigned_to;

    private Integer resolved_by;

    private Date resolved_at;

    private Date created_at;

    private Date updated_at;
}
