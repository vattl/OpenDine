package com.lanf.dto;

import lombok.Data;

import java.io.Serializable;

/**
 * 个人支付宝/微信监听 App 异步通知请求体 DTO
 */
@Data
public class PersonalAlipayNotifyDTO implements Serializable {
    private static final long serialVersionUID = 1L;

    /** 渠道：alipay, wechat 等 */
    private String channel;

    /** 到账金额（单位：分，例如 1000 代表 10.00 元） */
    private Long amount;

    /** 时间戳（毫秒或秒） */
    private Object timestamp;

    /** 唯一事件 ID（用于幂等去重） */
    private String event_id;
    private String eventId;

    /** 原始到账通知文本内容（如：“支付宝通知: 收到一笔 10.00 元款项”） */
    private String raw_text;
    private String rawText;

    /** 可选门店 ID */
    private Integer shop_id;
    private Integer shopId;
}
