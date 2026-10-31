package com.lanf.receivable.model;

import lombok.Data;

@Data
public class ReceivableAccountRequest {
    private String scopeType;
    private String customerType;
    private String customerName;
    private String contactName;
    private String contactPhone;
    private String taxNo;
    private Long creditLimitFen;
    private Integer paymentTermsDays;
    private String notes;
}
