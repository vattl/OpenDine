package com.lanf.access.service;

import com.lanf.common.ApiException;
import com.lanf.entity.AccessApprovalRateLimit;
import com.lanf.mapper.AccessApprovalRateLimitMapper;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Database-authoritative approval throttling shared across application instances. */
@Service
public class ApprovalRateLimitService {

    public enum Scope {
        ONSITE_AUTHORIZE(10, 60, 300),
        QR_CREATE(10, 60, 300),
        QR_CONFIRM(20, 60, 300),
        CREDENTIAL_FAILURE(5, 900, 900);

        private final int maxAttempts;
        private final long windowSeconds;
        private final long blockSeconds;

        Scope(int maxAttempts, long windowSeconds, long blockSeconds) {
            this.maxAttempts = maxAttempts;
            this.windowSeconds = windowSeconds;
            this.blockSeconds = blockSeconds;
        }
    }

    private final AccessApprovalRateLimitMapper mapper;
    private final SecurityAuditService auditService;
    private final Clock clock;

    @Autowired
    public ApprovalRateLimitService(AccessApprovalRateLimitMapper mapper, SecurityAuditService auditService) {
        this(mapper, auditService, Clock.systemUTC());
    }

    public ApprovalRateLimitService(AccessApprovalRateLimitMapper mapper,
                                    SecurityAuditService auditService,
                                    Clock clock) {
        this.mapper = mapper;
        this.auditService = auditService;
        this.clock = clock;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW, noRollbackFor = ApiException.class)
    public void acquireRequest(Scope scope, Integer shopId, String actorKey) {
        if (scope == Scope.CREDENTIAL_FAILURE) {
            throw new IllegalArgumentException("credential failure scope requires failure-specific methods");
        }
        String limitKey = requestKey(scope, shopId, actorKey);
        applyAttempt(limitKey, scope, shopId, null, true);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW, noRollbackFor = ApiException.class)
    public void assertCredentialAllowed(Integer shopId, String account, Integer actorId) {
        String key = credentialKey(shopId, account);
        AccessApprovalRateLimit row = lockRow(key, Scope.CREDENTIAL_FAILURE);
        Date now = now();
        if (isBlocked(row, now)) {
            reject(Scope.CREDENTIAL_FAILURE, shopId, actorId, row.getBlockedUntil(), now);
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordCredentialFailure(Integer shopId, String account, Integer actorId) {
        applyAttempt(credentialKey(shopId, account), Scope.CREDENTIAL_FAILURE, shopId, actorId, false);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void clearCredentialFailures(Integer shopId, String account) {
        mapper.deleteByLimitKey(credentialKey(shopId, account));
    }

    public String credentialKey(Integer shopId, String account) {
        String normalized = account == null ? "" : account.trim().toLowerCase(Locale.ROOT);
        return hashedKey(Scope.CREDENTIAL_FAILURE.name() + "|" + value(shopId) + "|" + normalized);
    }

    private String requestKey(Scope scope, Integer shopId, String actorKey) {
        return hashedKey(scope.name() + "|" + value(shopId) + "|" + value(actorKey));
    }

    private void applyAttempt(String limitKey, Scope scope, Integer shopId, Integer actorId,
                              boolean rejectCurrentAttemptAtLimit) {
        AccessApprovalRateLimit row = lockRow(limitKey, scope);
        Date now = now();
        if (isBlocked(row, now)) {
            reject(scope, shopId, actorId, row.getBlockedUntil(), now);
        }

        Date windowStart = row.getWindowStartedAt();
        int attempts;
        if (windowStart == null || now.getTime() - windowStart.getTime() >= scope.windowSeconds * 1000L) {
            windowStart = now;
            attempts = 1;
        } else {
            attempts = value(row.getAttempts()) + 1;
        }

        boolean limitReached = rejectCurrentAttemptAtLimit
                ? attempts > scope.maxAttempts
                : attempts >= scope.maxAttempts;
        Date blockedUntil = limitReached
                ? new Date(now.getTime() + scope.blockSeconds * 1000L)
                : null;
        mapper.updateState(limitKey, windowStart, attempts, blockedUntil);
        if (rejectCurrentAttemptAtLimit && limitReached) {
            reject(scope, shopId, actorId, blockedUntil, now);
        }
    }

    private AccessApprovalRateLimit lockRow(String limitKey, Scope scope) {
        Date now = now();
        mapper.insertIfAbsent(limitKey, scope.name(), now);
        AccessApprovalRateLimit row = mapper.selectForUpdate(limitKey);
        if (row == null) {
            throw new ApiException(503, "ACCESS_APPROVAL_RATE_LIMIT_UNAVAILABLE", "审批安全控制暂不可用，请稍后重试");
        }
        return row;
    }

    private boolean isBlocked(AccessApprovalRateLimit row, Date now) {
        return row.getBlockedUntil() != null && row.getBlockedUntil().after(now);
    }

    private void reject(Scope scope, Integer shopId, Integer actorId, Date blockedUntil, Date now) {
        long retryAfter = Math.max(1L, (blockedUntil.getTime() - now.getTime() + 999L) / 1000L);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("retryAfterSeconds", retryAfter);
        data.put("rateLimitScope", scope.name());
        if (auditService != null) {
            Map<String, Object> snapshot = new LinkedHashMap<>();
            snapshot.put("rateLimitScope", scope.name());
            snapshot.put("retryAfterSeconds", retryAfter);
            auditService.recordRejected(null, shopId, "access", "approval_rate_limited",
                    scope.name(), actorId, snapshot, 429, "ACCESS_APPROVAL_RATE_LIMITED");
        }
        throw new ApiException(429, "ACCESS_APPROVAL_RATE_LIMITED", "请求过于频繁，请稍后重试", data);
    }

    private Date now() {
        return Date.from(clock.instant());
    }

    private static int value(Integer value) {
        return value == null ? 0 : value;
    }

    private static String value(Object value) {
        return value == null ? "-" : String.valueOf(value);
    }

    private static String hashedKey(String material) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(material.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte value : digest) {
                out.append(String.format("%02x", value & 0xff));
            }
            return out.toString();
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
