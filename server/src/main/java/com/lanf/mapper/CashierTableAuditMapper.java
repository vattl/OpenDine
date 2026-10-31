package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.CashierTableAudit;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface CashierTableAuditMapper extends BaseMapper<CashierTableAudit> {

    @Select("SELECT * FROM t_operation_log WHERE shop_id=#{shopId} AND module='cashier_table' " +
            "AND action=#{action} AND request_key=#{requestKey} ORDER BY id DESC LIMIT 1")
    CashierTableAudit findByRequest(@Param("shopId") Integer shopId,
                                    @Param("action") String action,
                                    @Param("requestKey") String requestKey);
}
