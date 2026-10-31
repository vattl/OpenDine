package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import com.lanf.entity.MemberRecharge;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminReportControllerDashboardTest {

    private AdminReportController controller;
    private IOrderService orderService;
    private IShopService shopService;
    private IUserService userService;
    private IMemberRechargeService memberRechargeService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminReportController();
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        userService = mock(IUserService.class);
        memberRechargeService = mock(IMemberRechargeService.class);
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);

        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void dashboardReturnsSevenPaymentChannelsIncludingWechatQrAndAlipayQr() {
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());
        when(orderService.getTodayOrderCount(eq(1), any())).thenReturn(10L);

        Map<String, Object> dayPaid = new LinkedHashMap<>();
        dayPaid.put("business_revenue_net", 12560.50);
        dayPaid.put("total_refund_amount", 120.00);
        dayPaid.put("total_discount_amount", 800.00);
        dayPaid.put("paid_order_count", 8L);
        dayPaid.put("pay_channel_wechat", 5000.00);
        dayPaid.put("pay_channel_wechat_qr", 4000.00);
        dayPaid.put("pay_channel_alipay", 1500.00);
        dayPaid.put("pay_channel_alipay_qr", 500.00);
        dayPaid.put("pay_channel_balance", 1000.00);
        dayPaid.put("pay_channel_cash", 500.50);
        dayPaid.put("pay_channel_gift", 60.00);

        when(orderService.aggregateOperationalDayPaidOrderMetrics(eq(1), any()))
                .thenReturn(dayPaid);
        when(memberRechargeService.list(any())).thenReturn(Collections.emptyList());

        R response = controller.dashboard(null, null, null, null, null, null, null, null, 30, null, null);

        assertNotNull(response);
        Map<?, ?> data = (Map<?, ?>) response.get("data");
        assertNotNull(data);
        Map<?, ?> businessDay = (Map<?, ?>) data.get("businessDay");
        assertNotNull(businessDay);

        assertEquals(12560.50d, businessDay.get("todayRevenue"));
        assertEquals(12560.50d, businessDay.get("businessRevenueNet"));
        assertEquals(8L, businessDay.get("todayPaidOrderCount"));

        List<?> channels = (List<?>) businessDay.get("revenueByPayChannel");
        assertNotNull(channels);
        assertEquals(7, channels.size());

        Map<?, ?> ch0 = (Map<?, ?>) channels.get(0);
        assertEquals("wechat", ch0.get("channelCode"));
        assertEquals("微信支付", ch0.get("channelLabel"));
        assertEquals(5000.00d, ch0.get("amount"));

        Map<?, ?> ch1 = (Map<?, ?>) channels.get(1);
        assertEquals("wechat_qr", ch1.get("channelCode"));
        assertEquals("微信收款码", ch1.get("channelLabel"));
        assertEquals(4000.00d, ch1.get("amount"));

        Map<?, ?> ch2 = (Map<?, ?>) channels.get(2);
        assertEquals("alipay", ch2.get("channelCode"));
        assertEquals("支付宝", ch2.get("channelLabel"));
        assertEquals(1500.00d, ch2.get("amount"));

        Map<?, ?> ch3 = (Map<?, ?>) channels.get(3);
        assertEquals("alipay_qr", ch3.get("channelCode"));
        assertEquals("支付宝收款码", ch3.get("channelLabel"));
        assertEquals(500.00d, ch3.get("amount"));

        Map<?, ?> ch4 = (Map<?, ?>) channels.get(4);
        assertEquals("balance", ch4.get("channelCode"));
        assertEquals("余额支付", ch4.get("channelLabel"));
        assertEquals(1000.00d, ch4.get("amount"));

        Map<?, ?> ch5 = (Map<?, ?>) channels.get(5);
        assertEquals("cash", ch5.get("channelCode"));
        assertEquals("现金", ch5.get("channelLabel"));
        assertEquals(500.50d, ch5.get("amount"));

        Map<?, ?> ch6 = (Map<?, ?>) channels.get(6);
        assertEquals("gift", ch6.get("channelCode"));
        assertEquals("赠送金支付", ch6.get("channelLabel"));
        assertEquals(60.00d, ch6.get("amount"));
    }

    @Test
    void dashboardSurvivesMissingShopSettleTimeAndReturnsBusinessDay() {
        Shop shopWithoutSettle = new Shop();
        shopWithoutSettle.setId(1);
        shopWithoutSettle.setSettle_time(null);
        when(shopService.getById(1)).thenReturn(shopWithoutSettle);
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());
        when(orderService.getTodayOrderCount(eq(1), any())).thenReturn(5L);

        Map<String, Object> dayPaid = new LinkedHashMap<>();
        dayPaid.put("business_revenue_net", 320.0);
        dayPaid.put("paid_order_count", 5L);
        when(orderService.aggregateOperationalDayPaidOrderMetrics(eq(1), any()))
                .thenReturn(dayPaid);
        when(memberRechargeService.list(any())).thenReturn(Collections.emptyList());

        R response = controller.dashboard(null, null, null, null, null, null, null, null, 30, null, null);

        assertNotNull(response);
        Map<?, ?> data = (Map<?, ?>) response.get("data");
        assertNotNull(data);
        Map<?, ?> businessDay = (Map<?, ?>) data.get("businessDay");
        assertNotNull(businessDay);
        assertEquals(320.0, businessDay.get("todayRevenue"));
        assertEquals(5L, businessDay.get("todayOrderCount"));
    }

    @Test
    void dashboardRechargeAmountCountsOnlyPrincipal() {
        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.emptyList());
        when(orderService.getTodayOrderCount(eq(1), any())).thenReturn(1L);

        Map<String, Object> dayPaid = new LinkedHashMap<>();
        dayPaid.put("business_revenue_net", 100.0);
        dayPaid.put("paid_order_count", 1L);
        when(orderService.aggregateOperationalDayPaidOrderMetrics(eq(1), any()))
                .thenReturn(dayPaid);

        MemberRecharge recharge1 = new MemberRecharge();
        recharge1.setShop_id(1);
        recharge1.setStatus("success");
        recharge1.setRecharge_amount(new BigDecimal("100.00")); // 实付本金
        recharge1.setGift_amount(new BigDecimal("20.00"));     // 赠送金额
        recharge1.setTotal_amount(new BigDecimal("120.00"));   // 入账总额

        MemberRecharge recharge2 = new MemberRecharge();
        recharge2.setShop_id(1);
        recharge2.setStatus("success");
        recharge2.setRecharge_amount(new BigDecimal("200.00")); // 实付本金
        recharge2.setGift_amount(new BigDecimal("50.00"));     // 赠送金额
        recharge2.setTotal_amount(new BigDecimal("250.00"));   // 入账总额

        when(memberRechargeService.list(any())).thenReturn(Arrays.asList(recharge1, recharge2));

        R response = controller.dashboard(null, null, null, null, null, null, null, null, 30, null, null);

        assertNotNull(response);
        Map<?, ?> data = (Map<?, ?>) response.get("data");
        assertNotNull(data);
        Map<?, ?> businessDay = (Map<?, ?>) data.get("businessDay");
        assertNotNull(businessDay);

        // 验证：今日充值金额只算实付本金 (100.00 + 200.00 = 300.00)
        assertEquals(300.00d, businessDay.get("todayMemberRechargeAmount"));
        assertEquals(300.00d, businessDay.get("todayMemberRechargePrincipal"));
        assertEquals(70.00d, businessDay.get("todayMemberRechargeGift"));
        assertEquals(370.00d, businessDay.get("todayMemberRechargeTotal"));
        assertEquals(2L, businessDay.get("todayMemberRechargeSuccessCount"));
    }
}
