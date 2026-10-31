package com.lanf.config;

import org.springframework.boot.task.TaskSchedulerBuilder;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/**
 * 显式注册 TaskScheduler，避免 @EnableWebSocket 注册的 defaultSockJsTaskScheduler（NullBean）
 * 与 @EnableScheduling 冲突导致启动失败。
 *
 * @see <a href="https://github.com/spring-projects/spring-boot/issues/28449">Spring Boot #28449</a>
 */
@Configuration
@EnableScheduling
@ConditionalOnProperty(name = "app.scheduling.enabled", havingValue = "true", matchIfMissing = true)
public class SchedulingConfig {

    @Bean
    public ThreadPoolTaskScheduler taskScheduler(TaskSchedulerBuilder builder) {
        return builder.build();
    }
}
