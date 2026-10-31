package com.lanf.payment.channel.wechat;

import com.lanf.payment.config.ResolvedWechatMerchant;
import com.lanf.payment.service.PaymentMerchantConfigService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class WechatMerchantKeyStoreTest {
    @Test
    void preservesArbitraryMerchantKeyInsteadOfCollapsingToDefault() {
        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        ResolvedWechatMerchant cfg = new ResolvedWechatMerchant();
        cfg.merchantKey = "delivery"; cfg.legacyMerchantId = "1"; cfg.dbConfigId = 9L;
        cfg.dbCredentialVersion = 4; cfg.dbShopId = 7;
        when(configs.resolveWechat(7, "delivery")).thenReturn(cfg);

        WechatMerchantKeyStore store = new WechatMerchantKeyStore();
        ReflectionTestUtils.setField(store, "paymentMerchantConfigService", configs);
        ReflectionTestUtils.setField(store, "platformPublicKeyLoader", mock(WechatPlatformPublicKeyLoader.class));

        WechatMerchantKeyStore.ResolvedMerchant resolved = store.resolveForPay(7, "delivery", null);

        assertEquals("delivery", resolved.merchantKey);
        assertEquals(9L, resolved.dbConfigId);
        assertEquals(4, resolved.dbConfigVersion);
    }

    @Test
    void rejectsBoundCredentialOwnedByAnotherShop() {
        PaymentMerchantConfigService configs = mock(PaymentMerchantConfigService.class);
        ResolvedWechatMerchant cfg = new ResolvedWechatMerchant();
        cfg.merchantKey = "default"; cfg.legacyMerchantId = "1"; cfg.dbConfigId = 9L;
        cfg.dbCredentialVersion = 4; cfg.dbShopId = 8;
        when(configs.resolveWechatBound(9L, 4)).thenReturn(cfg);

        WechatMerchantKeyStore store = new WechatMerchantKeyStore();
        ReflectionTestUtils.setField(store, "paymentMerchantConfigService", configs);
        ReflectionTestUtils.setField(store, "platformPublicKeyLoader", mock(WechatPlatformPublicKeyLoader.class));

        assertNull(store.resolveBound(9L, 4, 7));
    }
}
