package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 仓库，对应 t_inventory_warehouse。
 * legal_entity（经营主体）为调拨约束维度：跨经营主体调拨必败（TRANSFER_LEGAL_ENTITY_MISMATCH）。
 */
@TableName("t_inventory_warehouse")
@Data
public class InventoryWarehouse {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private String name;

    /** 经营主体 */
    private String legal_entity;

    private String address;

    /** ENABLED 启用 / DISABLED 停用 */
    private String status;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
