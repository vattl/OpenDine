package com.lanf.printing.model;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.List;

/**
 * 统一出票调度请求 DTO
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UnifiedPrintRequest implements Serializable {

    private static final long serialVersionUID = 1L;

    /** 订单号 (业务流水号) */
    @JsonProperty("order_no")
    @JsonAlias({"orderNo", "order_sn", "orderSn"})
    private String orderNo;

    /** 订单主键 ID */
    @JsonProperty("order_id")
    @JsonAlias({"orderId", "id"})
    private Long orderId;

    /**
     * 场景编码 (可选，若不传则后端依据上下文智能推导，默认推导为 kitchen)
     * 可选值见 {@link PrintScenario}：kitchen, checkout, pre_checkout, full_order, packing, takeout, expedite, refund, shift, label, test
     */
    private String scenario;

    /** 是否为补打单据 (默认 true，补打时小票自动印上【补打】标识、补打人与补打时间) */
    @JsonProperty("is_reprint")
    @JsonAlias({"isReprint", "reprint"})
    @Builder.Default
    private Boolean isReprint = Boolean.TRUE;

    /** 厨房打印指定分类过滤 (可选，仅包含指定分类 ID 的菜品出单) */
    @JsonProperty("cid_list")
    @JsonAlias({"cidList", "cids"})
    private List<String> cidList;

    /** 交接班 ID (可选，未指定且为 shift 场景时自动取当前活跃班次) */
    @JsonProperty("shift_id")
    @JsonAlias({"shiftId"})
    private Long shiftId;

    /** 定向设备 ID (可选，若指定则直接下发到该设备，覆盖出票规则) */
    @JsonProperty("device_id")
    @JsonAlias({"deviceId"})
    private Long deviceId;

    /** 定向模板 ID (可选，若指定则直接使用该模板，覆盖场景默认模板) */
    @JsonProperty("template_id")
    @JsonAlias({"templateId"})
    private Long templateId;

    /** 出单联数 (可选，覆盖默认配置份数) */
    private Integer copies;

    /** 补打或操作原因 */
    private String reason;

    /** 幂等防重键 */
    @JsonProperty("idempotency_key")
    @JsonAlias({"idempotencyKey", "requestId"})
    private String idempotencyKey;

    /** 自定义打印内容文本 (仅自定义文本场景使用) */
    @JsonProperty("custom_content")
    @JsonAlias({"customContent", "content"})
    private String customContent;
}
