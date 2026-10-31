package com.lanf.config.properties;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;

/**
 * C 端用户身份（旧版小程序无 X-User-Token）临时兼容配置。
 * 仅用于新旧小程序过渡期，到期或关闭后系统全量回归严格 Token 校验。
 */
@Component
@ConfigurationProperties(prefix = "auth.c-user-identity")
public class UserIdentityCompatibilityProperties {

    private static final Logger log = LoggerFactory.getLogger(UserIdentityCompatibilityProperties.class);

    /** 是否开启旧版小程序无 Token 临时兼容 */
    private boolean compatibilityEnabled = true;

    /** 临时兼容截止时间（ISO-8601 格式，如 2026-12-31T23:59:59+08:00）。到达该时间后自动硬拒绝，即使 enabled=true */
    private String compatibilityDeadline = "2026-12-31T23:59:59+08:00";

    /** 兼容模式（默认 legacy-openid） */
    private String compatibilityMode = "legacy-openid";

    public boolean isCompatibilityEnabled() {
        return compatibilityEnabled;
    }

    public void setCompatibilityEnabled(boolean compatibilityEnabled) {
        this.compatibilityEnabled = compatibilityEnabled;
    }

    public String getCompatibilityDeadline() {
        return compatibilityDeadline;
    }

    public void setCompatibilityDeadline(String compatibilityDeadline) {
        this.compatibilityDeadline = compatibilityDeadline;
    }

    public String getCompatibilityMode() {
        return compatibilityMode;
    }

    public void setCompatibilityMode(String compatibilityMode) {
        this.compatibilityMode = compatibilityMode;
    }

    /**
     * 判断当前时间临时兼容是否生效。
     */
    public boolean isEffective() {
        if (!compatibilityEnabled) {
            return false;
        }
        if (compatibilityDeadline != null && !compatibilityDeadline.trim().isEmpty()) {
            try {
                ZonedDateTime deadline = ZonedDateTime.parse(compatibilityDeadline.trim(), DateTimeFormatter.ISO_OFFSET_DATE_TIME);
                if (ZonedDateTime.now().isAfter(deadline)) {
                    log.warn("旧版小程序无 Token 临时兼容已于 {} 到期硬失效", compatibilityDeadline);
                    return false;
                }
            } catch (Exception e) {
                log.error("解析兼容截止时间失败: deadline={}, err={}", compatibilityDeadline, e.getMessage());
            }
        }
        return true;
    }
}
