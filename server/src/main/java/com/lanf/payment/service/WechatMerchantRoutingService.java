package com.lanf.payment.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.payment.PaymentChannels;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.util.List;

/** 服务端商户路由；客户端/订单历史 merchantId 不得决定新交易的资金去向。 */
@Service
public class WechatMerchantRoutingService {
    private static final Logger log = LoggerFactory.getLogger(WechatMerchantRoutingService.class);
    @Autowired private PaymentMerchantConfigService configService;
    @Autowired(required = false) private PaymentRoutingRuleService routingRuleService;
    @Autowired(required = false) private com.lanf.payment.routing.PaymentRoutingRuleMatcher ruleMatcher;
    @Autowired private ObjectMapper objectMapper;

    /**
     * 全渠道完整路由入口（包含菜品明细与下单时段）。
     */
    public String route(com.lanf.payment.routing.PaymentRoutingContext ctx) {
        if (ctx == null) {
            return routeToken("default");
        }
        int shopId = ctx.shopId != null ? ctx.shopId : 0;

        // 1. 优先评估新版门店多条件规则链 (t_payment_routing_rule)
        if (routingRuleService != null && ruleMatcher != null) {
            try {
                List<com.lanf.payment.entity.PaymentRoutingRuleEntity> rules =
                        routingRuleService.listRuntimeRules(shopId, PaymentChannels.WECHAT);
                for (com.lanf.payment.entity.PaymentRoutingRuleEntity rule : rules) {
                    if (ruleMatcher.isMatch(rule.getConditions_json(), rule.getMatch_mode(), ctx)) {
                        String target = rule.getTarget_merchant_key();
                        if (StringUtils.hasText(target)) {
                            if (configService.isMerchantPayReady(shopId, PaymentChannels.WECHAT, target)) {
                                log.info("命中新商户分流规则: shopId={}, ruleName={}, targetKey={}",
                                        shopId, rule.getRule_name(), target);
                                return routeToken(target);
                            } else {
                                log.warn("商户分流规则 [{}] 目标商户 [{}] 未就绪，自动跳过尝试下一条规则",
                                        rule.getRule_name(), target);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                log.error("评估新商户路由规则异常，回退旧规则 shopId={}: {}", shopId, e.getMessage());
            }
        }

        // 2. 向下兼容旧商户行中的 routing_rule_json
        return routeLegacy(shopId, ctx.paidYuan, ctx.diningType, ctx.currentMerchantId);
    }

    /**
     * 保持向下兼容的轻量重载。
     */
    public String route(int shopId, double paidYuan, String diningType, String currentMerchantId) {
        com.lanf.payment.routing.PaymentRoutingContext ctx =
                new com.lanf.payment.routing.PaymentRoutingContext(shopId, paidYuan, diningType, currentMerchantId);
        return route(ctx);
    }

    private String routeLegacy(int shopId, double paidYuan, String diningType, String currentMerchantId) {
        List<PaymentMerchantConfigEntity> rows = configService.listRuntimeMerchants(shopId, PaymentChannels.WECHAT);
        BigDecimal amount = BigDecimal.valueOf(paidYuan);
        String configuredDefault = null;
        for (PaymentMerchantConfigEntity row : rows) {
            if (!StringUtils.hasText(row.getRouting_rule_json())) continue;
            try {
                JsonNode rule = objectMapper.readTree(row.getRouting_rule_json());
                if (!"amount_and_dining".equals(rule.path("type").asText())) continue;
                String defaultKey = rule.path("defaultMerchantKey").asText("").trim();
                if (configuredDefault == null && StringUtils.hasText(defaultKey)
                        && configService.isMerchantPayReady(shopId, PaymentChannels.WECHAT, defaultKey)) {
                    configuredDefault = routeToken(defaultKey);
                }
                if (rule.has("minPaidYuan") && amount.compareTo(rule.path("minPaidYuan").decimalValue()) < 0) continue;
                if (rule.has("maxPaidYuan") && amount.compareTo(rule.path("maxPaidYuan").decimalValue()) > 0) continue;
                JsonNode types = rule.path("diningTypes");
                if (types.isArray() && types.size() > 0) {
                    boolean found = false;
                    for (JsonNode type : types) if (type.asText().equals(diningType)) { found = true; break; }
                    if (!found) continue;
                }
                String target = rule.path("targetMerchantKey").asText("").trim();
                if (StringUtils.hasText(target)) {
                    if (configService.isMerchantPayReady(shopId, PaymentChannels.WECHAT, target)) {
                        return routeToken(target);
                    } else {
                        log.warn("商户路由目标商户未就绪或凭据不完整，跳过分流 shopId={} targetMerchantKey={}", shopId, target);
                    }
                }
            } catch (Exception e) {
                log.error("商户路由规则无效，已跳过 merchantConfigId={}", row.getId());
            }
        }
        if (configuredDefault != null) return configuredDefault;
        return routeToken("default");
    }

    private static String routeToken(String key) {
        if ("default".equals(key) || "1".equals(key)) return "1";
        if ("small_amount".equals(key) || "2".equals(key)) return "2";
        return key;
    }
}
