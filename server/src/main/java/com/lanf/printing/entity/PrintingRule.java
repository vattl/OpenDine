package com.lanf.printing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 打印规则（场景 → 设备/模板/份数），对应 t_printing_rule。
 * 门店规则集「整体保存」：PUT 以 shop 内各行 version 最大值为整体乐观锁基准，
 * 保存时整组替换，新行 version = 基准 + 1。
 */
@TableName("t_printing_rule")
@Data
public class PrintingRule {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** t_shop.id，门店隔离维度 */
    private Integer shop_id;

    /** 打印场景：order/kitchen/refund/shift… */
    private String scenario;

    /** t_printing_device.id，可为空（暂不指派设备） */
    private Long device_id;

    /** 打印模板编码 */
    private String template_code;

    /** 打印份数，1-9 */
    private Integer copies;

    /** 是否启用：1 启用 / 0 停用 */
    private Integer enabled;

    /** 乐观锁版本 */
    private Integer version;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
