package com.lanf.realtime;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.adapter.NativeWebSocketSession;

import javax.annotation.PreDestroy;
import javax.websocket.RemoteEndpoint;
import javax.websocket.SendResult;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Owns all server-to-client WebSocket writes.  A client has one FIFO queue and at most one writer,
 * so a slow client cannot block an HTTP/transaction callback or reorder its own messages.
 */
@Component
public class WebSocketOutboundDispatcher {

    private static final Logger log = LoggerFactory.getLogger(WebSocketOutboundDispatcher.class);
    private static final CloseStatus SLOW_CONSUMER = CloseStatus.SESSION_NOT_RELIABLE.withReason("slow consumer");
    private static final CloseStatus SEND_TIMEOUT = CloseStatus.SESSION_NOT_RELIABLE.withReason("send timeout");
    private static final CloseStatus OVERLOADED = CloseStatus.SESSION_NOT_RELIABLE.withReason("outbound overloaded");
    private static final CloseStatus ACK_WINDOW_OVERFLOW = CloseStatus.SESSION_NOT_RELIABLE.withReason("ack window overflow");
    private static final CloseStatus ACK_TIMEOUT = CloseStatus.SESSION_NOT_RELIABLE.withReason("ack timeout");

    private final Map<WebSocketSession, SessionQueue> queues = new IdentityHashMap<>();
    private final ThreadPoolExecutor writers;
    private final ScheduledExecutorService watchdog;
    private final int maxPendingMessages;
    private final int maxPendingBytes;
    private final long sendTimeoutMs;
    private final long ackTimeoutMs;
    private final FrameSender frameSender;

    @Autowired(required = false)
    private com.lanf.kds.service.KdsMetricsService metricsService;

    public void setMetricsService(com.lanf.kds.service.KdsMetricsService metricsService) {
        this.metricsService = metricsService;
    }

    @Autowired
    public WebSocketOutboundDispatcher(
            @Value("${app.websocket.outbound-workers:4}") int workers,
            @Value("${app.websocket.outbound-queue-capacity:256}") int queueCapacity,
            @Value("${app.websocket.session-max-pending-messages:32}") int maxPendingMessages,
            @Value("${app.websocket.session-max-pending-bytes:65536}") int maxPendingBytes,
            @Value("${app.websocket.send-timeout-ms:5000}") long sendTimeoutMs,
            @Value("${app.websocket.ack-timeout-ms:15000}") long ackTimeoutMs) {
        this(workers, queueCapacity, maxPendingMessages, maxPendingBytes, sendTimeoutMs, ackTimeoutMs,
                new NativeAsyncFrameSender(sendTimeoutMs));
    }

    WebSocketOutboundDispatcher(int workers, int queueCapacity, int maxPendingMessages,
                                int maxPendingBytes, long sendTimeoutMs) {
        this(workers, queueCapacity, maxPendingMessages, maxPendingBytes, sendTimeoutMs, 15000,
                new NativeAsyncFrameSender(sendTimeoutMs));
    }

    WebSocketOutboundDispatcher(
            int workers,
            int queueCapacity,
            int maxPendingMessages,
            int maxPendingBytes,
            long sendTimeoutMs,
            FrameSender frameSender) {
        this(workers, queueCapacity, maxPendingMessages, maxPendingBytes, sendTimeoutMs, 15000, frameSender);
    }

    WebSocketOutboundDispatcher(
            int workers,
            int queueCapacity,
            int maxPendingMessages,
            int maxPendingBytes,
            long sendTimeoutMs,
            long ackTimeoutMs,
            FrameSender frameSender) {
        int workerCount = Math.max(1, workers);
        this.maxPendingMessages = Math.max(1, maxPendingMessages);
        this.maxPendingBytes = Math.max(1024, maxPendingBytes);
        this.sendTimeoutMs = Math.max(100, sendTimeoutMs);
        this.ackTimeoutMs = Math.max(100, ackTimeoutMs);
        this.frameSender = frameSender;
        this.writers = new ThreadPoolExecutor(workerCount, workerCount, 0, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(Math.max(workerCount, queueCapacity)), daemonFactory("ws-outbound"),
                new ThreadPoolExecutor.AbortPolicy());
        ScheduledThreadPoolExecutor scheduler = new ScheduledThreadPoolExecutor(1, daemonFactory("ws-watchdog"));
        scheduler.setRemoveOnCancelPolicy(true);
        this.watchdog = scheduler;
    }

    public void register(WebSocketSession session) {
        synchronized (queues) {
            queues.put(session, new SessionQueue(session));
        }
    }

    public void unregister(WebSocketSession session) {
        SessionQueue queue;
        synchronized (queues) {
            queue = queues.remove(session);
        }
        if (queue != null) {
            synchronized (queue) {
                queue.closed = true;
                queue.pending.clear();
                queue.pendingBytes = 0;
                clearAcknowledgements(queue);
            }
        }
    }

    /** Returns false when the session is unavailable or has been closed as a slow consumer. */
    public boolean dispatch(WebSocketSession session, TextMessage message) {
        return dispatchInternal(session, message, null);
    }

