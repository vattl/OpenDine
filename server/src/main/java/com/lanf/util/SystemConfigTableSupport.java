package com.lanf.util;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;

/**
 * 探测 {@code t_system_config} 是否已执行 {@code shop_id} 列迁移。
 */
@Component
public class SystemConfigTableSupport {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    private volatile boolean shopIdColumnPresent;

    @PostConstruct
    public void detectSchema() {
        try {
            Integer count = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS "
                            + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_system_config' AND COLUMN_NAME = 'shop_id'",
                    Integer.class);
            shopIdColumnPresent = count != null && count > 0;
        } catch (Exception e) {
            shopIdColumnPresent = false;
        }
    }

    public boolean hasShopIdColumn() {
        return shopIdColumnPresent;
    }
}
