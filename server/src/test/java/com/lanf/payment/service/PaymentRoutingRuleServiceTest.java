package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentRoutingRuleEntity;
import com.lanf.payment.mapper.PaymentRoutingRuleMapper;
import com.lanf.payment.routing.PaymentRoutingContext;
import com.lanf.payment.routing.PaymentRoutingRuleMatcher;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PaymentRoutingRuleServiceTest {

    private PaymentRoutingRuleService service;
    private PaymentRoutingRuleMapper ruleMapper;
    private PaymentMerchantConfigService merchantConfigService;
    private PaymentMerchantPolicyService merchantPolicyService;
    private PaymentRoutingRuleMatcher ruleMatcher;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        service = new PaymentRoutingRuleService();
        ruleMapper = mock(PaymentRoutingRuleMapper.class);
        merchantConfigService = mock(PaymentMerchantConfigService.class);
        merchantPolicyService = mock(PaymentMerchantPolicyService.class);
        ruleMatcher = new PaymentRoutingRuleMatcher();
        objectMapper = new ObjectMapper();

        ReflectionTestUtils.setField(ruleMatcher, "objectMapper", objectMapper);

        ReflectionTestUtils.setField(service, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchantConfigService);
        ReflectionTestUtils.setField(service, "merchantPolicyService", merchantPolicyService);
        ReflectionTestUtils.setField(service, "ruleMatcher", ruleMatcher);
        ReflectionTestUtils.setField(service, "objectMapper", objectMapper);
    }

    @Test
    void simulateHitsFirstMatchingHighPriorityRule() {
        PaymentRoutingRuleEntity highPriorityRule = new PaymentRoutingRuleEntity();
        highPriorityRule.setId(10L);
        highPriorityRule.setShop_id(1);
        highPriorityRule.setChannel("wechat");
        highPriorityRule.setRule_name("打包进小额商户");
        highPriorityRule.setPriority(200);
        highPriorityRule.setEnabled(1);
        highPriorityRule.setTarget_merchant_key("small_amount");
        highPriorityRule.setMatch_mode("ALL");
        highPriorityRule.setConditions_json("{\"diningTypes\":[\"打包\"]}");

        PaymentRoutingRuleEntity lowPriorityRule = new PaymentRoutingRuleEntity();
        lowPriorityRule.setId(11L);
        lowPriorityRule.setShop_id(1);
        lowPriorityRule.setChannel("wechat");
        lowPriorityRule.setRule_name("三文鱼进特产商户");
        lowPriorityRule.setPriority(100);
        lowPriorityRule.setEnabled(1);
        lowPriorityRule.setTarget_merchant_key("specialty");
        lowPriorityRule.setMatch_mode("ALL");
        lowPriorityRule.setConditions_json("{\"goodsMatch\":{\"goodsNameKeywords\":[\"三文鱼\"]}}");

        when(ruleMapper.selectList(any())).thenReturn(Arrays.asList(highPriorityRule, lowPriorityRule));
        when(merchantConfigService.isMerchantPayReady(eq(1), eq("wechat"), eq("small_amount"))).thenReturn(true);
        PaymentMerchantConfigEntity smallAmountCfg = new PaymentMerchantConfigEntity();
        smallAmountCfg.setId(2L);
        smallAmountCfg.setMerchant_key("small_amount");
        smallAmountCfg.setApp_id("wx111");
        smallAmountCfg.setMch_id("mch111");
        when(merchantConfigService.findMergedRow(eq(1), eq("wechat"), eq("small_amount"))).thenReturn(smallAmountCfg);

        Map<String, Object> body = new HashMap<>();
        body.put("channel", "wechat");
        body.put("diningType", "打包");
        body.put("paidYuan", 88.00);
        body.put("goodsItems", Collections.singletonList(
                Collections.singletonMap("goodsName", "三文鱼刺身")
        ));

        Map<String, Object> result = service.simulate(1, body);
        assertTrue((Boolean) result.get("matched"));
        assertEquals("small_amount", result.get("targetMerchantKey"));
        assertEquals(10L, result.get("matchedRuleId"));
        assertEquals("打包进小额商户", result.get("matchedRuleName"));
        assertTrue((Boolean) result.get("targetMerchantPayReady"));
        assertEquals("small_amount", result.get("effectiveMerchantKey"));
        assertFalse((Boolean) result.get("fallbackOccurred"));
    }

    @Test
    void simulateDowngradesToDefaultWhenTargetMerchantNotReady() {
        PaymentRoutingRuleEntity rule = new PaymentRoutingRuleEntity();
        rule.setId(20L);
        rule.setShop_id(1);
        rule.setChannel("wechat");
        rule.setRule_name("自提进小额");
        rule.setPriority(100);
        rule.setEnabled(1);
        rule.setTarget_merchant_key("small_amount");
        rule.setMatch_mode("ALL");
        rule.setConditions_json("{\"diningTypes\":[\"自提\"]}");

        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule));
        when(merchantConfigService.isMerchantPayReady(eq(1), eq("wechat"), eq("small_amount"))).thenReturn(false);
        when(merchantConfigService.isMerchantPayReady(eq(1), eq("wechat"), eq("default"))).thenReturn(true);

        PaymentMerchantConfigEntity defaultCfg = new PaymentMerchantConfigEntity();
        defaultCfg.setId(1L);
        defaultCfg.setMerchant_key("default");
        defaultCfg.setMch_id("mch_default");
        when(merchantConfigService.findMergedRow(eq(1), eq("wechat"), eq("default"))).thenReturn(defaultCfg);

        Map<String, Object> body = new HashMap<>();
        body.put("channel", "wechat");
        body.put("diningType", "自提");
        body.put("paidYuan", 20.00);

        Map<String, Object> result = service.simulate(1, body);
        assertTrue((Boolean) result.get("matched"));
        assertTrue((Boolean) result.get("fallbackOccurred"));
        assertEquals("default", result.get("effectiveMerchantKey"));
    }

    @Test
    void sortRulesUpdatesPriorities() {
        List<Long> ruleIds = Arrays.asList(101L, 102L, 103L);

        PaymentRoutingRuleEntity r1 = new PaymentRoutingRuleEntity();
        r1.setId(101L); r1.setShop_id(1);
        PaymentRoutingRuleEntity r2 = new PaymentRoutingRuleEntity();
        r2.setId(102L); r2.setShop_id(1);
        PaymentRoutingRuleEntity r3 = new PaymentRoutingRuleEntity();
        r3.setId(103L); r3.setShop_id(1);

        when(ruleMapper.selectById(101L)).thenReturn(r1);
        when(ruleMapper.selectById(102L)).thenReturn(r2);
        when(ruleMapper.selectById(103L)).thenReturn(r3);

        service.sort(1, "wechat", ruleIds);

        // total = 3; i=0 -> (3-0)*10 = 30; i=1 -> 20; i=2 -> 10
        verify(ruleMapper).updateById(argThat(r -> r.getId().equals(101L) && r.getPriority() == 30));
        verify(ruleMapper).updateById(argThat(r -> r.getId().equals(102L) && r.getPriority() == 20));
        verify(ruleMapper).updateById(argThat(r -> r.getId().equals(103L) && r.getPriority() == 10));
    }
}