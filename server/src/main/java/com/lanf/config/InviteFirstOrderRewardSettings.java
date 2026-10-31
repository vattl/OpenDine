package com.lanf.config;

import com.lanf.constant.InviteFirstOrderRewardConfigKeys;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 邀请好友首单余额奖励规则（运行时修改，持久化见 {@link SystemConfigSync} 与 {@code t_system_config}）。
 */
@Component
public class InviteFirstOrderRewardSettings {

    private volatile boolean enabled = false;
    /** 实付金额的百分比，如 5 表示 5% */
    private volatile double rewardPercent = 5d;

    public boolean isEnabled() {
        return enabled;
    }

    public double getRewardPercent() {
        return rewardPercent;
    }

    public Map<String, Object> toPublicMap() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("enabled", enabled);
        m.put("rewardPercent", rewardPercent);
        return m;
    }

    public void applyFromKeyValue(String key, String rawValue) {
        if (key == null) {
            return;
        }
        String k = key.trim();
        String v = rawValue == null ? "" : rawValue.trim();
        if (InviteFirstOrderRewardConfigKeys.ENABLED.equals(k)) {
            enabled = parseBool(v, enabled);
        } else if (InviteFirstOrderRewardConfigKeys.PERCENT.equals(k)) {
            rewardPercent = parsePercent(v, rewardPercent);
        }
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public void setRewardPercent(double rewardPercent) {
        this.rewardPercent = clampPercent(rewardPercent);
    }

    private static boolean parseBool(String v, boolean def) {
        if (v.isEmpty()) {
            return def;
        }
        if ("1".equals(v) || "true".equalsIgnoreCase(v) || "yes".equalsIgnoreCase(v)) {
            return true;
        }
        if ("0".equals(v) || "false".equalsIgnoreCase(v) || "no".equalsIgnoreCase(v)) {
            return false;
        }
        return def;
    }

    private static double parsePercent(String v, double def) {
        if (v.isEmpty()) {
            return def;
        }
        try {
            return clampPercent(Double.parseDouble(v));
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static double clampPercent(double p) {
        if (Double.isNaN(p) || p < 0d) {
            return 0d;
        }
        if (p > 100d) {
            return 100d;
        }
        return p;
    }
}
