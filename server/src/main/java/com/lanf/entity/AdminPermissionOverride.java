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
 * 员工级显式权限覆盖实体，对应 t_admin_permission_override
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_admin_permission_override")
public class AdminPermissionOverride {

    public static final String EFFECT_ALLOW = "ALLOW";
    public static final String EFFECT_DENY = "DENY";

    public static final String SOURCE_MANUAL = "MANUAL";
    public static final String SOURCE_TEMP_GRANT = "TEMP_GRANT";
    public static final String SOURCE_SECURITY_BLOCK = "SECURITY_BLOCK";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 管理员ID */
    private Integer admin_id;

    /** 权限码 */
    private String permission_code;

    /** 覆盖效果: ALLOW/DENY */
    private String effect;

    /** 指定门店ID (NULL表示全局) */
    private Integer shop_id;

    /** 特定覆盖策略JSON (可选) */
    private String policy_json;

    /** 生效开始时间 */
    private Date valid_from;

    /** 生效截止时间 */
    private Date valid_until;

    /** 覆盖来源: MANUAL, TEMP_GRANT, SECURITY_BLOCK */
    private String source;

    /** 覆盖原因 */
    private String reason;

    /** 创建者管理员ID */
    private Integer created_by;

    private Date created_at;
}
