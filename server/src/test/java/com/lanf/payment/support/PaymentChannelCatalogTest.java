package com.lanf.payment.support;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PaymentChannelCatalogTest {

    @Test
    void normalizePaymentMethod_shouldAcceptNewCodesAndLegacyValues() {
        assertEquals("微信支付", PaymentChannelCatalog.normalizePaymentMethod("online_wechat"));
        assertEquals("微信支付", PaymentChannelCatalog.normalizePaymentMethod("wechat"));
        assertEquals("支付宝支付", PaymentChannelCatalog.normalizePaymentMethod("alipay"));
        assertEquals("余额支付", PaymentChannelCatalog.normalizePaymentMethod("balance"));
        assertEquals("组合支付", PaymentChannelCatalog.normalizePaymentMethod("combined"));
        assertEquals("微信收款码", PaymentChannelCatalog.normalizePaymentMethod("wechat_qr"));
        assertEquals("微信收款码自动", PaymentChannelCatalog.normalizePaymentMethod("微信收款码自动"));
        assertEquals("微信收款码自动", PaymentChannelCatalog.normalizePaymentMethod("微信收款码(自动)"));
        assertEquals("微信收款码自动", PaymentChannelCatalog.normalizePaymentMethod("offline_wechat_qr_auto"));
        assertEquals("支付宝收款码", PaymentChannelCatalog.normalizePaymentMethod("offline_alipay_qr"));
        assertEquals("支付宝收款码自动", PaymentChannelCatalog.normalizePaymentMethod("支付宝收款码自动"));
        assertEquals("支付宝收款码自动", PaymentChannelCatalog.normalizePaymentMethod("支付宝收款码(自动)"));
        assertEquals("支付宝收款码自动", PaymentChannelCatalog.normalizePaymentMethod("offline_alipay_qr_auto"));
        assertEquals("挂账", PaymentChannelCatalog.normalizePaymentMethod("receivable"));
        assertEquals("挂账", PaymentChannelCatalog.normalizePaymentMethod("credit"));
        assertEquals("挂账", PaymentChannelCatalog.normalizePaymentMethod("on_account"));
        assertEquals("挂账", PaymentChannelCatalog.normalizePaymentMethod("挂账"));
        assertEquals("自定义挂账", PaymentChannelCatalog.normalizePaymentMethod(" 自定义挂账 "));
    }

    @Test
    void codeAndType_shouldKeepOnlineAndOfflineIdentitySeparate() {
        assertEquals("online_wechat", PaymentChannelCatalog.codeFromPaymentMethod("微信支付"));
        assertEquals("offline_wechat_qr", PaymentChannelCatalog.codeFromPaymentMethod("微信收款码"));
        assertEquals("offline_wechat_qr", PaymentChannelCatalog.codeFromPaymentMethod("微信收款码自动"));
        assertEquals("online", PaymentChannelCatalog.typeFromPaymentMethod("支付宝支付"));
        assertEquals("offline", PaymentChannelCatalog.typeFromPaymentMethod("支付宝收款码"));
        assertEquals("offline_alipay_qr", PaymentChannelCatalog.codeFromPaymentMethod("支付宝收款码自动"));
        assertEquals("offline", PaymentChannelCatalog.typeFromPaymentMethod("微信收款码自动"));
        assertEquals("offline", PaymentChannelCatalog.typeFromPaymentMethod("支付宝收款码自动"));
        assertEquals("cash", PaymentChannelCatalog.codeFromPaymentMethod("cash"));
        assertEquals("cash", PaymentChannelCatalog.codeFromPaymentMethod("现金"));
        assertEquals("offline", PaymentChannelCatalog.typeFromPaymentMethod("cash"));
        assertEquals("receivable", PaymentChannelCatalog.codeFromPaymentMethod("挂账"));
        assertEquals("offline", PaymentChannelCatalog.typeFromPaymentMethod("挂账"));
        assertNull(PaymentChannelCatalog.codeFromPaymentMethod("自定义支付"));
    }

    @Test
    void reportingChannel_shouldPreferCollectionMethodOverGenericLedgerChannel() {
        assertEquals("wechat_qr",
                PaymentChannelCatalog.reportingCode("WECHAT", "微信收款码"));
        assertEquals("alipay_qr",
                PaymentChannelCatalog.reportingCode("ALIPAY", "支付宝收款码自动"));
        assertEquals("wechat",
                PaymentChannelCatalog.reportingCode("WECHAT", "微信支付"));
        assertEquals("alipay",
                PaymentChannelCatalog.reportingCode("ALIPAY", "支付宝支付"));
        assertEquals("wechat_qr",
                PaymentChannelCatalog.reportingCode("WECHAT_QR", null));
        assertEquals("微信收款码", PaymentChannelCatalog.reportingLabel("wechat_qr"));
        assertEquals("支付宝收款码", PaymentChannelCatalog.reportingLabel("alipay_qr"));
        assertEquals("receivable", PaymentChannelCatalog.reportingCode(null, "挂账"));
        assertEquals("receivable", PaymentChannelCatalog.reportingCode("receivable", null));
        assertEquals("挂账", PaymentChannelCatalog.reportingLabel("receivable"));
    }

    @Test
    void ledgerChannel_shouldPersistQrIdentityForNewSettlements() {
        assertEquals("WECHAT_QR",
                PaymentChannelCatalog.ledgerChannel("微信收款码自动", "WECHAT"));
        assertEquals("ALIPAY_QR",
                PaymentChannelCatalog.ledgerChannel("offline_alipay_qr", "ALIPAY"));
        assertEquals("WECHAT",
                PaymentChannelCatalog.ledgerChannel("微信支付", "WECHAT"));
        assertEquals("ALIPAY",
                PaymentChannelCatalog.ledgerChannel("微信收款码", "ALIPAY"));
        assertEquals("OTHER",
                PaymentChannelCatalog.ledgerChannel("自定义支付", "OTHER"));
    }

    @SuppressWarnings("unchecked")
    @Test
    void groupedMethods_shouldReturnFourOnlineAndTwoOfflineMethods() {
        Map<String, Object> groups = PaymentChannelCatalog.groupedMethods(
                true, false, true, true, true, false);
        List<Map<String, Object>> online = (List<Map<String, Object>>) groups.get("online");
        List<Map<String, Object>> offline = (List<Map<String, Object>>) groups.get("offline");

        assertEquals(4, online.size());
        assertEquals(2, offline.size());
        assertTrue((Boolean) online.get(0).get("enabled"));
        assertFalse((Boolean) online.get(1).get("enabled"));
        assertEquals("offline_wechat_qr", offline.get(0).get("code"));
        assertFalse((Boolean) offline.get(1).get("enabled"));
    }

    @Test
    void clientMethods_shouldExposeManualCashierChannelsAndPreserveMiniProgramChannels() {
        List<Map<String, Object>> cashier =
                PaymentChannelCatalog.cashierMethods(true, true, false, true, true);

        assertEquals(5, cashier.size());
        assertEquals("cash", cashier.get(0).get("code"));
        assertEquals("offline_wechat_qr", cashier.get(1).get("code"));
        assertEquals("offline_alipay_qr", cashier.get(2).get("code"));
        assertEquals("online_balance", cashier.get(3).get("code"));
        assertEquals("online_combined", cashier.get(4).get("code"));
        assertTrue((Boolean) cashier.get(0).get("enabled"));
        assertTrue((Boolean) cashier.get(1).get("enabled"));
        assertFalse((Boolean) cashier.get(2).get("enabled"));
        assertEquals(2, PaymentChannelCatalog.miniProgramMethods(true, true).size());
        assertEquals("online_wechat",
                PaymentChannelCatalog.miniProgramMethods(true, true).get(0).get("code"));
        assertEquals("online_balance",
                PaymentChannelCatalog.miniProgramMethods(true, true).get(1).get("code"));
    }
}
