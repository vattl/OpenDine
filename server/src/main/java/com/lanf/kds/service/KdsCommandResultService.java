package com.lanf.kds.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

@Service
public class KdsCommandResultService {

    @Autowired
    private KdsV2CommandLedger commandLedger;

    /**
     * Stably records a rejected KDS command in a new transaction.
     * This ensures the rejection is persisted even if the surrounding business transaction rolls back.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void saveResultInNewTransaction(int shopId, String commandId, String actorId,
                                           String actorType, String commandType,
                                           String schemaVersion, Map<String, Object> request,
                                           int httpStatus, int businessCode, String message) {
        commandLedger.recordRejected(shopId, commandId, actorId, actorType, commandType,
                schemaVersion, request, httpStatus, businessCode, message);
    }
}
