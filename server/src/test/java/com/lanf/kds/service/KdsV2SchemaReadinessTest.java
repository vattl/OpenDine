package com.lanf.kds.service;

import com.lanf.database.KdsCloudAuthorityFailClosedSchemaMigration;
import com.lanf.database.KdsDevicePairingSchemaMigration;
import com.lanf.database.KdsV2RetentionArchiveSchemaMigration;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class KdsV2SchemaReadinessTest {

    @Test
    void acceptsRequiredInnoDbTablesAndIndexes() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString())).thenReturn(Collections.emptyList());
        when(jdbc.queryForList(contains("version='V010'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsCloudAuthorityFailClosedSchemaMigration.checksum()));
        when(jdbc.queryForList(contains("version='V011'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsDevicePairingSchemaMigration.checksum()));
        when(jdbc.queryForList(contains("version='V012'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsV2RetentionArchiveSchemaMigration.checksum()));
        when(jdbc.queryForObject(contains("STATISTICS"), eq(Integer.class), anyString(), anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(contains("TABLES"), eq(String.class), anyString()))
                .thenReturn("InnoDB");

        assertDoesNotThrow(() -> new KdsV2SchemaReadiness(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
    }

    @Test
    void failsStartupWhenMigrationWasNotApplied() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString())).thenThrow(new RuntimeException("missing table"));

        assertThrows(IllegalStateException.class, () -> new KdsV2SchemaReadiness(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
    }

    @Test
    void failsStartupWhenV010MarkerIsMissing() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString())).thenReturn(Collections.emptyList());
        when(jdbc.queryForObject(contains("STATISTICS"), eq(Integer.class), anyString(), anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(contains("TABLES"), eq(String.class), anyString()))
                .thenReturn("InnoDB");

        assertThrows(IllegalStateException.class, () -> new KdsV2SchemaReadiness(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
    }

    @Test
    void failsStartupWhenV011MarkerIsMissing() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString())).thenReturn(Collections.emptyList());
        when(jdbc.queryForList(contains("version='V010'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsCloudAuthorityFailClosedSchemaMigration.checksum()));
        when(jdbc.queryForObject(contains("STATISTICS"), eq(Integer.class), anyString(), anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(contains("TABLES"), eq(String.class), anyString()))
                .thenReturn("InnoDB");

        assertThrows(IllegalStateException.class, () -> new KdsV2SchemaReadiness(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
    }

    @Test
    void failsStartupWhenV012MarkerIsMissing() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString())).thenReturn(Collections.emptyList());
        when(jdbc.queryForList(contains("version='V010'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsCloudAuthorityFailClosedSchemaMigration.checksum()));
        when(jdbc.queryForList(contains("version='V011'"), eq(String.class)))
                .thenReturn(Collections.singletonList(
                        KdsDevicePairingSchemaMigration.checksum()));
        when(jdbc.queryForObject(contains("STATISTICS"), eq(Integer.class), anyString(), anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(contains("TABLES"), eq(String.class), anyString()))
                .thenReturn("InnoDB");

        assertThrows(IllegalStateException.class, () -> new KdsV2SchemaReadiness(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
    }
}
