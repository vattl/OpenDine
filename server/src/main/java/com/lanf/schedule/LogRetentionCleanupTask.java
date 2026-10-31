package com.lanf.schedule;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * 日志保留策略物理清理：每日定时删除超过保留期的操作/订单/库存日志。
 * <p>查询侧边界（在线 30 天 / 归档与导出 365 天）由 {@code AdminLogService} 窗口裁剪实现；
 * 本任务将「1 年销毁」落地为物理删除：保留期默认 400 天（&gt; 365 天查询边界），
 * 保证查询/归档/导出窗口永不返回已删数据，同时避免日志表无限膨胀。</p>
 * <p>分批删除（单批 5000 行）控制单事务行数，避免长事务与大表锁；任何异常仅记录，不阻断启动。</p>
 */
@Component
public class LogRetentionCleanupTask {

    private static final Logger log = LoggerFactory.getLogger(LogRetentionCleanupTask.class);
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final int BATCH = 5000;

    private final JdbcTemplate jdbc;

    /** 日志保留天数（须大于查询侧 365 天边界）；可用 log.retention-days 覆盖 */
    @Value("${log.retention-days:400}")
    private int retentionDays;

    public LogRetentionCleanupTask(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Scheduled(cron = "${log.retention-clean-cron:0 20 3 * * ?}")
    public void cleanExpiredLogs() {
        try {
            int days = Math.max(30, retentionDays);
            LocalDateTime cutoff = LocalDateTime.now().minusDays(days);
            String ts = cutoff.format(TS);
            long total = 0;
            total += cleanup("t_operation_log", ts);
            total += cleanup("t_order_log", ts);
            total += cleanup("t_dish_stock_log", ts);
            if (total > 0) {
                log.info("[log-retention] 日志清理完成 cutoff={} retentionDays={} deleted={}", ts, days, total);
            }
        } catch (Exception e) {
            log.error("[log-retention] 日志清理失败: {}", e.getMessage(), e);
        }
    }

    private long cleanup(String table, String ts) {
        long deleted = 0;
        while (true) {
            int n = jdbc.update("DELETE FROM `" + table + "` WHERE created_at < ? LIMIT " + BATCH, ts);
            if (n <= 0) {
                break;
            }
            deleted += n;
            if (n < BATCH) {
                break;
            }
        }
        if (deleted > 0) {
            log.info("[log-retention] 清理 {} 行 {} deleted={}", deleted, table, ts);
        }
        return deleted;
    }
}
