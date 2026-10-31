package com.lanf.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.entity.CashierTableAudit;
import com.lanf.mapper.CashierTableAuditMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class CashierTableFailureAuditService {
    private final CashierTableAuditMapper auditMapper;
    private final ObjectMapper objectMapper;

    public CashierTableFailureAuditService(CashierTableAuditMapper auditMapper, ObjectMapper objectMapper) {
        this.auditMapper = auditMapper;
        this.objectMapper = objectMapper;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordRolledBack(CashierTableOperationRequest request, String safeReason) {
        CashierTableAudit existing = auditMapper.findByRequest(
                request.getShopId(), request.getAction(), request.getRequestKey());
        if (existing != null) return;
        CashierTableAudit audit = new CashierTableAudit();
        audit.setShop_id(request.getShopId());
        audit.setModule("cashier_table");
        audit.setAction(request.getAction());
        audit.setTarget_id(limit(request.getSourceTable(), 64));
        audit.setAdmin_id(request.getOperatorId());
        audit.setIp(limit(request.getIp(), 64));
        audit.setSource_table(limit(request.getSourceTable(), 50));
        audit.setTarget_table(limit(request.getTargetTable(), 50));
        audit.setOrder_nos("[]");
        audit.setBefore_state("{}");
        audit.setAfter_state("{}");
        audit.setResult_status("ROLLED_BACK");
        audit.setResult_code(500);
        audit.setReason(safeReason);
        audit.setRequest_key(request.getRequestKey());
        audit.setRequest_fingerprint(CashierTableOperationService.fingerprint(request));
        audit.setTrace_id(limit(request.getTraceId(), 128));
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("sourceTable", limit(request.getSourceTable(), 50));
        snapshot.put("targetTable", limit(request.getTargetTable(), 50));
        audit.setRequest_snapshot(json(snapshot));
        auditMapper.insert(audit);
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("审计数据序列化失败", e);
        }
    }

    private static String limit(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}
