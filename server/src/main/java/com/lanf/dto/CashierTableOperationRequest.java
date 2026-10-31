package com.lanf.dto;

import lombok.Data;

@Data
public class CashierTableOperationRequest {
    private String action;
    private Integer shopId;
    private Integer operatorId;
    private String sourceTable;
    private String targetTable;
    private String orderNo;
    private String requestKey;
    private String traceId;
    private String ip;
}
