package com.lanf.integration.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.http.converter.StringHttpMessageConverter;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.apache.http.client.config.RequestConfig;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.impl.conn.PoolingHttpClientConnectionManager;

@Configuration
@EnableConfigurationProperties(ZsqProperties.class)
public class ZsqIntegrationConfig {

    @Bean(destroyMethod = "close")
    public CloseableHttpClient zsqHttpClient(ZsqProperties properties) {
        validateHttpBudgets(properties);
        PoolingHttpClientConnectionManager pool = new PoolingHttpClientConnectionManager();
        pool.setMaxTotal(properties.getHttpMaxConnections());
        pool.setDefaultMaxPerRoute(properties.getHttpMaxConnectionsPerRoute());
        RequestConfig config = RequestConfig.custom()
                .setConnectionRequestTimeout(properties.getHttpConnectionRequestTimeoutMs())
                .setConnectTimeout(properties.getHttpConnectTimeoutMs())
                .setSocketTimeout(properties.getHttpReadTimeoutMs())
                .build();
        return HttpClients.custom().setConnectionManager(pool).setDefaultRequestConfig(config).build();
    }

    @Bean
    public RestTemplate zsqRestTemplate(CloseableHttpClient zsqHttpClient, ObjectMapper zsqObjectMapper,
                                        ZsqProperties properties) {
        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(zsqHttpClient);
        factory.setConnectionRequestTimeout(properties.getHttpConnectionRequestTimeoutMs());
        factory.setConnectTimeout(properties.getHttpConnectTimeoutMs());
        factory.setReadTimeout(properties.getHttpReadTimeoutMs());
        RestTemplate restTemplate = new RestTemplate(factory);
        // 响应仍用 String 原始 JSON，由 ZsqApiResponseParser 二次解析
        StringHttpMessageConverter stringConverter = new StringHttpMessageConverter(StandardCharsets.UTF_8);
        stringConverter.setWriteAcceptCharset(false);
        MappingJackson2HttpMessageConverter jsonConverter = new MappingJackson2HttpMessageConverter(zsqObjectMapper);
        jsonConverter.setSupportedMediaTypes(Arrays.asList(
                MediaType.APPLICATION_JSON,
                new MediaType("application", "*+json")));
        restTemplate.setMessageConverters(Arrays.asList(stringConverter, jsonConverter));
        return restTemplate;
    }

    private static void validateHttpBudgets(ZsqProperties properties) {
        if (properties.getHttpMaxConnections() < 1
                || properties.getHttpMaxConnectionsPerRoute() < 1
                || properties.getHttpMaxConnectionsPerRoute() > properties.getHttpMaxConnections()
                || properties.getHttpConnectionRequestTimeoutMs() < 1
                || properties.getHttpConnectTimeoutMs() < 1
                || properties.getHttpReadTimeoutMs() < 1) {
            throw new IllegalStateException("zsq HTTP budgets must be positive and per-route cannot exceed total");
        }
    }

    @Bean
    public ObjectMapper zsqObjectMapper() {
        return new ObjectMapper();
    }
}
