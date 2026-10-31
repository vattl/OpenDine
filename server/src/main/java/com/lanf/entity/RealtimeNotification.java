package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 统一实时消息与通知持久化实体（对应 t_realtime_notification）。
 */
@Data
@TableName("t_realtime_notification")
public class RealtimeNotification {

    @TableId(value = "seq_id", type = IdType.AUTO)
    private Long seq_id;

    /** 全局唯一幂等键（如 ntf_order_paid_ORD123, ntf_timeout_ORD123_stage1） */
    private String message_id;

    /** 目标范围：SHOP / USER / BROADCAST */
    private String target_scope;

    /** 目标门店ID（0表示全店） */
    private Integer shop_id;

    /** 目标C端用户ID */
    private Integer user_id;

    /** 目标C端用户OpenID */
    private String user_openid;

    /** 目标终端类型：CASHIER / MINI_PROGRAM / ALL */
    private String client_type;

    /** 业务域：ORDER / COUPON / TABLE / KDS / MENU / TAKEOUT / SYSTEM */
    private String business_type;

    /** 事件类型：NEW_ORDER_PAID / ORDER_PREP_TIMEOUT / COUPON_GRANTED / ALERT_DISMISSED 等 */
    private String event_type;

    /** 优先级：P0 / P1 / P2 */
    private String priority;

    /** 是否需要客户端回执确认：0否 1是 */
    private Integer require_ack;

    /** 前端展示与播报策略JSON */
    private String display_strategy_json;

    /** 业务载荷JSON */
    private String payload_json;

    /** 状态：0未读/待处理 1已读/已确认 2已过期 */
    private Integer read_status;

    /** 确认处理的终端/操作员标识 */
    private String acked_by;

    /** 确认处理时间 */
    private Date acked_at;

    /** 消息过期时间 */
    private Date expire_at;

    /** 创建时间 */
    private Date created_at;

    /** 更新时间 */
    private Date updated_at;
}
