package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.io.Serializable;
import java.util.Date;

/**
 * 用户微信订阅消息可用额度与台账实体
 */
@Data
@TableName("t_user_subscribe_quota")
public class UserSubscribeQuota implements Serializable {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 微信用户OpenID */
    private String openid;

    /** 业务场景编码 */
    private String scene_code;

    /** 微信模板ID */
    private String template_id;

    /** 可用推送剩余额度 */
    private Integer available_quota;

    /** 累计同意授权次数 */
    private Integer accept_count;

    /** 累计拒绝授权次数 */
    private Integer reject_count;

    /** 是否被设为总是保持拒绝(ban) */
    private Integer ban_status;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date last_authorized_at;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date last_sent_at;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date created_at;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date updated_at;
}
