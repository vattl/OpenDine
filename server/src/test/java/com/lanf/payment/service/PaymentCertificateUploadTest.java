package com.lanf.payment.service;

import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.config.PaymentCredentialCipher;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentMerchantConfigHistoryEntity;
import com.lanf.payment.mapper.PaymentMerchantConfigHistoryMapper;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.util.Base64;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentCertificateUploadTest {

    @TempDir
    Path tempDir;

    private PaymentMerchantConfigService service;
    private PaymentMerchantConfigMapper merchantMapper;
    private PaymentMerchantConfigHistoryMapper historyMapper;
    private PaymentConfigCache configCache;

    @BeforeEach
    void setUp() {
        merchantMapper = mock(PaymentMerchantConfigMapper.class);
        historyMapper = mock(PaymentMerchantConfigHistoryMapper.class);
        configCache = mock(PaymentConfigCache.class);

        service = new PaymentMerchantConfigService();
        ReflectionTestUtils.setField(service, "merchantMapper", merchantMapper);
        ReflectionTestUtils.setField(service, "merchantHistoryMapper", historyMapper);
        ReflectionTestUtils.setField(service, "configCache", configCache);
        ReflectionTestUtils.setField(service, "credentialCipher", new PaymentCredentialCipher("test-cipher-key-32-chars-long!"));
        ReflectionTestUtils.setField(service, "privateKeyUploadDir", tempDir.toString());
        ReflectionTestUtils.setField(service, "platformPublicKeyLoader", new com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader());
        ReflectionTestUtils.setField(service, "wechatMerchantKeyStore", mock(com.lanf.payment.channel.wechat.WechatMerchantKeyStore.class));
    }

    @Test
    void storeClientCertP12_successWithValidPkcs12File() throws Exception {
        byte[] p12Bytes = generatePkcs12Bytes("1900000109");
        MockMultipartFile file = new MockMultipartFile("file", "apiclient_cert.p12", "application/x-pkcs12", p12Bytes);

        String pathRef = service.storeClientCertP12(1, "default", file);

        assertNotNull(pathRef);
        assertTrue(pathRef.endsWith(".p12"));
        Path savedPath = Paths.get(pathRef);
        assertTrue(Files.exists(savedPath));
        assertTrue(savedPath.startsWith(tempDir.resolve("shop-1")));
        assertEquals(p12Bytes.length, Files.size(savedPath));
    }

    @Test
    void storeClientCertP12_rejectsCorruptedOrNonPkcs12Bytes() {
        byte[] badBytes = "not-a-pkcs12-binary-keystore-content-at-all".getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "fake_cert.p12", "application/x-pkcs12", badBytes);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.storeClientCertP12(1, "default", file));
        assertTrue(ex.getMessage().contains("PKCS12") || ex.getMessage().contains("证书格式"));
    }

    @Test
    void storeClientCertP12_rejectsPemTextFile() {
        byte[] pemBytes = "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----".getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "cert.pem", "application/x-pem-file", pemBytes);

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.storeClientCertP12(1, "default", file));
        assertTrue(ex.getMessage().contains("PEM 文本文件"));
    }

    @Test
    void storeCertificateMaterial_autoDetectsPkcs12AndStores() throws Exception {
        byte[] p12Bytes = generatePkcs12Bytes("1900000109");
        MockMultipartFile file = new MockMultipartFile("file", "apiclient_cert.p12", "application/x-pkcs12", p12Bytes);

        PaymentMerchantConfigService.UnifiedCertificateResult result =
                service.storeCertificateMaterial(1, "default", "AUTO", file);

        assertEquals("CLIENT_CERT_P12", result.getCertificateType());
        assertTrue(result.getFileRef().endsWith(".p12"));
        assertTrue(Files.exists(Paths.get(result.getFileRef())));
    }

    @Test
    void storeCertificateMaterial_autoDetectsPrivateKeyPem() throws Exception {
        String privateKeyPem = generateRsaPrivateKeyPem();
        MockMultipartFile file = new MockMultipartFile("file", "apiclient_key.pem", "application/x-pem-file",
                privateKeyPem.getBytes(StandardCharsets.UTF_8));

        PaymentMerchantConfigService.UnifiedCertificateResult result =
                service.storeCertificateMaterial(1, "default", "AUTO", file);

        assertEquals("PRIVATE_KEY", result.getCertificateType());
        assertTrue(result.getFileRef().endsWith("-private-key.pem"));
        assertTrue(Files.exists(Paths.get(result.getFileRef())));
    }

    @Test
    void storeCertificateMaterial_autoDetectsPlatformPublicKeyPem() throws Exception {
        String pubKeyPem = generateRsaPublicKeyPem();
        MockMultipartFile file = new MockMultipartFile("file", "pub_key.pem", "application/x-pem-file",
                pubKeyPem.getBytes(StandardCharsets.UTF_8));

        PaymentMerchantConfigService.UnifiedCertificateResult result =
                service.storeCertificateMaterial(1, "default", "AUTO", file);

        assertEquals("PLATFORM_PUBLIC_KEY", result.getCertificateType());
        assertEquals("PUBLIC_KEY", result.getMaterialType());
        assertTrue(result.getFileRef().endsWith("-platform-public.pem"));
    }

    @Test
    void uploadCertificateForMerchant_bindsPkcs12DirectlyAndIncrementsVersion() throws Exception {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(10L);
        row.setShop_id(1);
        row.setChannel("wechat");
        row.setMerchant_key("default");
        row.setCredential_version(1);

        when(merchantMapper.updateById(any(PaymentMerchantConfigEntity.class))).thenReturn(1);

        byte[] p12Bytes = generatePkcs12Bytes("1900000109");
        MockMultipartFile file = new MockMultipartFile("file", "apiclient_cert.p12", "application/x-pkcs12", p12Bytes);

        PaymentMerchantConfigService.CertificateBindResult bound =
                service.uploadCertificateForMerchant(row, "CLIENT_CERT_P12", file);

        assertEquals(2, bound.row.getCredential_version());
        assertNotNull(bound.row.getClient_cert_p12_ref());
        assertTrue(bound.row.getClient_cert_p12_ref().endsWith(".p12"));
        verify(historyMapper).insert(any(PaymentMerchantConfigHistoryEntity.class));
        verify(merchantMapper).updateById(bound.row);
    }

    @Test
    void getWechatMicropayMissingFields_identifiesMissingCredentials() throws Exception {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setId(20L);
        row.setShop_id(1);
        row.setChannel("wechat");
        row.setMerchant_key("default");
        row.setEnabled(1);
        row.setStatus("ACTIVE");
        row.setApp_id("wx1234567890123456");
        row.setMch_id("1900000109");

        when(merchantMapper.selectList(any())).thenReturn(java.util.Collections.singletonList(row));

        List<String> missing = service.getWechatMicropayMissingFields(1, "default");
        assertTrue(missing.contains("apiV2Key"));
        assertTrue(missing.contains("clientCertP12Ref"));

        // Now supply valid apiV2Key and valid clientCertP12Ref
        PaymentCredentialCipher cipher = new PaymentCredentialCipher("test-cipher-key-32-chars-long!");
        row.setApi_v2_key_enc(cipher.encrypt("12345678901234567890123456789012"));

        Path p12File = tempDir.resolve("shop-1").resolve("valid.p12");
        Files.createDirectories(p12File.getParent());
        Files.write(p12File, generatePkcs12Bytes("1900000109"));
        row.setClient_cert_p12_ref(p12File.toAbsolutePath().toString());

        List<String> readyMissing = service.getWechatMicropayMissingFields(1, "default");
        assertTrue(readyMissing.isEmpty());
    }

    private static byte[] generatePkcs12Bytes(String password) throws Exception {
        KeyStore ks = KeyStore.getInstance("PKCS12");
        ks.load(null, null);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ks.store(out, password.toCharArray());
        return out.toByteArray();
    }

    private static String generateRsaPrivateKeyPem() throws Exception {
        byte[] encoded = KeyPairGenerator.getInstance("RSA").generateKeyPair().getPrivate().getEncoded();
        return "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(encoded)
                + "\n-----END PRIVATE KEY-----\n";
    }

    private static String generateRsaPublicKeyPem() throws Exception {
        byte[] encoded = KeyPairGenerator.getInstance("RSA").generateKeyPair().getPublic().getEncoded();
        return "-----BEGIN PUBLIC KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(encoded)
                + "\n-----END PUBLIC KEY-----\n";
    }
}
