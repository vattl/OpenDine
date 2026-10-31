package com.lanf.access.policy;

import com.lanf.access.model.ApprovalRequirement;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 策略评估结果
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PolicyResult {
    private boolean passed;
    private boolean approvable;
    private String reason;
    private ApprovalRequirement requirement;

    public static PolicyResult pass() {
        return PolicyResult.builder().passed(true).build();
    }

    public static PolicyResult needApproval(ApprovalRequirement requirement, String reason) {
        return PolicyResult.builder()
                .passed(false)
                .approvable(true)
                .requirement(requirement)
                .reason(reason)
                .build();
    }

    public static PolicyResult deny(String reason) {
        return PolicyResult.builder()
                .passed(false)
                .approvable(false)
                .reason(reason)
                .build();
    }
}
