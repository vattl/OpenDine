package com.lanf.config;

import com.alibaba.druid.pool.DruidDataSource;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

import javax.sql.DataSource;

/** Explicit binding is required: the plain Druid dependency does not bind its own pool settings. */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(DataSourceProperties.class)
@ConditionalOnProperty(name = "spring.datasource.type",
        havingValue = "com.alibaba.druid.pool.DruidDataSource", matchIfMissing = true)
public class DataSourceBudgetConfiguration {
    @Bean(destroyMethod = "close")
    @ConditionalOnMissingBean(DataSource.class)
    public DruidDataSource dataSource(DataSourceProperties connection, Environment env) {
        String prefix = "spring.datasource.druid.";
        int maximum = env.getProperty(prefix + "max-active", Integer.class, 8);
        long waitMs = env.getProperty(prefix + "max-wait", Long.class, 2000L);
        int initial = env.getProperty(prefix + "initial-size", Integer.class, 0);
        int minimum = env.getProperty(prefix + "min-idle", Integer.class, 0);
        if (maximum <= 0 || waitMs <= 0 || initial < 0 || initial > maximum
                || minimum < 0 || minimum > maximum) {
            throw new IllegalArgumentException("Invalid datasource budget: max-active/max-wait must be positive; "
                    + "initial-size/min-idle must be between zero and max-active");
        }
        DruidDataSource pool = connection.initializeDataSourceBuilder().type(DruidDataSource.class).build();
        pool.setMaxActive(maximum);
        pool.setMaxWait(waitMs);
        pool.setInitialSize(initial);
        pool.setMinIdle(minimum);
        pool.setValidationQuery("SELECT 1");
        pool.setTestWhileIdle(true);
        return pool;
    }
}
