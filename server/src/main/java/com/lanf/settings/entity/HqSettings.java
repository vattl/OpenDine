package com.lanf.settings.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 总部级设置默认值，对应 t_hq_settings（module 为主键）。
 * 生效优先级：门店覆盖（t_shop_settings）&gt; 总部默认 &gt; 系统内置。
 */
@TableName("t_hq_settings")
@Data
public class HqSettings {

    /** 模块标识，如 store / printing / payment / notifications */
    @TableId(type = IdType.INPUT)
    private String module;

    /** 模块配置 JSON */
    private String payload_json;

    /** 乐观锁版本，从 1 起 */
    private Integer version;

    private Integer updated_by;

    private LocalDateTime updated_at;
}
