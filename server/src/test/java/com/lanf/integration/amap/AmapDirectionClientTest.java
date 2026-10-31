package com.lanf.integration.amap;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class AmapDirectionClientTest {

    @Test
    void parseDrivingV3_success() throws Exception {
        String json = "{\"status\":\"1\",\"route\":{\"paths\":[{\"distance\":\"3250\"}]}}";
        Double km = AmapDirectionClient.parseDrivingV3(json);
        assertNotNull(km);
        assertEquals(3.25, km, 0.001);
    }

    @Test
    void parseDrivingV3_failStatus() throws Exception {
        assertNull(AmapDirectionClient.parseDrivingV3("{\"status\":\"0\"}"));
    }
}
