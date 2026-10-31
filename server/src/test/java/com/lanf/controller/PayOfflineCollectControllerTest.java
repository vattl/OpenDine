package com.lanf.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.dto.OfflineCollectTokenPayload;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.OfflineCollectTokenService;
import com.lanf.service.PersonalPaymentWebhookService;
import com.lanf.util.OfflineCollectQrCodec;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.ByteArrayInputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.Base64;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

class PayOfflineCollectControllerTest {

    @Test
    void cancelReleasesOnlyThePendingLeaseOwnedByTheClosingCashier() {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        when(intents.cancelPending(7, "ORD-1", "session-a", "wechat"))
                .thenReturn(1);
        PayOfflineCollectController controller = controller(intents);
        MockHttpServletRequest request = shopRequest(7);
        Map<String, Object> body = collectionBody("ORD-1", "session-a", "wechat", 28000);

        R result = controller.cancelCollection(body, request);

        assertEquals(0, result.get("code"));
        assertEquals(true, result.get("released"));
        assertEquals("PENDING_ONLY_CURRENT_SESSION", result.get("releasePolicy"));
        verify(intents).cancelPending(7, "ORD-1", "session-a", "wechat");
    }

    @Test
    void confirmReturnsTheLatestAmountStoredByTheLastQrReservation() {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        when(intents.confirm(7, "ORD-1", "session-a", "wechat", 28000))
                .thenReturn(26000);
        PayOfflineCollectController controller = controller(intents);
        MockHttpServletRequest request = shopRequest(7);
        Map<String, Object> body = collectionBody("ORD-1", "session-a", "wechat", 28000);

        R result = controller.confirmCollection(body, request);

        assertEquals(0, result.get("code"));
        assertEquals(26000, result.get("amountFen"));
    }

    @Test
    void tempQrDoesNotReserveAnOrderWhenTheShopQrCodeIsUnavailable() throws Exception {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        IOrderService orders = mock(IOrderService.class);
        IShopService shops = mock(IShopService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR))
                .thenReturn(true);
        Order order = new Order();
        order.setTransac_status("unsettled");
        when(orders.getOne(org.mockito.ArgumentMatchers.any())).thenReturn(order);
        PayOfflineCollectController controller = new PayOfflineCollectController(
                mock(OfflineCollectTokenService.class),
                shops,
                new ObjectMapper(),
                capabilities,
                intents,
                mock(PersonalPaymentWebhookService.class),
                orders);

        R result = controller.tempQrcode(
                collectionBody("ORD-1", "session-a", "wechat", 28000),
                shopRequest(7));

