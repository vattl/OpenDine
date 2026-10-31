package com.lanf.receivable.model;

import lombok.Data;

@Data
public class ReceivableActionRequest {
    private String requestId;
    private String reason;
    private String status;
}
