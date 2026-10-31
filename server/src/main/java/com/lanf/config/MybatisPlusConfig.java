package com.lanf.config;

import com.baomidou.mybatisplus.autoconfigure.ConfigurationCustomizer;
import com.baomidou.mybatisplus.extension.plugins.PaginationInterceptor;
import com.lanf.common.LocalDateTimeCompatHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.LocalDateTime;

/**
 * MybatisPlus配置类
 */
@Configuration
public class MybatisPlusConfig {

    @Bean
    public PaginationInterceptor paginationInterceptor(){
        return new PaginationInterceptor();
    }

    /**
     * 注册 LocalDateTime 兼容 TypeHandler（老 Druid 连接池不支持 getObject(LocalDateTime.class)，
     * 改用 getTimestamp/setTimestamp）。全局生效，覆盖 MyBatis 默认注册。
     */
    @Bean
    public ConfigurationCustomizer jsr310CompatCustomizer() {
        return configuration -> configuration.getTypeHandlerRegistry()
                .register(LocalDateTime.class, new LocalDateTimeCompatHandler());
    }
}
