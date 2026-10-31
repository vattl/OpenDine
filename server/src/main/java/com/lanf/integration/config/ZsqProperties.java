package com.lanf.integration.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "zsq")
public class ZsqProperties {

    /** 真省钱 API 根路径，如 https://zsq.wlhulian.com/api */
    private String apiBase = "https://zsq.wlhulian.com/api";

    private String username;
    private String password;

    /** merchant=商户(type=2) | partner=接口方(type=1) */
    private String role = "merchant";

    /** password | sms */
    private String loginMode = "password";

    /** 骑手 ETA 估算速度（km/h），默认 20 */
    private double riderSpeedKmh = 20.0;

    /** 一键发配送默认选择的渠道数（按价格从低到高） */
    private int autoDispatchChannelCount = 1;

    /** HTTP connection pool budget for the remote delivery platform. */
    private int httpMaxConnections = 4;
    private int httpMaxConnectionsPerRoute = 4;
    private int httpConnectionRequestTimeoutMs = 1000;
    private int httpConnectTimeoutMs = 2000;
    private int httpReadTimeoutMs = 5000;

    public String getApiBase() {
        return apiBase;
    }

    public void setApiBase(String apiBase) {
        this.apiBase = apiBase;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public String getLoginMode() {
        return loginMode;
    }

    public void setLoginMode(String loginMode) {
        this.loginMode = loginMode;
    }

    public double getRiderSpeedKmh() {
        return riderSpeedKmh;
    }

    public void setRiderSpeedKmh(double riderSpeedKmh) {
        this.riderSpeedKmh = riderSpeedKmh;
    }

    public int getAutoDispatchChannelCount() {
        return autoDispatchChannelCount;
    }

    public void setAutoDispatchChannelCount(int autoDispatchChannelCount) {
        this.autoDispatchChannelCount = autoDispatchChannelCount;
    }

    public int getHttpMaxConnections() { return httpMaxConnections; }
    public void setHttpMaxConnections(int httpMaxConnections) { this.httpMaxConnections = httpMaxConnections; }
    public int getHttpMaxConnectionsPerRoute() { return httpMaxConnectionsPerRoute; }
    public void setHttpMaxConnectionsPerRoute(int httpMaxConnectionsPerRoute) { this.httpMaxConnectionsPerRoute = httpMaxConnectionsPerRoute; }
    public int getHttpConnectionRequestTimeoutMs() { return httpConnectionRequestTimeoutMs; }
    public void setHttpConnectionRequestTimeoutMs(int httpConnectionRequestTimeoutMs) { this.httpConnectionRequestTimeoutMs = httpConnectionRequestTimeoutMs; }
    public int getHttpConnectTimeoutMs() { return httpConnectTimeoutMs; }
    public void setHttpConnectTimeoutMs(int httpConnectTimeoutMs) { this.httpConnectTimeoutMs = httpConnectTimeoutMs; }
    public int getHttpReadTimeoutMs() { return httpReadTimeoutMs; }
    public void setHttpReadTimeoutMs(int httpReadTimeoutMs) { this.httpReadTimeoutMs = httpReadTimeoutMs; }

    public int roleType() {
        return "partner".equalsIgnoreCase(role) ? 1 : 2;
    }

    public int loginType() {
        return "sms".equalsIgnoreCase(loginMode) ? 2 : 1;
    }

    public boolean hasConfiguredAccount() {
        return username != null && !username.trim().isEmpty()
                && password != null && !password.trim().isEmpty();
    }
}
