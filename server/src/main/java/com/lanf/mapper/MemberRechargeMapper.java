package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.MemberRecharge;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Date;
import java.util.Map;

public interface MemberRechargeMapper extends BaseMapper<MemberRecharge> {

    @Select("SELECT COUNT(*) AS success_count, "
            + "COALESCE(SUM(recharge_amount), 0) AS principal_amount, "
            + "COALESCE(SUM(gift_amount), 0) AS gift_amount "
            + "FROM t_member_recharge "
            + "WHERE shop_id = #{shopId} AND status = 'success' AND pay_time IS NOT NULL "
            + "AND pay_time >= #{startInclusive} AND pay_time < #{endExclusive}")
    Map<String, Object> summarizeSuccessfulByWindow(@Param("shopId") Integer shopId,
                                                    @Param("startInclusive") Date startInclusive,
                                                    @Param("endExclusive") Date endExclusive);

    @Select("SELECT COUNT(*) AS success_count, "
            + "COALESCE(SUM(recharge_amount), 0) AS principal_amount, "
            + "COALESCE(SUM(gift_amount), 0) AS gift_amount "
            + "FROM t_member_recharge WHERE drawer_session_id = #{drawerSessionId} AND status = 'success'")
    Map<String, Object> summarizeSuccessfulByDrawerSession(@Param("drawerSessionId") Long drawerSessionId);
}
