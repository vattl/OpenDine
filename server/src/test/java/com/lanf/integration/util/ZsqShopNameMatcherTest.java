package com.lanf.integration.util;

import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.dto.ZsqShopAddress;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ZsqShopNameMatcherTest {

    private static final double BASE_LAT = 22.5787;
    private static final double BASE_LNG = 113.0819;
    /** 约 11 米 */
    private static final double NEAR_LAT = 22.5788;
    /** 约 111 米 */
    private static final double FAR_LAT = 22.5797;

    private static ZsqShopAddress shop(long id, String name) {
        return shop(id, name, null, null);
    }

    private static ZsqShopAddress shop(long id, String name, String lat, String lng) {
        ZsqShopAddress s = new ZsqShopAddress();
        s.setId(id);
        s.setShopName(name);
        s.setShopLat(lat);
        s.setShopLng(lng);
        return s;
    }

    @Test
    void normalize_stripsWhitespace() {
        assertEquals("江门旗舰店", ZsqShopNameMatcher.normalize(" 江门 旗舰\u3000店 "));
    }

    @Test
    void pickByShopName_exactMatch() {
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Arrays.asList(shop(1L, "江门旗舰店"), shop(2L, "开平分店")),
                "江门旗舰店");
        assertEquals(1L, matched.getId());
    }

    @Test
    void pickByShopName_exactMatchIgnoresSpaces() {
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(3L, "江门 旗舰 店")),
                "江门旗舰店");
        assertEquals(3L, matched.getId());
    }

    @Test
    void pickByShopName_fuzzyContainsWhenUnique() {
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(4L, "江门市XX餐厅旗舰店")),
                "XX餐厅");
        assertEquals(4L, matched.getId());
    }

    @Test
    void pickByShopName_noMatchReturnsNull() {
        assertNull(ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(5L, "A店")),
                "B店"));
    }

    @Test
    void pickByShopName_ambiguousThrowsWithoutCoords() {
        assertThrows(ZsqApiException.class, () -> ZsqShopNameMatcher.pickByShopName(
                Arrays.asList(shop(6L, "XX餐厅江门店"), shop(7L, "XX餐厅开平店")),
                "XX餐厅"));
    }

    @Test
    void pickByShopName_locationWithin50m() {
        double[] bdNear = gcj02ToBd09(NEAR_LAT, BASE_LNG);
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(8L, "江门旗舰店",
                        String.valueOf(bdNear[0]), String.valueOf(bdNear[1]))),
                "江门旗舰店",
                BASE_LAT,
                BASE_LNG);
        assertEquals(8L, matched.getId());
    }

    @Test
    void pickByShopName_locationBeyond50mThrows() {
        double[] bdFar = gcj02ToBd09(FAR_LAT, BASE_LNG);
        assertThrows(ZsqApiException.class, () -> ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(9L, "江门旗舰店",
                        String.valueOf(bdFar[0]), String.valueOf(bdFar[1]))),
                "江门旗舰店",
                BASE_LAT,
                BASE_LNG));
    }

    @Test
    void pickByShopName_locationDisambiguatesSameName() {
        double[] bdFar = gcj02ToBd09(FAR_LAT, BASE_LNG);
        double[] bdNear = gcj02ToBd09(NEAR_LAT, BASE_LNG);
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Arrays.asList(
                        shop(10L, "XX餐厅", String.valueOf(bdFar[0]), String.valueOf(bdFar[1])),
                        shop(11L, "XX餐厅", String.valueOf(bdNear[0]), String.valueOf(bdNear[1]))),
                "XX餐厅",
                BASE_LAT,
                BASE_LNG);
        assertEquals(11L, matched.getId());
    }

    @Test
    void pickByShopName_acceptsBaiduCoordsAfterConversion() {
        double[] bd = gcj02ToBd09(BASE_LAT, BASE_LNG);
        ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                Collections.singletonList(shop(12L, "江门旗舰店",
                        String.valueOf(bd[0]), String.valueOf(bd[1]))),
                "江门旗舰店",
                BASE_LAT,
                BASE_LNG);
        assertEquals(12L, matched.getId());
    }

    /** 测试用：GCJ-02 → BD-09，模拟真省钱侧坐标。 */
    private static double[] gcj02ToBd09(double lat, double lng) {
        double z = Math.sqrt(lng * lng + lat * lat) + 0.00002 * Math.sin(lat * Math.PI * 3000.0 / 180.0);
        double theta = Math.atan2(lat, lng) + 0.000003 * Math.cos(lng * Math.PI * 3000.0 / 180.0);
        double bdLng = z * Math.cos(theta) + 0.0065;
        double bdLat = z * Math.sin(theta) + 0.006;
        return new double[]{bdLat, bdLng};
    }
}
