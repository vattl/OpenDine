package com.lanf.notify.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 实时通知过期与历史已读记录定期清理调度器。
 */
@Component
public class NotificationRetentionCleanupScheduler {

    private static final Logger log = LoggerFactory.getLogger(NotificationRetentionCleanupScheduler.class);
    private static final int DEFAULT_RETENTION_DAYS = 7;

    private final UnifiedNotificationService notificationService;

    public NotificationRetentionCleanupScheduler(UnifiedNotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @Scheduled(cron = "${notify.cleanup.cron:0 15 4 * * ?}")
    public int purgeExpiredAndArchivedNotifications() {
        int deleted = notificationService.cleanupExpiredNotifications(DEFAULT_RETENTION_DAYS);
        if (deleted > 0) {
            log.info("[notify-cleanup] purged {} expired/read notifications", deleted);
        }
        return deleted;
    }
}
