package com.lanf.database;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsCloudAuthorityFailClosedSchemaMigrationTest {

    @Test
    void exposesVersionedResourceAndStableSha256Checksum() throws Exception {
        assertEquals(
                "db/migration/V010__kds_cloud_authority_fail_closed.sql",
                KdsCloudAuthorityFailClosedSchemaMigration.RESOURCE);
        assertTrue(KdsCloudAuthorityFailClosedSchemaMigration.checksum()
                .matches("[0-9a-f]{64}"));
    }
}
