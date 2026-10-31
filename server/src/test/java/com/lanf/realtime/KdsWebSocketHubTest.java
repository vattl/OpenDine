package com.lanf.realtime;

import com.lanf.kds.event.KdsDeviceCredentialChangedEvent;
import org.junit.jupiter.api.Test;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.HashMap;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsWebSocketHubTest {

    @Test
    void credentialChangeImmediatelyClosesOnlyTheMatchingDeviceSession() throws Exception {
        WebSocketOutboundDispatcher outbound = mock(WebSocketOutboundDispatcher.class);
        KdsWebSocketHub hub = new KdsWebSocketHub(outbound);
        WebSocketSession revoked = session("revoked", 7, "KDS-01");
        WebSocketSession other = session("other", 7, "KDS-02");
        hub.register(revoked, 7, "workflow_board");
        hub.register(other, 7, "workflow_board");

        hub.closeRevokedDeviceSessions(new KdsDeviceCredentialChangedEvent(7, "KDS-01"));

        verify(outbound).unregister(revoked);
        verify(revoked).close(argThat(status -> status.equals(
                CloseStatus.POLICY_VIOLATION.withReason("device credential changed"))));
        assertEquals(1, hub.sessionCount());
    }

    @Test
    void v2BroadcastReservesAnAcknowledgementWindowEntry() {
        WebSocketOutboundDispatcher outbound = mock(WebSocketOutboundDispatcher.class);
        KdsWebSocketHub hub = new KdsWebSocketHub(outbound);
        WebSocketSession session = session("v2", 7, "KDS-01");
        session.getAttributes().put("kds_protocol_version", 2);
        hub.register(session, 7, "workflow_board");
        String envelope = "{\"protocol_version\":2,\"event_seq\":41,\"event_id\":\"event-41\",\"type\":\"order_updated\"}";
        when(outbound.dispatchAcknowledged(eq(session), org.mockito.ArgumentMatchers.any(TextMessage.class),
                eq("41:event-41"))).thenReturn(true);

        assertEquals(1, hub.broadcastV2(7, "workflow_board", envelope));

        verify(outbound).dispatchAcknowledged(eq(session),
                argThat(message -> envelope.equals(message.getPayload())), eq("41:event-41"));
    }

    @Test
    void unregisterEvictsEmptyBucketFromMap() {
        WebSocketOutboundDispatcher outbound = mock(WebSocketOutboundDispatcher.class);
        KdsWebSocketHub hub = new KdsWebSocketHub(outbound);
        WebSocketSession session = session("s1", 99, "KDS-99");
        hub.register(session, 99, "workflow_board");
        assertEquals(1, hub.sessionCount());
        assertEquals(1, hub.bucketCount());

        hub.unregister(session);
        assertEquals(0, hub.sessionCount());
        assertEquals(0, hub.bucketCount());
    }

    private static WebSocketSession session(String id, int shopId, String deviceCode) {
        WebSocketSession session = mock(WebSocketSession.class);
        HashMap<String, Object> attributes = new HashMap<>();
        attributes.put("kds_shop_id", shopId);
        attributes.put("kds_device_code", deviceCode);
        when(session.getId()).thenReturn(id);
        when(session.getAttributes()).thenReturn(attributes);
        when(session.isOpen()).thenReturn(true);
        return session;
    }
}
