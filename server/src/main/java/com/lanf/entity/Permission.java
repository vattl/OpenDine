package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 权限实体，对应 t_permission（见 docs/db_diancan_permission.sql）
 */
@TableName("t_permission")
@Data
public class Permission {

    @TableId(type = IdType.AUTO)
    private Integer id;
    /** 权限编码，如 order:view, dish:manage */
    private String permission_code;
    /** 权限名称 */
    private String permission_name;
    private String module;
    private String remark;
    private Integer sort_order;
}
