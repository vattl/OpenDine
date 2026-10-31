package com.lanf.controller;

import com.lanf.service.PersonalPaymentWebhookService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.*;

class PersonalAlipayWebhookControllerTest {

    private PersonalAlipayWebhookController controller;
    private PersonalPaymentWebhookService webhookService;
    private static final String SECRET = "my_secret_key_888";

    @BeforeEach
    void setUp() {
        webhookService = mock(PersonalPaymentWebhookService.class);
        controller = new PersonalAlipayWebhookController(webhookService);
        ReflectionTestUtils.setField(controller, "webhookSecret", SECRET);
    }

    @Test
    void testPingEndpointReturnsSuccess() {
        ResponseEntity<Map<String, Object>> response = controller.ping();
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals(true, response.getBody().get("success"));
    }

    @Test
    void testNotifyWithValidSignatureProcessesPayment() {
        Map<String, Object> body = new HashMap<>();
        body.put("channel", "alipay");
        body.put("amount", 1000);
        body.put("timestamp", "1724458800000");
        body.put("event_id", "evt_123456");
        body.put("raw_text", "支付宝通知: 收到一笔 10.00 元款项");

        // Payload: alipay\n1000\n1724458800000\nevt_123456
        String payload = "alipay\n1000\n1724458800000\nevt_123456";
        String sig = PersonalAlipayWebhookController.calculateHmacSha256Hex(SECRET, payload);

        when(webhookService.isEventProcessed("evt_123456")).thenReturn(false);

        ResponseEntity<Map<String, Object>> response = controller.notify(sig, null, body);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals(true, response.getBody().get("success"));
        verify(webhookService).processPayment(eq("evt_123456"), eq("alipay"), eq(1000L), eq("1724458800000"), eq("支付宝通知: 收到一笔 10.00 元款项"), isNull(), isNull());
    }

    @Test
    void testNotifyWithInvalidSignatureReturns401() {
        Map<String, Object> body = new HashMap<>();
        body.put("channel", "alipay");
        body.put("amount", 1000);
        body.put("timestamp", "1724458800000");
        body.put("event_id", "evt_123456");

        ResponseEntity<Map<String, Object>> response = controller.notify("invalid_signature_hex", null, body);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertEquals(false, response.getBody().get("success"));
        assertEquals("bad signature", response.getBody().get("message"));
        verify(webhookService, never()).processPayment(any(), any(), anyLong(), any(), any(), any(), any());
    }

    @Test
    void testNotifyWithDuplicateEventReturnsDuplicateTrue() {
        Map<String, Object> body = new HashMap<>();
        body.put("channel", "wechat");
        body.put("amount", 2500);
        body.put("timestamp", "1724459999000");
        body.put("event_id", "evt_dup_999");

        String payload = "wechat\n2500\n1724459999000\nevt_dup_999";
        String sig = PersonalAlipayWebhookController.calculateHmacSha256Hex(SECRET, payload);

        when(webhookService.isEventProcessed("evt_dup_999")).thenReturn(true);

        ResponseEntity<Map<String, Object>> response = controller.notify(null, sig, body);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals(true, response.getBody().get("success"));
        assertEquals(true, response.getBody().get("duplicate"));
        verify(webhookService, never()).processPayment(any(), any(), anyLong(), any(), any(), any(), any());
    }
}
