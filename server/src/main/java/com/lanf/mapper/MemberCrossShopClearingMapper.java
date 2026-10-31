package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.MemberCrossShopClearing;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;
import java.util.Map;

public interface MemberCrossShopClearingMapper extends BaseMapper<MemberCrossShopClearing> {

    @Select("SELECT * FROM t_member_cross_shop_clearing WHERE order_no = #{orderNo}")
    List<MemberCrossShopClearing> selectByOrderNo(@Param("orderNo") String orderNo);

    @Select("<script>"
            + "SELECT source_shop_id, consume_shop_id, "
            + "IFNULL(SUM(principal_amount), 0) AS principal_amount, "
            + "IFNULL(SUM(gift_amount), 0) AS gift_amount, "
            + "IFNULL(SUM(total_amount), 0) AS total_amount, "
            + "COUNT(*) AS order_count "
            + "FROM t_member_cross_shop_clearing "
            + "<where>"
            + "  <if test='shopId != null and shopId &gt; 0'>"
            + "    AND (source_shop_id = #{shopId} OR consume_shop_id = #{shopId})"
            + "  </if>"
            + "  <if test='startDate != null and startDate != \"\"'>"
            + "    AND created_at &gt;= #{startDate}"
            + "  </if>"
            + "  <if test='endDate != null and endDate != \"\"'>"
            + "    AND created_at &lt;= #{endDate}"
            + "  </if>"
            + "</where>"
            + "GROUP BY source_shop_id, consume_shop_id"
            + "</script>")
    List<Map<String, Object>> summarizeCrossShopClearing(
            @Param("shopId") Integer shopId,
            @Param("startDate") String startDate,
            @Param("endDate") String endDate);
}
