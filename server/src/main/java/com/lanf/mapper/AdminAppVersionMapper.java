package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.AdminAppVersion;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface AdminAppVersionMapper extends BaseMapper<AdminAppVersion> {

    @Select("SELECT * FROM t_admin_app_version WHERE platform=#{platform} AND channel=#{channel} "
            + "AND enabled=1 ORDER BY updated_at DESC,id DESC LIMIT 1")
    AdminAppVersion findCurrent(@Param("platform") String platform, @Param("channel") String channel);

    @Select("SELECT * FROM t_admin_app_version WHERE platform=#{platform} AND channel=#{channel} "
            + "AND enabled=1 AND (gray_shop_ids IS NULL OR TRIM(gray_shop_ids) = '') "
            + "ORDER BY updated_at DESC,id DESC LIMIT 1")
    AdminAppVersion findCurrentGeneral(@Param("platform") String platform, @Param("channel") String channel);

    @Select("SELECT * FROM t_admin_app_version WHERE platform=#{platform} "
            + "AND enabled=1 ORDER BY updated_at DESC,id DESC LIMIT 1")
    AdminAppVersion findCurrentByPlatform(@Param("platform") String platform);

    @Select("SELECT * FROM t_admin_app_version WHERE platform=#{platform} "
            + "AND enabled=1 AND (gray_shop_ids IS NULL OR TRIM(gray_shop_ids) = '') "
            + "ORDER BY updated_at DESC,id DESC LIMIT 1")
    AdminAppVersion findCurrentGeneralByPlatform(@Param("platform") String platform);
}
