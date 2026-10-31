package com.lanf.realtime;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

/**
 * 统一实时消息通道标准信封协议（Unified Message Envelope v1）。
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.ALWAYS)
public class UnifiedMessageEnvelope {

    /** 帧类型：EVENT / CONNECTED / PONG / ACK_RESULT / CONTEXT_BOUND */
    private String frame_type;

    /** 全局唯一幂等键 */
    private String message_id;

    /** 单调递增游标（P3瞬态消息为0） */
    private Long seq_id;

    /** 服务端生成毫秒时间戳 */
    private Long timestamp;

    /** 过期毫秒时间戳 */
    private Long expire_at;

    /** 路由目标信息 */
    private Target target;

    /** 业务域：ORDER / COUPON / TABLE / KDS / MENU / TAKEOUT / SYSTEM */
    private String business_type;

    /** 事件类型：NEW_ORDER_PAID / ORDER_PREP_TIMEOUT / COUPON_GRANTED / ALERT_DISMISSED 等 */
    private String event_type;

    /** 优先级：P0 / P1 / P2 / P3 */
    private String priority;

    /** 是否要求客户端回执确认 */
    private Boolean require_ack;

    /** 前端展示与声音播报策略 */
    private DisplayStrategy display_strategy;

    /** 业务扩展载荷 */
    private Map<String, Object> payload;

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Target {
        /** SHOP / USER / BROADCAST */
        private String scope;
        private Integer shop_id;
        private Integer user_id;
        private String openid;
        private String client_type;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DisplayStrategy {
        /** PERSISTENT_ALERT_BANNER / TOP_BANNER_AND_VOICE / COUPON_MODAL_OR_TOAST / SILENT_INVALIDATE */
        private String ui_type;
        /** NONE / VOICE_NEW_ORDER / VOICE_TIMEOUT_ALERT / SOUND_COUPON */
        private String sound;
        /** 语音合成/播报文案 */
        private String tts_text;
        /** 持续毫秒（0表示常驻直至手动确认） */
        private Long duration_ms;
        /** 未确认时重复语音提醒间隔毫秒 */
        private Long repeat_interval_ms;
        /** 聚合键（如 COUPON_GRANTED） */
        private String aggregation_key;
        /** 聚合窗口毫秒（如 800） */
        private Long aggregation_window_ms;
        /** 交互按钮文案 */
        private String action_text;
        /** 交互跳转路由 */
        private String action_route;
    }
}
