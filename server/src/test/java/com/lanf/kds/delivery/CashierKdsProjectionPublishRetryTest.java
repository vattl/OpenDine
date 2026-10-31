package com.lanf.kds.delivery;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.scheduling.TaskScheduler;

import java.util.Date;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class CashierKdsProjectionPublishRetryTest {

    @Test
    void fullQueueRejectsWithoutRunningOnCallerAndCloseRejectsNewWork() throws Exception {
        CashierKdsProjectionPublishRetry retry = new CashierKdsProjectionPublishRetry(mock(TaskScheduler.class));
        CountDownLatch running = new CountDownLatch(2);
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger rejectedTaskRuns = new AtomicInteger();
        Runnable blocked = () -> {
            running.countDown();
            try { release.await(); }
            catch (InterruptedException ex) { Thread.currentThread().interrupt(); }
        };
        try {
            assertTrue(retry.submit(1, blocked));
            assertTrue(retry.submit(2, blocked));
            assertTrue(running.await(2, TimeUnit.SECONDS));
            for (int i = 0; i < 128; i++) assertTrue(retry.submit(i + 3, blocked));
            org.junit.jupiter.api.Assertions.assertFalse(retry.submit(999, rejectedTaskRuns::incrementAndGet));
            assertEquals(0, rejectedTaskRuns.get());
            assertEquals(1, retry.rejectedCount());
        } finally { retry.close(); release.countDown(); }
        org.junit.jupiter.api.Assertions.assertFalse(retry.submit(1000, rejectedTaskRuns::incrementAndGet));
        assertEquals(0, rejectedTaskRuns.get());
    }

    @Test
    void delayedRetriesCountAgainstCapacityEvenWhenExecutorQueueHasDrained() throws Exception {
        TaskScheduler scheduler = mock(TaskScheduler.class);
        CountDownLatch scheduled = new CountDownLatch(130);
        org.mockito.Mockito.when(scheduler.schedule(any(Runnable.class), any(Date.class))).thenAnswer(call -> {
            scheduled.countDown();
            return mock(java.util.concurrent.ScheduledFuture.class);
        });
        CashierKdsProjectionPublishRetry retry = new CashierKdsProjectionPublishRetry(scheduler);
        try {
            for (int i = 0; i < 130; i++) {
                assertTrue(retry.submit(i, () -> { throw new IllegalStateException("offline"); }));
            }
            assertTrue(scheduled.await(3, TimeUnit.SECONDS));
            org.junit.jupiter.api.Assertions.assertFalse(retry.submit(131, () -> { }));
        } finally { retry.close(); }
    }

    @Test
    void retriesFailedProjectionAfterOneSecond() {
        TaskScheduler scheduler = mock(TaskScheduler.class);
        CashierKdsProjectionPublishRetry retry = new CashierKdsProjectionPublishRetry(scheduler);
        AtomicInteger attempts = new AtomicInteger();
        long startedAt = System.currentTimeMillis();

        retry.execute(42, () -> {
            attempts.incrementAndGet();
            throw new IllegalStateException("database temporarily unavailable");
        });

        org.mockito.ArgumentCaptor<Date> runAt = org.mockito.ArgumentCaptor.forClass(Date.class);
        verify(scheduler).schedule(any(Runnable.class), runAt.capture());
        assertEquals(1, attempts.get());
        assertTrue(runAt.getValue().getTime() >= startedAt + 900L);
        assertTrue(runAt.getValue().getTime() <= startedAt + 1500L);
    }

    @Test
    void selectsApplicationSchedulerWhenSockJsSchedulerAlsoExists() {
        TaskScheduler applicationScheduler = mock(TaskScheduler.class);
        TaskScheduler sockJsScheduler = mock(TaskScheduler.class);
        try (AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext()) {
            context.registerBean("taskScheduler", TaskScheduler.class, () -> applicationScheduler);
            context.registerBean("defaultSockJsTaskScheduler", TaskScheduler.class, () -> sockJsScheduler);
            context.register(CashierKdsProjectionPublishRetry.class);
            context.refresh();

            context.getBean(CashierKdsProjectionPublishRetry.class).execute(43, () -> {
                throw new IllegalStateException("database temporarily unavailable");
            });

            verify(applicationScheduler).schedule(any(Runnable.class), any(Date.class));
            verifyNoInteractions(sockJsScheduler);
        }
    }
}
