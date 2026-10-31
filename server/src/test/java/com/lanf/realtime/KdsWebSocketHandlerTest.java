package com.lanf.realtime;

import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.net.URI;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsWebSocketHandlerTest {

    @Test
    void handshakeBindsDeviceIdentityAndCredentialExpiryToSession() throws Exception {
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        KdsWebSocketHandler handler = handler(devices, hub, mock(WebSocketOutboundDispatcher.class));
        WebSocketSession session = session(URI.create(
                "ws://localhost/ws/kds/v2?shop_id=7&screen_tag=workflow_board"), "valid-token");
        Date expiresAt = new Date(System.currentTimeMillis() + 60_000);
        KdsDevice device = device(expiresAt);
        when(devices.findByToken("valid-token")).thenReturn(device);

        handler.afterConnectionEstablished(session);

        assertEquals("KDS-01", session.getAttributes().get("kds_device_code"));
        assertEquals(expiresAt.getTime(), session.getAttributes().get("kds_token_expires_at_ms"));
        verify(hub).register(session, 7, "workflow_board");
    }

    @Test
    void proxiedShopHeaderMustMatchCloudDeviceBinding() throws Exception {
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        KdsWebSocketHandler handler = handler(devices, hub, mock(WebSocketOutboundDispatcher.class));
        WebSocketSession session = session(URI.create("ws://localhost/ws/kds/v2"), "valid-token");
        session.getHandshakeHeaders().set("X-Shop-Id", "8");
        when(devices.findByToken("valid-token")).thenReturn(device(new Date(System.currentTimeMillis() + 60_000)));

        handler.afterConnectionEstablished(session);

        verify(session).close(argThat(status -> status.equals(
                CloseStatus.POLICY_VIOLATION.withReason("X-Shop-Id mismatch"))));
        verify(hub, never()).register(any(WebSocketSession.class), anyInt(), any(String.class));
    }

    @Test
    void pingClosesAConnectionWhoseCredentialExpiredWhileOnline() throws Exception {
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        WebSocketOutboundDispatcher outbound = mock(WebSocketOutboundDispatcher.class);
        KdsWebSocketHandler handler = handler(devices, hub, outbound);
        WebSocketSession session = session(URI.create("ws://localhost/ws/kds/v2"), "token");
        session.getAttributes().put("kds_protocol_version", 2);
        session.getAttributes().put("kds_token_expires_at_ms", System.currentTimeMillis() - 1);

        handler.handleTextMessage(session, new TextMessage("ping"));

        verify(hub).unregister(session);
        verify(session).close(argThat(status -> status.equals(
                CloseStatus.POLICY_VIOLATION.withReason("token expired"))));
        verify(outbound, never()).dispatch(eq(session), any(TextMessage.class));
    }

    @Test
    void v2AcknowledgementReleasesTheExactEventWindowEntry() throws Exception {
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        WebSocketOutboundDispatcher outbound = mock(WebSocketOutboundDispatcher.class);
        KdsWebSocketHandler handler = handler(devices, hub, outbound);
        WebSocketSession session = session(URI.create("ws://localhost/ws/kds/v2"), "token");
        session.getAttributes().put("kds_protocol_version", 2);

        handler.handleTextMessage(session, new TextMessage(
                "{\"protocol_version\":2,\"type\":\"ack\",\"event_seq\":41,\"event_id\":\"event-41\"}"));

        verify(outbound).acknowledge(session, "41:event-41");
    }

    private static KdsWebSocketHandler handler(KdsDeviceService devices, KdsWebSocketHub hub,
                                                WebSocketOutboundDispatcher outbound) {
        KdsWebSocketHandler handler = new KdsWebSocketHandler();
        ReflectionTestUtils.setField(handler, "deviceService", devices);
        ReflectionTestUtils.setField(handler, "hub", hub);
        ReflectionTestUtils.setField(handler, "outbound", outbound);
        return handler;
    }

    private static WebSocketSession session(URI uri, String token) {
        WebSocketSession session = mock(WebSocketSession.class);
        Map<String, Object> attributes = new HashMap<>();
        HttpHeaders headers = new HttpHeaders();
        headers.set("X-Kds-Device-Token", token);
        when(session.getUri()).thenReturn(uri);
        when(session.getHandshakeHeaders()).thenReturn(headers);
        when(session.getAttributes()).thenReturn(attributes);
        when(session.isOpen()).thenReturn(true);
        return session;
    }

    private static KdsDevice device(Date expiresAt) {
        KdsDevice device = new KdsDevice();
        device.setShop_id(7);
        device.setDevice_code("KDS-01");
        device.setScreen_tag("workflow_board");
        device.setToken_expires_at(expiresAt);
        return device;
    }
}
