package com.lanf.controller;

import com.lanf.service.IFeishuInboxService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

public class FeishuCallbackControllerTest {

    private FeishuCallbackController controller;
    private IFeishuInboxService mockService;

    @BeforeEach
    public void setUp() {
        controller = new FeishuCallbackController();
        mockService = mock(IFeishuInboxService.class);
        ReflectionTestUtils.setField(controller, "feishuInboxService", mockService);
    }

    @Test
    public void testHandleCallback_urlVerification_returnsChallenge() {
        Map<String, Object> respMap = new HashMap<>();
        respMap.put("challenge", "my_challenge_str");
        when(mockService.handleCallback(anyString(), anyMap())).thenReturn(respMap);

        ResponseEntity<Map<String, Object>> resp = controller.handleCallback("{\"type\":\"url_verification\"}", Collections.emptyMap());
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertEquals("my_challenge_str", resp.getBody().get("challenge"));
    }

    @Test
    public void testHandleCallback_eventSuccess_returnsCodeZero() {
        Map<String, Object> respMap = new HashMap<>();
        respMap.put("code", 0);
        when(mockService.handleCallback(anyString(), anyMap())).thenReturn(respMap);

        ResponseEntity<Map<String, Object>> resp = controller.handleCallback("{\"header\":{}}", Collections.emptyMap());
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertEquals(0, resp.getBody().get("code"));
    }

    @Test
    public void testHandleCallback_tokenMismatch_returns403() {
        Map<String, Object> respMap = new HashMap<>();
        respMap.put("code", 403);
        respMap.put("msg", "Token mismatch");
        when(mockService.handleCallback(anyString(), anyMap())).thenReturn(respMap);

        ResponseEntity<Map<String, Object>> resp = controller.handleCallback("{\"header\":{}}", Collections.emptyMap());
        assertEquals(HttpStatus.FORBIDDEN, resp.getStatusCode());
        assertEquals(403, resp.getBody().get("code"));
    }
}
