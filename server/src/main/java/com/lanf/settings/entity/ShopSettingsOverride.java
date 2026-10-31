package com.lanf.settings.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 门店设置覆盖行，对应 t_shop_settings。
 * 行存在即代表该门店对该模块做了「门店覆盖」（source=SHOP）；
 * 行不存在则继承总部/系统默认。
 */
@TableName("t_shop_settings")
@Data
public class ShopSettingsOverride {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    /** 模块标识，如 store */
    private String module;

    /** 覆盖配置 JSON（仅存被覆盖的字段） */
    private String payload_json;

    /** 乐观锁版本，从 1 起 */
    private Integer version;

    private Integer updated_by;

    private LocalDateTime updated_at;
}
