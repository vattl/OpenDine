package com.lanf.receivable.model;

import lombok.Data;

@Data
public class ReceivableChargeRequest {
    private String orderNo;
    private Long accountId;
    private String requestId;
    private String note;
}
