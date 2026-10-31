package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 批次，对应 t_inventory_batch。
 * FEFO：按 expiry_date 升序消耗；调拨收货在目标仓生成新批次并沿用源批次到期日。
 */
@TableName("t_inventory_batch")
@Data
public class InventoryBatch {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    /** 原材料 t_material.id */
    private Integer material_id;

    /** 所属仓库 t_inventory_warehouse.id */
    private Long warehouse_id;

    private String batch_no;

    /** 剩余可用数量 */
    private BigDecimal qty;

    /** 到期日（FEFO 升序；NULL 排最后） */
    private LocalDate expiry_date;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
