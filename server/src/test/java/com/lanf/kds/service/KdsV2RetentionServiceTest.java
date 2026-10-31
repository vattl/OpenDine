package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsV2RetentionServiceTest {

    @Mock
    private JdbcTemplate jdbc;
    private KdsV2RetentionService service;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        service = new KdsV2RetentionService();
        ReflectionTestUtils.setField(service, "jdbc", jdbc);
        ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
    }

    @Test
    void archiveTerminalCommandsCopiesToArchiveAndDeletesFromHotTable() {
        when(jdbc.queryForList(anyString(), eq(String.class), eq(7), eq(14), eq(50)))
                .thenReturn(Arrays.asList("cmd-1", "cmd-2"));
        when(jdbc.update(contains("INSERT IGNORE INTO t_kds_v2_command_archive"), (Object[]) any()))
                .thenReturn(2);
        when(jdbc.update(contains("DELETE FROM t_kds_v2_command"), (Object[]) any()))
                .thenReturn(2);

        int archived = service.archiveTerminalCommands(7, 14, 50);
        assertEquals(2, archived);

        verify(jdbc).update(contains("INSERT IGNORE INTO t_kds_v2_command_archive"),
                (Object[]) any());
        verify(jdbc).update(contains("DELETE FROM t_kds_v2_command"),
                (Object[]) any());
    }

    @Test
    void archiveTerminalCommandsReturnsZeroWhenNoDueCommands() {
        when(jdbc.queryForList(anyString(), eq(String.class), eq(7), eq(7), eq(100)))
                .thenReturn(Collections.emptyList());

        int archived = service.archiveTerminalCommands(7, 7, 100);
        assertEquals(0, archived);
    }

    @Test
    void archiveTerminalCommandsAllShopsIteratesOverActiveShops() {
        when(jdbc.queryForList(contains("SELECT DISTINCT shop_id"), eq(Integer.class)))
                .thenReturn(Arrays.asList(1, 2));
        when(jdbc.queryForList(anyString(), eq(String.class), eq(1), eq(7), eq(500)))
                .thenReturn(Collections.singletonList("cmd-shop1"));
        when(jdbc.queryForList(anyString(), eq(String.class), eq(2), eq(7), eq(500)))
                .thenReturn(Collections.emptyList());
        when(jdbc.update(contains("DELETE FROM t_kds_v2_command"), (Object[]) any()))
                .thenReturn(1);

        int total = service.archiveTerminalCommandsAllShops(7, 500);
        assertEquals(1, total);
    }

    @Test
    void archivePrunedEventsCopiesEventsToArchiveAndDeletesFromHotTable() {
        when(jdbc.queryForList(anyString(), eq(Long.class), eq(7), eq(1000L), eq(100)))
                .thenReturn(Arrays.asList(900L, 901L));
        when(jdbc.update(contains("INSERT IGNORE INTO t_kds_v2_event_archive"), (Object[]) any()))
                .thenReturn(2);
        when(jdbc.update(contains("DELETE FROM t_kds_v2_event"), (Object[]) any()))
                .thenReturn(2);

        int count = service.archivePrunedEvents(7, 1000L, 100);
        assertEquals(2, count);

        verify(jdbc).update(contains("INSERT IGNORE INTO t_kds_v2_event_archive"),
                (Object[]) any());
        verify(jdbc).update(contains("DELETE FROM t_kds_v2_event"),
                (Object[]) any());
    }
}
