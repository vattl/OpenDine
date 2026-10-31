package com.lanf.database;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.Collections;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
class PaymentSchemaReadinessTest {
    @Test void missingMigrationRejectsStartupWithoutDdl() {
        JdbcTemplate jdbc=mock(JdbcTemplate.class);
        assertThrows(IllegalStateException.class,()->new PaymentSchemaReadiness(jdbc).verify());
        verify(jdbc,never()).execute(anyString());
    }
    @Test void validVersionStillProbesActualTablesReadOnly() throws Exception {
        JdbcTemplate jdbc=mock(JdbcTemplate.class);
        when(jdbc.queryForList(contains("t_app_schema_version"),eq(String.class)))
                .thenReturn(Collections.singletonList(AuditSchemaMigration.checksum()));
        new PaymentSchemaReadiness(jdbc).verify();
        verify(jdbc).queryForList(contains("FROM t_personal_payment_event WHERE 1=0"));
        verify(jdbc,never()).execute(anyString());
    }
}
