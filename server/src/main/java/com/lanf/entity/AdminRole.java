package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 管理员-角色关联，对应 t_admin_role（见 docs/db_diancan_permission.sql）
 */
@TableName("t_admin_role")
@Data
public class AdminRole {

    @TableId(type = IdType.AUTO)
    private Integer id;
    private Integer admin_id;
    private Integer role_id;
}
