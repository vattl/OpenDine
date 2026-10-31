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
 * 历史账本回填执行日志，对应 t_ledger_backfill_log (POS-SDC-501)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_ledger_backfill_log")
public class LedgerBackfillLog {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;
    private String stat_date;
    private Boolean dry_run;
    private Integer total_orders_scanned;
    private Integer backfilled_orders;
    private Integer skipped_orders;
    private Integer total_rows_inserted;
    private Long total_amount_fen;
    private Integer anomalies_count;
    private String anomalies_json;
    private String integrity_hash;
    private Integer executed_by;
    private Date executed_at;
}
