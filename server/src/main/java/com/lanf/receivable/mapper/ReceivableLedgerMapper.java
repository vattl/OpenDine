package com.lanf.receivable.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.receivable.entity.ReceivableLedger;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Date;
import java.util.Map;

public interface ReceivableLedgerMapper extends BaseMapper<ReceivableLedger> {
    @Select("SELECT " +
            "COALESCE(SUM(CASE WHEN entry_type='CHARGE' THEN amount_fen ELSE 0 END),0) charged_fen," +
            "COALESCE(-SUM(CASE WHEN entry_type='COLLECTION' THEN amount_fen ELSE 0 END),0) collected_fen," +
            "COALESCE(-SUM(CASE WHEN entry_type='WRITE_OFF' THEN amount_fen ELSE 0 END),0) writeoff_fen," +
            "COALESCE(-SUM(CASE WHEN entry_type='REVERSAL' THEN amount_fen ELSE 0 END),0) reversed_fen," +
            "COALESCE(MAX(id),0) cutoff_ledger_id " +
            "FROM t_receivable_ledger WHERE merchant_id=#{merchantId} AND shop_id=#{shopId} " +
            "AND occurred_at >= #{start} AND occurred_at < #{end}")
    Map<String, Object> summarizeWindow(@Param("merchantId") String merchantId,
                                        @Param("shopId") Integer shopId,
                                        @Param("start") Date start,
                                        @Param("end") Date end);
}
