package com.lanf.kds.delivery;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class CashierKdsProjectionIntentReadinessTest {
    @Test void missingSchemaOrIndexAndNonTransactionalEngineFailStartup() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        CashierKdsProjectionIntentReadiness guard = new CashierKdsProjectionIntentReadiness(jdbc);
        assertThrows(IllegalStateException.class, () -> guard.run(null));
        when(jdbc.queryForObject(anyString(), eq(Integer.class), anyString())).thenReturn(1);
        when(jdbc.queryForObject(anyString(), eq(String.class))).thenReturn("MyISAM");
        assertThrows(IllegalStateException.class, () -> guard.run(null));
        when(jdbc.queryForObject(anyString(), eq(String.class))).thenReturn("InnoDB");
        assertDoesNotThrow(() -> guard.run(null));
        verify(jdbc, never()).execute(anyString());
    }
}
