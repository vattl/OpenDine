package com.lanf.schedule;

import com.lanf.config.ZsqSystemSettings;
import com.lanf.service.ITakeoutZsqIntegrationService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.concurrent.ScheduledExecutorService;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class TakeoutZsqSyncSchedulerTest {
    @Test void cursorResumesBoundedDeliveryBatchesAndWrapsOnlyAfterEnd() {
        ITakeoutZsqIntegrationService service = mock(ITakeoutZsqIntegrationService.class);
        ZsqSystemSettings settings = new ZsqSystemSettings(false, true);
        TakeoutZsqSyncScheduler scheduler = new TakeoutZsqSyncScheduler(service, settings);
        try {
            when(service.syncActiveDeliveriesAfter(eq(0L), anyInt(), anyLong()))
                    .thenReturn(new ITakeoutZsqIntegrationService.DeliverySyncBatch(20, 20, false));
            when(service.syncActiveDeliveriesAfter(eq(20L), anyInt(), anyLong()))
                    .thenReturn(new ITakeoutZsqIntegrationService.DeliverySyncBatch(3, 23, true));
            scheduler.syncActiveDeliveries();
            scheduler.syncActiveDeliveries();
            scheduler.syncActiveDeliveries();
            verify(service, times(2)).syncActiveDeliveriesAfter(eq(0L), eq(20), anyLong());
            verify(service).syncActiveDeliveriesAfter(eq(20L), eq(20), anyLong());
        } finally { scheduler.close(); }
    }

    @Test void disabledDeliveryDoesNotConsumeItsDedicatedWorker() {
        ITakeoutZsqIntegrationService service = mock(ITakeoutZsqIntegrationService.class);
        TakeoutZsqSyncScheduler scheduler = new TakeoutZsqSyncScheduler(service, new ZsqSystemSettings(false, false));
        try {
            scheduler.syncActiveDeliveries();
            verifyNoInteractions(service);
            ScheduledExecutorService worker = (ScheduledExecutorService) ReflectionTestUtils.getField(scheduler, "worker");
            assertFalse(worker.isShutdown());
        } finally { scheduler.close(); }
    }

    @Test void timeBudgetKeepsCursorOnTheLastAttemptedDelivery() {
        ITakeoutZsqIntegrationService service = mock(ITakeoutZsqIntegrationService.class);
        TakeoutZsqSyncScheduler scheduler = new TakeoutZsqSyncScheduler(service, new ZsqSystemSettings(false, true));
        try {
            when(service.syncActiveDeliveriesAfter(eq(0L), anyInt(), anyLong()))
                    .thenReturn(new ITakeoutZsqIntegrationService.DeliverySyncBatch(1, 1, false));
            when(service.syncActiveDeliveriesAfter(eq(1L), anyInt(), anyLong()))
                    .thenReturn(new ITakeoutZsqIntegrationService.DeliverySyncBatch(1, 2, true));
            scheduler.syncActiveDeliveries(); scheduler.syncActiveDeliveries();
            verify(service).syncActiveDeliveriesAfter(eq(1L), eq(20), anyLong());
        } finally { scheduler.close(); }
    }
}
