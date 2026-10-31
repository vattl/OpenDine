package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 角色实体，对应 t_role（见 docs/db_diancan_permission.sql）
 */
@TableName("t_role")
@Data
public class Role {

    @TableId(type = IdType.AUTO)
    private Integer id;
    /** 角色编码，如 super_admin, order_manager */
    private String role_code;
    /** 角色名称 */
    private String role_name;
    private String remark;
    private Integer sort_order;
    public static final String TYPE_SYSTEM = "SYSTEM";
    public static final String TYPE_CUSTOM = "CUSTOM";

    /** 乐观锁版本（db_migration_access_extension.sql 加列；默认 1） */
    private Integer version;

    /** 角色类型: SYSTEM, CUSTOM */
    private String role_type;

    /** 是否允许编辑 1=允许 0=禁止 */
    private Integer editable;

    /** 是否系统受保护角色(不可删除) 1=是 0=否 */
    private Integer system_protected;

    /** 角色优先级(数值越小优先级越高) */
    private Integer priority;
}
