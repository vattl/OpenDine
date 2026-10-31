package com.lanf.realtime;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.socket.WebSocketSession;
import java.util.HashMap;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
class CashierWakeRecoveryTest {
    @Test void remoteCommittedCursorWakesOnlyLocallyConnectedShop() throws Exception {
        JdbcTemplate jdbc=mock(JdbcTemplate.class);
        WebSocketOutboundDispatcher outbound = new WebSocketOutboundDispatcher(1, 8, 4, 1024, 1000);
        CashierEventWebSocketHub hub=new CashierEventWebSocketHub(outbound);
        WebSocketSession session=mock(WebSocketSession.class);
        when(session.getAttributes()).thenReturn(new HashMap<>());
        when(session.isOpen()).thenReturn(true);
        hub.register(7,session);
        when(jdbc.queryForObject(anyString(),eq(Long.class),eq(7))).thenReturn(42L);
        new CashierWakeRecovery(jdbc,hub).recover();
        verify(session, timeout(1000)).sendMessage(argThat(m->m.getPayload().toString().contains("42")));
        hub.unregister(session);
        reset(jdbc);
        new CashierWakeRecovery(jdbc,hub).recover();
        verifyNoInteractions(jdbc);
        outbound.shutdown();
    }
}
