package com.lanf.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.converter.StringHttpMessageConverter;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

@Configuration
public class RestTemplateConfig {

    @org.springframework.beans.factory.annotation.Value("${app.http.connect-timeout-ms:3000}")
    private int connectTimeoutMs = 3000;
    @org.springframework.beans.factory.annotation.Value("${app.http.read-timeout-ms:15000}")
    private int readTimeoutMs = 15000;

    @Bean
    public RestTemplate restTemplate() {
        if (connectTimeoutMs <= 0 || readTimeoutMs <= 0) throw new IllegalStateException("HTTP timeouts must be positive");
        org.springframework.http.client.SimpleClientHttpRequestFactory factory = new org.springframework.http.client.SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(connectTimeoutMs);
        factory.setReadTimeout(readTimeoutMs);
        RestTemplate restTemplate = new RestTemplate(factory);

        // 解决text/plain类型转换问题
        List<HttpMessageConverter<?>> converters = new ArrayList<>();
        // 添加字符串转换器
        StringHttpMessageConverter stringConverter = new StringHttpMessageConverter(StandardCharsets.UTF_8);
        converters.add(stringConverter);
        // 添加JSON转换器
        converters.add(new MappingJackson2HttpMessageConverter());

        restTemplate.setMessageConverters(converters);
        return restTemplate;
    }
}