package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.KdsScreenTag;
import com.lanf.realtime.KdsWebSocketHub;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionSynchronizationUtils;

import java.util.*;

import static org.mockito.Mockito.*;

class KdsPushServiceTransactionBroadcastTest {

    @AfterEach
    void tearDown() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clear();
        }
    }

    @Test
    void broadcastV2EnvelopeExecutesDuringAfterCommitWithoutDropping() {
        TransactionSynchronizationManager.initSynchronization();
        TransactionSynchronizationManager.setActualTransactionActive(true);

        KdsWebSocketHub hub = mock(KdsWebSocketHub.class);
        KdsPushService pushService = new KdsPushService();
        ReflectionTestUtils.setField(pushService, "hub", hub);
        ReflectionTestUtils.setField(pushService, "objectMapper", new ObjectMapper());

        // Simulate KdsWorkflowV2Service.publishEnvelope registering afterCommit
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                Map<String, Object> envelope = new HashMap<>();
                envelope.put("event_seq", 100L);
                envelope.put("event_id", "test-100");
                envelope.put("protocol_version", 2);
                pushService.broadcastV2Envelope(1, envelope);
            }
        });

        // Trigger afterCommit
        TransactionSynchronizationUtils.triggerAfterCommit();

        // Cleanup
        TransactionSynchronizationManager.clear();

        // Verify that hub.broadcastV2 was actually called for all broadcast tags
        verify(hub, times(KdsScreenTag.allBroadcastTags().size()))
                .broadcastV2(eq(1), anyString(), anyString());
    }
}
