package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.RealtimeNotification;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface RealtimeNotificationMapper extends BaseMapper<RealtimeNotification> {

    @Select("SELECT COALESCE(MAX(seq_id), 0) FROM t_realtime_notification")
    Long selectMaxSeqId();

    @Select("SELECT COALESCE(MAX(seq_id), 0) FROM t_realtime_notification WHERE (shop_id = #{shopId} OR shop_id = 0)")
    Long selectShopMaxSeqId(@Param("shopId") Integer shopId);
}
