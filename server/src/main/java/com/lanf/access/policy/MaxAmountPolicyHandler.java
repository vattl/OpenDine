package com.lanf.access.policy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.access.model.AccessContext;
import com.lanf.access.model.ApprovalRequirement;
import com.lanf.entity.AccessPolicy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 金额上限策略处理器 (MAX_AMOUNT)
 */
@Component
public class MaxAmountPolicyHandler implements AccessPolicyHandler {

    private static final Logger log = LoggerFactory.getLogger(MaxAmountPolicyHandler.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public String type() {
        return AccessPolicy.TYPE_MAX_AMOUNT;
    }

    @Override
    public PolicyResult evaluate(AccessPolicy policy, AccessContext ctx) {
        if (ctx.getAmount() == null) {
            return PolicyResult.pass();
        }
        if (policy.getConfig_json() == null || policy.getConfig_json().trim().isEmpty()) {
            return PolicyResult.pass();
        }

        try {
            JsonNode root = objectMapper.readTree(policy.getConfig_json());
            JsonNode maxAmountNode = root.get("maxAmount");
            if (maxAmountNode == null || maxAmountNode.isNull()) {
                maxAmountNode = root.get("max_amount");
            }
            if (maxAmountNode == null || maxAmountNode.isNull()) {
                return PolicyResult.pass();
            }

            BigDecimal maxAmount = new BigDecimal(maxAmountNode.asText());
            if (ctx.getAmount().compareTo(maxAmount) > 0) {
                String approvalPerm = root.has("approvalPermission")
                        ? root.get("approvalPermission").asText()
                        : (root.has("approval_permission") ? root.get("approval_permission").asText() : "access:approve");

                List<String> requiredRoles = new ArrayList<>();
                if (root.has("requiredRoles") && root.get("requiredRoles").isArray()) {
                    root.get("requiredRoles").forEach(r -> requiredRoles.add(r.asText()));
                } else {
                    requiredRoles.add("store_manager");
                    requiredRoles.add("owner");
                }

                ApprovalRequirement req = ApprovalRequirement.builder()
                        .required(true)
                        .permission(approvalPerm)
                        .reason("MAX_AMOUNT_EXCEEDED")
                        .currentAmount(ctx.getAmount())
                        .allowedAmount(maxAmount)
                        .requiredRoles(requiredRoles)
                        .build();

                return PolicyResult.needApproval(req, "操作金额 (" + ctx.getAmount() + "元) 超过策略限额 (" + maxAmount + "元)，需要店长审批");
            }
        } catch (Exception e) {
            log.warn("解析 MAX_AMOUNT 策略规则异常: policyCode={}, err={}", policy.getPolicy_code(), e.getMessage());
        }

        return PolicyResult.pass();
    }
}
