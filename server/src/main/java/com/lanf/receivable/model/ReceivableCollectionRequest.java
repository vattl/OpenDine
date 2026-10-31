package com.lanf.receivable.model;

import lombok.Data;

@Data
public class ReceivableCollectionRequest {
    private Long claimId;
    private Long amountFen;
    private String channel;
    private String requestId;
    private String note;
    private Long drawerSessionId;
}
