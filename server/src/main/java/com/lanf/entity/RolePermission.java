package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 角色-权限关联，对应 t_role_permission（见 docs/db_diancan_permission.sql）
 */
@TableName("t_role_permission")
@Data
public class RolePermission {

    @TableId(type = IdType.AUTO)
    private Integer id;
    private Integer role_id;
    private Integer permission_id;
}
