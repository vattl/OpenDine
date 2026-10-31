package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.service.impl.ReconciliationServiceImpl;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.MockitoJUnitRunner;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@RunWith(MockitoJUnitRunner.class)
public class ReconciliationServiceTest {

    @InjectMocks
    private ReconciliationServiceImpl reconciliationService;

    @Mock
    private ChannelStatementBatchMapper batchMapper;
    @Mock
    private ChannelStatementEntryMapper entryMapper;
    @Mock
    private ReconciliationCaseMapper caseMapper;
    @Mock
    private PaymentLedgerMapper ledgerMapper;
    @Mock
    private IOrderService orderService;
    @Mock
    private IShopService shopService;

    @Spy
    private ObjectMapper objectMapper = new ObjectMapper();

    private Shop mockShop;

    @Before
    public void setUp() {
        mockShop = new Shop();
        mockShop.setId(1);
        mockShop.setName("测试分店");
        mockShop.setSettle_time("04:00");
        lenient().when(shopService.getById(anyInt())).thenReturn(mockShop);
        lenient().when(shopService.getOne(any())).thenReturn(mockShop);
    }

    @Test
    public void testImportStatement_duplicateSha256Blocked() {
        ChannelStatementBatch existing = new ChannelStatementBatch();
        existing.setBatch_no("BAT-20261003-EXIST1");
        existing.setImported_at(new Date());

        when(batchMapper.selectOne(any())).thenReturn(existing);

        try {
            reconciliationService.importStatement(1, 99, "WECHAT", "statement.csv", "sample-content");
            fail("应抛出 409 冲突异常");
        } catch (ApiException e) {
            assertEquals(409, e.getHttpStatus());
            assertTrue(e.getMessage().contains("对账单文件已导入"));
        }
    }

    @Test
    public void testImportStatement_genericCsvSuccess() {
        when(batchMapper.selectOne(any())).thenReturn(null);

        String csv = "trade_time,channel,channel_trade_no,merchant_order_no,entry_type,amount,fee\n"
                + "2026-10-03 10:00:00,WECHAT,WX10001,ORD2026100301,PAYMENT,50.00,0.30\n"
                + "2026-10-03 11:30:00,WECHAT,WX10002,ORD2026100302,PAYMENT,30.00,0.18\n";

        ChannelStatementBatch batch = reconciliationService.importStatement(1, 88, "WECHAT", "wechat_oct03.csv", csv);

        assertNotNull(batch);
        assertEquals(Integer.valueOf(2), batch.getTotal_count());
        assertEquals(Long.valueOf(8000), batch.getTotal_amount_fen());
        assertEquals(Long.valueOf(48), batch.getFee_fen());
        assertEquals(Long.valueOf(7952), batch.getNet_amount_fen());
        assertEquals(ChannelStatementBatch.STATUS_PARSED, batch.getStatus());

        verify(batchMapper, times(1)).insert(any(ChannelStatementBatch.class));
        verify(entryMapper, times(2)).insert(any(ChannelStatementEntry.class));
    }

    @Test
    public void testImportStatement_wechatCsvSuccess() {
        when(batchMapper.selectOne(any())).thenReturn(null);

        // 模拟微信商户官方对账单格式（带反引号、表头与汇总行）
        String wxCsv = "交易时间,公众账号ID,商户号,特约商户号,设备号,微信订单号,商户订单号,用户标识,交易类型,交易状态,付款银行,货币种类,应结订单金额,代金券金额,微信退款单号,商户退款单号,退款金额,充值券退款金额,退款类型,退款状态,商品名称,商户数据包,手续费,费率,订单金额,申请退款金额,费率备注\n"
                + "`2026-10-03 14:00:00,`wx123,`190001,`0,`POS01,`4200002001,`ORD2026100388,`user1,`JSAPI,`SUCCESS,`CFT,`CNY,`100.00,`0.00,`0,`0,`0.00,`0.00,`,` ,`点餐消费,`pkg,`0.60,`0.60%,`100.00,`0.00,`\n"
                + "总交易单数,总交易额,总退款金额,总代金券金额,总手续费\n"
                + "`1,`100.00,`0.00,`0.00,`0.60\n";

        ChannelStatementBatch batch = reconciliationService.importStatement(1, 88, "WECHAT", "wx_daily.csv", wxCsv);

        assertNotNull(batch);
        assertEquals(Integer.valueOf(1), batch.getTotal_count());
        assertEquals(Long.valueOf(10000), batch.getTotal_amount_fen());
        assertEquals(Long.valueOf(60), batch.getFee_fen());
    }

