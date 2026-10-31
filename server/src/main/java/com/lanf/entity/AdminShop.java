package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 管理员可管门店，对应 t_admin_shop（见 docs/db_diancan_chain_store_patch.sql）。
 */
@Data
@TableName("t_admin_shop")
public class AdminShop {

    @TableId(type = IdType.AUTO)
    private Integer id;
    private Integer admin_id;
    private Integer shop_id;
}
