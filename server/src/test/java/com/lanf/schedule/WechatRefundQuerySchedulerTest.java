package com.lanf.schedule;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatJsapiChannel;
import com.lanf.payment.service.PaymentRefundLedger;
import com.lanf.payment.service.WechatRefundSettlementService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Constructor;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatRefundQuerySchedulerTest {

    private final PaymentRefundLedger ledger = mock(PaymentRefundLedger.class);
    private final IOrderService orderService = mock(IOrderService.class);
    private final WechatJsapiChannel wechatJsapiChannel = mock(WechatJsapiChannel.class);
    private final WechatRefundSettlementService refundSettlementService =
            mock(WechatRefundSettlementService.class);
    private final WechatRefundQueryScheduler scheduler =
            new WechatRefundQueryScheduler(ledger, orderService, wechatJsapiChannel, refundSettlementService);

    private static Order wechatOrder(String orderNo) {
        Order o = new Order();
        o.setOrder_no(orderNo);
        o.setShop_id(7);
        o.setTransaction_id("TX-1");
        return o;
    }

    private static PaymentRefundLedger.Entry pendingEntry(String orderNo, String outRefundNo) {
        try {
            Constructor<PaymentRefundLedger.Entry> ctor =
                    PaymentRefundLedger.Entry.class.getDeclaredConstructor(
                            String.class, String.class, String.class, int.class, int.class, String.class);
            ctor.setAccessible(true);
            return ctor.newInstance(orderNo, "KEY-" + outRefundNo, outRefundNo, 1000, 0, "REQUESTED");
        } catch (Exception e) {
            throw new IllegalStateException("无法构造测试台账条目", e);
        }
    }

    private void stubOnePending() {
        when(ledger.findPending(anyInt()))
                .thenReturn(Collections.singletonList(pendingEntry("ORD-1", "RF-1")));
    }

    @Test
    void successStatusSettlesViaSharedService() {
        stubOnePending();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(wechatOrder("ORD-1"));
        when(wechatJsapiChannel.queryDomesticRefund(any(), anyString()))
                .thenReturn(R.ok().put("status", "SUCCESS").put("amount_refund_fen", 500));

        scheduler.reconcilePendingWechatRefunds();

        verify(refundSettlementService).settle("ORD-1", "RF-1", 500, "compensate");
    }

    @Test
    void closedStatusMarksFailedAndReleasesIdempotencyKey() {
        stubOnePending();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(wechatOrder("ORD-1"));
        when(wechatJsapiChannel.queryDomesticRefund(any(), anyString()))
                .thenReturn(R.ok().put("status", "CLOSED").put("amount_refund_fen", 0));

        scheduler.reconcilePendingWechatRefunds();

        verify(refundSettlementService, never()).settle(anyString(), anyString(), anyInt(), anyString());
        verify(ledger).markRequestFailed(7, "KEY-RF-1");
    }

    @Test
    void nonWechatOrderWithoutTransactionIdMarksFailed() {
        stubOnePending();
        Order cash = new Order();
        cash.setOrder_no("ORD-1");
        cash.setShop_id(7);
        cash.setTransaction_id(null);
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(cash);

        scheduler.reconcilePendingWechatRefunds();

        verify(refundSettlementService, never()).settle(anyString(), anyString(), anyInt(), anyString());
        verify(wechatJsapiChannel, never()).queryDomesticRefund(any(), anyString());
        verify(ledger).markRequestFailed(7, "KEY-RF-1");
    }

    @Test
    void queryFailureLeavesEntryForNextRound() {
        stubOnePending();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(wechatOrder("ORD-1"));
        when(wechatJsapiChannel.queryDomesticRefund(any(), anyString()))
                .thenReturn(R.error("退款查询失败：微信网络异常"));

        assertDoesNotThrow(() -> scheduler.reconcilePendingWechatRefunds());

        verify(refundSettlementService, never()).settle(anyString(), anyString(), anyInt(), anyString());
        verify(ledger, never()).markRequestFailed(anyInt(), anyString());
    }

    @Test
    void processingStatusKeepsEntryPending() {
        stubOnePending();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(wechatOrder("ORD-1"));
        when(wechatJsapiChannel.queryDomesticRefund(any(), anyString()))
                .thenReturn(R.ok().put("status", "PROCESSING").put("amount_refund_fen", 0));

        scheduler.reconcilePendingWechatRefunds();

        verify(refundSettlementService, never()).settle(anyString(), anyString(), anyInt(), anyString());
        verify(ledger, never()).markRequestFailed(anyInt(), anyString());
    }
}
