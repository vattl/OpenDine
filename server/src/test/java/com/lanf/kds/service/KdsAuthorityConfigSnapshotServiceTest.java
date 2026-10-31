package com.lanf.kds.service;

import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class KdsAuthorityConfigSnapshotServiceTest {
    @Test
    void versionMaterialExcludesResponseVersionAndVolatileTimestamps() {
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("version", 9L);
        snapshot.put("updated_at", "volatile");
        snapshot.put("catalog", java.util.Collections.singletonList(java.util.Collections.singletonMap("dish_id", 1)));
        snapshot.put("routing", java.util.Collections.emptyList());
        snapshot.put("workflow", java.util.Collections.emptyMap());
        snapshot.put("sla", java.util.Collections.emptyMap());
        snapshot.put("fixed_order", java.util.Collections.singletonList(1));
        snapshot.put("cashier_authority", java.util.Collections.singletonMap("cashier_device_code", "pos-1"));

        Map<String, Object> material = KdsAuthorityConfigSnapshotService.versionMaterial(snapshot);

        assertFalse(material.containsKey("version"));
        assertFalse(material.containsKey("updated_at"));
        assertEquals(6, material.size());
        assertTrue(material.containsKey("cashier_authority"));
    }

    @Test
    void snapshotAndAuthorityWritesAreTransactionalForVersionSerialization() throws Exception {
        Method snapshot = KdsAuthorityConfigSnapshotService.class.getMethod("snapshot", int.class);
        Method setAuthority = KdsAuthorityConfigSnapshotService.class.getMethod("setAuthorityDevice", int.class, String.class);
        assertNotNull(snapshot.getAnnotation(Transactional.class));
        assertNotNull(setAuthority.getAnnotation(Transactional.class));
    }
}
