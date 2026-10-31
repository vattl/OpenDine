package com.lanf.notify.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Coupon;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.realtime.UnifiedMessageEnvelope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 优惠券即将过期巡检调度器（Phase 2 C端营销触达能力）。
 * 定时扫描用户持有且未使用（status=0）、距离过期不足指定窗口（默认 120 分钟）的优惠券，
 * 触发 P2 级 COUPON_EXPIRING_SOON 提示（在线走 WebSocket 底部 SnackBar，离线走微信订阅消息兜底）。
 */
@Component
public class CouponExpiringWatchdogScheduler {

    private static final Logger log = LoggerFactory.getLogger(CouponExpiringWatchdogScheduler.class);
    public static final int DEFAULT_EXPIRING_WINDOW_MINUTES = 120;

    private final UserCouponMapper userCouponMapper;
    private final CouponMapper couponMapper;
    private final UnifiedNotificationService notificationService;

    @Value("${notify.coupon-expiring.window-minutes:120}")
    private int expiringWindowMinutes = DEFAULT_EXPIRING_WINDOW_MINUTES;

    private final Set<String> triggeredCouponKeys = ConcurrentHashMap.newKeySet();

    @Autowired
    public CouponExpiringWatchdogScheduler(@Autowired(required = false) UserCouponMapper userCouponMapper,
                                           @Autowired(required = false) CouponMapper couponMapper,
                                           UnifiedNotificationService notificationService) {
        this.userCouponMapper = userCouponMapper;
        this.couponMapper = couponMapper;
        this.notificationService = notificationService;
    }

    public void setExpiringWindowMinutes(int expiringWindowMinutes) {
        this.expiringWindowMinutes = expiringWindowMinutes > 0 ? expiringWindowMinutes : DEFAULT_EXPIRING_WINDOW_MINUTES;
    }

    @Scheduled(
            fixedDelayString = "${notify.coupon-expiring.scan-interval-ms:300000}",
            initialDelayString = "${notify.coupon-expiring.initial-delay-ms:60000}"
    )
    public void scheduledScan() {
        try {
            scanAndNotifyExpiringCoupons(System.currentTimeMillis());
        } catch (Exception e) {
            log.warn("[coupon-expiring-watchdog] scheduled scan error: {}", e.getMessage());
        }
    }

    /**
     * 扫描即将过期的未使用优惠券并发送临期提醒（每张用户券仅触发一次，幂等防重）。
     */
    public List<UnifiedMessageEnvelope> scanAndNotifyExpiringCoupons(long nowEpochMs) {
        if (userCouponMapper == null || notificationService == null) {
            return new ArrayList<>();
        }
        int windowMin = expiringWindowMinutes > 0 ? expiringWindowMinutes : DEFAULT_EXPIRING_WINDOW_MINUTES;
        Date nowDate = new Date(nowEpochMs);
        Date windowEnd = new Date(nowEpochMs + windowMin * 60_000L);

        QueryWrapper<UserCoupon> qw = new QueryWrapper<UserCoupon>()
                .eq("status", 0)
                .isNotNull("expire_time")
                .gt("expire_time", nowDate)
                .le("expire_time", windowEnd)
                .orderByAsc("expire_time")
                .last("LIMIT 200");

        List<UserCoupon> candidates = userCouponMapper.selectList(qw);
        if (candidates == null || candidates.isEmpty()) {
            return new ArrayList<>();
        }

        Map<Long, Coupon> couponCache = new HashMap<>();
        List<UnifiedMessageEnvelope> published = new ArrayList<>();

        for (UserCoupon uc : candidates) {
            if (uc == null || uc.getId() == null || !StringUtils.hasText(uc.getUser_openid()) || uc.getExpire_time() == null) {
                continue;
            }
            if (uc.getStatus() != null && uc.getStatus() != 0) {
                continue;
            }
            long diffMs = uc.getExpire_time().getTime() - nowEpochMs;
            if (diffMs <= 0 || diffMs > windowMin * 60_000L) {
                continue;
            }

            String messageId = "ntf_coupon_exp_" + uc.getId();
            if (triggeredCouponKeys.contains(messageId) || notificationService.existsByMessageId(messageId)) {
                triggeredCouponKeys.add(messageId);
                continue;
            }

            Coupon template = null;
            if (uc.getCoupon_id() != null && couponMapper != null) {
                template = couponCache.computeIfAbsent(uc.getCoupon_id(), id -> {
                    try {
                        return couponMapper.selectById(id);
                    } catch (Exception ignored) {
                        return null;
                    }
                });
            }

            long remainingMinutes = Math.max(1L, (diffMs + 59_999L) / 60_000L);
            UnifiedMessageEnvelope env = notificationService.publishCouponExpiringSoon(uc, template, remainingMinutes);
            if (env != null) {
                triggeredCouponKeys.add(messageId);
                published.add(env);
            }
        }
        return published;
    }

    public void clearTriggeredCacheForTest() {
        triggeredCouponKeys.clear();
    }
}
