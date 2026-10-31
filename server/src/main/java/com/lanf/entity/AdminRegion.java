package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 管理员区域绑定，对应 t_admin_region。
 */
@Data
@TableName("t_admin_region")
public class AdminRegion {

    @TableId(type = IdType.AUTO)
    private Integer id;
    private Integer admin_id;
    private Integer region_id;
}
