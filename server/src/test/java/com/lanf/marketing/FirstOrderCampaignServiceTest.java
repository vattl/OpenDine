package com.lanf.marketing;

import com.lanf.common.ApiException;
import com.lanf.marketing.entity.FirstOrderCampaign;
import com.lanf.marketing.entity.FirstOrderRedemption;
import com.lanf.marketing.mapper.FirstOrderCampaignMapper;
import com.lanf.marketing.mapper.FirstOrderRedemptionMapper;
import com.lanf.marketing.service.FirstOrderCampaignService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 首单营销单元测试：创建/叠加冲突/版本冲突/资格判定/核销列表。
 */
class FirstOrderCampaignServiceTest {

    private FirstOrderCampaignService service;
    private FirstOrderCampaignMapper campaignMapper;
    private FirstOrderRedemptionMapper redemptionMapper;
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        campaignMapper = mock(FirstOrderCampaignMapper.class);
        redemptionMapper = mock(FirstOrderRedemptionMapper.class);
        jdbcTemplate = mock(JdbcTemplate.class);
        service = new FirstOrderCampaignService();
        org.springframework.test.util.ReflectionTestUtils.setField(service, "campaignMapper", campaignMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "redemptionMapper", redemptionMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "jdbcTemplate", jdbcTemplate);
    }

    private FirstOrderCampaign campaign(long id, String status, LocalDateTime start, LocalDateTime end) {
        FirstOrderCampaign c = new FirstOrderCampaign();
        c.setId(id);
        c.setShop_id(1);
        c.setName("首单立减5元");
        c.setCampaign_type("DISCOUNT");
        c.setThreshold_amount(new BigDecimal("20"));
        c.setDiscount_value(new BigDecimal("5"));
        c.setStart_time(start);
        c.setEnd_time(end);
        c.setStatus(status);
        c.setVersion(1);
        return c;
    }

    private Map<String, Object> validBody(String status) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "首单立减5元");
        body.put("campaignType", "DISCOUNT");
        body.put("thresholdAmount", "20");
        body.put("discountValue", "5");
        body.put("startTime", "2026-08-01 00:00:00");
        body.put("endTime", "2026-12-31 23:59:59");
        body.put("status", status);
        return body;
    }

    @Test
    void createDraftCampaignSkipsOverlapCheck() {
        Map<String, Object> result = service.createCampaign(1, validBody("DRAFT"), 7);
        verify(campaignMapper).insert(any(FirstOrderCampaign.class));
        assertEquals("DRAFT", result.get("status"));
        assertEquals(1, result.get("version"));
    }

    @Test
    void createActiveCampaignConflictsWithExistingActive() {
        FirstOrderCampaign existing = campaign(2, "ACTIVE",
                LocalDateTime.of(2026, 8, 1, 0, 0), LocalDateTime.of(2026, 11, 30, 23, 59));
        when(campaignMapper.selectList(any())).thenReturn(Collections.singletonList(existing));

        ApiException ex = assertThrows(ApiException.class,
                () -> service.createCampaign(1, validBody("ACTIVE"), 7));
        assertEquals(409, ex.getHttpStatus());
        assertEquals(FirstOrderCampaignService.ERROR_RULE_CONFLICT, ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        List<?> conflicts = (List<?>) data.get("conflicts");
        assertEquals(1, conflicts.size());
    }

    @Test
    void updateRejectsStaleVersion() {
        when(campaignMapper.selectById(2L)).thenReturn(campaign(2, "DRAFT",
                LocalDateTime.of(2026, 8, 1, 0, 0), LocalDateTime.of(2026, 12, 31, 23, 59)));
        Map<String, Object> body = validBody("DRAFT");
        body.put("version", 9);
        ApiException ex = assertThrows(ApiException.class, () -> service.updateCampaign(1, 2, body, 7));
        assertEquals(409, ex.getHttpStatus());
        assertEquals(FirstOrderCampaignService.ERROR_VERSION_CONFLICT, ex.getErrorCode());
    }

    @Test
    void evaluateEligibleForTrueFirstOrder() {
        FirstOrderCampaign active = campaign(2, "ACTIVE",
                LocalDateTime.now().minusDays(1), LocalDateTime.now().plusDays(30));
        when(campaignMapper.selectList(any())).thenReturn(Collections.singletonList(active));
        when(redemptionMapper.selectCount(any())).thenReturn(0);
        when(jdbcTemplate.queryForObject(anyString(), (Class<Object>) any(), any(), any(), any(), any()))
                .thenReturn(0);

        Map<String, Object> result = service.evaluate(1, "openid-x", new BigDecimal("30"));

        assertTrue((Boolean) result.get("eligible"));
        assertNotNull(result.get("campaign"));
    }

    @Test
    void evaluateRejectedWhenAlreadyRedeemed() {
        FirstOrderCampaign active = campaign(2, "ACTIVE",
                LocalDateTime.now().minusDays(1), LocalDateTime.now().plusDays(30));
        when(campaignMapper.selectList(any())).thenReturn(Collections.singletonList(active));
        when(redemptionMapper.selectCount(any())).thenReturn(1);

        Map<String, Object> result = service.evaluate(1, "openid-x", new BigDecimal("30"));

        assertFalse((Boolean) result.get("eligible"));
        assertEquals("already_redeemed", result.get("reason"));
    }

    @Test
    void evaluateRejectedWhenHasPriorOrder() {
        FirstOrderCampaign active = campaign(2, "ACTIVE",
                LocalDateTime.now().minusDays(1), LocalDateTime.now().plusDays(30));
        when(campaignMapper.selectList(any())).thenReturn(Collections.singletonList(active));
        when(redemptionMapper.selectCount(any())).thenReturn(0);
        when(jdbcTemplate.queryForObject(anyString(), (Class<Object>) any(), any(), any(), any(), any()))
                .thenReturn(2);

        Map<String, Object> result = service.evaluate(1, "openid-x", new BigDecimal("30"));

        assertFalse((Boolean) result.get("eligible"));
        assertEquals("has_prior_order", result.get("reason"));
    }

    @Test
    void evaluateRejectedBelowThreshold() {
        FirstOrderCampaign active = campaign(2, "ACTIVE",
                LocalDateTime.now().minusDays(1), LocalDateTime.now().plusDays(30));
        when(campaignMapper.selectList(any())).thenReturn(Collections.singletonList(active));
        when(redemptionMapper.selectCount(any())).thenReturn(0);
        when(jdbcTemplate.queryForObject(anyString(), (Class<Object>) any(), any(), any(), any(), any()))
                .thenReturn(0);

        Map<String, Object> result = service.evaluate(1, "openid-x", new BigDecimal("10"));

        assertFalse((Boolean) result.get("eligible"));
        assertEquals("below_threshold", result.get("reason"));
    }

    @Test
    void listRedemptionsPaged() {
        FirstOrderRedemption r = new FirstOrderRedemption();
        r.setId(1L);
        r.setShop_id(1);
        r.setCampaign_id(2L);
        r.setCustomer_id("openid-x");
        r.setStatus("RESTORED");
        r.setRestored_reason("full_refund");
        when(redemptionMapper.selectList(any())).thenReturn(Collections.singletonList(r));

        Map<String, Object> result = service.listRedemptions(1, 2L, null, null, 1, 20);

        assertEquals(1, result.get("total"));
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        assertEquals("full_refund", items.get(0).get("restoredReason"));
    }
}
