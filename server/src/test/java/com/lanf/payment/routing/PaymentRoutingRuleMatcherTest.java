package com.lanf.payment.routing;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;

class PaymentRoutingRuleMatcherTest {

    private PaymentRoutingRuleMatcher matcher;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        matcher = new PaymentRoutingRuleMatcher();
        objectMapper = new ObjectMapper();
        ReflectionTestUtils.setField(matcher, "objectMapper", objectMapper);
    }

    @Test
    void matchesEmptyConditionsAsAlwaysTrue() {
        PaymentRoutingContext ctx = new PaymentRoutingContext();
        assertTrue(matcher.isMatch("", "ALL", ctx));
        assertTrue(matcher.isMatch("{}", "ALL", ctx));
        assertTrue(matcher.isMatch((String) null, "ALL", ctx));
    }

    @Test
    void matchesDiningTypes() {
        String json = "{\"diningTypes\":[\"打包\",\"自提\"]}";
        
        PaymentRoutingContext ctx1 = new PaymentRoutingContext();
        ctx1.diningType = "打包";
        assertTrue(matcher.isMatch(json, "ALL", ctx1));

        PaymentRoutingContext ctx2 = new PaymentRoutingContext();
        ctx2.diningType = "堂食";
        assertFalse(matcher.isMatch(json, "ALL", ctx2));

        PaymentRoutingContext ctx3 = new PaymentRoutingContext();
        ctx3.diningType = null;
        assertFalse(matcher.isMatch(json, "ALL", ctx3));
    }

    @Test
    void matchesAmountRange() {
        String json = "{\"minPaidYuan\":50.00,\"maxPaidYuan\":100.00}";

        PaymentRoutingContext ctx1 = new PaymentRoutingContext();
        ctx1.paidYuan = 75.50;
        assertTrue(matcher.isMatch(json, "ALL", ctx1));

        PaymentRoutingContext ctxMinBoundary = new PaymentRoutingContext();
        ctxMinBoundary.paidYuan = 50.00;
        assertTrue(matcher.isMatch(json, "ALL", ctxMinBoundary));

        PaymentRoutingContext ctxMaxBoundary = new PaymentRoutingContext();
        ctxMaxBoundary.paidYuan = 100.00;
        assertTrue(matcher.isMatch(json, "ALL", ctxMaxBoundary));

        PaymentRoutingContext ctxTooLow = new PaymentRoutingContext();
        ctxTooLow.paidYuan = 49.99;
        assertFalse(matcher.isMatch(json, "ALL", ctxTooLow));

        PaymentRoutingContext ctxTooHigh = new PaymentRoutingContext();
        ctxTooHigh.paidYuan = 100.01;
        assertFalse(matcher.isMatch(json, "ALL", ctxTooHigh));
    }

    @Test
    void matchesGoodsWithSalmonKeywordContainsAny() {
        String json = "{\"goodsMatch\":{\"goodsNameKeywords\":[\"三文鱼\"],\"mode\":\"CONTAINS_ANY\"}}";

        PaymentRoutingContext ctx1 = new PaymentRoutingContext();
        ctx1.goodsItems = Arrays.asList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "挪威三文鱼刺身", 10L, new BigDecimal("68.00"), 1),
                new PaymentRoutingContext.RoutingGoodsItem(2L, "炭烤牛排", 11L, new BigDecimal("88.00"), 1)
        );
        assertTrue(matcher.isMatch(json, "ALL", ctx1));

        PaymentRoutingContext ctx2 = new PaymentRoutingContext();
        ctx2.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(2L, "炭烤牛排", 11L, new BigDecimal("88.00"), 1)
        );
        assertFalse(matcher.isMatch(json, "ALL", ctx2));
    }

    @Test
    void matchesGoodsWithCategoryIdContainsAny() {
        String json = "{\"goodsMatch\":{\"categoryIds\":[10, 20],\"mode\":\"CONTAINS_ANY\"}}";

        PaymentRoutingContext ctx = new PaymentRoutingContext();
        ctx.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(100L, "生鱼片", 10L, new BigDecimal("35.00"), 1)
        );
        assertTrue(matcher.isMatch(json, "ALL", ctx));

        PaymentRoutingContext ctxOther = new PaymentRoutingContext();
        ctxOther.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(101L, "可乐", 30L, new BigDecimal("5.00"), 1)
        );
        assertFalse(matcher.isMatch(json, "ALL", ctxOther));
    }

    @Test
    void matchesGoodsWithOnlyMode() {
        String json = "{\"goodsMatch\":{\"categoryIds\":[10],\"mode\":\"ONLY\"}}";

        PaymentRoutingContext ctxAllMatch = new PaymentRoutingContext();
        ctxAllMatch.goodsItems = Arrays.asList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼", 10L, new BigDecimal("30.00"), 1),
                new PaymentRoutingContext.RoutingGoodsItem(2L, "金枪鱼", 10L, new BigDecimal("40.00"), 1)
        );
        assertTrue(matcher.isMatch(json, "ALL", ctxAllMatch));

        PaymentRoutingContext ctxMixed = new PaymentRoutingContext();
        ctxMixed.goodsItems = Arrays.asList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼", 10L, new BigDecimal("30.00"), 1),
                new PaymentRoutingContext.RoutingGoodsItem(3L, "米饭", 99L, new BigDecimal("2.00"), 1)
        );
        assertFalse(matcher.isMatch(json, "ALL", ctxMixed));
    }

    @Test
    void matchesMultiConditionAndMode() {
        // AND 模式：打包 且 包含三文鱼 且 金额大于50
        String json = "{\"diningTypes\":[\"打包\"],\"minPaidYuan\":50.00,\"goodsMatch\":{\"goodsNameKeywords\":[\"三文鱼\"],\"mode\":\"CONTAINS_ANY\"}}";

        PaymentRoutingContext allPass = new PaymentRoutingContext();
        allPass.diningType = "打包";
        allPass.paidYuan = 60.00;
        allPass.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼寿司", 10L, new BigDecimal("60.00"), 1)
        );
        assertTrue(matcher.isMatch(json, "ALL", allPass));

        PaymentRoutingContext wrongDining = new PaymentRoutingContext();
        wrongDining.diningType = "堂食";
        wrongDining.paidYuan = 60.00;
        wrongDining.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼寿司", 10L, new BigDecimal("60.00"), 1)
        );
        assertFalse(matcher.isMatch(json, "ALL", wrongDining));

        PaymentRoutingContext wrongAmount = new PaymentRoutingContext();
        wrongAmount.diningType = "打包";
        wrongAmount.paidYuan = 30.00;
        wrongAmount.goodsItems = Collections.singletonList(
                new PaymentRoutingContext.RoutingGoodsItem(1L, "三文鱼寿司", 10L, new BigDecimal("30.00"), 1)
        );
        assertFalse(matcher.isMatch(json, "ALL", wrongAmount));
    }

    @Test
    void matchesMultiConditionOrMode() {
        // ANY (OR) 模式：只要是打包，或者金额>=100，任一满足即命中
        String json = "{\"diningTypes\":[\"打包\"],\"minPaidYuan\":100.00}";

        PaymentRoutingContext diningOnly = new PaymentRoutingContext();
        diningOnly.diningType = "打包";
        diningOnly.paidYuan = 20.00;
        assertTrue(matcher.isMatch(json, "ANY", diningOnly));

        PaymentRoutingContext amountOnly = new PaymentRoutingContext();
        amountOnly.diningType = "堂食";
        amountOnly.paidYuan = 150.00;
        assertTrue(matcher.isMatch(json, "ANY", amountOnly));

        PaymentRoutingContext neither = new PaymentRoutingContext();
        neither.diningType = "堂食";
        neither.paidYuan = 50.00;
        assertFalse(matcher.isMatch(json, "ANY", neither));
    }
}