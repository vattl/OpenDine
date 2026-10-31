package com.lanf.printing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 打印小票模板配置，对应 t_printing_template。
 */
@TableName("t_printing_template")
@Data
public class PrintingTemplate {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 门店 ID（0 为系统内置通用模板，>0 为门店自定义） */
    private Integer shop_id;

    /** 模板唯一标识编码（如 tpl_order_default） */
    private String template_code;

    /** 模板名称 */
    private String template_name;

    /** 适用场景：ORDER / KITCHEN / SERVE / REFUND / SHIFT / LABEL / TEST */
    private String scenario;

    /** 纸张规格：58mm / 80mm */
    private String paper_size;

    /** 是否系统内置：1 是，0 否 */
    private Integer is_system;

    /** 是否场景默认模板：1 是，0 否 */
    private Integer is_default;

    /** 模板 JSON 结构（包含 blocks 列表、样式及字段开关） */
    private String template_json;

    /** 乐观锁版本号 */
    private Integer version;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