    public boolean dispatchAcknowledged(WebSocketSession session, TextMessage message, String acknowledgementKey) {
        if (acknowledgementKey == null || acknowledgementKey.trim().isEmpty()) {
            return false;
        }
        return dispatchInternal(session, message, acknowledgementKey);
    }

    private boolean dispatchInternal(WebSocketSession session, TextMessage message, String acknowledgementKey) {
        if (session == null || message == null) {
            return false;
        }
        SessionQueue queue = queueFor(session);
        boolean schedule = false;
        boolean closeSlowConsumer = false;
        boolean closeAckOverflow = false;
        synchronized (queue) {
            if (queue.closed || !session.isOpen()) {
                return false;
            }
            int bytes = message.getPayloadLength();
            if (acknowledgementKey != null && queue.acknowledgements.containsKey(acknowledgementKey)) {
                return true;
            }
            if (acknowledgementKey != null &&
                    (queue.acknowledgements.size() >= maxPendingMessages
                            || queue.acknowledgedBytes + bytes > maxPendingBytes)) {
                queue.closed = true;
                closeAckOverflow = true;
            } else if (bytes > maxPendingBytes || queue.pending.size() >= maxPendingMessages
                    || queue.pendingBytes + bytes > maxPendingBytes) {
                queue.closed = true;
                closeSlowConsumer = true;
            } else {
                if (acknowledgementKey != null) {
                    PendingAcknowledgement acknowledgement = new PendingAcknowledgement(bytes);
                    queue.acknowledgements.put(acknowledgementKey, acknowledgement);
                    queue.acknowledgedBytes += bytes;
                    acknowledgement.timeout = watchdog.schedule(
                            () -> removeAndClose(queue, ACK_TIMEOUT), ackTimeoutMs, TimeUnit.MILLISECONDS);
                }
                queue.pending.addLast(message);
                queue.pendingBytes += bytes;
                if (metricsService != null) {
                    metricsService.recordWsDispatched(1);
                }
                if (!queue.writerScheduled) {
                    queue.writerScheduled = true;
                    schedule = true;
                }
            }
        }
        if (closeAckOverflow) {
            removeAndClose(queue, ACK_WINDOW_OVERFLOW);
            return false;
        }
        if (closeSlowConsumer) {
            removeAndClose(queue, SLOW_CONSUMER);
            return false;
        }
        if (schedule) {
            try {
                writers.execute(() -> drain(queue));
            } catch (RejectedExecutionException ex) {
                synchronized (queue) {
                    queue.writerScheduled = false;
                    queue.closed = true;
                    queue.pending.clear();
                    queue.pendingBytes = 0;
                }
                removeAndClose(queue, OVERLOADED);
                return false;
            }
        }
        return true;
    }

    public boolean acknowledge(WebSocketSession session, String acknowledgementKey) {
        if (session == null || acknowledgementKey == null) {
            return false;
        }
        SessionQueue queue;
        synchronized (queues) {
            queue = queues.get(session);
        }
        if (queue == null) return false;
        synchronized (queue) {
            PendingAcknowledgement acknowledgement = queue.acknowledgements.remove(acknowledgementKey);
            if (acknowledgement == null) return false;
            acknowledgement.timeout.cancel(false);
            queue.acknowledgedBytes -= acknowledgement.bytes;
            if (metricsService != null) {
                metricsService.recordWsAcknowledged();
            }
            return true;
        }
    }

    private SessionQueue queueFor(WebSocketSession session) {
        synchronized (queues) {
            SessionQueue queue = queues.get(session);
            if (queue == null) {
                queue = new SessionQueue(session);
                queues.put(session, queue);
            }
            return queue;
        }
    }

    private void drain(SessionQueue queue) {
        TextMessage message;
        synchronized (queue) {
            if (queue.closed || !queue.session.isOpen()) {
                queue.writerScheduled = false;
                return;
            }
            message = queue.pending.pollFirst();
            if (message == null) {
                queue.writerScheduled = false;
                return;
            }
            queue.pendingBytes -= message.getPayloadLength();
        }
        ScheduledFuture<?> timeout = watchdog.schedule(
                () -> removeAndClose(queue, SEND_TIMEOUT), sendTimeoutMs, TimeUnit.MILLISECONDS);
        CompletionStage<Void> completion;
        try {
            completion = frameSender.send(queue.session, message);
        } catch (IOException | RuntimeException ex) {
            timeout.cancel(false);
            log.debug("event=ws_outbound_send_failed session_id={} error_type={}",
                    queue.session.getId(), ex.getClass().getSimpleName());
            removeAndClose(queue, SLOW_CONSUMER);
            return;
        }
        completion.whenComplete((ignored, failure) -> {
            timeout.cancel(false);
            if (failure != null) {
                log.debug("event=ws_outbound_send_failed session_id={} error_type={}",
                        queue.session.getId(), failure.getClass().getSimpleName());
                removeAndClose(queue, SLOW_CONSUMER);
                return;
            }
            scheduleDrain(queue);
        });
    }

