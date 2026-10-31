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
import java.util.List;

/**
 * 折扣策略处理器 (MIN_DISCOUNT_RATE / MAX_DISCOUNT_AMOUNT)
 */
@Component
public class DiscountPolicyHandler implements AccessPolicyHandler {

    private static final Logger log = LoggerFactory.getLogger(DiscountPolicyHandler.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public String type() {
        return AccessPolicy.TYPE_MIN_DISCOUNT_RATE;
    }

    @Override
    public PolicyResult evaluate(AccessPolicy policy, AccessContext ctx) {
        if (policy.getConfig_json() == null || policy.getConfig_json().trim().isEmpty()) {
            return PolicyResult.pass();
        }

        try {
            JsonNode root = objectMapper.readTree(policy.getConfig_json());
            String approvalPerm = root.has("approvalPermission")
                    ? root.get("approvalPermission").asText()
                    : "discount:approve";

            List<String> requiredRoles = new ArrayList<>();
            if (root.has("requiredRoles") && root.get("requiredRoles").isArray()) {
                root.get("requiredRoles").forEach(r -> requiredRoles.add(r.asText()));
            } else {
                requiredRoles.add("store_manager");
                requiredRoles.add("owner");
            }

            // 1. 折扣率校验 (如 95折 = 0.95，低于 0.95 需要审批)
            if (ctx.getDiscountRate() != null) {
                JsonNode minRateNode = root.get("minDiscountRate");
                if (minRateNode == null || minRateNode.isNull()) {
                    minRateNode = root.get("min_discount_rate");
                }
                if (minRateNode != null && !minRateNode.isNull()) {
                    BigDecimal minRate = new BigDecimal(minRateNode.asText());
                    if (ctx.getDiscountRate().compareTo(minRate) < 0) {
                        ApprovalRequirement req = ApprovalRequirement.builder()
                                .required(true)
                                .permission(approvalPerm)
                                .reason("MIN_DISCOUNT_RATE_EXCEEDED")
                                .currentAmount(ctx.getDiscountRate())
                                .allowedAmount(minRate)
                                .requiredRoles(requiredRoles)
                                .build();
                        return PolicyResult.needApproval(req, "折扣力度低于最低允许折扣率 (" + minRate + ")，需要店长审批");
                    }
                }
            }

            // 2. 优惠减免金额上限校验
            if (ctx.getAmount() != null) {
                JsonNode maxDiscountAmountNode = root.get("maxDiscountAmount");
                if (maxDiscountAmountNode == null || maxDiscountAmountNode.isNull()) {
                    maxDiscountAmountNode = root.get("max_discount_amount");
                }
                if (maxDiscountAmountNode != null && !maxDiscountAmountNode.isNull()) {
                    BigDecimal maxDiscountAmt = new BigDecimal(maxDiscountAmountNode.asText());
                    if (ctx.getAmount().compareTo(maxDiscountAmt) > 0) {
                        ApprovalRequirement req = ApprovalRequirement.builder()
                                .required(true)
                                .permission(approvalPerm)
                                .reason("MAX_DISCOUNT_AMOUNT_EXCEEDED")
                                .currentAmount(ctx.getAmount())
                                .allowedAmount(maxDiscountAmt)
                                .requiredRoles(requiredRoles)
                                .build();
                        return PolicyResult.needApproval(req, "优惠减免金额 (" + ctx.getAmount() + "元) 超过上限 (" + maxDiscountAmt + "元)，需要店长审批");
                    }
                }
            }
        } catch (Exception e) {
            log.warn("解析折扣策略规则异常: policyCode={}, err={}", policy.getPolicy_code(), e.getMessage());
        }

        return PolicyResult.pass();
    }
}
