package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Date;

/**
 * 权限策略实体，对应 t_access_policy
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_access_policy")
public class AccessPolicy {

    public static final String TYPE_MAX_AMOUNT = "MAX_AMOUNT";
    public static final String TYPE_MIN_DISCOUNT_RATE = "MIN_DISCOUNT_RATE";
    public static final String TYPE_MAX_DISCOUNT_AMOUNT = "MAX_DISCOUNT_AMOUNT";
    public static final String TYPE_MAX_DAILY_COUNT = "MAX_DAILY_COUNT";
    public static final String TYPE_ORDER_STATUS = "ORDER_STATUS";
    public static final String TYPE_TIME_WINDOW = "TIME_WINDOW";

    public static final String EFFECT_ALLOW = "ALLOW";
    public static final String EFFECT_DENY = "DENY";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 策略唯一编码 */
    private String policy_code;

    /** 策略名称 */
    private String policy_name;

    /** 绑定的功能权限码 */
    private String permission_code;

    /** 策略类型: MAX_AMOUNT, MIN_DISCOUNT_RATE, MAX_DISCOUNT_AMOUNT等 */
    private String policy_type;

    /** 默认作用: ALLOW / DENY */
    private String effect;

    /** 优先级，数值越小优先级越高 (默认100) */
    private Integer priority;

    /** 是否启用 1=启用 0=禁用 */
    private Integer enabled;

    /** 策略配置规则JSON */
    private String config_json;

    private Date created_at;
    private Date updated_at;
}