        assertEquals(404, result.get("code"));
        verify(intents, never()).reserve(
                7, "ORD-1", "session-a", "wechat", 28000);
    }

    @Test
    void tempQrUsesMerchantTwoFixedWechatPayloadFromOrder() throws Exception {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        IOrderService orders = mock(IOrderService.class);
        IShopService shops = mock(IShopService.class);
        OfflineCollectTokenService tokens = mock(OfflineCollectTokenService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR))
                .thenReturn(true);
        Order order = new Order();
        order.setTransac_status("unsettled");
        order.setMerchantId("2");
        when(orders.getOne(org.mockito.ArgumentMatchers.any())).thenReturn(order);
        when(shops.getById(7)).thenReturn(new Shop());
        when(tokens.newToken(7, "wechat", "2")).thenReturn("merchant-two-token");
        PayOfflineCollectController controller = new PayOfflineCollectController(
                tokens, shops, new ObjectMapper(), capabilities, intents, mock(PersonalPaymentWebhookService.class), orders);
        Map<String, Object> body = collectionBody(
                "ORD-1", "session-a", "wechat", 28000);
        body.put("merchantId", "1");

        R result = controller.tempQrcode(body, shopRequest(7));

        assertEquals(0, result.get("code"));
        assertEquals("2", result.get("merchantId"));
        byte[] png = Base64.getDecoder().decode(result.get("qrImageBase64").toString());
        assertEquals(
                "wxp://f2f05JKIRZqDSA-IOrNU9MXzGYgNaYLIYzU5uvp8OAKYJVA",
                OfflineCollectQrCodec.decodeFirstQrPayload(new ByteArrayInputStream(png)));
    }

    @Test
    void tempWechatQrUsesThePersonalQrSwitchWhenOnlineWechatIsDisabled() throws Exception {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        IOrderService orders = mock(IOrderService.class);
        IShopService shops = mock(IShopService.class);
        OfflineCollectTokenService tokens = mock(OfflineCollectTokenService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR)).thenReturn(true);
        Order order = new Order();
        order.setTransac_status("unsettled");
        order.setMerchantId("2");
        when(orders.getOne(org.mockito.ArgumentMatchers.any())).thenReturn(order);
        when(shops.getById(7)).thenReturn(new Shop());
        when(tokens.newToken(7, "wechat", "2")).thenReturn("personal-wechat-token");
        PayOfflineCollectController controller = new PayOfflineCollectController(
                tokens, shops, new ObjectMapper(), capabilities, intents,
                mock(PersonalPaymentWebhookService.class), orders);

        R result = controller.tempQrcode(
                collectionBody("ORD-1", "session-a", "wechat", 28000),
                shopRequest(7));

        assertEquals(0, result.get("code"));
        verify(capabilities).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR);
        verify(capabilities, never()).isCashierConfiguredChannelEnabled(7, "wechat");
    }

    @Test
    void tempWechatQrIsRejectedWhenOnlyOnlineWechatIsEnabled() throws Exception {
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        when(capabilities.isCashierConfiguredChannelEnabled(7, "wechat"))
                .thenReturn(true);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR)).thenReturn(false);
        PayOfflineCollectController controller = new PayOfflineCollectController(
                mock(OfflineCollectTokenService.class),
                mock(IShopService.class),
                new ObjectMapper(),
                capabilities,
                mock(CashierCollectionIntentService.class),
                mock(PersonalPaymentWebhookService.class),
                mock(IOrderService.class));

        R result = controller.tempQrcode(
                collectionBody("ORD-1", "session-a", "wechat", 28000),
                shopRequest(7));

        assertEquals(400, result.get("code"));
        assertEquals("当前门店未启用微信收款码", result.get("msg"));
        verify(capabilities).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR);
    }

    @Test
    void tempAlipayQrUsesThePersonalAlipayQrSwitch() throws Exception {
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_ALIPAY_QR)).thenReturn(false);
        PayOfflineCollectController controller = new PayOfflineCollectController(
                mock(OfflineCollectTokenService.class),
                mock(IShopService.class),
                new ObjectMapper(),
                capabilities,
                mock(CashierCollectionIntentService.class),
                mock(PersonalPaymentWebhookService.class),
                mock(IOrderService.class));

        R result = controller.tempQrcode(
                collectionBody("ORD-1", "session-a", "alipay", 28000),
                shopRequest(7));

        assertEquals(400, result.get("code"));
        assertEquals("当前门店未启用支付宝收款码", result.get("msg"));
        verify(capabilities).isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_ALIPAY_QR);
    }

    @Test
    void jumpUsesTheSameMerchantTwoWechatPayloadAsTheQrImage() throws Exception {
        OfflineCollectTokenService tokens = mock(OfflineCollectTokenService.class);
        IShopService shops = mock(IShopService.class);
        when(tokens.resolve("merchant-two-token")).thenReturn(Optional.of(
                new OfflineCollectTokenPayload(7, "wechat", "2")));
        when(shops.getById(7)).thenReturn(new Shop());
        PayOfflineCollectController controller = new PayOfflineCollectController(
                tokens,
                shops,
                new ObjectMapper(),
                mock(PaymentCapabilityService.class),
                mock(CashierCollectionIntentService.class),
                mock(PersonalPaymentWebhookService.class),
                mock(IOrderService.class));
        MockHttpServletResponse response = new MockHttpServletResponse();

        controller.jump(
                "merchant-two-token", new MockHttpServletRequest(), response);

        assertEquals(
                "wxp://f2f05JKIRZqDSA-IOrNU9MXzGYgNaYLIYzU5uvp8OAKYJVA",
                response.getRedirectedUrl());
    }

    @Test
    void tempQrRejectsConflictingMerchantIdAliases() throws Exception {
        PayOfflineCollectController controller = controller(
                mock(CashierCollectionIntentService.class));
        Map<String, Object> body = new HashMap<>();
        body.put("channel", "wechat");
        body.put("merchantId", "2");
        body.put("merchant_id", 1);

        R result = controller.tempQrcode(body, shopRequest(7));

        assertEquals(400, result.get("code"));
        assertEquals("merchantId 与 merchant_id 不一致", result.get("msg"));
    }

    @Test
    void tempQrFallsBackToOrderNetRevenueWhenAmountFenIsZeroOrMissing() throws Exception {
        CashierCollectionIntentService intents = mock(CashierCollectionIntentService.class);
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        IOrderService orders = mock(IOrderService.class);
        IShopService shops = mock(IShopService.class);
        OfflineCollectTokenService tokens = mock(OfflineCollectTokenService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR))
                .thenReturn(true);
        Order order = new Order();
        order.setTransac_status("unsettled");
        order.setSett_amount(50.0);
        when(orders.getOne(org.mockito.ArgumentMatchers.any())).thenReturn(order);
        Shop shop = new Shop();
        shop.setOffline_collect_wechat_payload("wxp://test-payload");
        when(shops.getById(7)).thenReturn(shop);
        when(tokens.newToken(7, "wechat", "1")).thenReturn("test-token");
        PayOfflineCollectController controller = new PayOfflineCollectController(
                tokens, shops, new ObjectMapper(), capabilities, intents, mock(PersonalPaymentWebhookService.class), orders);

        Map<String, Object> body = collectionBody("ORD-1", "session-a", "wechat", 0);
        R result = controller.tempQrcode(body, shopRequest(7));

        assertEquals(0, result.get("code"));
        assertEquals(5000, result.get("amountFen"));
        verify(intents).reserve(7, "ORD-1", "session-a", "wechat", 5000);
    }

    @Test
    void tempQrRejectsWhenOrderAmountIsZero() throws Exception {
        PaymentCapabilityService capabilities = mock(PaymentCapabilityService.class);
        IOrderService orders = mock(IOrderService.class);
        when(capabilities.isCashierPaymentMethodEnabled(
                7, PaymentChannelCatalog.OFFLINE_WECHAT_QR))
                .thenReturn(true);
        Order order = new Order();
        order.setTransac_status("unsettled");
        order.setSett_amount(0.0);
        when(orders.getOne(org.mockito.ArgumentMatchers.any())).thenReturn(order);
        PayOfflineCollectController controller = new PayOfflineCollectController(
                mock(OfflineCollectTokenService.class), mock(IShopService.class), new ObjectMapper(),
                capabilities, mock(CashierCollectionIntentService.class), mock(PersonalPaymentWebhookService.class), orders);

        Map<String, Object> body = collectionBody("ORD-1", "session-a", "wechat", 0);
        R result = controller.tempQrcode(body, shopRequest(7));

        assertEquals(400, result.get("code"));
        assertEquals("订单待收金额为 ¥0.00，无需生成收款码", result.get("msg"));
    }

    private static PayOfflineCollectController controller(CashierCollectionIntentService intents) {
        return new PayOfflineCollectController(
                mock(OfflineCollectTokenService.class),
                mock(IShopService.class),
                new ObjectMapper(),
                mock(PaymentCapabilityService.class),
                intents,
                mock(PersonalPaymentWebhookService.class),
                mock(IOrderService.class));
    }

    private static MockHttpServletRequest shopRequest(int shopId) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Shop-Id", String.valueOf(shopId));
        return request;
    }

    private static Map<String, Object> collectionBody(
            String orderNo, String sessionId, String channel, int amountFen) {
        Map<String, Object> body = new HashMap<>();
        body.put("order_no", orderNo);
        body.put("session_id", sessionId);
        body.put("channel", channel);
        body.put("amount_fen", amountFen);
        return body;
    }
}
