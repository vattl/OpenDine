package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.SystemConfig;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

/**
 * 系统配置 Mapper，对应 t_system_config
 */
public interface SystemConfigMapper extends BaseMapper<SystemConfig> {

    @Select("SELECT id, config_key, config_value, remark FROM t_system_config")
    List<SystemConfig> selectAllLegacy();

    @Select("SELECT id, config_key, config_value, remark FROM t_system_config WHERE config_key = #{key} LIMIT 1")
    SystemConfig selectLegacyByKey(@Param("key") String key);

    @Insert("INSERT INTO t_system_config (config_key, config_value, remark) VALUES (#{key}, #{value}, #{remark})")
    int insertLegacy(@Param("key") String key, @Param("value") String value, @Param("remark") String remark);

    @Update("UPDATE t_system_config SET config_value = #{value}, remark = #{remark} WHERE config_key = #{key}")
    int updateLegacy(@Param("key") String key, @Param("value") String value, @Param("remark") String remark);

    @Select("SELECT id, shop_id, config_key, config_value, remark FROM t_system_config "
            + "WHERE shop_id = #{shopId} AND config_key = #{key} LIMIT 1")
    SystemConfig selectByShopAndKey(@Param("shopId") int shopId, @Param("key") String key);
}

