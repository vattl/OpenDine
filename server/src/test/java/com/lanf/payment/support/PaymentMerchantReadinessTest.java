package com.lanf.payment.support;

import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PaymentMerchantReadinessTest {

    @Test
    void missingFields_shouldListEveryRequiredWechatCredentialWhenMerchantDoesNotExist() {
        List<String> missing = PaymentMerchantReadiness.missingFields(null);

        assertEquals(Arrays.asList(
                "enabled",
                "appId",
                "mchId",
                "notifyUrl",
                "serialNo",
                "platformPubKeyId",
                "platformPubKeyRef",
                "privateKeyRef",
                "apiV3Key"), missing);
    }

    @Test
    void missingFields_shouldBeEmptyForCompleteEnabledWechatMerchant() {
        PaymentMerchantConfigEntity row = new PaymentMerchantConfigEntity();
        row.setEnabled(1);
        row.setApp_id("wx-app-id");
        row.setMch_id("1900000109");
        row.setNotify_url("https://example.com/order/pay/notify");
        row.setSerial_no("ABC123");
        row.setPlatform_pub_key_id("PUB_KEY_ID_011");
        row.setPlatform_pub_key_ref("classpath:wechatpay_pub.pem");
        row.setPrivate_key_ref("classpath:apiclient_key.pem");
        row.setApi_v3_key_enc("encrypted-value");

        assertTrue(PaymentMerchantReadiness.missingFields(row).isEmpty());
    }
}