    @Test
    public void testImportStatement_duplicateOrderRefundRowsAreMatchedIndependently() {
        when(batchMapper.selectOne(any())).thenReturn(null);
        doAnswer(invocation -> {
            ChannelStatementBatch batch = invocation.getArgument(0);
            batch.setId(101L);
            return 1;
        }).when(batchMapper).insert(any(ChannelStatementBatch.class));
        java.util.concurrent.atomic.AtomicLong entryId = new java.util.concurrent.atomic.AtomicLong(200L);
        List<ChannelStatementEntry> savedEntries = new ArrayList<>();
        doAnswer(invocation -> {
            ChannelStatementEntry entry = invocation.getArgument(0);
            entry.setId(entryId.incrementAndGet());
            savedEntries.add(entry);
            return 1;
        }).when(entryMapper).insert(any(ChannelStatementEntry.class));
        when(entryMapper.selectList(any())).thenReturn(savedEntries);

        PaymentLedger refund1 = PaymentLedger.builder().id(11L).shop_id(1).order_no("ORD-SAME")
                .entry_type(PaymentLedger.ENTRY_TYPE_REFUND).channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(-1000).status(PaymentLedger.STATUS_SUCCEEDED).build();
        PaymentLedger refund2 = PaymentLedger.builder().id(12L).shop_id(1).order_no("ORD-SAME")
                .entry_type(PaymentLedger.ENTRY_TYPE_REFUND).channel(PaymentLedger.CHANNEL_WECHAT)
                .amount_fen(-500).status(PaymentLedger.STATUS_SUCCEEDED).build();
        when(ledgerMapper.selectList(any())).thenReturn(Arrays.asList(refund1, refund2));

        String csv = "trade_time,channel,channel_trade_no,merchant_order_no,entry_type,amount,fee\n"
                + "2026-10-03 10:00:00,WECHAT,R1,ORD-SAME,REFUND,10.00,0.00\n"
                + "2026-10-03 11:00:00,WECHAT,R2,ORD-SAME,REFUND,5.00,0.00\n";
        reconciliationService.importStatement(1, 88, "WECHAT", "refunds.csv", csv);

        org.mockito.ArgumentCaptor<ChannelStatementEntry> captor =
                org.mockito.ArgumentCaptor.forClass(ChannelStatementEntry.class);
        verify(entryMapper, times(2)).updateById(captor.capture());
        List<ChannelStatementEntry> updated = captor.getAllValues();
        assertEquals(2, updated.stream().map(ChannelStatementEntry::getId).distinct().count());
        assertTrue(updated.stream().allMatch(e -> ChannelStatementEntry.MATCH_STATUS_MATCHED.equals(e.getMatch_status())));
        assertTrue(updated.stream().allMatch(e -> e.getAmount_fen() < 0));
    }

    @Test
    public void testImportStatement_corruptFileFails() {
        when(batchMapper.selectOne(any())).thenReturn(null);

        String invalidCsv = "colA,colB\nabc,def\n";

        try {
            reconciliationService.importStatement(1, 88, "WECHAT", "bad.csv", invalidCsv);
            fail("应抛出 400 校验异常");
        } catch (ApiException e) {
            assertEquals(400, e.getHttpStatus());
            assertTrue(e.getMessage().contains("未解析到有效对账明细"));
        }
    }

