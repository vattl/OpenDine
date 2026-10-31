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
 * 渠道对账单明细实体 (t_channel_statement_entry)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_channel_statement_entry")
public class ChannelStatementEntry {

    public static final String MATCH_STATUS_MATCHED = "MATCHED";
    public static final String MATCH_STATUS_UNMATCHED = "UNMATCHED";
    public static final String MATCH_STATUS_AMOUNT_MISMATCH = "AMOUNT_MISMATCH";
    public static final String MATCH_STATUS_TIMING_DIFFERENCE = "TIMING_DIFFERENCE";

    public static final String ENTRY_TYPE_PAYMENT = "PAYMENT";
    public static final String ENTRY_TYPE_REFUND = "REFUND";

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long batch_id;

    private Integer shop_id;

    private String channel;

    private String channel_trade_no;

    private String merchant_order_no;

    private String entry_type;

    private Integer amount_fen;

    private Integer fee_fen;

    private Integer net_amount_fen;

    private Date trade_time;

    private Long matched_ledger_id;

    private String match_status;

    private Date created_at;
}
