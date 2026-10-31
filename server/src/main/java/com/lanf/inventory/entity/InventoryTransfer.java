package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 调拨单，对应 t_inventory_transfer。
 * 禁止跨经营主体（TRANSFER_LEGAL_ENTITY_MISMATCH）；两仓同店创建即 IN_TRANSIT，否则 OUTBOUND。
 * items_json: [{batchId,materialId,qty,fefoOverrideReason}]
 */
@TableName("t_inventory_transfer")
@Data
public class InventoryTransfer {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    /** 调出仓库 t_inventory_warehouse.id */
    private Long from_warehouse_id;

    /** 调入仓库 t_inventory_warehouse.id */
    private Long to_warehouse_id;

    /** OUTBOUND 已出库 / IN_TRANSIT 在途 / RECEIVED 已收货 */
    private String status;

    /** 明细 JSON */
    private String items_json;

    private Integer created_by;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
