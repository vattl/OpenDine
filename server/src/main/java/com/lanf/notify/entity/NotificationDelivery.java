package com.lanf.notify.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 通知发送记录，对应 t_notification_delivery（接收人仅存脱敏形态）。
 */
@TableName("t_notification_delivery")
@Data
public class NotificationDelivery {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private Long rule_id;
    private String event_type;
    private String channel;
    private String recipient_masked;
    private String title;
    private String status;
    private String error;
    private Integer retry_count;
    private LocalDateTime created_at;
    private LocalDateTime updated_at;
}
