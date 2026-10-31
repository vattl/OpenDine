package com.lanf.payment.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierCollectionIntentServiceTest {

    @Test
    void reserveAllowsAnotherSessionToTakeOverPendingCollection() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(orderRow("unsettled")),
                        Collections.singletonList(row(
                                "other-session", 0, "PENDING", 1000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(
                () -> service.reserve(7, "ORD-1", "this-session", "wechat", 1000));
    }

    @Test
    void reserveAllowsTheSameSessionAndRefreshesItsLease() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(orderRow("unsettled")),
                        Collections.singletonList(row(
                                "same-session", 0, "PENDING", 2500, "alipay")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(
                () -> service.reserve(7, "ORD-1", "same-session", "alipay", 2500));
    }

    @Test
    void reserveReplacesPendingAmountWithTheLatestCheckoutAmount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(orderRow("unsettled")),
                        Collections.singletonList(row(
                                "same-session", 0, "PENDING", 28000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(
                () -> service.reserve(7, "ORD-1", "same-session", "wechat", 26000));

        verify(jdbc).update(
                contains("amount_fen = ?"),
                eq("same-session"), eq(26000), eq(180),
                eq(7), eq("ORD-1"), eq("wechat"));
    }

    @Test
    void reserveReopensACancelledLeaseForAnotherCashierAtTheLatestAmount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(orderRow("unsettled")),
                        Collections.singletonList(row(
                                "closed-session", 1, "CANCELLED", 28000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(
                () -> service.reserve(7, "ORD-1", "cashier-b-session", "wechat", 26000));

        verify(jdbc).update(
                contains("amount_fen = ?"),
                eq("cashier-b-session"), eq(26000), eq(180),
                eq(7), eq("ORD-1"), eq("wechat"));
    }

    @Test
    void reserveNeverReopensAConfirmedCollectionForAnotherSession() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(
                        Collections.singletonList(orderRow("unsettled")),
                        Collections.singletonList(row(
                                "confirmed-session", 1, "CONFIRMED", 1000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertThrows(IllegalStateException.class,
                () -> service.reserve(7, "ORD-1", "other-session", "wechat", 1000));
    }

    @Test
    void validateCheckoutRequiresConfirmedMatchingSessionAndAmount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Map<String, Object> confirmed = row(
                "same-session", 0, "CONFIRMED", 1000, "wechat");
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(confirmed));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(() -> service.validateCheckout(
                7, "ORD-1", "same-session", 1000, 0));
        assertThrows(IllegalStateException.class, () -> service.validateCheckout(
                7, "ORD-1", "other-session", 1000, 0));
    }

    @Test
    void validateCheckoutAllowsSwitchFromPendingQrToNonQrPayment() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(row(
                        "old-session", 0, "PENDING", 1000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(() -> service.validateCheckout(
                7, "ORD-1", null, 0, 0));
        verify(jdbc).update(contains("SET status = 'CANCELLED'"), eq(7), eq("ORD-1"));
    }

    @Test
    void validateCheckoutAllowsConfirmedNewChannelAndCancelsObsoletePendingChannel() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Arrays.asList(
                        row("same-session", 0, "PENDING", 1000, "wechat"),
                        row("same-session", 0, "CONFIRMED", 1000, "alipay")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertDoesNotThrow(() -> service.validateCheckout(
                7, "ORD-1", "same-session", 0, 1000));
        verify(jdbc).update(contains("SET status = 'CANCELLED'"), eq(7), eq("ORD-1"));
    }

    @Test
    void validateCheckoutRejectsSwitchAwayFromConfirmedQrPayment() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(row(
                        "same-session", 0, "CONFIRMED", 1000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        assertThrows(IllegalStateException.class, () -> service.validateCheckout(
                7, "ORD-1", "same-session", 0, 0));
    }

    @Test
    void confirmUsesTheLatestReservedAmountInsteadOfAStaleClientAmount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);
        when(jdbc.update(anyString(), anyInt(), anyString(), anyString(), anyString()))
                .thenReturn(1);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(orderRow("unsettled")));
        when(jdbc.queryForList(anyString(), anyInt(), anyString(), anyString()))
                .thenReturn(Collections.singletonList(row(
                        "same-session", 0, "PENDING", 26000, "wechat")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        int confirmedAmountFen = assertDoesNotThrow(() -> service.confirm(
                7, "ORD-1", "same-session", "wechat", 28000));

        assertEquals(26000, confirmedAmountFen);
        verify(jdbc).update(
                contains("SET status = 'CONFIRMED'"),
                eq(7), eq("ORD-1"), eq("wechat"), eq("same-session"));
    }

    @Test
    void cancelReturnsSuccessWhenSessionIsCompleted() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Map<String, Object> completedRow = row("same-session", 0, "COMPLETED", 26000, "wechat");
        when(jdbc.queryForList(anyString(), anyInt(), anyString(), anyString(), anyString()))
                .thenReturn(Collections.singletonList(completedRow));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        int released = assertDoesNotThrow(() -> service.cancelPending(
                7, "ORD-1", "same-session", "wechat"));

        assertEquals(1, released);
    }

    @Test
    void lockUnsettledOrderThrowsClearExceptionWhenSettled() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.singletonList(orderRow("success")));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> service.confirm(7, "ORD-1", "same-session", "wechat", 1000));
        assertEquals("订单已结账", ex.getMessage());
    }

    @Test
    void lockUnsettledOrderThrowsClearExceptionWhenNotFound() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.emptyList());
        when(jdbc.queryForList(anyString(), anyString()))
                .thenReturn(Collections.emptyList());
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> service.confirm(7, "ORD-1", "same-session", "wechat", 1000));
        assertEquals("订单不存在", ex.getMessage());
    }

    @Test
    void lockUnsettledOrderThrowsClearExceptionWhenInAnotherShop() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString()))
                .thenReturn(Collections.emptyList());
        Map<String, Object> otherShopOrder = new HashMap<>();
        otherShopOrder.put("shop_id", 99);
        otherShopOrder.put("transac_status", "unsettled");
        when(jdbc.queryForList(anyString(), anyString()))
                .thenReturn(Collections.singletonList(otherShopOrder));
        CashierCollectionIntentService service = new CashierCollectionIntentService(jdbc);

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> service.confirm(7, "ORD-1", "same-session", "wechat", 1000));
        assertEquals("订单不属于当前门店", ex.getMessage());
    }

    private static Map<String, Object> row(
            String sessionId,
            int expired,
            String status,
            int amountFen,
            String channel) {
        Map<String, Object> row = new HashMap<>();
        row.put("session_id", sessionId);
        row.put("expired", expired);
        row.put("status", status);
        row.put("amount_fen", amountFen);
        row.put("channel", channel);
        return row;
    }

    private static Map<String, Object> orderRow(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("transac_status", status);
        return row;
    }
}