    private void scheduleDrain(SessionQueue queue) {
        synchronized (queue) {
            if (queue.closed) {
                queue.writerScheduled = false;
                return;
            }
        }
        try {
            writers.execute(() -> drain(queue));
        } catch (RejectedExecutionException ex) {
            removeAndClose(queue, OVERLOADED);
        }
    }

    private void removeAndClose(SessionQueue queue, CloseStatus status) {
        int pendingMessages;
        int pendingBytes;
        int unacknowledgedMessages;
        int unacknowledgedBytes;
        synchronized (queue) {
            if (queue.closeInitiated) {
                return;
            }
            queue.closeInitiated = true;
            pendingMessages = queue.pending.size();
            pendingBytes = queue.pendingBytes;
            unacknowledgedMessages = queue.acknowledgements.size();
            unacknowledgedBytes = queue.acknowledgedBytes;
            queue.closed = true;
            queue.pending.clear();
            queue.pendingBytes = 0;
            clearAcknowledgements(queue);
        }
        synchronized (queues) {
            queues.remove(queue.session);
        }
        if (metricsService != null && status != null) {
            String reason = status.getReason();
            metricsService.recordWsDisconnect(reason != null ? reason : status.toString());
        }
        log.warn("event=ws_outbound_session_closed reason={} session_id={} pending_messages={} pending_bytes={} unacknowledged_messages={} unacknowledged_bytes={}",
                status.getReason(), queue.session.getId(), pendingMessages, pendingBytes,
                unacknowledgedMessages, unacknowledgedBytes);
        try {
            if (queue.session.isOpen()) {
                queue.session.close(status);
            }
        } catch (IOException ex) {
            log.debug("[ws] close failed id={}: {}", queue.session.getId(), ex.getMessage());
        }
    }

    int trackedSessionCount() {
        synchronized (queues) {
            return queues.size();
        }
    }

    @PreDestroy
    void shutdown() {
        synchronized (queues) {
            for (SessionQueue queue : queues.values()) {
                synchronized (queue) {
                    queue.closed = true;
                    queue.pending.clear();
                    queue.pendingBytes = 0;
                    clearAcknowledgements(queue);
                }
            }
            queues.clear();
        }
        writers.shutdownNow();
        watchdog.shutdownNow();
    }

    private static ThreadFactory daemonFactory(String prefix) {
        AtomicInteger sequence = new AtomicInteger();
        return runnable -> {
            Thread thread = new Thread(runnable, prefix + "-" + sequence.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        };
    }

    private static void clearAcknowledgements(SessionQueue queue) {
        for (PendingAcknowledgement acknowledgement : queue.acknowledgements.values()) {
            if (acknowledgement.timeout != null) acknowledgement.timeout.cancel(false);
        }
        queue.acknowledgements.clear();
        queue.acknowledgedBytes = 0;
    }

    @FunctionalInterface
    interface FrameSender {
        CompletionStage<Void> send(WebSocketSession session, TextMessage message) throws IOException;
    }

    private static final class NativeAsyncFrameSender implements FrameSender {
        private final long sendTimeoutMs;

        private NativeAsyncFrameSender(long sendTimeoutMs) {
            this.sendTimeoutMs = Math.max(100, sendTimeoutMs);
        }

        @Override
        public CompletionStage<Void> send(WebSocketSession session, TextMessage message) throws IOException {
            if (!(session instanceof NativeWebSocketSession)) {
                session.sendMessage(message);
                return CompletableFuture.completedFuture(null);
            }
            javax.websocket.Session nativeSession =
                    ((NativeWebSocketSession) session).getNativeSession(javax.websocket.Session.class);
            if (nativeSession == null) {
                session.sendMessage(message);
                return CompletableFuture.completedFuture(null);
            }
            CompletableFuture<Void> completion = new CompletableFuture<>();
            RemoteEndpoint.Async remote = nativeSession.getAsyncRemote();
            remote.setSendTimeout(sendTimeoutMs);
            remote.sendText(message.getPayload(), result -> complete(completion, result));
            return completion;
        }

        private static void complete(CompletableFuture<Void> completion, SendResult result) {
            if (result.isOK()) {
                completion.complete(null);
            } else {
                completion.completeExceptionally(result.getException());
            }
        }
    }

    private static final class SessionQueue {
        private final WebSocketSession session;
        private final ArrayDeque<TextMessage> pending = new ArrayDeque<>();
        private final Map<String, PendingAcknowledgement> acknowledgements = new LinkedHashMap<>();
        private int pendingBytes;
        private int acknowledgedBytes;
        private boolean writerScheduled;
        private boolean closed;
        private boolean closeInitiated;

        private SessionQueue(WebSocketSession session) {
            this.session = session;
        }
    }

    private static final class PendingAcknowledgement {
        private final int bytes;
        private ScheduledFuture<?> timeout;

        private PendingAcknowledgement(int bytes) {
            this.bytes = bytes;
        }
    }
}
