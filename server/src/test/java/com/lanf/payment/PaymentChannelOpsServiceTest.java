package com.lanf.payment;

import com.lanf.common.ApiException;
import com.lanf.payment.admin.PaymentChannelOpsService;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentTestTxnEntity;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import com.lanf.payment.mapper.PaymentTestTxnMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 支付渠道运营扩展单元测试：影响判定、幂等测试交易、未知渠道 404。
 */
class PaymentChannelOpsServiceTest {

    private PaymentChannelOpsService service;
    private PaymentTestTxnMapper testTxnMapper;
    private PaymentMerchantConfigMapper merchantConfigMapper;
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        testTxnMapper = mock(PaymentTestTxnMapper.class);
        merchantConfigMapper = mock(PaymentMerchantConfigMapper.class);
        jdbcTemplate = mock(JdbcTemplate.class);
        service = new PaymentChannelOpsService();
        org.springframework.test.util.ReflectionTestUtils.setField(service, "testTxnMapper", testTxnMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "merchantConfigMapper", merchantConfigMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "jdbcTemplate", jdbcTemplate);
    }

    @Test
    void impactCountsPendingTransactions() {
        when(jdbcTemplate.queryForObject(anyString(), (Class<Object>) any(), any(), any()))
                .thenReturn(3);

        Map<String, Object> result = service.impact(1, "online_wechat", "disabled");

        assertEquals(3, result.get("pendingTxCount"));
        assertEquals(Boolean.TRUE, result.get("blocking"));
        assertTrue(((java.util.List<?>) result.get("affectedEntries")).contains("小程序扫码下单"));
    }

    @Test
    void impactNotBlockingWhenNoPending() {
        when(jdbcTemplate.queryForObject(anyString(), (Class<Object>) any(), any(), any()))
                .thenReturn(0);
        Map<String, Object> result = service.impact(1, "cash", "disabled");
        assertEquals(Boolean.FALSE, result.get("blocking"));
    }

    @Test
    void impactRejectsUnknownChannel() {
        ApiException ex = assertThrows(ApiException.class, () -> service.impact(1, "magic_pay", "disabled"));
        assertEquals(404, ex.getHttpStatus());
        assertEquals(PaymentChannelOpsService.ERROR_CHANNEL_UNKNOWN, ex.getErrorCode());
    }

    @Test
    void impactRejectsBadTargetStatus() {
        ApiException ex = assertThrows(ApiException.class, () -> service.impact(1, "cash", "paused"));
        assertEquals(400, ex.getHttpStatus());
    }

    @Test
    void testTransactionRequiresIdempotencyKey() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.testTransaction(1, "cash", new BigDecimal("0.01"), null, null, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals(PaymentChannelOpsService.ERROR_IDEMPOTENCY_KEY_REQUIRED, ex.getErrorCode());
    }

    @Test
    void offlineChannelDoneWithoutMoneyMovement() {
        when(testTxnMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.testTransaction(
                1, "offline_wechat_qr", new BigDecimal("0.01"), "POS-1", "idem-1", 7);

        assertEquals("DONE", result.get("status"));
        assertEquals("OFFLINE_NO_MONEY_MOVEMENT", result.get("chargeStatus"));
        assertEquals("NOT_REQUIRED", result.get("refundStatus"));
    }

    @Test
    void onlineWechatFailsWhenMerchantMissing() {
        when(testTxnMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(merchantConfigMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = service.testTransaction(
                1, "online_wechat", new BigDecimal("0.01"), null, "idem-2", 7);

        assertEquals("FAILED", result.get("status"));
        assertNotNull(result.get("error"));
        assertNull(result.get("refundStatus"));
    }

    @Test
    void testTransactionIsIdempotent() {
        PaymentTestTxnEntity existing = new PaymentTestTxnEntity();
        existing.setId(11L);
        existing.setChannel_code("cash");
        existing.setStatus("DONE");
        existing.setCharge_status("OFFLINE_NO_MONEY_MOVEMENT");
        when(testTxnMapper.selectList(any())).thenReturn(Collections.singletonList(existing));

        Map<String, Object> result = service.testTransaction(
                1, "cash", new BigDecimal("0.01"), null, "idem-dup", 7);

        assertEquals(Boolean.TRUE, result.get("duplicate"));
        assertEquals(11L, result.get("paymentId"));
    }
}
