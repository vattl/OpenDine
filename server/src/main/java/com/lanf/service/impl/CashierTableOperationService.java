package com.lanf.service.impl;

import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.dto.CashierTableOperationResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@Service
public class CashierTableOperationService {
    private static final Logger log = LoggerFactory.getLogger(CashierTableOperationService.class);
    private final CashierTableOperationTransactionalService transactionalService;
    private final CashierTableFailureAuditService failureAuditService;

    public CashierTableOperationService(CashierTableOperationTransactionalService transactionalService,
                                        CashierTableFailureAuditService failureAuditService) {
        this.transactionalService = transactionalService;
        this.failureAuditService = failureAuditService;
    }

    public CashierTableOperationResult execute(CashierTableOperationRequest request) {
        try {
            return transactionalService.execute(request);
        } catch (DuplicateKeyException duplicate) {
            // Concurrent requests with the same idempotency key: the winner has committed the replayable audit row.
            return transactionalService.execute(request);
        } catch (RuntimeException failure) {
            String reason = "操作未完成，事务已回滚，请重试";
            try {
                failureAuditService.recordRolledBack(request, reason);
            } catch (RuntimeException auditFailure) {
                log.error("cashier table rollback audit failed: shopId={}, action={}, traceId={}",
                        request.getShopId(), request.getAction(), request.getTraceId());
            }
            log.warn("cashier table operation rolled back: shopId={}, action={}, traceId={}, errorType={}",
                    request.getShopId(), request.getAction(), request.getTraceId(),
                    failure.getClass().getSimpleName());
            return CashierTableOperationResult.rejected(500, reason);
        }
    }

    public java.util.Map<String, Object> batchClear(Integer shopId, java.util.List<com.lanf.entity.Table> tables,
                                                    Integer operatorId, String operatorAccount, String traceId) {
        return transactionalService.batchClear(shopId, tables, operatorId, operatorAccount, traceId);
    }

    static String fingerprint(CashierTableOperationRequest request) {
        String raw = "TRANSFER".equals(request.getAction())
                ? request.getAction() + "|" + request.getTargetTable() + "|" + request.getOrderNo()
                : request.getAction() + "|" + request.getSourceTable() + "|" + request.getTargetTable();
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            StringBuilder value = new StringBuilder();
            for (byte b : digest) value.append(String.format("%02x", b));
            return value.toString();
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