    @Test
    public void testOverview_unimportedStatusWhenNoBatches() {
        when(batchMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(ledgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(caseMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> overview = reconciliationService.getReconciliationOverview(1, "2026-10-03");

        assertNotNull(overview);
        assertEquals(false, overview.get("has_channel_statement"));
        // 核心守则：未导入对账单强制为 UNIMPORTED，绝不可显示 RECONCILED
        assertEquals("UNIMPORTED", overview.get("summary_status"));

        Map<?, ?> layer2 = (Map<?, ?>) overview.get("layer2");
        assertNotNull(layer2);
        assertEquals("UNIMPORTED", layer2.get("status"));
        assertTrue(layer2.get("message").toString().contains("未导入"));
    }

    @Test
    public void testOverview_discrepancyWhenDifferenceExists() {
        ChannelStatementBatch batch = ChannelStatementBatch.builder()
                .id(101L)
                .statement_date(new Date())
                .total_count(1)
                .total_amount_fen(5000L)
                .fee_fen(30L)
                .build();
        when(batchMapper.selectList(any())).thenReturn(Collections.singletonList(batch));

        ChannelStatementEntry entry = ChannelStatementEntry.builder()
                .id(201L)
                .batch_id(101L)
                .match_status(ChannelStatementEntry.MATCH_STATUS_UNMATCHED) // 未对平
                .amount_fen(5000)
                .build();
        when(entryMapper.selectList(any())).thenReturn(Collections.singletonList(entry));
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(ledgerMapper.selectList(any())).thenReturn(Collections.emptyList());

        ReconciliationCase openCase = ReconciliationCase.builder()
                .id(301L)
                .status(ReconciliationCase.STATUS_OPEN)
                .build();
        when(caseMapper.selectList(any())).thenReturn(Collections.singletonList(openCase));

        Map<String, Object> overview = reconciliationService.getReconciliationOverview(1, "2026-10-03");

        assertNotNull(overview);
        assertEquals(true, overview.get("has_channel_statement"));
        assertEquals("DISCREPANCY", overview.get("summary_status"));
        assertEquals(1L, overview.get("open_cases_count"));
    }

    @Test
    public void testOverview_reconciledWhenAllBalanced() {
        ChannelStatementBatch batch = ChannelStatementBatch.builder()
                .id(101L)
                .statement_date(new Date())
                .total_count(1)
                .total_amount_fen(5000L)
                .fee_fen(30L)
                .build();
        when(batchMapper.selectList(any())).thenReturn(Collections.singletonList(batch));

        ChannelStatementEntry entry = ChannelStatementEntry.builder()
                .id(201L)
                .batch_id(101L)
                .match_status(ChannelStatementEntry.MATCH_STATUS_MATCHED)
                .amount_fen(5000)
                .build();
        when(entryMapper.selectList(any())).thenReturn(Collections.singletonList(entry));

        Order order = new Order();
        order.setId(1);
        order.setSett_amount(50.0);
        order.setService_fee(0.0);
        order.setDiscount_amount(0.0);
        order.setRefund_amount(0.0);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));

        PaymentLedger ledger = PaymentLedger.builder()
                .id(11L)
                .order_id(1L)
                .amount_fen(5000)
                .entry_type("PAYMENT")
                .status("SUCCEEDED")
                .build();
        when(ledgerMapper.selectList(any())).thenReturn(Collections.singletonList(ledger));
        when(caseMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> overview = reconciliationService.getReconciliationOverview(1, "2026-10-03");

        assertNotNull(overview);
        assertEquals(true, overview.get("has_channel_statement"));
        assertEquals("RECONCILED", overview.get("summary_status"));
        assertEquals(0L, overview.get("open_cases_count"));
    }

    @Test
    public void testOverview_unmatchedInternalForcesDiscrepancyEvenWithoutOpenCases() {
        ChannelStatementBatch batch = ChannelStatementBatch.builder()
                .id(101L).channel("WECHAT").statement_date(new Date())
                .total_count(0).total_amount_fen(0L).fee_fen(0L).build();
        when(batchMapper.selectList(any())).thenReturn(Collections.singletonList(batch));
        when(entryMapper.selectList(any())).thenReturn(Collections.emptyList());

        Order order = new Order();
        order.setSett_amount(50d);
        order.setPay_amount_wechat(50d);
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(order));
        PaymentLedger ledger = PaymentLedger.builder()
                .id(11L).channel(PaymentLedger.CHANNEL_WECHAT).amount_fen(5000)
                .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                .status(PaymentLedger.STATUS_SUCCEEDED).build();
        when(ledgerMapper.selectList(any())).thenReturn(Collections.singletonList(ledger));
        when(caseMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> overview = reconciliationService.getReconciliationOverview(1, "2026-10-03");

        assertEquals("DISCREPANCY", overview.get("summary_status"));
        Map<?, ?> layer2 = (Map<?, ?>) overview.get("layer2");
        assertEquals(1, layer2.get("unmatched_internal_count"));
    }

    @Test
    public void testOverview_usesPaymentWindowAndExcludesReceivables() {
        when(batchMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(orderService.list(any(Wrapper.class))).thenReturn(Collections.emptyList());
        when(ledgerMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(caseMapper.selectList(any())).thenReturn(Collections.emptyList());

        reconciliationService.getReconciliationOverview(1, "2026-10-03");

        @SuppressWarnings("unchecked")
        org.mockito.ArgumentCaptor<Wrapper<Order>> captor = org.mockito.ArgumentCaptor.forClass(Wrapper.class);
        verify(orderService).list(captor.capture());
        String sql = captor.getValue().getCustomSqlSegment();
        assertTrue(sql.contains("pay_time"));
        assertTrue(sql.contains("payment_method"));
    }

    @Test
    public void testResolveCase_updatesStatusAndAudits() {
        ReconciliationCase rc = ReconciliationCase.builder()
                .id(501L)
                .shop_id(1)
                .case_no("CASE-20261003-0001")
                .status(ReconciliationCase.STATUS_OPEN)
                .build();

        when(caseMapper.selectById(501L)).thenReturn(rc);

        ReconciliationCase resolved = reconciliationService.resolveCase(1, 99, 501L, "CLOSED", "经核对为跨日延迟入账，已平账", "张三财务");

        assertNotNull(resolved);
        assertEquals(ReconciliationCase.STATUS_CLOSED, resolved.getStatus());
        assertEquals("经核对为跨日延迟入账，已平账", resolved.getResolution_note());
        assertEquals("张三财务", resolved.getResponsible_person());
        assertEquals(Integer.valueOf(99), resolved.getResolved_by());
        assertNotNull(resolved.getResolved_at());

        verify(caseMapper, times(1)).updateById(rc);
    }
}
