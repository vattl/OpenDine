package com.lanf.integration.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.http.impl.client.CloseableHttpClient;
import org.junit.jupiter.api.Test;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ZsqIntegrationConfigTest {

    @Test
    void configUsesPooledRequestFactoryWithFiniteBudgets() throws Exception {
        ZsqProperties properties = new ZsqProperties();
        properties.setHttpMaxConnections(4);
        properties.setHttpMaxConnectionsPerRoute(4);
        properties.setHttpConnectionRequestTimeoutMs(1000);
        properties.setHttpConnectTimeoutMs(2000);
        properties.setHttpReadTimeoutMs(5000);
        ZsqIntegrationConfig config = new ZsqIntegrationConfig();
        try (CloseableHttpClient client = config.zsqHttpClient(properties)) {
            RestTemplate restTemplate = config.zsqRestTemplate(client, new ObjectMapper(), properties);
            assertTrue(restTemplate.getRequestFactory() instanceof HttpComponentsClientHttpRequestFactory);
        }
    }

    @Test
    void rejectsUnboundedOrInconsistentPoolBudget() {
        ZsqProperties properties = new ZsqProperties();
        properties.setHttpMaxConnections(2);
        properties.setHttpMaxConnectionsPerRoute(3);
        assertThrows(IllegalStateException.class, () -> new ZsqIntegrationConfig().zsqHttpClient(properties));
    }
}
