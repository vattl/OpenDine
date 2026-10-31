package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 供应商，对应 t_inventory_supplier。
 * settlement_info（结算字段）仅 inventory:manage 权限可见（协调文档 §2）。
 */
@TableName("t_inventory_supplier")
@Data
public class InventorySupplier {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private String name;

    private String contact_name;

    private String contact_phone;

    /** 供货范围描述 */
    private String supply_scope;

    /** 结算信息（结算方式/账期/账户摘要），敏感字段按权限过滤 */
    private String settlement_info;

    /** ENABLED 启用 / DISABLED 停用 */
    private String status;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
