package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.io.Serializable;
import java.util.Date;

/**
 * 微信订阅消息发送审计与调用日志
 */
@Data
@TableName("t_subscribe_send_log")
public class SubscribeSendLog implements Serializable {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 关联业务单号（如订单号 order_no） */
    private String biz_no;

    /** 目标微信用户OpenID */
    private String openid;

    /** 业务场景编码 */
    private String scene_code;

    /** 使用的微信模板ID */
    private String template_id;

    /** 发送状态：SUCCESS / FAILED / SKIPPED_NO_QUOTA */
    private String send_status;

    /** 微信错误码（0为成功，43101为额度耗尽） */
    private Integer errcode;

    /** 微信错误信息 */
    private String errmsg;

    /** 发送前配额 */
    private Integer quota_before;

    /** 发送后配额 */
    private Integer quota_after;

    /** 耗时（毫秒） */
    private Long duration_ms;

    /** 发送载荷摘要 */
    private String payload_summary;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date created_at;
}
