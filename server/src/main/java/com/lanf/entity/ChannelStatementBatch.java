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
 * 渠道对账单导入批次实体 (t_channel_statement_batch)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_channel_statement_batch")
public class ChannelStatementBatch {

    public static final String STATUS_PARSED = "PARSED";
    public static final String STATUS_FAILED = "FAILED";

    @TableId(type = IdType.AUTO)
    private Long id;

    private String batch_no;

    private Integer shop_id;

    private String channel;

    private Date statement_date;

    private String file_name;

    private String file_hash_sha256;

    private Integer total_count;

    private Long total_amount_fen;

    private Long fee_fen;

    private Long net_amount_fen;

    private String status;

    private String error_summary;

    private Integer imported_by;

    private Date imported_at;

    private Date created_at;
}
