package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentCapabilityEntity;
import com.lanf.payment.mapper.PaymentCapabilityMapper;
import com.lanf.payment.support.PaymentChannelCatalog;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentCapabilityServiceClientTest {

    @SuppressWarnings("unchecked")
    @Test
    void toPublicMap_shouldRoundTripStoredClientSwitchesAndOmitDeprecatedPaymentMethods() {
        PaymentCapabilityEntity row = baseRow();
        row.setOnline_pay_enabled(0);
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(0);
        row.setCashier_alipay_enabled(0);
        row.setCashier_balance_enabled(1);
        row.setCashier_combined_enabled(1);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(0);
        row.setMini_program_balance_enabled(1);
        row.setOffline_collect_enabled(1);
        row.setOffline_collect_channels("wechat,alipay");
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(1);

        Map<String, Object> out = serviceWithRow(row).toPublicMap(1);
        Map<String, Object> clients = (Map<String, Object>) out.get("clients");
        Map<String, Object> cashier = (Map<String, Object>) clients.get("cashier");
        Map<String, Object> mini = (Map<String, Object>) clients.get("miniProgram");
        Map<String, Object> cashierChannels = (Map<String, Object>) cashier.get("channels");
        Map<String, Object> miniChannels = (Map<String, Object>) mini.get("channels");
        assertTrue((Boolean) cashier.get("enabled"));
        assertTrue((Boolean) mini.get("enabled"));
        // effectiveEnabled 已随 D017 移出 C 端响应（B 端 GET /admin/payment/capabilities 保留）
        assertFalse((Boolean) cashierChannels.get("wechat"));
        assertFalse((Boolean) cashierChannels.get("alipay"));
        assertTrue((Boolean) cashierChannels.get("balance"));
        assertFalse((Boolean) miniChannels.get("wechat"));
        assertTrue((Boolean) miniChannels.get("balance"));
        assertFalse(out.containsKey("paymentMethods"));
        assertFalse(cashier.containsKey("paymentMethods"));
        assertFalse(mini.containsKey("paymentMethods"));
    }

    @Test
    void cashierChannelSwitches_shouldRemainIndependentFromLegacyOnlineMasterSwitch() {
        PaymentCapabilityEntity row = baseRow();
        row.setOnline_pay_enabled(0);
        row.setCashier_pay_enabled(1);
        row.setCashier_alipay_enabled(1);
        row.setCashier_balance_enabled(1);

        PaymentCapabilityService service = serviceWithRow(row);

        assertTrue(service.isCashierPaymentMethodEnabled(1, "online_alipay"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "online_balance"));
    }

    @Test
    void cashierConfiguredChannelSwitch_shouldDriveOfflineQrcodeAndCheckoutAvailability() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(1);
        row.setCashier_alipay_enabled(0);
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(0);
        row.setOffline_collect_enabled(0);
        row.setOffline_collect_channels("");

        PaymentCapabilityService service = serviceWithRow(row, false);

        assertTrue(service.isCashierConfiguredChannelEnabled(1, "wechat"));
        assertFalse(service.isCashierConfiguredChannelEnabled(1, "alipay"));
        assertTrue(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.OFFLINE_WECHAT_QR));
        assertFalse(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.OFFLINE_ALIPAY_QR));

        row.setCashier_pay_enabled(0);
        assertFalse(service.isCashierConfiguredChannelEnabled(1, "wechat"));
        assertFalse(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.OFFLINE_WECHAT_QR));
    }

    @Test
    void personalQrSwitchesShouldRemainIndependentFromOnlineMerchantSwitches() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(0);
        row.setCashier_alipay_enabled(1);
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(0);

        PaymentCapabilityService service = serviceWithRow(row);

        assertFalse(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.ONLINE_WECHAT));
        assertTrue(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.OFFLINE_WECHAT_QR));
        assertTrue(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.ONLINE_ALIPAY));
        assertFalse(service.isCashierPaymentMethodEnabled(
                1, PaymentChannelCatalog.OFFLINE_ALIPAY_QR));
    }

    @Test
    void miniProgramChannelSwitches_shouldRemainIndependentFromLegacyOnlineMasterSwitch() {
        PaymentCapabilityEntity row = baseRow();
        row.setOnline_pay_enabled(0);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(1);
        row.setMini_program_balance_enabled(1);

        PaymentCapabilityService service = serviceWithRow(row);

        assertTrue(service.isMiniProgramPayEnabled(1));
        assertTrue(service.isWechatEnabled(1));
        assertTrue(service.isBalanceEnabled(1));
    }

    @SuppressWarnings("unchecked")
    @Test
    void toPublicMap_shouldResolveCashierAndMiniProgramIndependently() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(1);
        row.setCashier_alipay_enabled(0);
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(0);
        row.setCashier_balance_enabled(1);
        row.setCashier_combined_enabled(1);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(0);
        row.setMini_program_balance_enabled(1);
        row.setOffline_collect_channels("wechat");

        PaymentCapabilityService service = serviceWithRow(row);
        Map<String, Object> out = service.toPublicMap(1);
        Map<String, Object> clients = (Map<String, Object>) out.get("clients");
        Map<String, Object> cashier = (Map<String, Object>) clients.get("cashier");
        Map<String, Object> mini = (Map<String, Object>) clients.get("miniProgram");
        Map<String, Object> cashierChannels = (Map<String, Object>) cashier.get("channels");
        Map<String, Object> miniChannels = (Map<String, Object>) mini.get("channels");

        assertTrue((Boolean) cashier.get("enabled"));
        assertTrue((Boolean) cashierChannels.get("wechat"));
        assertFalse((Boolean) cashierChannels.get("alipay"));
        assertTrue((Boolean) cashierChannels.get("combined"));
        assertFalse((Boolean) miniChannels.get("wechat"));
        assertTrue((Boolean) miniChannels.get("balance"));
        // configuredChannels 已随 D014 精简移除（与 channels 同值别名）
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cash"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "offline_wechat_qr"));
        assertFalse(service.isCashierPaymentMethodEnabled(1, "offline_alipay_qr"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "online_wechat"));
        assertFalse(service.isCashierPaymentMethodEnabled(1, "online_alipay"));
        assertFalse(service.isCashierPaymentMethodEnabled(1, "会员余额"));
        assertFalse(service.isCashierPaymentMethodEnabled(1, "custom_unknown_code"));
        assertFalse(service.isWechatEnabled(1));
        assertTrue(service.isBalanceEnabled(1));
    }

    @SuppressWarnings("unchecked")
    @Test
    void toPublicMap_shouldDisableCombinedWhenCashIsTheOnlyEnabledCashierBaseMethod() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(0);
        row.setCashier_alipay_enabled(0);
        row.setCashier_balance_enabled(0);
        row.setCashier_combined_enabled(1);
        row.setOffline_collect_enabled(0);

        PaymentCapabilityService service = serviceWithRow(row);
        Map<String, Object> clients =
                (Map<String, Object>) service.toPublicMap(1).get("clients");
        Map<String, Object> cashier = (Map<String, Object>) clients.get("cashier");
        Map<String, Object> channels = (Map<String, Object>) cashier.get("channels");
        Map<String, Object> states = (Map<String, Object>) cashier.get("channelStates");
        Map<String, Object> combinedState = (Map<String, Object>) states.get("combined");

        assertTrue((Boolean) cashier.get("enabled"));
        assertTrue((Boolean) channels.get("combined"));
        assertFalse((Boolean) combinedState.get("available"));
        assertFalse(service.isCashierPaymentMethodEnabled(1, "online_combined"));
    }

    @Test
    void upsert_shouldAcceptNestedClientChannelSettings() {
        PaymentCapabilityEntity row = baseRow();
        PaymentCapabilityMapper mapper = mock(PaymentCapabilityMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        PaymentMerchantConfigService merchants = mock(PaymentMerchantConfigService.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        when(mapper.selectOne(any(Wrapper.class))).thenReturn(row);
        when(merchants.hasWechatPayReady(1)).thenReturn(true);
        when(merchants.hasWechatMiniProgramPayReady(1)).thenReturn(true);
        when(merchants.getWechatMiniProgramMissingFields(1)).thenReturn(Collections.emptyList());
        PaymentCapabilityService service = new PaymentCapabilityService();
        ReflectionTestUtils.setField(service, "capabilityMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchants);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);

        Map<String, Object> cashierStates = new LinkedHashMap<>();
        cashierStates.put("wechat", Collections.singletonMap("enabled", true));
        cashierStates.put("alipay", Collections.singletonMap("enabled", false));
        cashierStates.put("balance", Collections.singletonMap("enabled", true));
        cashierStates.put("combined", Collections.singletonMap("enabled", true));
        Map<String, Object> cashier = new LinkedHashMap<>();
        cashier.put("enabled", true);
        cashier.put("channelStates", cashierStates);
        Map<String, Object> miniStates = new LinkedHashMap<>();
        miniStates.put("wechat", Collections.singletonMap("enabled", false));
        miniStates.put("balance", Collections.singletonMap("enabled", true));
        Map<String, Object> mini = new LinkedHashMap<>();
        mini.put("enabled", true);
        mini.put("channelStates", miniStates);
        Map<String, Object> clients = new LinkedHashMap<>();
        clients.put("cashier", cashier);
        clients.put("miniProgram", mini);
        Map<String, Object> body = Collections.<String, Object>singletonMap("clients", clients);

        service.upsert(1, body);

        assertEquals(1, row.getCashier_pay_enabled());
        assertEquals(1, row.getCashier_wechat_enabled());
        assertEquals(0, row.getCashier_alipay_enabled());
        assertEquals(1, row.getCashier_balance_enabled());
        assertEquals(1, row.getCashier_combined_enabled());
        assertEquals(1, row.getMini_program_pay_enabled());
        assertEquals(0, row.getMini_program_wechat_enabled());
        assertEquals(1, row.getMini_program_balance_enabled());
        verify(mapper).updateById(row);
    }

    @Test
    void upsert_legacyMiniProgramFields_shouldNotModifyCashierSwitches() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(1);
        row.setCashier_balance_enabled(1);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(1);
        row.setMini_program_balance_enabled(1);
        PaymentCapabilityService service = serviceForUpsert(row, true, true);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("onlinePayEnabled", false);
        body.put("wechatEnabled", false);
        body.put("balanceEnabled", false);

        service.upsert(1, body);

        // D017：legacy 平铺键（onlinePayEnabled/wechatEnabled/balanceEnabled）完全忽略，任何开关不受影响
        assertEquals(1, row.getCashier_pay_enabled());
        assertEquals(1, row.getCashier_wechat_enabled());
        assertEquals(1, row.getCashier_balance_enabled());
        assertEquals(1, row.getMini_program_pay_enabled());
        assertEquals(1, row.getMini_program_wechat_enabled());
        assertEquals(1, row.getMini_program_balance_enabled());
    }

    @Test
    void upsert_nestedClientSettings_shouldOverrideLegacyCompatibilityFields() {
        PaymentCapabilityEntity row = baseRow();
        PaymentCapabilityService service = serviceForUpsert(row, true, true);
        Map<String, Object> miniStates = new LinkedHashMap<>();
        miniStates.put("wechat", Collections.singletonMap("enabled", true));
        miniStates.put("balance", Collections.singletonMap("enabled", true));
        Map<String, Object> mini = new LinkedHashMap<>();
        mini.put("enabled", true);
        mini.put("channelStates", miniStates);
        Map<String, Object> clients = new LinkedHashMap<>();
        clients.put("miniProgram", mini);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("clients", clients);

        service.upsert(1, body);

        assertEquals(1, row.getMini_program_pay_enabled());
        assertEquals(1, row.getMini_program_wechat_enabled());
        assertEquals(1, row.getMini_program_balance_enabled());
    }

    @Test
    void upsert_nestedDisabledWechat_shouldOverrideLegacyEnabledFieldsBeforeReadinessValidation() {
        PaymentCapabilityEntity row = baseRow();
        PaymentCapabilityService service = serviceForUpsert(row, false, false);
        Map<String, Object> cashierStates = new LinkedHashMap<>();
        cashierStates.put("wechat", Collections.singletonMap("enabled", false));
        Map<String, Object> cashier = new LinkedHashMap<>();
        cashier.put("channelStates", cashierStates);
        Map<String, Object> miniStates = new LinkedHashMap<>();
        miniStates.put("wechat", Collections.singletonMap("enabled", false));
        Map<String, Object> mini = new LinkedHashMap<>();
        mini.put("channelStates", miniStates);
        Map<String, Object> clients = new LinkedHashMap<>();
        clients.put("cashier", cashier);
        clients.put("miniProgram", mini);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("clients", clients);

        service.upsert(1, body);

        assertEquals(0, row.getCashier_wechat_enabled());
        assertEquals(0, row.getMini_program_wechat_enabled());
    }

    @Test
    void upsert_shouldRejectMiniProgramWechatWhenMerchantCredentialsAreIncomplete() {
        PaymentCapabilityEntity row = baseRow();
        PaymentCapabilityMapper mapper = mock(PaymentCapabilityMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        PaymentMerchantConfigService merchants = mock(PaymentMerchantConfigService.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        when(merchants.hasWechatMiniProgramPayReady(1)).thenReturn(false);
        when(merchants.getWechatMiniProgramMissingFields(1))
                .thenReturn(Arrays.asList("serialNo", "privateKeyRef"));
        PaymentCapabilityService service = new PaymentCapabilityService();
        ReflectionTestUtils.setField(service, "capabilityMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchants);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);

        Map<String, Object> miniStates = new LinkedHashMap<>();
        miniStates.put("wechat", Collections.singletonMap("enabled", true));
        Map<String, Object> mini = new LinkedHashMap<>();
        mini.put("channelStates", miniStates);
        Map<String, Object> clients = new LinkedHashMap<>();
        clients.put("miniProgram", mini);

        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> service.upsert(1, Collections.<String, Object>singletonMap("clients", clients)));

        assertTrue(error.getMessage().contains("serialNo"));
        assertTrue(error.getMessage().contains("privateKeyRef"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void merchantReadiness_shouldAffectEffectiveStateWithoutRewritingConfiguredSwitches() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_wechat_enabled(1);
        row.setMini_program_wechat_enabled(1);
        PaymentCapabilityMapper mapper = mock(PaymentCapabilityMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        PaymentMerchantConfigService merchants = mock(PaymentMerchantConfigService.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        when(mapper.selectOne(any(Wrapper.class))).thenReturn(row);
        when(merchants.hasWechatPayReady(1)).thenReturn(true);
        when(merchants.hasWechatMiniProgramPayReady(1)).thenReturn(false);
        PaymentCapabilityService service = new PaymentCapabilityService();
        ReflectionTestUtils.setField(service, "capabilityMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchants);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);

        Map<String, Object> clients = (Map<String, Object>) service.toPublicMap(1).get("clients");
        Map<String, Object> cashier = (Map<String, Object>) clients.get("cashier");
        Map<String, Object> mini = (Map<String, Object>) clients.get("miniProgram");
        Map<String, Object> cashierStates = (Map<String, Object>) cashier.get("channelStates");
        Map<String, Object> miniStates = (Map<String, Object>) mini.get("channelStates");
        Map<String, Object> cashierWechatState = (Map<String, Object>) cashierStates.get("wechat");
        Map<String, Object> miniWechatState = (Map<String, Object>) miniStates.get("wechat");

        assertEquals(1, row.getCashier_wechat_enabled());
        assertEquals(1, row.getMini_program_wechat_enabled());
        assertTrue((Boolean) cashierWechatState.get("available"));
        assertFalse((Boolean) miniWechatState.get("available"));
        verify(mapper, never()).updateById(row);
    }

    @Test
    void isCashierPaymentMethodEnabled_shouldMatchDirectResponseFieldNamesAndPaths() {
        PaymentCapabilityEntity row = baseRow();
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(1);
        row.setCashier_alipay_enabled(1);
        row.setCashier_balance_enabled(1);
        row.setCashier_combined_enabled(1);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(1);
        row.setMini_program_balance_enabled(1);
        row.setOffline_collect_enabled(1);
        row.setOffline_collect_channels("wechat,alipay");
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(1);

        PaymentCapabilityService service = serviceWithRow(row);

        // 1. Direct entity / response field names (camelCase & snake_case)
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier_wechat_enabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashierWechatEnabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier_alipay_enabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashierAlipayEnabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier_balance_enabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashierBalanceEnabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier_combined_enabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashierCombinedEnabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "offline_collect_enabled"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "offlineCollectEnabled"));

        // 2. Dot paths from response
        assertTrue(service.isCashierPaymentMethodEnabled(1, "clients.cashier.channels.wechat"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "clients.cashier.effectiveChannels.wechat"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier.wechat"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier.alipay"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier.balance"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "cashier.combined"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "offlineCollect.wechat"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "offlineCollect.alipay"));

        // 3. Mini program & master capabilities
        assertTrue(service.isCapabilityEnabled(1, "clients.miniProgram.channels.wechat"));
        assertTrue(service.isCapabilityEnabled(1, "miniProgramWechatEnabled"));
        assertTrue(service.isCapabilityEnabled(1, "mini_program_balance_enabled"));
        assertTrue(service.isCapabilityEnabled(1, "clients.cashier.enabled"));
        assertTrue(service.isCapabilityEnabled(1, "cashierPayEnabled"));

        // 4. Standard names & aliases
        assertTrue(service.isCashierPaymentMethodEnabled(1, "微信支付"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "支付宝支付"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "微信收款码"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "微信收款码自动"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "支付宝收款码"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "支付宝收款码自动"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "现金"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "余额支付"));
        assertTrue(service.isCashierPaymentMethodEnabled(1, "组合支付"));
    }

    private static PaymentCapabilityService serviceForUpsert(PaymentCapabilityEntity row,
                                                               boolean cashierWechatReady,
                                                               boolean miniProgramWechatReady) {
        PaymentCapabilityMapper mapper = mock(PaymentCapabilityMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        PaymentMerchantConfigService merchants = mock(PaymentMerchantConfigService.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        when(mapper.selectOne(any(Wrapper.class))).thenReturn(row);
        when(merchants.hasWechatPayReady(1)).thenReturn(cashierWechatReady);
        when(merchants.hasWechatMiniProgramPayReady(1)).thenReturn(miniProgramWechatReady);
        when(merchants.getWechatMiniProgramMissingFields(1)).thenReturn(Collections.emptyList());
        PaymentCapabilityService service = new PaymentCapabilityService();
        ReflectionTestUtils.setField(service, "capabilityMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchants);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);
        return service;
    }

    private static PaymentCapabilityService serviceWithRow(PaymentCapabilityEntity row) {
        return serviceWithRow(row, true);
    }

    private static PaymentCapabilityService serviceWithRow(PaymentCapabilityEntity row,
                                                             boolean cashierWechatReady) {
        PaymentCapabilityMapper mapper = mock(PaymentCapabilityMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        PaymentMerchantConfigService merchants = mock(PaymentMerchantConfigService.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        when(cache.getCapabilityRow(1)).thenReturn(row);
        when(merchants.hasWechatPayReady(1)).thenReturn(cashierWechatReady);
        when(merchants.hasWechatMiniProgramPayReady(1)).thenReturn(true);
        when(merchants.getWechatMiniProgramMissingFields(1)).thenReturn(Collections.emptyList());
        when(ninefold.toPublicMap(1)).thenReturn(Collections.<String, Object>emptyMap());
        PaymentCapabilityService service = new PaymentCapabilityService();
        ReflectionTestUtils.setField(service, "capabilityMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantConfigService", merchants);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);
        return service;
    }

    private static PaymentCapabilityEntity baseRow() {
        PaymentCapabilityEntity row = new PaymentCapabilityEntity();
        row.setId(1L);
        row.setShop_id(1);
        row.setOnline_pay_enabled(1);
        row.setWechat_enabled(1);
        row.setAlipay_enabled(1);
        row.setBalance_enabled(1);
        row.setCombined_enabled(1);
        row.setOffline_collect_enabled(1);
        row.setOffline_collect_channels("wechat,alipay");
        row.setCashier_wechat_qr_enabled(1);
        row.setCashier_alipay_qr_enabled(1);
        row.setDisabled_message("已关闭");
        return row;
    }
}
