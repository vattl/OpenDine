package com.lanf.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DebugProfileIsolationTest {

    private final List<PropertySource<?>> sources = loadDebugProfile();

    @Test
    void debugProfileUsesDedicatedLocalResources() {
        assertEquals("127.0.0.1", property("server.address"));
        assertEquals(18080, property("server.port"));
        assertFalse((Boolean) property("server.ssl.enabled"));
        assertTrue(String.valueOf(property("spring.datasource.url")).contains("127.0.0.1:3307/db_diancan_debug"));
        assertTrue(String.valueOf(property("qrcodeImgsFilePath")).contains("DEBUG_DATA_DIR"));
        assertEquals("http://127.0.0.1:18080", property("app.public-base-url"));
    }

    @Test
    void debugProfileDisablesBackgroundAndExternalWork() {
        assertFalse((Boolean) property("app.scheduling.enabled"));
        assertFalse((Boolean) property("zsq.auto-api-enabled"));
        assertFalse((Boolean) property("zsq.takeout-sync-enabled"));
        assertFalse((Boolean) property("stock-prep-forecast.scheduled-enabled"));
        assertFalse((Boolean) property("amap.route-distance-enabled"));
    }

    private Object property(String name) {
        for (PropertySource<?> source : sources) {
            Object value = source.getProperty(name);
            if (value != null) {
                return value;
            }
        }
        assertNotNull(null, "Missing debug property: " + name);
        return null;
    }

    private static List<PropertySource<?>> loadDebugProfile() {
        try {
            return new YamlPropertySourceLoader().load(
                    "debug-profile",
                    new ClassPathResource("application-debug.yml"));
        } catch (IOException e) {
            throw new AssertionError("Cannot load application-debug.yml", e);
        }
    }
}
