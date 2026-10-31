package com.lanf.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 高德 Web 服务：外卖配送路网距离（路径规划）。
 */
@Component
@ConfigurationProperties(prefix = "amap")
public class AmapRouteProperties {

    /** 高德 Web 服务 Key（路径规划）；未配置则回退直线距离 */
    private String webKey = "";

    /** 是否启用路网距离计费 */
    private boolean routeDistanceEnabled = true;

    /**
     * 路径规划方式：{@code driving}（驾车，v3）或 {@code bicycling}（骑行，v4）。
     */
    private String routeMode = "driving";

    /** 路网规划失败时是否回退 Haversine 直线距离 */
    private boolean fallbackStraightLine = true;

    /** 同起终点缓存分钟数（减轻配额消耗） */
    private int routeCacheMinutes = 30;

    public String getWebKey() {
        return webKey;
    }

    public void setWebKey(String webKey) {
        this.webKey = webKey;
    }

    public boolean isRouteDistanceEnabled() {
        return routeDistanceEnabled;
    }

    public void setRouteDistanceEnabled(boolean routeDistanceEnabled) {
        this.routeDistanceEnabled = routeDistanceEnabled;
    }

    public String getRouteMode() {
        return routeMode;
    }

    public void setRouteMode(String routeMode) {
        this.routeMode = routeMode;
    }

    public boolean isFallbackStraightLine() {
        return fallbackStraightLine;
    }

    public void setFallbackStraightLine(boolean fallbackStraightLine) {
        this.fallbackStraightLine = fallbackStraightLine;
    }

    public int getRouteCacheMinutes() {
        return routeCacheMinutes;
    }

    public void setRouteCacheMinutes(int routeCacheMinutes) {
        this.routeCacheMinutes = routeCacheMinutes;
    }

    public boolean hasWebKey() {
        return webKey != null && !webKey.trim().isEmpty();
    }
}
