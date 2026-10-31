package com.lanf.integration.remote;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.integration.config.ZsqProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class ZsqRemoteClientOrderLogTest {

    @Test
    void cancelOpenOrderAcceptsSuccessfulNullDataResponse() {
        RestTemplate restTemplate = new RestTemplate();
        MockRestServiceServer server = MockRestServiceServer.bindTo(restTemplate).build();
        ZsqProperties properties = new ZsqProperties();
        properties.setApiBase("https://zsq.wlhulian.com/api");
        ZsqRemoteClient client = new ZsqRemoteClient(restTemplate, new ObjectMapper(), properties);

        server.expect(requestTo("https://zsq.wlhulian.com/api/open/order/cancel"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "token"))
                .andExpect(content().json("{\"id\":54237416}"))
                .andRespond(withSuccess("{\"code\":200,\"message\":\"操作成功\",\"traceId\":\"b7e90586df04458c91b20bb30075102e\",\"data\":null}",
                        MediaType.APPLICATION_JSON));

        Map<String, Object> result = client.cancelOpenOrder("token", 54237416L);

        assertNull(result);
        server.verify();
    }

    @Test
    void requestsOrderLogUsingPathAndIdQueryParameter() {
        RestTemplate restTemplate = new RestTemplate();
        MockRestServiceServer server = MockRestServiceServer.bindTo(restTemplate).build();
        ZsqProperties properties = new ZsqProperties();
        properties.setApiBase("https://zsq.wlhulian.com/api");
        ZsqRemoteClient client = new ZsqRemoteClient(restTemplate, new ObjectMapper(), properties);

        server.expect(requestTo("https://zsq.wlhulian.com/api/open/order/log/54160088?id=54160088"))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "token"))
                .andRespond(withSuccess("{\"code\":200,\"message\":\"操作成功\",\"data\":[{\"id\":841183281213701,\"subType\":201,\"content\":\"回传状态: 已完成\"}]}",
                        MediaType.APPLICATION_JSON));

        List<Map<String, Object>> logs = client.getOpenOrderLog("token", 54160088L);

        assertEquals(841183281213701L, ((Number) logs.get(0).get("id")).longValue());
        server.verify();
    }
}
