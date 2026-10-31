package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shop;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.LedgerBackfillLogMapper;
import com.lanf.mapper.PaymentLedgerMapper;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.service.impl.LedgerMigrationServiceImpl;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.MockitoJUnitRunner;

import java.time.LocalDate;
import java.util.*;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@RunWith(MockitoJUnitRunner.class)
public class LedgerMigrationServiceTest {

    @InjectMocks
    private LedgerMigrationServiceImpl ledgerMigrationService;

    @Mock
    private PaymentLedgerMapper paymentLedgerMapper;

    @Mock
    private LedgerBackfillLogMapper ledgerBackfillLogMapper;

    @Mock
    private IOrderService orderService;

    @Mock
    private IShopService shopService;

    @Mock
    private SystemConfigMapper systemConfigMapper;

    @Spy
    private ObjectMapper objectMapper = new ObjectMapper();

    private Shop mockShop;

    @Before
    public void setUp() {
        mockShop = new Shop();
        mockShop.setId(1);
        mockShop.setName("测试分店");
        mockShop.setSettle_time("04:00");
        lenient().when(shopService.getById(1)).thenReturn(mockShop);
    }

    @Test
    public void testBackfill_dryRunDoesNotInsert() {
        Order o1 = new Order();
        o1.setId(101);
        o1.setOrder_no("ORD-101");
        o1.setShop_id(1);
        o1.setSett_amount(50.0);
        o1.setPay_amount_cash(50.0);
        o1.setOrder_time(new Date());

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));
        when(paymentLedgerMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);

        Map<String, Object> res = ledgerMigrationService.executeBackfill(1, 999, "2026-10-03", true);

        assertEquals(true, res.get("dry_run"));
        assertEquals(1, res.get("total_orders_scanned"));
        assertEquals(1, res.get("backfilled_orders"));
        assertEquals(0, res.get("skipped_orders"));
        assertEquals(1, res.get("total_rows_inserted"));
        assertEquals(5000L, res.get("total_amount_fen"));
        assertEquals(0, res.get("anomalies_count"));
        assertNotNull(res.get("integrity_hash"));

        // Dry-run should NEVER insert into DB
        verify(paymentLedgerMapper, never()).insert(any(PaymentLedger.class));
        verify(ledgerBackfillLogMapper, never()).insert(any());
    }

    @Test
    public void testBackfill_executesAndIdempotent() {
        Order o1 = new Order();
        o1.setId(102);
        o1.setOrder_no("ORD-102");
        o1.setShop_id(1);
        o1.setSett_amount(100.0);
        o1.setPay_amount_cash(40.0);
        o1.setPay_amount_wechat(60.0);
        o1.setOrder_time(new Date());

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));
        when(paymentLedgerMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);

        Map<String, Object> res = ledgerMigrationService.executeBackfill(1, 999, null, false);

        assertEquals(false, res.get("dry_run"));
        assertEquals(1, res.get("backfilled_orders"));
        assertEquals(2, res.get("total_rows_inserted"));
        assertEquals(10000L, res.get("total_amount_fen"));

        // Verify insertion of two rows (CASH and WECHAT)
        ArgumentCaptor<PaymentLedger> captor = ArgumentCaptor.forClass(PaymentLedger.class);
        verify(paymentLedgerMapper, times(2)).insert(captor.capture());
        List<PaymentLedger> captured = captor.getAllValues();
        assertEquals(PaymentLedger.SOURCE_BACKFILLED_ORDER, captured.get(0).getSource());
        assertEquals(PaymentLedger.TRUST_HIGH, captured.get(0).getTrust_level());
        assertEquals("UNKNOWN", captured.get(0).getTerminal_id());

        verify(ledgerBackfillLogMapper, times(1)).insert(any());

        // Second run: existingCount returns 2 -> skipped
        when(paymentLedgerMapper.selectCount(any(QueryWrapper.class))).thenReturn(2);
        Map<String, Object> res2 = ledgerMigrationService.executeBackfill(1, 999, null, false);
        assertEquals(1, res2.get("skipped_orders"));
        assertEquals(0, res2.get("backfilled_orders"));
    }

    @Test
    public void testBackfill_preservesWechatQrChannelFromPaymentMethod() {
        Order order = new Order();
        order.setId(104);
        order.setOrder_no("ORD-104");
        order.setShop_id(1);
        order.setSett_amount(66.0);
        order.setPay_amount_wechat(66.0);
        order.setPayment_method("微信收款码自动");
        order.setOrder_time(new Date());
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(order));
        when(paymentLedgerMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);

        ledgerMigrationService.executeBackfill(1, 999, null, false);

        ArgumentCaptor<PaymentLedger> captor = ArgumentCaptor.forClass(PaymentLedger.class);
        verify(paymentLedgerMapper).insert(captor.capture());
        assertEquals(PaymentLedger.CHANNEL_WECHAT_QR, captor.getValue().getChannel());
    }

    @Test
    public void testBackfill_detectsAnomalies() {
        Order o1 = new Order();
        o1.setId(103);
        o1.setOrder_no("ORD-103");
        o1.setShop_id(1);
        o1.setSett_amount(100.0);
        o1.setPay_amount_cash(20.0); // Only 20, missing 80
        o1.setOrder_time(new Date());

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));
        when(paymentLedgerMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);

        Map<String, Object> res = ledgerMigrationService.executeBackfill(1, 999, null, true);

        assertEquals(1, res.get("anomalies_count"));
        List<Map<String, Object>> anomalies = (List<Map<String, Object>>) res.get("anomalies");
        assertEquals(1, anomalies.size());
        assertEquals("CHANNEL_SUM_MISMATCH", anomalies.get(0).get("reason"));
        assertEquals(10000, anomalies.get(0).get("expected_fen"));
        assertEquals(2000, anomalies.get(0).get("channel_sum_fen"));
    }

    @Test
    public void testShadowVerify_balanced() {
        Order o1 = new Order();
        o1.setId(201);
        o1.setOrder_no("ORD-201");
        o1.setShop_id(1);
        o1.setSett_amount(88.0);
        o1.setPay_amount_cash(88.0);

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));

        PaymentLedger l1 = PaymentLedger.builder()
                .shop_id(1)
                .order_id(201L)
                .channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(8800)
                .status(PaymentLedger.STATUS_SUCCEEDED)
                .build();
        when(paymentLedgerMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(l1));

        Map<String, Object> res = ledgerMigrationService.shadowVerify(1, "2026-10-03");

        assertEquals(true, res.get("ready_for_cutover"));
        assertEquals(0L, res.get("net_variance_fen"));
        assertEquals(0, res.get("discrepancy_count"));
    }

    @Test
    public void testShadowVerify_detectsVariance() {
        Order o1 = new Order();
        o1.setId(202);
        o1.setOrder_no("ORD-202");
        o1.setShop_id(1);
        o1.setSett_amount(100.0);
        o1.setPay_amount_wechat(100.0);

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));
        // Empty ledger: missing ledger entry
        when(paymentLedgerMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        Map<String, Object> res = ledgerMigrationService.shadowVerify(1, "2026-10-03");

        assertEquals(false, res.get("ready_for_cutover"));
        assertEquals(-10000L, res.get("net_variance_fen"));
        assertEquals(1, res.get("discrepancy_count"));
    }

    @Test
    public void testCutoverReadSource_switchesAndPersists() {
        when(systemConfigMapper.selectByShopAndKey(1, ILedgerMigrationService.CONFIG_KEY_READ_SOURCE)).thenReturn(null);

        Map<String, Object> res = ledgerMigrationService.cutoverReadSource(1, 999, "LEGACY_ORDER");
        assertEquals("LEGACY_ORDER", res.get("current_read_source"));

        verify(systemConfigMapper, times(1)).insert(any(SystemConfig.class));

        // When queried, returns configured value
        SystemConfig sc = new SystemConfig();
        sc.setConfig_value("LEGACY_ORDER");
        when(systemConfigMapper.selectByShopAndKey(1, ILedgerMigrationService.CONFIG_KEY_READ_SOURCE)).thenReturn(sc);

        String readSource = ledgerMigrationService.getReadSource(1);
        assertEquals("LEGACY_ORDER", readSource);
    }

    @Test(expected = ApiException.class)
    public void testCutoverReadSource_rejectsInvalid() {
        ledgerMigrationService.cutoverReadSource(1, 999, "INVALID_SOURCE");
    }
}
