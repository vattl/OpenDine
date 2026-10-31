package com.lanf.receivable;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.receivable.entity.ReceivableAccount;
import com.lanf.receivable.entity.ReceivableClaim;
import com.lanf.receivable.entity.ReceivableLedger;
import com.lanf.receivable.mapper.ReceivableAccountMapper;
import com.lanf.receivable.mapper.ReceivableClaimMapper;
import com.lanf.receivable.mapper.ReceivableLedgerMapper;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ReceivableServiceTest {

    private ReceivableService service;
    private ReceivableAccountMapper accountMapper;
    private ReceivableClaimMapper claimMapper;
    private ReceivableLedgerMapper ledgerMapper;
    private IOrderService orderService;
    private PaymentSuccessHandler paymentSuccessHandler;

    @BeforeEach
    void setUp() {
        service = new ReceivableService();
        accountMapper = mock(ReceivableAccountMapper.class);
        claimMapper = mock(ReceivableClaimMapper.class);
        ledgerMapper = mock(ReceivableLedgerMapper.class);
        orderService = mock(IOrderService.class);
        paymentSuccessHandler = mock(PaymentSuccessHandler.class);
        ReflectionTestUtils.setField(service, "accountMapper", accountMapper);
        ReflectionTestUtils.setField(service, "claimMapper", claimMapper);
        ReflectionTestUtils.setField(service, "ledgerMapper", ledgerMapper);
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "paymentSuccessHandler", paymentSuccessHandler);
        ReflectionTestUtils.setField(service, "clock", Clock.fixed(
                Instant.parse("2026-10-17T04:00:00Z"), ZoneId.of("Asia/Shanghai")));
    }

    @Test
    void charge_usesServerOrderAmountAndCreatesOpenClaimWithoutPaymentAmounts() {
        ReceivableAccount account = activeAccount(1_000_000L, 200_000L);
        Order order = unsettledOrder(128.50d);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(accountMapper.updateById(any())).thenReturn(1);
        when(claimMapper.insert(any())).thenReturn(1);
        when(ledgerMapper.insert(any())).thenReturn(1);
        when(orderService.updateById(any())).thenReturn(true);

        ReceivableClaim claim = service.charge(7, 9, "1", "ORD-1", 11L, "REQ-CHARGE-1", "月结客户");

        assertEquals(12_850L, claim.getOriginalAmountFen());
        assertEquals(12_850L, claim.getOutstandingFen());
        assertEquals(ReceivableClaim.STATUS_OPEN, claim.getStatus());
        assertEquals(212_850L, account.getOutstandingFen());
        assertEquals("success", order.getTransac_status());
        assertEquals(ReceivableService.PAYMENT_METHOD_RECEIVABLE, order.getPayment_method());
        assertEquals(0d, order.getPay_amount_cash());
        verify(paymentSuccessHandler).run(order, 0d);
    }

    @Test
    void charge_rejectsWhenCreditLimitWouldBeExceeded() {
        ReceivableAccount account = activeAccount(210_000L, 200_000L);
        Order order = unsettledOrder(128.50d);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.charge(7, 9, "1", "ORD-1", 11L, "REQ-CHARGE-2", null));

        assertEquals("RECEIVABLE_CREDIT_EXCEEDED", error.getErrorCode());
        verify(claimMapper, never()).insert(any());
        verify(orderService, never()).updateById(any());
    }

    @Test
    void charge_replaysSameRequestWithoutLoadingOrUpdatingOrder() {
        ReceivableClaim existing = openClaim(12_850L);
        existing.setOrderNo("ORD-1");
        existing.setAccountId(11L);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(existing);

        ReceivableClaim replay = service.charge(7, 9, "1", "ORD-1", 11L, "REQ-CHARGE-REPLAY", null);

        assertSame(existing, replay);
        verify(orderService, never()).getOne(any(Wrapper.class));
        verify(accountMapper, never()).updateById(any());
    }

    @Test
    void charge_rechecksIdempotencyAfterOrderLockForConcurrentWinner() {
        ReceivableClaim existing = openClaim(12_850L);
        existing.setOrderNo("ORD-1");
        existing.setAccountId(11L);
        Order committedOrder = unsettledOrder(128.50d);
        committedOrder.setTransac_status("success");
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(null, existing);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(committedOrder);

        ReceivableClaim replay = service.charge(7, 9, "1", "ORD-1", 11L, "REQ-CONCURRENT", null);

        assertSame(existing, replay);
        verify(claimMapper, never()).insert(any());
        verify(orderService, never()).updateById(any());
    }

    @Test
    void charge_allowsExplicitMerchantScopedAccountFromAnotherStore() {
        ReceivableAccount account = activeAccount(1_000_000L, 0L);
        account.setScopeType(ReceivableAccount.SCOPE_MERCHANT);
        account.setShopId(null);
        Order order = unsettledOrder(10d);
        order.setShop_id(8);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(accountMapper.updateById(any())).thenReturn(1);
        when(claimMapper.insert(any())).thenReturn(1);
        when(ledgerMapper.insert(any())).thenReturn(1);
        when(orderService.updateById(any())).thenReturn(true);

        ReceivableClaim claim = service.charge(8, 9, "1", "ORD-1", 11L, "REQ-MERCHANT-SCOPE", null);

        assertEquals(8, claim.getShopId());
        assertEquals(1_000L, account.getOutstandingFen());
    }

    @Test
    void charge_rejectsSuspendedAccountWithoutWritingFinancialRows() {
        ReceivableAccount account = activeAccount(1_000_000L, 0L);
        account.setStatus(ReceivableAccount.STATUS_SUSPENDED);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(unsettledOrder(10d));
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.charge(7, 9, "1", "ORD-1", 11L, "REQ-SUSPENDED", null));

        assertEquals("RECEIVABLE_ACCOUNT_INACTIVE", error.getErrorCode());
        verify(claimMapper, never()).insert(any());
        verify(ledgerMapper, never()).insert(any());
    }

    @Test
    void collect_partiallyReducesClaimAndAccountAndAppendsNegativeLedger() {
        ReceivableAccount account = activeAccount(1_000_000L, 12_850L);
        ReceivableClaim claim = new ReceivableClaim();
        claim.setId(31L);
        claim.setMerchantId("1");
        claim.setShopId(7);
        claim.setAccountId(11L);
        claim.setOrderNo("ORD-1");
        claim.setOriginalAmountFen(12_850L);
        claim.setOutstandingFen(12_850L);
        claim.setStatus(ReceivableClaim.STATUS_OPEN);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(accountMapper.updateById(any())).thenReturn(1);
        when(claimMapper.updateById(any())).thenReturn(1);
        when(ledgerMapper.insert(any())).thenReturn(1);

        ReceivableLedger ledger = service.collect(
                7, 9, "1", 31L, 5_000L, "BANK_TRANSFER", "REQ-COLLECT-1", "首期回款", null);

        assertEquals(-5_000L, ledger.getAmountFen());
        assertEquals(7_850L, claim.getOutstandingFen());
        assertEquals(ReceivableClaim.STATUS_PARTIAL, claim.getStatus());
        assertEquals(7_850L, account.getOutstandingFen());
    }

    @Test
    void collect_replaysSameRequestWithoutApplyingBalanceTwice() {
        ReceivableLedger existing = new ReceivableLedger();
        existing.setClaimId(31L);
        existing.setEntryType(ReceivableLedger.TYPE_COLLECTION);
        existing.setAmountFen(-5_000L);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(existing);

        ReceivableLedger replay = service.collect(
                7, 9, "1", 31L, 5_000L, "BANK_TRANSFER", "REQ-COLLECT-REPLAY", null, null);

        assertSame(existing, replay);
        verify(claimMapper, never()).updateById(any());
        verify(accountMapper, never()).updateById(any());
        verify(ledgerMapper, never()).insert(any());
    }

    @Test
    void collect_fullAmountSettlesClaimAndReleasesAccountBalance() {
        ReceivableAccount account = activeAccount(1_000_000L, 12_850L);
        ReceivableClaim claim = openClaim(12_850L);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(accountMapper.updateById(any())).thenReturn(1);
        when(claimMapper.updateById(any())).thenReturn(1);
        when(ledgerMapper.insert(any())).thenReturn(1);

        service.collect(7, 9, "1", 31L, 12_850L, "BANK_TRANSFER", "REQ-COLLECT-FULL", null, null);

        assertEquals(0L, claim.getOutstandingFen());
        assertEquals(ReceivableClaim.STATUS_SETTLED, claim.getStatus());
        assertEquals(0L, account.getOutstandingFen());
    }

    @Test
    void collect_rejectsAmountAboveOutstanding() {
        ReceivableClaim claim = openClaim(12_850L);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);

        ApiException error = assertThrows(ApiException.class, () -> service.collect(
                7, 9, "1", 31L, 12_851L, "BANK_TRANSFER", "REQ-COLLECT-OVER", null, null));

        assertEquals("COLLECTION_EXCEEDS_OUTSTANDING", error.getErrorCode());
        verify(ledgerMapper, never()).insert(any());
    }

    @Test
    void writeOff_closesRemainingClaimAndReleasesAccountBalance() {
        ReceivableClaim claim = openClaim(7_850L);
        claim.setStatus(ReceivableClaim.STATUS_PARTIAL);
        ReceivableAccount account = activeAccount(1_000_000L, 7_850L);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(ledgerMapper.insert(any())).thenReturn(1);
        when(claimMapper.updateById(any())).thenReturn(1);
        when(accountMapper.updateById(any())).thenReturn(1);

        ReceivableLedger ledger = service.writeOff(7, 9, "1", 31L, "REQ-WRITEOFF-1", "确认无法收回");

        assertEquals(-7_850L, ledger.getAmountFen());
        assertEquals(ReceivableLedger.TYPE_WRITE_OFF, ledger.getEntryType());
        assertEquals(0L, claim.getOutstandingFen());
        assertEquals(ReceivableClaim.STATUS_WRITTEN_OFF, claim.getStatus());
        assertEquals(0L, account.getOutstandingFen());
    }

    @Test
    void reverse_unpaidClaimRestoresOrderAndReleasesCredit() {
        ReceivableClaim claim = openClaim(12_850L);
        claim.setActiveKey("1:7:ORD-1");
        ReceivableAccount account = activeAccount(1_000_000L, 12_850L);
        Order order = unsettledOrder(12.85d);
        order.setTransac_status("success");
        order.setPayment_method("挂账");
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);
        when(ledgerMapper.selectCount(any(Wrapper.class))).thenReturn(0);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);
        when(ledgerMapper.insert(any())).thenReturn(1);
        when(claimMapper.updateById(any())).thenReturn(1);
        when(accountMapper.updateById(any())).thenReturn(1);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(orderService.updateById(any())).thenReturn(true);

        ReceivableLedger ledger = service.reverse(7, 9, "1", 31L, "REQ-REVERSE-1", "客户取消");

        assertEquals(-12_850L, ledger.getAmountFen());
        assertEquals(ReceivableClaim.STATUS_REVERSED, claim.getStatus());
        assertEquals(0L, account.getOutstandingFen());
        assertEquals("unsettled", order.getTransac_status());
    }

    @Test
    void reverse_rejectsClaimAfterAnyPartialCollection() {
        ReceivableClaim claim = openClaim(7_850L);
        claim.setStatus(ReceivableClaim.STATUS_PARTIAL);
        when(ledgerMapper.selectOne(any(Wrapper.class))).thenReturn(null);
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);

        ApiException error = assertThrows(ApiException.class,
                () -> service.reverse(7, 9, "1", 31L, "REQ-REVERSE-PARTIAL", "错误挂账"));

        assertEquals("CLAIM_REVERSAL_NOT_ALLOWED", error.getErrorCode());
        verify(ledgerMapper, never()).insert(any());
    }

    @Test
    void closeAccount_rejectsAccountWithOutstandingBalance() {
        ReceivableAccount account = activeAccount(1_000_000L, 1L);
        when(accountMapper.selectOne(any(Wrapper.class))).thenReturn(account);

        ApiException error = assertThrows(ApiException.class,
                () -> service.closeAccount(7, 9, "1", 11L));

        assertEquals("RECEIVABLE_ACCOUNT_HAS_BALANCE", error.getErrorCode());
        verify(accountMapper, never()).updateById(any());
    }

    @Test
    void createAccount_initializesActiveZeroBalanceAccount() {
        when(accountMapper.insert(any())).thenReturn(1);

        ReceivableAccount account = service.createAccount(
                7, 9, "1", "SHOP", "COMPANY", "测试企业", "张三", "13800000000",
                "TAX-1", 500_000L, 30, "月结");

        assertEquals(ReceivableAccount.STATUS_ACTIVE, account.getStatus());
        assertEquals(0L, account.getOutstandingFen());
        assertEquals(7, account.getShopId());
        assertEquals(500_000L, account.getCreditLimitFen());
        verify(accountMapper).insert(account);
    }

    @Test
    void createMerchantScopedAccount_requiresHeadquartersPermission() {
        ApiException error = assertThrows(ApiException.class, () -> service.createAccount(
                7, 9, "1", "MERCHANT", "COMPANY", "跨店客户", null, null,
                null, 500_000L, 30, null));

        assertEquals(403, error.getHttpStatus());
        assertEquals("RECEIVABLE_MERCHANT_SCOPE_FORBIDDEN", error.getErrorCode());
        verify(accountMapper, never()).insert(any());
    }

    @Test
    void summarizeWindow_usesShopClaimsForOutstandingInsteadOfMerchantAccountBalance() {
        when(ledgerMapper.summarizeWindow(any(), any(), any(), any()))
                .thenReturn(Collections.emptyMap());
        when(claimMapper.sumOutstandingByShop("1", 7)).thenReturn(7_850L);

        ReceivableWindowSummary summary = service.summarizeWindow(
                "1", 7, new Date(1_000L), new Date(2_000L));

        assertEquals(7_850L, summary.getOutstandingFen());
        verify(accountMapper, never()).selectList(any(Wrapper.class));
    }

    @Test
    void aging_treatsDueDateAsBusinessDateAndBucketsOverdueBalances() {
        ReceivableClaim dueToday = openClaim(1_000L);
        dueToday.setDueDate(atStartOfDay("2026-10-17"));
        ReceivableClaim oneDayLate = openClaim(2_000L);
        oneDayLate.setDueDate(atStartOfDay("2026-10-16"));
        ReceivableClaim thirtyOneDaysLate = openClaim(3_000L);
        thirtyOneDaysLate.setDueDate(atStartOfDay("2026-09-16"));
        when(claimMapper.selectList(any(Wrapper.class)))
                .thenReturn(Arrays.asList(dueToday, oneDayLate, thirtyOneDaysLate));

        java.util.Map<String, Object> aging = service.aging("1", 7);

        assertEquals(1_000L, aging.get("current_fen"));
        assertEquals(2_000L, aging.get("days_1_30_fen"));
        assertEquals(3_000L, aging.get("days_31_60_fen"));
        assertEquals(6_000L, aging.get("total_outstanding_fen"));
    }

    @Test
    void getClaim_exposesPastDueOpenClaimAsOverdueWithoutFinancialWrite() {
        ReceivableClaim claim = openClaim(1_000L);
        claim.setDueDate(atStartOfDay("2026-10-16"));
        when(claimMapper.selectOne(any(Wrapper.class))).thenReturn(claim);

        ReceivableClaim result = service.getClaim("1", 7, 31L);

        assertEquals(ReceivableClaim.STATUS_OVERDUE, result.getStatus());
        verify(claimMapper, never()).updateById(any());
    }

    private static ReceivableAccount activeAccount(long limitFen, long outstandingFen) {
        ReceivableAccount account = new ReceivableAccount();
        account.setId(11L);
        account.setMerchantId("1");
        account.setScopeType(ReceivableAccount.SCOPE_SHOP);
        account.setShopId(7);
        account.setCustomerName("测试客户");
        account.setCreditLimitFen(limitFen);
        account.setOutstandingFen(outstandingFen);
        account.setPaymentTermsDays(30);
        account.setStatus(ReceivableAccount.STATUS_ACTIVE);
        account.setVersion(1);
        return account;
    }

    private static Order unsettledOrder(double amount) {
        Order order = new Order();
        order.setId(21);
        order.setOrder_no("ORD-1");
        order.setMerchantId("1");
        order.setShop_id(7);
        order.setSett_amount(amount);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        order.setRefund_amount(0d);
        order.setTransac_status("unsettled");
        order.setDineInOrTakeOut("打包");
        return order;
    }

    private static ReceivableClaim openClaim(long outstandingFen) {
        ReceivableClaim claim = new ReceivableClaim();
        claim.setId(31L);
        claim.setMerchantId("1");
        claim.setShopId(7);
        claim.setAccountId(11L);
        claim.setOrderNo("ORD-1");
        claim.setOriginalAmountFen(12_850L);
        claim.setOutstandingFen(outstandingFen);
        claim.setStatus(ReceivableClaim.STATUS_OPEN);
        claim.setVersion(1);
        return claim;
    }

    private static Date atStartOfDay(String date) {
        return Date.from(LocalDate.parse(date).atStartOfDay(ZoneId.of("Asia/Shanghai")).toInstant());
    }
}
