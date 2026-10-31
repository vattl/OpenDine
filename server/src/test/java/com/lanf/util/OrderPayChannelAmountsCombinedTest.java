package com.lanf.util;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class OrderPayChannelAmountsCombinedTest {

    @Test
    void applyOnlineCombined_shouldWriteExactThreeChannelSplit() {
        Order target = new Order();
        Order request = new Order();
        request.setPay_amount_wechat(30d);
        request.setPay_amount_alipay(20d);
        request.setPay_amount_balance(10d);

        OrderPayChannelAmounts.applyOnlineCombined(target, request, 60d);

        assertEquals(30d, target.getPay_amount_wechat());
        assertEquals(20d, target.getPay_amount_alipay());
        assertEquals(10d, target.getPay_amount_balance());
        assertEquals(0d, target.getPay_amount_cash());
        assertEquals(0d, target.getPay_amount_gift());
    }

    @Test
    void applyOnlineCombined_shouldRejectSingleChannelOrMismatchedTotal() {
        Order single = new Order();
        single.setPay_amount_wechat(60d);
        assertThrows(IllegalArgumentException.class,
                () -> OrderPayChannelAmounts.applyOnlineCombined(new Order(), single, 60d));

        Order mismatch = new Order();
        mismatch.setPay_amount_wechat(30d);
        mismatch.setPay_amount_alipay(20d);
        assertThrows(IllegalArgumentException.class,
                () -> OrderPayChannelAmounts.applyOnlineCombined(new Order(), mismatch, 60d));
    }

    @Test
    void applyOnlineCombined_shouldAcceptAndPersistCashPlusBalance() {
        Order target = new Order();
        Order request = new Order();
        request.setPay_amount_cash(35d);
        request.setPay_amount_balance(25d);

        OrderPayChannelAmounts.applyOnlineCombined(target, request, 60d);

        assertEquals(35d, target.getPay_amount_cash());
        assertEquals(25d, target.getPay_amount_balance());
        assertEquals(0d, target.getPay_amount_wechat());
        assertEquals(0d, target.getPay_amount_alipay());
    }

    @Test
    void applyOnlineCombined_shouldAcceptAndPersistCashPlusWechat() {
        Order target = new Order();
        Order request = new Order();
        request.setPay_amount_cash(10d);
        request.setPay_amount_wechat(50d);

        OrderPayChannelAmounts.applyOnlineCombined(target, request, 60d);

        assertEquals(10d, target.getPay_amount_cash());
        assertEquals(50d, target.getPay_amount_wechat());
        assertEquals(0d, target.getPay_amount_balance());
        assertEquals(0d, target.getPay_amount_alipay());
    }
}
