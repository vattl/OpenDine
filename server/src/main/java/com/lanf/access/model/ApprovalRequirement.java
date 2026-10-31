package com.lanf.access.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.List;

/**
 * 审批授权需求说明
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ApprovalRequirement {
    private boolean required;
    private String permission;
    private String reason;
    private BigDecimal currentAmount;
    private BigDecimal allowedAmount;
    private List<String> requiredRoles;
}
