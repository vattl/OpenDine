package com.lanf.integration.service;

import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.ZsqLoginRequest;
import com.lanf.integration.remote.dto.ZsqLoginTokenData;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpStatusCodeException;

import java.util.Map;

/**
 * 真省钱登录与会话；yml 配置账号的 token 内存缓存，失效时自动重新登录。
 */
@Service
public class ZsqAuthService {

    private static final Logger log = LoggerFactory.getLogger(ZsqAuthService.class);

    @FunctionalInterface
    public interface ConfigAuthCallback<T> {
        T call(String authorization);
    }

    private final ZsqRemoteClient remoteClient;
    private final ZsqProperties properties;

    private volatile ConfigSession configSession;

    public ZsqAuthService(ZsqRemoteClient remoteClient, ZsqProperties properties) {
        this.remoteClient = remoteClient;
        this.properties = properties;
    }

    public LoginResult login(String username, String password, String role, String loginMode, String smsCode) {
        ZsqLoginRequest req = new ZsqLoginRequest();
        req.setUsername(username);
        req.setPassword("sms".equalsIgnoreCase(loginMode) ? "" : password);
        req.setCode(smsCode == null ? "" : smsCode);
        req.setType("partner".equalsIgnoreCase(role) ? 1 : 2);
        req.setLoginType("sms".equalsIgnoreCase(loginMode) ? 2 : 1);

        ZsqLoginTokenData data = "partner".equalsIgnoreCase(role)
                ? remoteClient.partnerLogin(req)
                : remoteClient.merchantLogin(req);

        if (data == null || data.getToken() == null) {
            throw new ZsqApiException("登录失败：未返回 token");
        }
        return new LoginResult(data.fullAuthorization(), role);
    }

    /**
     * 使用 yml 账号登录并更新内存会话。
     */
    public synchronized LoginResult loginWithConfig() {
        if (!properties.hasConfiguredAccount()) {
            throw new ZsqApiException("未配置 zsq.username / zsq.password");
        }
        LoginResult result = login(
                properties.getUsername(),
                properties.getPassword(),
                properties.getRole(),
                properties.getLoginMode(),
                "");
        configSession = new ConfigSession(result.getAuthorization(), System.currentTimeMillis());
        return result;
    }

    /**
     * 获取 yml 配置账号的 Authorization（优先缓存）。
     */
    public String getConfigAuthorization() {
        ConfigSession session = configSession;
        if (session != null && session.authorization != null && !session.authorization.isEmpty()) {
            return session.authorization;
        }
        return refreshConfigAuthorizationAfterFailure(null);
    }

    public synchronized String refreshConfigAuthorization() {
        return loginWithConfig().getAuthorization();
    }

    /**
     * Only one caller refreshes an expired configured credential. Callers that observed an older
     * token reuse the already refreshed value rather than turning one remote expiry into a login storm.
     */
    private synchronized String refreshConfigAuthorizationAfterFailure(String failedAuthorization) {
        ConfigSession current = configSession;
        if (current != null && current.authorization != null && !current.authorization.isEmpty()
                && (failedAuthorization == null || !current.authorization.equals(failedAuthorization))) {
            return current.authorization;
        }
        return loginWithConfig().getAuthorization();
    }

    public void invalidateConfigAuthorization() {
        configSession = null;
    }

    /**
     * 使用配置账号 token 执行远程调用；若真省钱返回登录过期/未登录，则重新登录并重试一次。
     */
    public <T> T executeWithConfigAuth(ConfigAuthCallback<T> callback) {
        String auth = getConfigAuthorization();
        try {
            return callback.call(auth);
        } catch (RuntimeException first) {
            if (!isAuthenticationFailure(first)) {
                throw first;
            }
            log.warn("真省钱会话失效，重新登录后继续: {}", first.getMessage());
            auth = refreshConfigAuthorizationAfterFailure(auth);
            return callback.call(auth);
        }
    }

    public Map<String, Object> verifySession(String authorization) {
        return remoteClient.merchantInfo(authorization);
    }

    public static boolean isAuthenticationFailure(Throwable error) {
        Throwable cur = error;
        while (cur != null) {
            if (cur instanceof ZsqApiException) {
                ZsqApiException z = (ZsqApiException) cur;
                if (z.getCode() == 401 || z.getCode() == 403) {
                    return true;
                }
                if (looksLikeAuthMessage(z.getMessage())) {
                    return true;
                }
            }
            if (cur instanceof HttpStatusCodeException) {
                HttpStatusCodeException h = (HttpStatusCodeException) cur;
                int status = h.getStatusCode().value();
                if (status == 401 || status == 403) {
                    return true;
                }
                if (looksLikeAuthMessage(h.getResponseBodyAsString())) {
                    return true;
                }
            }
            cur = cur.getCause();
        }
        return false;
    }

    private static boolean looksLikeAuthMessage(String message) {
        if (message == null || message.trim().isEmpty()) {
            return false;
        }
        String lower = message.toLowerCase();
        return message.contains("登录")
                || message.contains("登陆")
                || message.contains("未登录")
                || message.contains("未登陆")
                || message.contains("登录过期")
                || message.contains("登陆过期")
                || message.contains("请先登录")
                || message.contains("请先登陆")
                || lower.contains("token")
                || lower.contains("unauthorized")
                || message.contains("授权")
                || message.contains("身份");
    }

    private static final class ConfigSession {
        private final String authorization;

        private ConfigSession(String authorization, long cachedAtMs) {
            this.authorization = authorization;
        }
    }

    public static class LoginResult {
        private final String authorization;
        private final String role;

        public LoginResult(String authorization, String role) {
            this.authorization = authorization;
            this.role = role;
        }

        public String getAuthorization() {
            return authorization;
        }

        public String getRole() {
            return role;
        }
    }
}
