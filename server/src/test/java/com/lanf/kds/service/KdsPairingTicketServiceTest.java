package com.lanf.kds.service;

import com.lanf.kds.entity.KdsDevice;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsPairingTicketServiceTest {

    @Test
    void issuesShortLivedTicketOnlyForPreBoundEnabledDeviceAndStoresNoPlaintext() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsDevice bound = device(1, "KDS-01", 1);
        when(devices.findByDeviceCode("KDS-01")).thenReturn(bound);
        when(jdbc.update(anyString(), any(), any(), any(), any())).thenReturn(1);
        KdsPairingTicketService service = new KdsPairingTicketService(jdbc, devices, 300);

        KdsPairingTicketService.PairingTicket ticket = service.issue(1, "KDS-01", "admin:7");

        assertTrue(ticket.getPairingCode().matches("[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}"));
        assertEquals("KDS-01", ticket.getDeviceCode());
        assertTrue(ticket.getExpiresAtMs() > System.currentTimeMillis());
        verify(jdbc).update(
                eq("INSERT INTO t_kds_device_pairing_ticket "
                        + "(shop_id,device_code,code_hash,expires_at,created_by) VALUES (?,?,?,?,?)"),
                eq(1), eq("KDS-01"), eq(KdsPairingTicketService.hashCode(ticket.getPairingCode())),
                any(Date.class), eq("admin:7"));
    }

    @Test
    void rejectsTicketForUnknownCrossShopOrDisabledDevice() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsPairingTicketService service = new KdsPairingTicketService(jdbc, devices, 300);

        assertThrows(IllegalArgumentException.class,
                () -> service.issue(1, "UNKNOWN", "admin:7"));
        when(devices.findByDeviceCode("KDS-OTHER")).thenReturn(device(2, "KDS-OTHER", 1));
        assertThrows(IllegalArgumentException.class,
                () -> service.issue(1, "KDS-OTHER", "admin:7"));
        when(devices.findByDeviceCode("KDS-OFF")).thenReturn(device(1, "KDS-OFF", 0));
        assertThrows(IllegalArgumentException.class,
                () -> service.issue(1, "KDS-OFF", "admin:7"));

        verify(jdbc, never()).update(anyString(), any(), any(), any(), any());
    }

    @Test
    void atomicallyConsumesTicketForExactDeviceAndIssuesCloudToken() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        KdsDeviceService devices = mock(KdsDeviceService.class);
        Map<String, Object> row = new HashMap<>();
        row.put("id", 19L);
        row.put("shop_id", 1);
        row.put("device_code", "KDS-01");
        when(jdbc.queryForList(anyString(), eq(KdsPairingTicketService.hashCode("ABCDEFGH"))))
                .thenReturn(Collections.singletonList(row));
        when(jdbc.update(anyString(), eq(19L))).thenReturn(1);
        KdsDevice loggedIn = device(1, "KDS-01", 1);
        loggedIn.setDevice_token("cloud-token");
        when(devices.loginBoundDevice(1, "KDS-01", "Kitchen", "cook",
                Collections.emptyList(), null)).thenReturn(loggedIn);
        KdsPairingTicketService service = new KdsPairingTicketService(jdbc, devices, 300);

        KdsDevice result = service.consumeAndLogin(
                "ABCDEFGH", "KDS-01", "Kitchen", "cook", Collections.emptyList());

        assertNotNull(result);
        assertEquals("cloud-token", result.getDevice_token());
        verify(jdbc).update(
                eq("UPDATE t_kds_device_pairing_ticket SET consumed_at=NOW() "
                        + "WHERE id=? AND consumed_at IS NULL AND expires_at>NOW()"),
                eq(19L));
    }

    @Test
    void rejectsMissingReplayedOrDeviceMismatchedTicketBeforeTokenIssue() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        KdsDeviceService devices = mock(KdsDeviceService.class);
        KdsPairingTicketService service = new KdsPairingTicketService(jdbc, devices, 300);
        when(jdbc.queryForList(anyString(), anyString())).thenReturn(Collections.emptyList());

        assertThrows(IllegalArgumentException.class, () -> service.consumeAndLogin(
                "ABCDEFGH", "KDS-01", "Kitchen", "cook", Collections.emptyList()));

        Map<String, Object> otherDevice = new HashMap<>();
        otherDevice.put("id", 20L);
        otherDevice.put("shop_id", 1);
        otherDevice.put("device_code", "KDS-02");
        when(jdbc.queryForList(anyString(), eq(KdsPairingTicketService.hashCode("BCDEFGHJ"))))
                .thenReturn(Collections.singletonList(otherDevice));
        assertThrows(IllegalArgumentException.class, () -> service.consumeAndLogin(
                "BCDEFGHJ", "KDS-01", "Kitchen", "cook", Collections.emptyList()));

        verify(devices, never()).loginBoundDevice(
                eq(1), anyString(), anyString(), anyString(), any(), any());
    }

    private static KdsDevice device(int shopId, String code, int enabled) {
        KdsDevice device = new KdsDevice();
        device.setId(11L);
        device.setShop_id(shopId);
        device.setDevice_code(code);
        device.setEnabled(enabled);
        return device;
    }
}
