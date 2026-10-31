package com.lanf.kds.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D026：设备可见岗存储（t_kds_device_screen）读写与三岗过滤。
 */
class KdsDeviceScreenStoreTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final KdsDeviceScreenStore store = new KdsDeviceScreenStore(jdbc);

    @Test
    @DisplayName("无记录返回空列表（调用方回默认三岗）")
    void getWithoutRowReturnsEmpty() {
        when(jdbc.queryForList("SELECT screen_tags FROM t_kds_device_screen WHERE device_id=?", String.class, 5L))
                .thenReturn(Collections.emptyList());
        assertTrue(store.get(5L).isEmpty());
    }

    @Test
    @DisplayName("get 解析逗号分隔并过滤三岗")
    void getParsesCsvAndNormalizes() {
        when(jdbc.queryForList("SELECT screen_tags FROM t_kds_device_screen WHERE device_id=?", String.class, 7L))
                .thenReturn(Collections.singletonList("meat_grill,workflow_board,veg_grill"));
        List<String> tags = store.get(7L);
        assertEquals(Arrays.asList("meat_grill", "veg_grill"), tags);
    }

    @Test
    @DisplayName("save 写入去重后的三岗子集")
    void saveWritesNormalizedCsv() {
        store.save(9L, Arrays.asList("veg_grill", "meat_grill", "veg_grill", "expedition"));
        verify(jdbc).update(
                "INSERT INTO t_kds_device_screen(device_id, screen_tags) VALUES (?,?) "
                        + "ON DUPLICATE KEY UPDATE screen_tags=VALUES(screen_tags)",
                9L, "veg_grill,meat_grill");
    }

    @Test
    @DisplayName("save 全非法/空 → 删除记录（回默认三岗）")
    void saveInvalidDeletesRow() {
        store.save(9L, Arrays.asList("workflow_board", "expedition"));
        store.save(9L, Collections.emptyList());
        verify(jdbc, times(2)).update("DELETE FROM t_kds_device_screen WHERE device_id=?", 9L);
    }

    @Test
    @DisplayName("normalizeList 纯逻辑：去重、非法忽略、保序")
    void normalizeListFilters() {
        assertEquals(Collections.emptyList(), KdsDeviceScreenStore.normalizeList(null));
        assertEquals(Collections.emptyList(), KdsDeviceScreenStore.normalizeList(Collections.emptyList()));
        assertEquals(Collections.emptyList(), KdsDeviceScreenStore.normalizeList(Arrays.asList("expedition", "boss_overview")));
        assertEquals(Arrays.asList("meat_grill", "seafood_special"),
                KdsDeviceScreenStore.normalizeList(Arrays.asList("meat_grill", "x", "seafood_special", "meat_grill")));
    }
}
