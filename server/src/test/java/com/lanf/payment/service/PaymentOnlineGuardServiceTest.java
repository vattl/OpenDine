package com.lanf.payment.service;

import com.lanf.entity.R;
import com.lanf.payment.PaymentErrorCodes;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PaymentOnlineGuardServiceTest {

    @Test
    void cashierWechatUsesCashierSwitchInsteadOfMiniProgramSwitch() {
        PaymentCapabilityService capabilityService = mock(PaymentCapabilityService.class);
        PaymentCapabilityService.ResolvedCapability capability = new PaymentCapabilityService.ResolvedCapability();
        capability.cashierPayEnabled = true;
        capability.cashierWechatEnabledConfigured = true;
        capability.wechatMerchantReady = true;
        capability.miniProgramPayEnabled = false;
        when(capabilityService.resolve(1)).thenReturn(capability);
        PaymentOnlineGuardService guard = new PaymentOnlineGuardService();
        ReflectionTestUtils.setField(guard, "capabilityService", capabilityService);

        assertEquals(null, guard.checkCashierWechatPay(1));
    }

    @Test
    void checkWechatPay_shouldRejectConfiguredChannelWhenMerchantCredentialsAreIncomplete() {
        PaymentCapabilityService capabilityService = mock(PaymentCapabilityService.class);
        PaymentCapabilityService.ResolvedCapability capability =
                new PaymentCapabilityService.ResolvedCapability();
        capability.miniProgramWechatEnabledConfigured = true;
        capability.miniProgramWechatMerchantReady = false;
        capability.miniProgramWechatMissingFields = Arrays.asList("apiV3Key", "privateKeyRef");
        when(capabilityService.isMiniProgramPayEnabled(1)).thenReturn(true);
        when(capabilityService.resolve(1)).thenReturn(capability);
        PaymentOnlineGuardService guard = new PaymentOnlineGuardService();
        ReflectionTestUtils.setField(guard, "capabilityService", capabilityService);

        R result = guard.checkWechatPay(1);

        assertEquals(PaymentErrorCodes.MERCHANT_NOT_CONFIGURED, result.get("code"));
        assertTrue(result.get("msg").toString().contains("apiV3Key"));
        assertTrue(result.get("msg").toString().contains("privateKeyRef"));
    }
}
