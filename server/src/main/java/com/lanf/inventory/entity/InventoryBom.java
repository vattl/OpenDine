package com.lanf.inventory.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * BOM 版本，对应 t_inventory_bom。
 * 同 (shop_id, dish_id) 同时仅一个 ACTIVE 版本；历史版本 status=HISTORY。
 * items_json: [{materialId,qty,unit,alternates:[materialId…]}]
 */
@TableName("t_inventory_bom")
@Data
public class InventoryBom {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    /** 菜品 t_dish.id */
    private Integer dish_id;

    /** 版本号，同 (shop_id,dish_id) 内自 1 递增 */
    private Integer version_no;

    /** ACTIVE 有效 / HISTORY 历史 */
    private String status;

    /** BOM 明细 JSON */
    private String items_json;

    /** 生效时间 */
    private LocalDateTime effective_from;

    private Integer created_by;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
