package com.lanf.payment.notify;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.User;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WechatMemberRechargeNotifyHandlerTest {

    private final IMemberRechargeService memberRechargeService = mock(IMemberRechargeService.class);
    private final IUserService userService = mock(IUserService.class);
    private final WechatMerchantKeyStore merchantKeyStore = mock(WechatMerchantKeyStore.class);
    private WechatMemberRechargeNotifyHandler handler;

    @BeforeEach
    void setUp() {
        handler = new WechatMemberRechargeNotifyHandler();
        ReflectionTestUtils.setField(handler, "paymentNotifyState", new PaymentNotifyState());
        ReflectionTestUtils.setField(handler, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(handler, "userService", userService);
        ReflectionTestUtils.setField(handler, "merchantKeyStore", merchantKeyStore);
    }

    private WechatMerchantKeyStore.ResolvedMerchant sampleResolved(int shopId, String mchId, String appId) {
        WechatMerchantKeyStore.ResolvedMerchant r = new WechatMerchantKeyStore.ResolvedMerchant();
        r.dbShopId = shopId;
        r.mchId = mchId;
        r.appId = appId;
        r.merchantKey = "default";
        return r;
    }

    private MemberRecharge sampleRecharge(int shopId, double rechargeAmount, double giftAmount) {
        MemberRecharge r = new MemberRecharge();
        r.setId(101L);
        r.setOrder_no("RCH20261021001");
        r.setShop_id(shopId);
        r.setOpenid("wx_user_openid_1");
        r.setUser_id(12);
        r.setChannel("wechat");
        r.setStatus("pending");
        r.setRecharge_amount(BigDecimal.valueOf(rechargeAmount));
        r.setGift_amount(BigDecimal.valueOf(giftAmount));
        r.setTotal_amount(BigDecimal.valueOf(rechargeAmount + giftAmount));
        return r;
    }

    private Map<String, Object> samplePaymentResult(int totalFen, String mchId, String appId) {
        Map<String, Object> result = new HashMap<>();
        result.put("trade_state", "SUCCESS");
        result.put("transaction_id", "4200002131202610211234567890");
        result.put("success_time", "2026-10-21T09:00:00+08:00");
        result.put("mchid", mchId);
        result.put("appid", appId);
        Map<String, Object> amount = new HashMap<>();
        amount.put("total", totalFen);
        result.put("amount", amount);
        return result;
    }

    @Test
    void handlesSuccessfulRechargeNotification() throws Exception {
        MemberRecharge recharge = sampleRecharge(7, 100.0, 20.0);
        when(memberRechargeService.getOne(any(QueryWrapper.class))).thenReturn(recharge);
        when(merchantKeyStore.resolveForPay(7, "1", null))
                .thenReturn(sampleResolved(7, "1900000001", "wx-app-1"));

        User user = new User();
        user.setId(12);
        user.setOpenid("wx_user_openid_1");
        when(userService.getUserByOpenid("wx_user_openid_1")).thenReturn(user);
        when(userService.addBalanceAndGift(eq(12), any(BigDecimal.class), any(BigDecimal.class))).thenReturn(true);

        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);

        handler.handle(pw, "NOTIFY_001", "RCH20261021001", "OUT_TRADE_001",
                samplePaymentResult(10000, "1900000001", "wx-app-1"));

        assertTrue(sw.toString().contains("\"code\":\"SUCCESS\""));
        verify(userService).addBalanceAndGift(eq(12), any(BigDecimal.class), any(BigDecimal.class));
        verify(memberRechargeService).markSuccessWechat(eq("RCH20261021001"), eq("4200002131202610211234567890"), any());
    }

    @Test
    void rejectsUnderpaidAmountAttemptingToClaimGift() throws Exception {
        MemberRecharge recharge = sampleRecharge(7, 100.0, 20.0);
        when(memberRechargeService.getOne(any(QueryWrapper.class))).thenReturn(recharge);
        when(merchantKeyStore.resolveForPay(7, "1", null))
                .thenReturn(sampleResolved(7, "1900000001", "wx-app-1"));

        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);

        handler.handle(pw, "NOTIFY_002", "RCH20261021001", "OUT_TRADE_001",
                samplePaymentResult(1, "1900000001", "wx-app-1"));

        assertTrue(sw.toString().contains("\"code\":\"FAIL\""));
        assertTrue(sw.toString().contains("金额不匹配"));
        verify(userService, never()).addBalanceAndGift(anyInt(), any(), any());
        verify(memberRechargeService, never()).markSuccessWechat(any(), any(), any());
    }

    @Test
    void rejectsMchIdMismatch() throws Exception {
        MemberRecharge recharge = sampleRecharge(7, 100.0, 20.0);
        when(memberRechargeService.getOne(any(QueryWrapper.class))).thenReturn(recharge);
        when(merchantKeyStore.resolveForPay(7, "1", null))
                .thenReturn(sampleResolved(7, "1900000001", "wx-app-1"));

        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);

        handler.handle(pw, "NOTIFY_003", "RCH20261021001", "OUT_TRADE_001",
                samplePaymentResult(10000, "1900000999", "wx-app-1"));

        assertTrue(sw.toString().contains("\"code\":\"FAIL\""));
        assertTrue(sw.toString().contains("商户号不匹配"));
        verify(userService, never()).addBalanceAndGift(anyInt(), any(), any());
    }

    @Test
    void rejectsAppIdMismatch() throws Exception {
        MemberRecharge recharge = sampleRecharge(7, 100.0, 20.0);
        when(memberRechargeService.getOne(any(QueryWrapper.class))).thenReturn(recharge);
        when(merchantKeyStore.resolveForPay(7, "1", null))
                .thenReturn(sampleResolved(7, "1900000001", "wx-app-1"));

        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);

        handler.handle(pw, "NOTIFY_004", "RCH20261021001", "OUT_TRADE_001",
                samplePaymentResult(10000, "1900000001", "wx-other-appid"));

        assertTrue(sw.toString().contains("\"code\":\"FAIL\""));
        assertTrue(sw.toString().contains("AppID不匹配"));
        verify(userService, never()).addBalanceAndGift(anyInt(), any(), any());
    }

    @Test
    void rejectsShopMismatch() throws Exception {
        MemberRecharge recharge = sampleRecharge(7, 100.0, 20.0);
        when(memberRechargeService.getOne(any(QueryWrapper.class))).thenReturn(recharge);
        when(merchantKeyStore.resolveForPay(7, "1", null))
                .thenReturn(sampleResolved(9, "1900000001", "wx-app-1"));

        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);

        handler.handle(pw, "NOTIFY_005", "RCH20261021001", "OUT_TRADE_001",
                samplePaymentResult(10000, "1900000001", "wx-app-1"));

        assertTrue(sw.toString().contains("\"code\":\"FAIL\""));
        assertTrue(sw.toString().contains("商户不属于当前门店"));
        verify(userService, never()).addBalanceAndGift(anyInt(), any(), any());
    }
}
