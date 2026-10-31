package com.lanf.integration.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ZsqGeoUtilsTest {

    /** 天安门 GCJ-02 与 BD-09 参考点（公开坐标）。 */
    private static final double GCJ_LAT = 39.908823;
    private static final double GCJ_LNG = 116.397470;
    private static final double BD_LAT = 39.915119;
    private static final double BD_LNG = 116.403963;

    @Test
    void bd09ToGcj02_convertsKnownPointWithin50m() {
        double[] gcj = ZsqGeoUtils.bd09ToGcj02(BD_LAT, BD_LNG);
        double meters = ZsqGeoUtils.haversineMeters(GCJ_LAT, GCJ_LNG, gcj[0], gcj[1]);
        assertTrue(meters < 50.0, "expected <50m but was " + meters);
    }
}
