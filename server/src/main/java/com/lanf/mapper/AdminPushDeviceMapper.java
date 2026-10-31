package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.AdminPushDevice;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

public interface AdminPushDeviceMapper extends BaseMapper<AdminPushDevice> {

    @Insert("INSERT INTO t_admin_push_device(admin_id,shop_id,device_token,platform,channel,app_version,device_model,enabled,last_registered_at) "
            + "VALUES(#{adminId},#{shopId},#{token},#{platform},#{channel},#{appVersion},#{deviceModel},1,NOW()) "
            + "ON DUPLICATE KEY UPDATE admin_id=VALUES(admin_id),shop_id=VALUES(shop_id),platform=VALUES(platform),"
            + "channel=VALUES(channel),app_version=VALUES(app_version),device_model=VALUES(device_model),"
            + "enabled=1,last_registered_at=NOW()")
    int register(@Param("adminId") Integer adminId, @Param("shopId") Integer shopId,
                 @Param("token") String token, @Param("platform") String platform,
                 @Param("channel") String channel, @Param("appVersion") String appVersion,
                 @Param("deviceModel") String deviceModel);

    @Update("UPDATE t_admin_push_device SET enabled=0,updated_at=NOW() "
            + "WHERE admin_id=#{adminId} AND device_token=#{token}")
    int unregister(@Param("adminId") Integer adminId, @Param("token") String token);

    @Select("SELECT * FROM t_admin_push_device WHERE shop_id=#{shopId} AND enabled=1")
    List<AdminPushDevice> listEnabledByShop(@Param("shopId") Integer shopId);
}
