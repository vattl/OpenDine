package com.lanf.payment.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentRoutingRuleEntity;
import com.lanf.payment.routing.PaymentRoutingContext;
import com.lanf.payment.routing.PaymentRoutingRuleMatcher;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class WechatMerchantRoutingServiceTest {

    @Test
    void ignoresClientMerchantFallbackWhenNoServerRuleMatches() {
        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        when(configs.listRuntimeMerchants(7, "wechat")).thenReturn(Collections.emptyList());
        WechatMerchantRoutingService routing = new WechatMerchantRoutingService();
        ReflectionTestUtils.setField(routing, "configService", configs);
        ReflectionTestUtils.setField(routing, "objectMapper", new ObjectMapper());

        assertEquals("1", routing.route(7, 88.50d, "外卖", "2"));
    }

    @Test
    void routesMatchingAmountAndDiningTypeToConfiguredMerchant() {
        PaymentMerchantConfigEntity rule = new PaymentMerchantConfigEntity();
        rule.setId(2L); rule.setMerchant_key("small_amount");
        rule.setRouting_rule_json("{\"type\":\"amount_and_dining\",\"maxPaidYuan\":159,"
                + "\"diningTypes\":[\"打包\",\"外卖\"],\"targetMerchantKey\":\"small_amount\","
                + "\"defaultMerchantKey\":\"default\"}");
        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        when(configs.listRuntimeMerchants(7, "wechat")).thenReturn(Arrays.asList(rule));
        when(configs.findMergedRow(eq(7), eq("wechat"), eq("small_amount"))).thenReturn(rule);
        when(configs.findMergedRow(eq(7), eq("wechat"), eq("default"))).thenReturn(rule);
        when(configs.isMerchantPayReady(eq(7), eq("wechat"), eq("small_amount"))).thenReturn(true);
        when(configs.isMerchantPayReady(eq(7), eq("wechat"), eq("default"))).thenReturn(true);
        WechatMerchantRoutingService routing = new WechatMerchantRoutingService();
        ReflectionTestUtils.setField(routing, "configService", configs);
        ReflectionTestUtils.setField(routing, "objectMapper", new ObjectMapper());

        assertEquals("2", routing.route(7, 88.50d, "外卖", "default"));
        assertEquals("1", routing.route(7, 188.50d, "外卖", "2"));
    }

    @Test
    void fallsBackToDefaultWhenTargetMerchantNotReady() {
        PaymentMerchantConfigEntity rule = new PaymentMerchantConfigEntity();
        rule.setId(2L); rule.setMerchant_key("small_amount");
        rule.setRouting_rule_json("{\"type\":\"amount_and_dining\",\"maxPaidYuan\":159,"
                + "\"diningTypes\":[\"打包\",\"外卖\"],\"targetMerchantKey\":\"small_amount\","
                + "\"defaultMerchantKey\":\"default\"}");
        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        when(configs.listRuntimeMerchants(7, "wechat")).thenReturn(Arrays.asList(rule));
        when(configs.isMerchantPayReady(eq(7), eq("wechat"), eq("small_amount"))).thenReturn(false);
        when(configs.isMerchantPayReady(eq(7), eq("wechat"), eq("default"))).thenReturn(true);
        WechatMerchantRoutingService routing = new WechatMerchantRoutingService();
        ReflectionTestUtils.setField(routing, "configService", configs);
        ReflectionTestUtils.setField(routing, "objectMapper", new ObjectMapper());

        assertEquals("1", routing.route(7, 88.50d, "外卖", "default"));
    }

    @Test
    void routesUsingNewMultiConditionRoutingRulesWithGoodsContext() {
        PaymentRoutingRuleService ruleService = mock(PaymentRoutingRuleService.class);
        PaymentRoutingRuleMatcher ruleMatcher = new PaymentRoutingRuleMatcher();
        ObjectMapper mapper = new ObjectMapper();
        ReflectionTestUtils.setField(ruleMatcher, "objectMapper", mapper);

        PaymentRoutingRuleEntity rule = new PaymentRoutingRuleEntity();
        rule.setId(99L);
        rule.setShop_id(7);
        rule.setChannel("wechat");
        rule.setRule_name("包含三文鱼到特约商户");
        rule.setPriority(100);
        rule.setEnabled(1);
        rule.setTarget_merchant_key("salmon_mch");
        rule.setMatch_mode("ALL");
        rule.setConditions_json("{\"goodsMatch\":{\"goodsNameKeywords\":[\"三文鱼\"]}}");

        when(ruleService.listRuntimeRules(7, "wechat")).thenReturn(Collections.singletonList(rule));

        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        PaymentMerchantConfigEntity salmonMchEntity = new PaymentMerchantConfigEntity();
        salmonMchEntity.setId(88L);
        salmonMchEntity.setMerchant_key("salmon_mch");
        when(configs.findMergedRow(eq(7), eq("wechat"), eq("salmon_mch"))).thenReturn(salmonMchEntity);
        when(configs.isMerchantPayReady(eq(7), eq("wechat"), eq("salmon_mch"))).thenReturn(true);

        WechatMerchantRoutingService routing = new WechatMerchantRoutingService();
        ReflectionTestUtils.setField(routing, "configService", configs);
        ReflectionTestUtils.setField(routing, "routingRuleService", ruleService);
        ReflectionTestUtils.setField(routing, "ruleMatcher", ruleMatcher);
        ReflectionTestUtils.setField(routing, "objectMapper", mapper);

        // 包含三文鱼 -> 命中 88L
        PaymentRoutingContext ctxSalmon = new PaymentRoutingContext();
        ctxSalmon.shopId = 7;
        ctxSalmon.paidYuan = 120.00;
        ctxSalmon.diningType = "堂食";
        ctxSalmon.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼刺身", 10L, new BigDecimal("120.00"), 1)
        );
        assertEquals("salmon_mch", routing.route(ctxSalmon));

        // 不含三文鱼 -> 未命中新规则，由于没有 legacy 规则，回退到主商户 ("1")
        PaymentRoutingContext ctxBeef = new PaymentRoutingContext();
        ctxBeef.shopId = 7;
        ctxBeef.paidYuan = 120.00;
        ctxBeef.diningType = "堂食";
        ctxBeef.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(2L, "雪花牛肉", 20L, new BigDecimal("120.00"), 1)
        );
        assertEquals("1", routing.route(ctxBeef));
    }
}