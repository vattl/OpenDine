package com.lanf.realtime;

import org.junit.jupiter.api.Test;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WebSocketOutboundDispatcherTest {

    @Test
    void keepsNativeWriteInFlightUntilTransportCompletionAndIsolatesHealthyPeer() throws Exception {
        WebSocketSession slow = openSession("slow-native");
        WebSocketSession healthy = openSession("healthy-native");
        CompletableFuture<Void> blockedTransportWrite = new CompletableFuture<>();
        CountDownLatch slowWriteStarted = new CountDownLatch(1);
        CountDownLatch healthyWriteCompleted = new CountDownLatch(1);
        WebSocketOutboundDispatcher.FrameSender sender = (session, message) -> {
            if (session == slow) {
                slowWriteStarted.countDown();
                return blockedTransportWrite;
            }
            healthyWriteCompleted.countDown();
            return CompletableFuture.completedFuture(null);
        };
        WebSocketOutboundDispatcher dispatcher =
                new WebSocketOutboundDispatcher(1, 8, 1, 1024, 1000, sender);

        dispatcher.register(slow);
        dispatcher.register(healthy);
        assertTrue(dispatcher.dispatch(slow, new TextMessage("in-flight")));
        assertTrue(slowWriteStarted.await(1, TimeUnit.SECONDS));
        assertTrue(dispatcher.dispatch(slow, new TextMessage("queued")));
        assertFalse(dispatcher.dispatch(slow, new TextMessage("overflow")));
        assertTrue(dispatcher.dispatch(healthy, new TextMessage("still-healthy")));

        verify(slow, timeout(1000)).close(argThat(status ->
                status.equals(CloseStatus.SESSION_NOT_RELIABLE.withReason("slow consumer"))));
        assertTrue(healthyWriteCompleted.await(1, TimeUnit.SECONDS));
        assertTrue(healthy.isOpen());
        blockedTransportWrite.complete(null);
        dispatcher.shutdown();
    }

    @Test
    void closesOnlySessionWhoseAcknowledgementWindowOverflows() throws Exception {
        WebSocketOutboundDispatcher.FrameSender sender =
                (session, message) -> CompletableFuture.completedFuture(null);
        WebSocketOutboundDispatcher dispatcher =
                new WebSocketOutboundDispatcher(2, 8, 2, 1024, 1000, 5000, sender);
        WebSocketSession slow = openSession("slow-ack");
        WebSocketSession healthy = openSession("healthy-ack");
        dispatcher.register(slow);
        dispatcher.register(healthy);

        assertTrue(dispatcher.dispatchAcknowledged(slow, new TextMessage("one"), "1:event-1"));
        assertTrue(dispatcher.dispatchAcknowledged(slow, new TextMessage("two"), "2:event-2"));
        assertFalse(dispatcher.dispatchAcknowledged(slow, new TextMessage("three"), "3:event-3"));
        assertTrue(dispatcher.dispatchAcknowledged(healthy, new TextMessage("one"), "1:event-1"));
        assertTrue(dispatcher.acknowledge(healthy, "1:event-1"));
        assertTrue(dispatcher.dispatchAcknowledged(healthy, new TextMessage("two"), "2:event-2"));

        verify(slow, timeout(1000)).close(argThat(status ->
                status.equals(CloseStatus.SESSION_NOT_RELIABLE.withReason("ack window overflow"))));
        assertTrue(healthy.isOpen());
        dispatcher.shutdown();
    }

    @Test
    void closesSessionWhenEventAcknowledgementTimesOut() throws Exception {
        WebSocketOutboundDispatcher.FrameSender sender =
                (session, message) -> CompletableFuture.completedFuture(null);
        WebSocketOutboundDispatcher dispatcher =
                new WebSocketOutboundDispatcher(1, 8, 4, 1024, 1000, 100, sender);
        WebSocketSession session = openSession("ack-timeout");
        dispatcher.register(session);

        assertTrue(dispatcher.dispatchAcknowledged(
                session, new TextMessage("event"), "9:event-9"));

        verify(session, timeout(1000)).close(argThat(status ->
                status.equals(CloseStatus.SESSION_NOT_RELIABLE.withReason("ack timeout"))));
        dispatcher.shutdown();
    }

    @Test
    void sendsEachSessionInSubmissionOrderOnWorkerThread() throws Exception {
        WebSocketOutboundDispatcher dispatcher = new WebSocketOutboundDispatcher(1, 8, 4, 1024, 1000);
        WebSocketSession session = openSession("ordered");
        List<String> sent = new ArrayList<>();
        CountDownLatch done = new CountDownLatch(2);
        doAnswer(invocation -> {
            sent.add(((TextMessage) invocation.getArgument(0)).getPayload());
            done.countDown();
            return null;
        }).when(session).sendMessage(any(TextMessage.class));

        dispatcher.register(session);
        assertTrue(dispatcher.dispatch(session, new TextMessage("first")));
        assertTrue(dispatcher.dispatch(session, new TextMessage("second")));

        assertTrue(done.await(1, TimeUnit.SECONDS));
        org.junit.jupiter.api.Assertions.assertEquals(Arrays.asList("first", "second"), sent);
        dispatcher.shutdown();
    }

    @Test
    void closesSessionWhenPendingQueueWouldOverflow() throws Exception {
        WebSocketOutboundDispatcher dispatcher = new WebSocketOutboundDispatcher(1, 8, 1, 1024, 1000);
        WebSocketSession session = openSession("slow");
        CountDownLatch firstWriteStarted = new CountDownLatch(1);
        CountDownLatch releaseWrite = new CountDownLatch(1);
        doAnswer(invocation -> {
            firstWriteStarted.countDown();
            releaseWrite.await(1, TimeUnit.SECONDS);
            return null;
        }).when(session).sendMessage(any(TextMessage.class));

        dispatcher.register(session);
        assertTrue(dispatcher.dispatch(session, new TextMessage("first")));
        assertTrue(firstWriteStarted.await(1, TimeUnit.SECONDS));
        assertTrue(dispatcher.dispatch(session, new TextMessage("queued")));
        assertFalse(dispatcher.dispatch(session, new TextMessage("overflow")));

        verify(session, timeout(1000)).close(argThat(status -> status.equals(CloseStatus.SESSION_NOT_RELIABLE.withReason("slow consumer"))));
        releaseWrite.countDown();
        dispatcher.shutdown();
    }

    @Test
    void closesStuckWriteAtConfiguredTimeout() throws Exception {
        WebSocketOutboundDispatcher dispatcher = new WebSocketOutboundDispatcher(1, 8, 4, 1024, 100);
        WebSocketSession session = openSession("timeout");
        CountDownLatch releaseWrite = new CountDownLatch(1);
        doAnswer(invocation -> {
            releaseWrite.await(1, TimeUnit.SECONDS);
            return null;
        }).when(session).sendMessage(any(TextMessage.class));

        dispatcher.register(session);
        assertTrue(dispatcher.dispatch(session, new TextMessage("stuck")));

        verify(session, timeout(1000)).close(argThat(status -> status.equals(CloseStatus.SESSION_NOT_RELIABLE.withReason("send timeout"))));
        releaseWrite.countDown();
        dispatcher.shutdown();
    }

    private static WebSocketSession openSession(String id) {
        WebSocketSession session = mock(WebSocketSession.class);
        when(session.isOpen()).thenReturn(true);
        when(session.getId()).thenReturn(id);
        return session;
    }
}
