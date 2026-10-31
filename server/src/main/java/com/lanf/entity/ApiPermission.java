package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 接口-权限映射实体，对应 t_api_permission（见 docs/db_diancan.sql）
 */
@TableName("t_api_permission")
@Data
public class ApiPermission {

    @TableId(type = IdType.AUTO)
    private Integer id;

    /** 请求方法，如 GET/POST/PUT/DELETE */
    private String method;

    /** 路径模式，如 /admin/order/list */
    private String path_pattern;

    /** 所需权限码，如 order:view */
    private String permission_code;

    /** 接口备注，前端展示用 */
    private String remark;
}

