package com.lanf.controller;

import com.lanf.properties.FeishuProperties;
import com.lanf.service.IFeishuInboxService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.servlet.HandlerMapping;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

public class BbqInboxControllerTest {

    private BbqInboxController controller;
    private IFeishuInboxService mockService;
    private FeishuProperties feishuProperties;

    @BeforeEach
    public void setUp() {
        controller = new BbqInboxController();
        mockService = mock(IFeishuInboxService.class);
        feishuProperties = new FeishuProperties();
        feishuProperties.setInboxToken("secret_token_123");

        ReflectionTestUtils.setField(controller, "feishuInboxService", mockService);
        ReflectionTestUtils.setField(controller, "feishuProperties", feishuProperties);
    }

    @Test
    public void testListInbox_withoutToken_returns401() {
        ResponseEntity<Map<String, Object>> resp = controller.listInbox(null, null, null);
        assertEquals(HttpStatus.UNAUTHORIZED, resp.getStatusCode());
        assertEquals(401, resp.getBody().get("code"));
    }

    @Test
    public void testListInbox_withValidHeaderToken_returns200() {
        Map<String, Object> serviceResp = new HashMap<>();
        serviceResp.put("code", 0);
        serviceResp.put("data", Collections.singletonMap("items", Collections.emptyList()));
        when(mockService.listPendingInboxItems(null)).thenReturn(serviceResp);

        ResponseEntity<Map<String, Object>> resp = controller.listInbox(null, null, "secret_token_123");
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertEquals(0, resp.getBody().get("code"));
        verify(mockService).listPendingInboxItems(null);
    }

    @Test
    public void testListInbox_withValidQueryToken_returns200() {
        Map<String, Object> serviceResp = new HashMap<>();
        serviceResp.put("code", 0);
        serviceResp.put("data", Collections.singletonMap("items", Collections.emptyList()));
        when(mockService.listPendingInboxItems("xhs")).thenReturn(serviceResp);

        ResponseEntity<Map<String, Object>> resp = controller.listInbox("xhs", "secret_token_123", null);
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertEquals(0, resp.getBody().get("code"));
        verify(mockService).listPendingInboxItems("xhs");
    }

    @Test
    public void testAckInbox_success() {
        when(mockService.ackInboxItem("20261031_001", "ok")).thenReturn(Collections.singletonMap("code", 0));

        Map<String, Object> body = new HashMap<>();
        body.put("inbox_id", "20261031_001");
        body.put("status", "ok");

        ResponseEntity<Map<String, Object>> resp = controller.ackInbox(body, null, "secret_token_123");
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertEquals(0, resp.getBody().get("code"));
        verify(mockService).ackInboxItem("20261031_001", "ok");
    }

    @Test
    public void testAckInbox_emptyBody_returns400() {
        ResponseEntity<Map<String, Object>> resp = controller.ackInbox(Collections.emptyMap(), null, "secret_token_123");
        assertEquals(HttpStatus.BAD_REQUEST, resp.getStatusCode());
        assertEquals(400, resp.getBody().get("code"));
    }

    @Test
    public void testGetInboxFile_success() throws IOException {
        File tempFile = File.createTempFile("test_meta_", ".json");
        Files.write(tempFile.toPath(), "{\"message_id\":\"om_1\"}".getBytes());

        when(mockService.getInboxFile("20261031_001", "meta.json")).thenReturn(tempFile);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE, "/bbq/inbox/{inboxId}/**");
        request.setAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE, "/bbq/inbox/20261031_001/meta.json");

        ResponseEntity<Resource> resp = controller.getInboxFile("20261031_001", null, "secret_token_123", request);
        assertEquals(HttpStatus.OK, resp.getStatusCode());
        assertNotNull(resp.getBody());
        assertTrue(resp.getBody().exists());

        tempFile.delete();
    }
}
