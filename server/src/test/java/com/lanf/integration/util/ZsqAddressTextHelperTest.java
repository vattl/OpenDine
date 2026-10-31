package com.lanf.integration.util;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ZsqAddressTextHelperTest {

    @Test
    void buildKeywordsFromPoiStyleDetail() {
        String detail = "鹤山碧桂园花岸 · 鹤山碧桂园花岸 凤盈西街与前进南路交叉口正南方向323米左右 18街8号608房";
        String kw = ZsqAddressTextHelper.buildKeywords("鹤山市", detail, null);
        assertTrue(kw.contains("鹤山碧桂园花岸"));
        assertTrue(kw.length() <= 48);
    }

    @Test
    void buildDetailExtractsRoom() {
        String detail = "鹤山碧桂园花岸 · 鹤山碧桂园花岸 凤盈西街与前进南路交叉口正南方向323米左右 18街8号608房";
        assertEquals("18街8号608房", ZsqAddressTextHelper.buildDetail(detail, null));
    }

    @Test
    void preservesRoadDoorplateAndDeliveryNoteFromSavedAddress() {
        String detail = "鹤山市人民政府·沙坪街道前进路18号 门牌：3栋1001 配送说明：2号门进";

        assertEquals("鹤山市沙坪街道前进路18号·鹤山市人民政府",
                ZsqAddressTextHelper.buildKeywords("鹤山市", detail, null));
        assertEquals("3栋1001；配送说明：2号门进",
                ZsqAddressTextHelper.buildDetail(detail, null));
    }

    @Test
    void resolveCityPrefersCountyFromDistrict() {
        assertEquals("鹤山市", ZsqAddressTextHelper.resolveCityName(null, "江门市", "鹤山市", "江门市"));
    }

    @Test
    void keywordAttemptsIncludeVariants() {
        String raw = "鹤山碧桂园花岸 · 鹤山碧桂园花岸 凤盈西街与前进南路交叉口正南方向323米左右 18街8号608房";
        List<String> attempts = ZsqAddressTextHelper.keywordAttempts(raw);
        assertTrue(attempts.size() >= 2);
        assertTrue(attempts.stream().anyMatch(s -> s.contains("鹤山碧桂园花岸")));
    }
}
