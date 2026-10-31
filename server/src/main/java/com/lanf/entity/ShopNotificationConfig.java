package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 门店消息通知与出餐超时动态阈值配置实体（对应 t_shop_notification_config）。
 */
@Data
@TableName("t_shop_notification_config")
public class ShopNotificationConfig {

    @TableId(value = "shop_id", type = IdType.INPUT)
    private Integer shop_id;

    /** 是否开启出餐超时告警：0关闭 1开启 */
    private Integer prep_timeout_enabled;

    /** 出餐超时动态阈值（分钟，合法范围 5~120，默认15） */
    private Integer prep_timeout_minutes;

    /** P0告警未确认时重复语音提醒间隔（秒，合法范围 15~600，默认60） */
    private Integer timeout_repeat_interval_seconds;

    /** 最后修改管理员ID */
    private Integer updated_by;

    /** 更新时间 */
    private Date updated_at;
}
