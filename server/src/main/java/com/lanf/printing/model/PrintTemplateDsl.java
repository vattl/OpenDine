package com.lanf.printing.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 打印模板 DSL 协议根模型
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class PrintTemplateDsl {

    /** 纸张规格：58mm / 80mm */
    private String paperSize = "58mm";

    /** 场景代码：ORDER / KITCHEN / SERVE / REFUND / SHIFT / LABEL / TEST */
    private String scenario = "ORDER";

    /** 是否自动切刀 */
    private Boolean autoCut = true;

    /** 是否蜂鸣提示 */
    private Boolean beeper = true;

    /** 飞鹅票尾语音：NONE / COMMON / MT / ELE / JD / CANCEL / REFUND。不会根据订单来源猜测。 */
    private String audio = "NONE";

    /** 底部留白走纸行数（1-5 行） */
    private Integer feedLines = 2;

    /** 模板模式：BLOCK（可视化区块模式，默认） / TEXT（纯文本模板模式） */
    private String mode = "BLOCK";

    /** 纯文本模板内容（当 mode 为 TEXT 时使用） */
    private String rawTemplate;

    /** 模板区块列表（按顺序渲染） */
    private List<TemplateBlock> blocks = new ArrayList<>();

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class TemplateBlock {
        /** 区块唯一 ID（如 block_header） */
        private String id;

        /** 区块类型：HEADER, ORDER_INFO, DISH_ITEMS, PAYMENT_SUMMARY, MEMBER_INFO, DELIVERY_INFO, REMARK, CUSTOM_TEXT, DIVIDER, QRCODE, FOOTER, CUT_PAPER */
        private String type;

        /** 区块显示名称（设计器中展示） */
        private String name;

        /** 是否启用该区块 */
        private Boolean enabled = true;

        /** 区块自定义属性参数 Map */
        private Map<String, Object> config;
    }
}
