package com.lanf.receivable.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.receivable.entity.ReceivableClaim;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface ReceivableClaimMapper extends BaseMapper<ReceivableClaim> {
    @Select("SELECT COALESCE(SUM(outstanding_fen),0) FROM t_receivable_claim " +
            "WHERE merchant_id=#{merchantId} AND shop_id=#{shopId} " +
            "AND status IN ('OPEN','PARTIAL','OVERDUE')")
    Long sumOutstandingByShop(@Param("merchantId") String merchantId,
                              @Param("shopId") Integer shopId);
}
