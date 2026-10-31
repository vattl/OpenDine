package com.lanf.payment.service;

import com.lanf.payment.config.PaymentCredentialCipher;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentMerchantConfigHistoryEntity;
import com.lanf.payment.mapper.PaymentMerchantConfigHistoryMapper;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.mock.web.MockMultipartFile;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;

import java.util.Collections;
import java.util.HashMap;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.times;

class PaymentMerchantConfigServiceTest {

    @TempDir
    Path tempDir;

    @Test
    void delete_shouldRetireMerchantWithoutDestroyingCredentials() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(2L);
        row.setShop_id(1);
        row.setChannel("wechat");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader keyLoader =
                mock(com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader.class);
        com.lanf.payment.channel.wechat.WechatMerchantKeyStore keyStore =
                mock(com.lanf.payment.channel.wechat.WechatMerchantKeyStore.class);
        when(mapper.selectById(2L)).thenReturn(row);
        when(mapper.updateById(any(PaymentMerchantConfigEntity.class))).thenReturn(1);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());

        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "merchantMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "platformPublicKeyLoader", keyLoader);
        ReflectionTestUtils.setField(service, "wechatMerchantKeyStore", keyStore);

        service.delete(2L, 1);

        verify(mapper, never()).deleteById(any(Long.class));
        verify(mapper).updateById(row);
        assertEquals("RETIRED", row.getStatus());
        assertEquals(0, row.getEnabled());
        verify(cache).putMerchants(eq(1), eq("wechat"), eq(Collections.emptyList()));
    }

    @Test
    void delete_shouldRejectMerchantFromAnotherShopWithoutDeleting() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(2L);
        row.setShop_id(2);
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectById(2L)).thenReturn(row);
        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "merchantMapper", mapper);

        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> service.delete(2L, 1));

        assertEquals("商户配置不存在", error.getMessage());
        verify(mapper, never()).deleteById(any(Long.class));
    }

    @Test
    void save_shouldRejectApiV3KeyThatIsNotExactly32Characters() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(1L);
        row.setShop_id(1);
        row.setChannel("wechat");
        row.setMerchant_key("default");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectById(1L)).thenReturn(row);
        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "merchantMapper", mapper);
        ReflectionTestUtils.setField(service, "credentialCipher", new PaymentCredentialCipher(""));

        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> service.save(1, 1L,
                        Collections.<String, Object>singletonMap("apiV3Key", "too-short")));

        assertEquals("apiV3Key 必须为 32 位", error.getMessage());
    }

    @Test
    void updateSnapshotsPreviousCredentialVersionBeforeIncrementing() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(3L); row.setShop_id(1); row.setChannel("wechat"); row.setMerchant_key("default");
        row.setEnabled(1); row.setStatus("ACTIVE"); row.setCredential_version(2); row.setMch_id("old-mch");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        PaymentMerchantConfigHistoryMapper history = mock(PaymentMerchantConfigHistoryMapper.class);
        when(mapper.selectById(3L)).thenReturn(row);
        when(mapper.updateById(row)).thenReturn(1);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "merchantHistoryMapper", history);
        HashMap<String, Object> body = new HashMap<>(); body.put("remark", "new");

        PaymentMerchantConfigEntity saved = service.save(1, 3L, body);

        assertEquals(3, saved.getCredential_version());
        org.mockito.ArgumentCaptor<PaymentMerchantConfigHistoryEntity> snapshot =
                org.mockito.ArgumentCaptor.forClass(PaymentMerchantConfigHistoryEntity.class);
        verify(history).insert(snapshot.capture());
        assertEquals(2, snapshot.getValue().getCredential_version());
        assertEquals("old-mch", snapshot.getValue().getMch_id());
    }

    @Test
    void strictShopIsolationDoesNotReadGlobalMerchantWithoutPolicy() {
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());
        PaymentMerchantPolicyService policy = mock(PaymentMerchantPolicyService.class);
        when(policy.allowsGlobalFallback(7)).thenReturn(false);
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "merchantPolicyService", policy);

        assertEquals(null, service.findMergedRow(7, "wechat", "default"));

        verify(mapper, times(1)).selectList(any());
    }

    @Test
    void runtimeResolutionDoesNotTrustStaleEnabledMerchantCache() {
        PaymentMerchantConfigEntity stale = new PaymentMerchantConfigEntity();
        stale.setId(9L); stale.setShop_id(7); stale.setChannel("wechat");
        stale.setMerchant_key("default"); stale.setEnabled(1); stale.setStatus("ACTIVE");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());
        PaymentConfigCache cache = mock(PaymentConfigCache.class);
        when(cache.getMerchants(7, "wechat")).thenReturn(Collections.singletonList(stale));
        PaymentMerchantPolicyService policy = mock(PaymentMerchantPolicyService.class);
        when(policy.allowsGlobalFallback(7)).thenReturn(false);
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "configCache", cache);
        ReflectionTestUtils.setField(service, "merchantPolicyService", policy);

        assertEquals(null, service.findMergedRow(7, "wechat", "default"));
    }

    @Test
    void notifyCandidateLookupFiltersCurrentAndHistoryByPlatformSerial() {
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        PaymentMerchantConfigHistoryMapper history = mock(PaymentMerchantConfigHistoryMapper.class);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());
        when(history.selectList(any())).thenReturn(Collections.emptyList());
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "merchantHistoryMapper", history);

        service.findNotifyCryptoMatches("PUB_KEY_ID_123");

        org.mockito.ArgumentCaptor<QueryWrapper<PaymentMerchantConfigEntity>> currentQuery =
                org.mockito.ArgumentCaptor.forClass(QueryWrapper.class);
        org.mockito.ArgumentCaptor<QueryWrapper<PaymentMerchantConfigHistoryEntity>> historyQuery =
                org.mockito.ArgumentCaptor.forClass(QueryWrapper.class);
        verify(mapper).selectList(currentQuery.capture());
        verify(history).selectList(historyQuery.capture());
        assertTrue(currentQuery.getValue().getSqlSegment().contains("platform_pub_key_id"));
        assertTrue(historyQuery.getValue().getSqlSegment().contains("platform_pub_key_id"));
    }

    @Test
    void explicitPolicyAllowsGlobalMerchantFallback() {
        PaymentMerchantConfigEntity global = new PaymentMerchantConfigEntity();
        global.setId(8L); global.setShop_id(0); global.setChannel("wechat");
        global.setMerchant_key("default"); global.setEnabled(1); global.setStatus("ACTIVE");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList(), Collections.singletonList(global));
        PaymentMerchantPolicyService policy = mock(PaymentMerchantPolicyService.class);
        when(policy.allowsGlobalFallback(7)).thenReturn(true);
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "merchantPolicyService", policy);

        assertEquals(8L, service.findMergedRow(7, "wechat", "default").getId());
        verify(mapper, times(2)).selectList(any());
    }

    @Test
    void restoreReactivatesRetiredMerchantWithoutRecreatingRow() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(4L); row.setShop_id(1); row.setChannel("wechat");
        row.setStatus("RETIRED"); row.setEnabled(0);
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        when(mapper.selectById(4L)).thenReturn(row);
        when(mapper.updateById(row)).thenReturn(1);
        when(mapper.selectList(any())).thenReturn(Collections.emptyList());
        PaymentMerchantConfigService service = configuredService(mapper);

        service.restore(4L, 1);

        assertEquals("ACTIVE", row.getStatus());
        assertEquals(1, row.getEnabled());
        verify(mapper, never()).insert(any(PaymentMerchantConfigEntity.class));
    }

    @Test
    void boundResolverReadsHistoricalCredentialVersionAfterRotation() {
        PaymentMerchantConfigEntity current = new PaymentMerchantConfigEntity();
        current.setId(5L); current.setShop_id(1); current.setChannel("wechat");
        current.setMerchant_key("default"); current.setCredential_version(2);
        PaymentMerchantConfigHistoryEntity old = new PaymentMerchantConfigHistoryEntity();
        old.setMerchant_config_id(5L); old.setShop_id(1); old.setChannel("wechat");
        old.setMerchant_key("default"); old.setCredential_version(1); old.setMch_id("old-mch");
        PaymentMerchantConfigMapper mapper = mock(PaymentMerchantConfigMapper.class);
        PaymentMerchantConfigHistoryMapper history = mock(PaymentMerchantConfigHistoryMapper.class);
        when(mapper.selectById(5L)).thenReturn(current);
        when(history.selectOne(any())).thenReturn(old);
        PaymentMerchantConfigService service = configuredService(mapper);
        ReflectionTestUtils.setField(service, "merchantHistoryMapper", history);
        ReflectionTestUtils.setField(service, "credentialCipher", new PaymentCredentialCipher("test-master"));

        assertEquals("old-mch", service.resolveWechatBound(5L, 1).mchId);
        assertEquals(1, service.resolveWechatBound(5L, 1).dbCredentialVersion);
    }

    @Test
    void storePlatformPublicKeyPemWritesValidatedShopScopedFile() throws Exception {
        String pem = publicKeyPem();
        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "privateKeyUploadDir", tempDir.toString());
        ReflectionTestUtils.setField(service, "platformPublicKeyLoader", new com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader());

        PaymentMerchantConfigService.PlatformPublicMaterial stored = service.storePlatformPublicKeyPem(
                7, "default", new MockMultipartFile("file", "wechatpay_pub.pem",
                        "application/x-pem-file", pem.getBytes(StandardCharsets.UTF_8)));

        assertEquals("PUBLIC_KEY", stored.materialType);
        Path storedPath = java.nio.file.Paths.get(stored.platformPubKeyRef);
        assertTrue(storedPath.startsWith(tempDir.resolve("shop-7")));
        assertTrue(Files.readAllBytes(storedPath).length > 0);
    }

    @Test
    void storePlatformPublicKeyPemRejectsPrivateKey() {
        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "privateKeyUploadDir", tempDir.toString());
        ReflectionTestUtils.setField(service, "platformPublicKeyLoader", new com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader());
        MockMultipartFile file = new MockMultipartFile("file", "private.pem", "application/x-pem-file",
                "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----".getBytes(StandardCharsets.UTF_8));

        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> service.storePlatformPublicKeyPem(7, "default", file));

        assertEquals("请上传微信支付平台公钥或平台证书，不要上传私钥文件", error.getMessage());
    }

    private static String publicKeyPem() throws Exception {
        byte[] encoded = KeyPairGenerator.getInstance("RSA").generateKeyPair().getPublic().getEncoded();
        return "-----BEGIN PUBLIC KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(encoded)
                + "\n-----END PUBLIC KEY-----\n";
    }

    private static PaymentMerchantConfigService configuredService(PaymentMerchantConfigMapper mapper) {
        PaymentMerchantConfigService service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "merchantMapper", mapper);
        ReflectionTestUtils.setField(service, "configCache", mock(PaymentConfigCache.class));
        ReflectionTestUtils.setField(service, "platformPublicKeyLoader",
                mock(com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader.class));
        ReflectionTestUtils.setField(service, "wechatMerchantKeyStore",
                mock(com.lanf.payment.channel.wechat.WechatMerchantKeyStore.class));
        return service;
    }
}
