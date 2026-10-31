package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.OrderDetail;


import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import java.util.Date;

/**
 * 订单细表Mapper接口
 */
public interface OrderDetailMapper extends BaseMapper<OrderDetail> {

    /**
     * 统计指定用户未取消订单中某套餐的已购买份数
     */
    @Select("<script>" +
            "SELECT COALESCE(SUM(CAST(od.quantity AS SIGNED)), 0) " +
            "FROM t_order_detail od " +
            "INNER JOIN t_order o ON od.mId = o.id " +
            "WHERE o.openid = #{openid} " +
            "AND od.line_type = 'combo_header' " +
            "AND od.combo_id = #{comboId} " +
            "AND (od.line_status IS NULL OR od.line_status = 'normal') " +
            "AND (o.transac_status IS NULL OR o.transac_status != 'cancelled') " +
            "<if test='startTime != null'> AND o.order_time &gt;= #{startTime} </if>" +
            "</script>")
    Integer sumUserPurchasedComboQty(@Param("openid") String openid,
                                     @Param("comboId") Long comboId,
                                     @Param("startTime") Date startTime);
}
