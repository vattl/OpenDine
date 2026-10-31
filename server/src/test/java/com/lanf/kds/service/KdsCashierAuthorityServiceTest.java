package com.lanf.kds.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class KdsCashierAuthorityServiceTest {
    @Test
    void onlyConfiguredCashierDeviceMayPublishState() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.contains("cashier_device_code"),
                org.mockito.ArgumentMatchers.eq(String.class), org.mockito.ArgumentMatchers.eq(7)))
                .thenReturn(Collections.singletonList("cashier-primary"));
        KdsCashierAuthorityService service = new KdsCashierAuthorityService(jdbc);

        assertDoesNotThrow(() -> service.requirePrimaryPublisher(7, "cashier-primary"));
        assertDoesNotThrow(() -> service.requireConfiguredPublisher(7, "cashier-primary"));
        assertThrows(RuntimeException.class,
                () -> service.requirePrimaryPublisher(7, "cashier-secondary"));
        assertThrows(RuntimeException.class,
                () -> service.requireConfiguredPublisher(7, "cashier-secondary"));
    }

    @Test
    void missingAuthorityFailsClosed() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.eq(String.class), org.mockito.ArgumentMatchers.eq(7)))
                .thenReturn(Collections.emptyList());
        KdsCashierAuthorityService service = new KdsCashierAuthorityService(jdbc);

        assertThrows(RuntimeException.class,
                () -> service.requirePrimaryPublisher(7, "cashier-1"));
    }
}
