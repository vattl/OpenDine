package com.lanf.payment.channel.wechat;

import org.junit.jupiter.api.Test;

import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class WechatPlatformPublicKeyLoaderTest {

    private static final String CERTIFICATE_PEM =
            "-----BEGIN CERTIFICATE-----\n"
                    + "MIIDCzCCAfOgAwIBAgIUNy7XvNJb/KORHH8RkAzRmcLn998wDQYJKoZIhvcNAQEL\n"
                    + "BQAwFTETMBEGA1UEAwwKdWkwNTctdGVzdDAeFw0yNjEwMjAyMzAwMTRaFw0yNjEw\n"
                    + "MjEyMzAwMTRaMBUxEzARBgNVBAMMCnVpMDU3LXRlc3QwggEiMA0GCSqGSIb3DQEB\n"
                    + "AQUAA4IBDwAwggEKAoIBAQCwhJdWI/lLGrAmvPyZk3QkTDLbyR6HlfdzNsCCDHJe\n"
                    + "IiexxqoCJYnmQd+yVXGNzX8fAnPaB/E/pksQ12slNDyO85BVuQySZ3/dYjinoQzI\n"
                    + "DcEJ/r/olN5wMIPvPfdKota5BWSNR0DlRGC79s6RRfoCgK1y32FrLvFaoUj1nuhQ\n"
                    + "YUA0L0D1adR0zZLAFx1y0bVOI96QdojtJYNLBaCq3iMAOOl9zPIwIKEuTxcQ2BvQ\n"
                    + "k58ADXOAPly8yb9AjtSckM7K+ajXvvZL9j++vlLx0gPF9rzO4758OFMKD08H597g\n"
                    + "aQgABDK/UL3houvV25GGg+3vM9IymV4P4uplM3SrOoOHAgMBAAGjUzBRMB0GA1Ud\n"
                    + "DgQWBBQCyPCBYp3F9PWhmHg3ZEQ99CSf8zAfBgNVHSMEGDAWgBQCyPCBYp3F9PWh\n"
                    + "mHg3ZEQ99CSf8zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQCr\n"
                    + "DgJOCTr7ClvNeBQ0S4EDdmSjZRN5sdevZU9n4yKOGeM8Paml0WH9MXBktM5U4AFW\n"
                    + "e5nxGZ+in+FCfgkWuImZWVTJ6TDcSwdT/v6RSsabWMVBlJ7D0l78KzplG1mC/9cW\n"
                    + "A/bKjkOLXCMQnR+RwZswVXnLol1V8Ovs4OAeZRF6DMkN2lHjSeYjS0gABdHnJA5R\n"
                    + "RW7f89fEH9cZzGaRN1UsphEyjNKPtIwrtNCBuyrkTOkZEqRNrzZGkecMJ+WXrOet\n"
                    + "QeEu2T4IpmTAvZQA2OaLoSDQ1u0fGM+my1fp9gk4akyNfe97cPLq95BQqwDyk+TG\n"
                    + "6HLbuZ7/tWkitL0D9p9j\n"
                    + "-----END CERTIFICATE-----\n";

    @Test
    void loadsInlinePublicKeyPem() throws Exception {
        PublicKey expected = KeyPairGenerator.getInstance("RSA").generateKeyPair().getPublic();
        String pem = "-----BEGIN PUBLIC KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(expected.getEncoded())
                + "\n-----END PUBLIC KEY-----\n";

        PublicKey actual = new WechatPlatformPublicKeyLoader().load(pem);

        assertArrayEquals(expected.getEncoded(), actual.getEncoded());
    }

    @Test
    void extractsRsaPublicKeyFromInlineX509Certificate() throws Exception {
        PublicKey actual = new WechatPlatformPublicKeyLoader().load(CERTIFICATE_PEM);

        assertEquals("RSA", actual.getAlgorithm());
    }

    @Test
    void rejectsPrivateKeyMaterial() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> new WechatPlatformPublicKeyLoader().load(
                        "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----"));

        assertEquals("微信平台公钥文件不能包含私钥", error.getMessage());
    }
}
