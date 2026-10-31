package com.lanf.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Runs device/network side effects only after the owning database transaction commits. */
public final class AfterCommitExecutor {

    private static final Logger log = LoggerFactory.getLogger(AfterCommitExecutor.class);

    private AfterCommitExecutor() {
    }

    public static void execute(String action, Runnable operation) {
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    runSafely(action, operation);
                }
            });
            return;
        }
        runSafely(action, operation);
    }

    private static void runSafely(String action, Runnable operation) {
        try {
            operation.run();
        } catch (RuntimeException ex) {
            log.error("事务提交后任务失败: action={}, error={}", action, ex.getMessage(), ex);
        }
    }
}
