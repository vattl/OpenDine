package com.lanf.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class AiToolParserContractTest {
    private com.lanf.service.AiToolResponseParser parser() {
        com.lanf.service.AiToolResponseParser parser = new com.lanf.service.AiToolResponseParser(new ObjectMapper());
        return parser;
    }
    @Test void embeddedJsonPreservesBracesInStringsAndParameterAlias() {
        List<Map<String,Object>> calls=ReflectionTestUtils.invokeMethod(parser(),"parseToolCallsFromText",
                "text [{\"name\":\"create_order\",\"parameters\":{\"note\":\"a } [ b\"}}] trailing text");
        assertNotNull(calls); assertEquals(1,calls.size());
        assertEquals("a } [ b",((Map<?,?>)calls.get(0).get("arguments")).get("note"));
    }
    @Test void plainTextDoesNotBecomeExecutable() {
        assertNull(ReflectionTestUtils.invokeMethod(parser(),"parseToolCallsFromText","please create an order"));
    }
    @Test void normalizePreservesCallIdAndSerializesArguments() throws Exception {
        Map<String,Object> raw=new HashMap<>(); raw.put("id","call-1");raw.put("name","get_order");raw.put("params",Collections.singletonMap("orderId",7));
        List<Map<String,Object>> calls=ReflectionTestUtils.invokeMethod(parser(),"normalizeToolCalls",Collections.singletonList(raw));
        assertEquals("call-1",calls.get(0).get("id"));
        Map<?,?> fn=(Map<?,?>)calls.get(0).get("function");
        assertEquals(7,new ObjectMapper().readValue((String)fn.get("arguments"),Map.class).get("orderId"));
    }
}
