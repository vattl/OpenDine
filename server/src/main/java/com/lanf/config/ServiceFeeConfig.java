package com.lanf.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

/**
 * 服务费配置：截止日期及之后不再收取服务费，此前按整单 5% 收取。
 * 配置项 order.service-fee-cutoff-date（yyyy-MM-dd），便于后期修改时间。
 */
@Component
public class ServiceFeeConfig {

    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    private static final LocalDate DEFAULT_CUTOFF = LocalDate.of(2026, 2, 25);

    @Value("${order.service-fee-cutoff-date:2026-02-25}")
    private String cutoffDateStr;

    private volatile LocalDate cutoffDate;

    /**
     * 当前是否收取服务费：true=收取（今日早于截止日），false=不收取（今日为截止日及之后）
     */
    public boolean isServiceFeeCharged() {
        return LocalDate.now().isBefore(getCutoffDate());
    }

    private LocalDate getCutoffDate() {
        if (cutoffDate == null) {
            synchronized (this) {
                if (cutoffDate == null) {
                    if (cutoffDateStr != null && !cutoffDateStr.trim().isEmpty()) {
                        try {
                            cutoffDate = LocalDate.parse(cutoffDateStr.trim(), DATE_FORMAT);
                        } catch (Exception e) {
                            cutoffDate = DEFAULT_CUTOFF;
                        }
                    } else {
                        cutoffDate = DEFAULT_CUTOFF;
                    }
                }
            }
        }
        return cutoffDate;
    }
}
