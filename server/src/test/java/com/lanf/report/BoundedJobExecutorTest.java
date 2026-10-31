package com.lanf.report;

import com.lanf.report.service.BoundedJobExecutor;
import org.junit.jupiter.api.Test;
import java.util.Set;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.jupiter.api.Assertions.*;

class BoundedJobExecutorTest {
    @Test void saturatedWakeupsAreRejectedWithoutCallerExecutionAndDuplicatesAreCoalesced() throws Exception {
        ExecutorService executor=BoundedJobExecutor.create("test-report-worker");
        Set<Long> scheduled=ConcurrentHashMap.newKeySet();
        CountDownLatch entered=new CountDownLatch(1), release=new CountDownLatch(1);
        AtomicInteger rejectedRuns=new AtomicInteger();
        Runnable blocked=()-> { entered.countDown(); try {release.await();} catch(InterruptedException e){Thread.currentThread().interrupt();} };
        try {
            assertTrue(BoundedJobExecutor.submit(executor,scheduled,1L,blocked));
            assertTrue(entered.await(2,TimeUnit.SECONDS));
            assertTrue(BoundedJobExecutor.submit(executor,scheduled,1L,rejectedRuns::incrementAndGet));
            for(long id=2;id<=17;id++) assertTrue(BoundedJobExecutor.submit(executor,scheduled,id,blocked));
            assertFalse(BoundedJobExecutor.submit(executor,scheduled,18L,rejectedRuns::incrementAndGet));
            assertFalse(scheduled.contains(18L));
            assertEquals(0,rejectedRuns.get());
        } finally {executor.shutdownNow();release.countDown();}
        assertFalse(BoundedJobExecutor.submit(executor,scheduled,19L,rejectedRuns::incrementAndGet));
    }
}
