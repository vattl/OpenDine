package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** Durable rate-limit state shared by all approval-service instances. */
@Data
@TableName("t_access_approval_rate_limit")
public class AccessApprovalRateLimit {

    @TableId("limit_key")
    private String limitKey;

    @TableField("limit_scope")
    private String limitScope;

    @TableField("window_started_at")
    private Date windowStartedAt;

    private Integer attempts;

    @TableField("blocked_until")
    private Date blockedUntil;

    @TableField("updated_at")
    private Date updatedAt;
}
