package com.lanf.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CoordinateNormalizerTest {

    @Test
    void gcj02CoordinatesRemainUnchanged() {
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                22.578738, 113.081901, "gcj02");

        assertEquals(22.578738, point.getLat(), 0.0000001);
        assertEquals(113.081901, point.getLng(), 0.0000001);
    }

    @Test
    void convertsBd09ToGcj02() {
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                39.915166, 116.403842, "bd09");

        assertEquals(39.908823, point.getLat(), 0.0005);
        assertEquals(116.397470, point.getLng(), 0.0005);
    }

    @Test
    void convertsWgs84ToGcj02InsideChina() {
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                39.907500, 116.391289, "wgs84");

        assertEquals(39.908901, point.getLat(), 0.0005);
        assertEquals(116.397531, point.getLng(), 0.0005);
    }

    @Test
    void rejectsUnknownCoordinateType() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> CoordinateNormalizer.toGcj02(22.5, 113.0, "map-x"));

        assertTrue(error.getMessage().contains("坐标系"));
    }

    @Test
    void rejectsInvalidCoordinateRange() {
        assertThrows(IllegalArgumentException.class,
                () -> CoordinateNormalizer.toGcj02(113.0, 22.5, "gcj02"));
    }

    @Test
    void bd09InputRemainsUnchangedAtBd09OutboundBoundary() {
        CoordinateNormalizer.Point point = CoordinateNormalizer.toBd09(
                22.771679, 112.970730, "bd09");

        assertEquals(22.771679, point.getLat(), 0.000000001);
        assertEquals(112.970730, point.getLng(), 0.000000001);
    }
}
