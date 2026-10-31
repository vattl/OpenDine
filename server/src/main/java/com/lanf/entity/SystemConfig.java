package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 系统配置表，对应 t_system_config（见 docs/db_diancan.sql）
 * 用于持久化基础配置（如飞鹅云、邀请海报等），避免仅在内存生效。
 */
@TableName("t_system_config")
@Data
public class SystemConfig {

    @TableId(type = IdType.AUTO)
    private Integer id;

    /** 0=全门店默认，>0=t_shop.id */
    private Integer shop_id;

    private String config_key;

    private String config_value;

    private String remark;
}

