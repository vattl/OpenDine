package com.lanf.access.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.Map;

/**
 * 统一访问决策上下文
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AccessContext {
    private Integer adminId;
    private Integer shopId;
    private String permissionCode;

    private String resourceType;
    private String resourceId;

    private BigDecimal amount;
    private BigDecimal discountRate;

    private String orderStatus;
    private String paymentStatus;

    private String terminalId;
    private String requestId;

    private String approvalToken;

    private Map<String, Object> attributes;
}
