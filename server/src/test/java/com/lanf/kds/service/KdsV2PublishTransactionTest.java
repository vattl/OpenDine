package com.lanf.kds.service;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

class KdsV2PublishTransactionTest {

    @AfterEach
    void clearTransactionContext() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
        TransactionSynchronizationManager.setActualTransactionActive(false);
    }

    @Test
    void persistsEventInsideTransactionAndPushesOnlyAfterCommit() {
        KdsV2EventStore eventStore = mock(KdsV2EventStore.class);
        KdsPushService pushService = mock(KdsPushService.class);
        KdsWorkflowV2Service service = new KdsWorkflowV2Service();
        ReflectionTestUtils.setField(service, "eventStore", eventStore);
        ReflectionTestUtils.setField(service, "pushService", pushService);
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("event_seq", 1L);
        envelope.put("event_id", "cmd:1");

        TransactionSynchronizationManager.setActualTransactionActive(true);
        TransactionSynchronizationManager.initSynchronization();
        service.publishEnvelope(7, envelope);

        org.junit.jupiter.api.Assertions.assertEquals("event:cmd:1", envelope.get("command_id"));
        org.junit.jupiter.api.Assertions.assertEquals("2.0", envelope.get("schema_version"));
        org.junit.jupiter.api.Assertions.assertEquals("shop:7", envelope.get("entity_id"));
        org.junit.jupiter.api.Assertions.assertEquals(1L, envelope.get("business_revision"));

        verify(eventStore).append(7, envelope);
        verify(pushService, never()).broadcastV2Envelope(eq(7), eq(envelope));

        for (TransactionSynchronization synchronization
                : TransactionSynchronizationManager.getSynchronizations()) {
            synchronization.afterCommit();
        }
        verify(pushService).broadcastV2Envelope(7, envelope);
    }
}
