package com.lanf.config;

import com.alibaba.druid.pool.DruidDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

class DataSourceBudgetConfigurationTest {
    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(DataSourceAutoConfiguration.class))
            .withUserConfiguration(DataSourceBudgetConfiguration.class)
            .withPropertyValues("spring.datasource.type=com.alibaba.druid.pool.DruidDataSource",
                    "spring.datasource.driver-class-name=org.h2.Driver",
                    "spring.datasource.url=jdbc:h2:mem:budget",
                    "spring.datasource.username=sa", "spring.datasource.password=");

    @Test
    void actualDataSourceHasFiniteDefaultsAndPreservesConnectionSettings() {
        runner.run(context -> {
            assertThat(context).hasSingleBean(DataSource.class);
            DruidDataSource pool = context.getBean(DruidDataSource.class);
            assertThat(pool.getMaxActive()).isEqualTo(8);
            assertThat(pool.getMaxWait()).isEqualTo(2000);
            assertThat(pool.getInitialSize()).isZero();
            assertThat(pool.getMinIdle()).isZero();
            assertThat(pool.getUrl()).isEqualTo("jdbc:h2:mem:budget");
            assertThat(pool.getUsername()).isEqualTo("sa");
        });
    }

    @Test
    void saturatedPoolTimesOutAndCanBeUsedAfterConnectionsReturn() {
        runner.withPropertyValues("spring.datasource.druid.max-active=2",
                "spring.datasource.druid.max-wait=80").run(context -> {
            DruidDataSource pool = context.getBean(DruidDataSource.class);
            assertThat(pool.getMaxActive()).isEqualTo(2);
            assertThat(pool.getMaxWait()).isEqualTo(80);
            try (Connection first = pool.getConnection(); Connection second = pool.getConnection()) {
                long start = System.nanoTime();
                assertThrows(SQLException.class, pool::getConnection);
                long elapsed = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
                assertThat(elapsed).isBetween(40L, 1500L);
                assertThat(pool.getActiveCount()).isEqualTo(2);
            }
            try (Connection recovered = pool.getConnection()) {
                assertThat(recovered.isClosed()).isFalse();
            }
        });
    }

    @Test
    void existingDataSourceIsNotReplaced() {
        DataSource existing = org.mockito.Mockito.mock(DataSource.class);
        runner.withBean("customDataSource", DataSource.class, () -> existing).run(context -> {
            assertThat(context).hasSingleBean(DataSource.class);
            assertThat(context.getBean(DataSource.class)).isSameAs(existing);
        });
    }

    @Test
    void invalidOrInfiniteBudgetsFailAtStartup() {
        for (String value : new String[]{"max-wait=-1", "max-wait=0", "max-active=0",
                "initial-size=9", "min-idle=9"}) {
            runner.withPropertyValues("spring.datasource.druid." + value)
                    .run(context -> assertThat(context).hasFailed());
        }
    }
}
