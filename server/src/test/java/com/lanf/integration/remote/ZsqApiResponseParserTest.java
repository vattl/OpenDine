package com.lanf.integration.remote;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class ZsqApiResponseParserTest {

    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void parseDataAsJsonStringForMap() {
        String json = "{\"code\":200,\"message\":\"ok\",\"data\":\"{\\\"msg\\\":\\\"支付成功\\\",\\\"payCode\\\":\\\"WF808520423821701\\\"}\"}";
        ZsqApiResponse<Map<String, Object>> api = ZsqApiResponseParser.parse(mapper, json,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
        assertEquals(200, api.getCode());
        assertNotNull(api.getData());
        assertEquals("支付成功", api.getData().get("msg"));
        assertEquals("WF808520423821701", api.getData().get("payCode"));
    }

    @Test
    void parseDataAsObjectForMap() {
        String json = "{\"code\":200,\"data\":{\"msg\":\"支付成功\",\"payCode\":\"WF1\"}}";
        ZsqApiResponse<Map<String, Object>> api = ZsqApiResponseParser.parse(mapper, json,
                new TypeReference<ZsqApiResponse<Map<String, Object>>>() {});
        assertEquals("WF1", api.getData().get("payCode"));
    }

    @Test
    void parseArrayOfJsonStringsForListMap() {
        String json = "{\"code\":200,\"data\":[\"{\\\"status\\\":30}\",\"{\\\"status\\\":40}\"]}";
        ZsqApiResponse<List<Map<String, Object>>> api = ZsqApiResponseParser.parse(mapper, json,
                new TypeReference<ZsqApiResponse<List<Map<String, Object>>>>() {});
        assertEquals(2, api.getData().size());
        assertEquals(30, ((Number) api.getData().get(0).get("status")).intValue());
    }
}
