package com.lanf.kds.replication;

import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsReplicationSchemaReadinessValidatorTest {
    @Test
    void readySchemaAllowsStartupWithoutExecutingDdl() {
        RecordingJdbcTemplate jdbc = new RecordingJdbcTemplate(null);
        assertDoesNotThrow(() -> new KdsReplicationSchemaReadinessValidator(jdbc)
                .run(new DefaultApplicationArguments(new String[0])));
        assertTrue(jdbc.onlyReadInformationSchema);
    }

    @Test
    void missingFingerprintColumnFailsFastWithMigrationInstructions() {
        RecordingJdbcTemplate jdbc = new RecordingJdbcTemplate("request_fingerprint");
        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> new KdsReplicationSchemaReadinessValidator(jdbc)
                        .run(new DefaultApplicationArguments(new String[0])));
        assertTrue(error.getMessage().contains("t_kds_replication_event.request_fingerprint"));
        assertTrue(error.getMessage().contains("db_migration_kds_authority_v2.sql"));
    }

    private static final class RecordingJdbcTemplate extends JdbcTemplate {
        private final String missingName;
        private boolean onlyReadInformationSchema = true;
        private RecordingJdbcTemplate(String missingName) { this.missingName = missingName; }

        @Override
        public <T> T queryForObject(String sql, Class<T> requiredType, Object... args) {
            onlyReadInformationSchema &= sql.startsWith("SELECT COUNT(*) FROM information_schema.");
            int count = 1;
            for (Object arg : args) if (missingName != null && missingName.equals(arg)) count = 0;
            return requiredType.cast(count);
        }
    }
}
