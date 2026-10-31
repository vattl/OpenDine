package com.lanf.database;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsDevicePairingSchemaMigrationTest {

    @Test
    void exposesVersionedResourceAndStableSha256Checksum() throws Exception {
        assertEquals("db/migration/V011__kds_device_pairing_ticket.sql",
                KdsDevicePairingSchemaMigration.RESOURCE);
        assertTrue(KdsDevicePairingSchemaMigration.checksum().matches("[0-9a-f]{64}"));
    }
}
