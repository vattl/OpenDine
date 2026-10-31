package com.lanf.config;

import com.lanf.Application;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.annotation.MapperScan;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ApplicationMapperScanTest {

    @Test
    void applicationScansAiMapperPackage() {
        MapperScan mapperScan = Application.class.getAnnotation(MapperScan.class);

        assertNotNull(mapperScan, "Application must declare the authoritative MyBatis mapper scan");
        assertTrue(Arrays.asList(mapperScan.value()).contains("com.lanf.ai.mapper"),
                "AI mapper package must be registered so AI services can start");
    }
}
