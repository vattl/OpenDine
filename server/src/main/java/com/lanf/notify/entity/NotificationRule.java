package com.lanf.notify.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 通知规则，对应 t_notification_rule。
 */
@TableName("t_notification_rule")
@Data
public class NotificationRule {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer shop_id;
    private String name;
    private String event_type;
    private String channels_json;
    private String recipients_json;
    private String time_window_json;
    private String frequency_control_json;
    private Integer enabled;
    private Integer version;
    private LocalDateTime created_at;
    private LocalDateTime updated_at;
}
