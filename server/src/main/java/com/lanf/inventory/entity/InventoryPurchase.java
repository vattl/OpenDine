package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 采购单，对应 t_inventory_purchase。
 * 默认启用审核：新建即 PENDING_REVIEW；状态机
 * PENDING_REVIEW -approve→ APPROVED -receive→ RECEIVED；PENDING_REVIEW -reject→ REJECTED。
 * audit_json: [{action,fromStatus,toStatus,adminId,at,reason}]
 */
@TableName("t_inventory_purchase")
@Data
public class InventoryPurchase {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    /** 供应商 t_inventory_supplier.id */
    private Long supplier_id;

    /** 收货仓库 t_inventory_warehouse.id */
    private Long warehouse_id;

    /** DRAFT/PENDING_REVIEW/APPROVED/REJECTED/RECEIVED */
    private String status;

    /** 明细 JSON [{materialId,qty,unit,price,remark}] */
    private String items_json;

    /** 审核记录 JSON */
    private String audit_json;

    private Integer created_by;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
