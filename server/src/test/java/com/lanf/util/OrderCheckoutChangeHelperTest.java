package com.lanf.util;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class OrderCheckoutChangeHelperTest {

    @Test
    void fullCashTenderAutoChange() {
        Order req = new Order();
        req.setCheckout_cash_tender(100d);
        req.setCheckout_change_channel("wechat");
        OrderCheckoutChangeHelper.ResolvedChange out = new OrderCheckoutChangeHelper.ResolvedChange();
        assertNull(OrderCheckoutChangeHelper.validateAndResolve(req, 70d, out));
        assertEquals(100d, out.cashTenderYuan);
        assertEquals(30d, out.changeAmountYuan);
        assertEquals("wechat", out.changeChannel);
    }

    @Test
    void explicitChangeRequiresChannel() {
        Order req = new Order();
        req.setCheckout_change_amount(30d);
        OrderCheckoutChangeHelper.ResolvedChange out = new OrderCheckoutChangeHelper.ResolvedChange();
        assertEquals("找零金额大于0时须指定找零渠道（wechat/cash/alipay）",
                OrderCheckoutChangeHelper.validateAndResolve(req, 70d, out));
    }

    @Test
    void exactTenderNoChange() {
        Order req = new Order();
        req.setCheckout_cash_tender(70d);
        OrderCheckoutChangeHelper.ResolvedChange out = new OrderCheckoutChangeHelper.ResolvedChange();
        assertNull(OrderCheckoutChangeHelper.validateAndResolve(req, 70d, out));
        assertEquals(0d, out.changeAmountYuan);
        assertNull(out.changeChannel);
    }

    @Test
    void enrichOrderChangeDisplayLabel() {
        Order o = new Order();
        o.setCheckout_change_amount(30d);
        o.setCheckout_change_channel("wechat");
        OrderCheckoutChangeHelper.enrichOrderChangeDisplay(o);
        assertEquals("微信", o.getCheckout_change_channel_label());
    }
}
