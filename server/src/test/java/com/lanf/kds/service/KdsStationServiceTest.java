package com.lanf.kds.service;

import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.mapper.KdsDishScreenMapper;
import com.lanf.kds.mapper.KdsStationCategoryMapper;
import com.lanf.kds.mapper.KdsStationMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * KdsStationService.save code 兜底逻辑：修复 t_kds_station.code NOT NULL 无默认值
 * 导致 station/save 500（Field 'code' doesn't have a default value）。
 */
@ExtendWith(MockitoExtension.class)
class KdsStationServiceTest {

    @Mock
    private KdsStationMapper stationMapper;
    @Mock
    private KdsStationCategoryMapper stationCategoryMapper;
    @Mock
    private KdsDishScreenMapper dishScreenMapper;
    @InjectMocks
    private KdsStationService service;

    @Test
    @DisplayName("新增未传 code：标准五屏自动生成预设编码")
    void saveWithoutCodeGeneratesSeedCodeForStandardScreen() {
        KdsStation station = new KdsStation();
        station.setScreen_tag("meat_grill");
        station.setName("荤菜烤制屏");
        when(stationMapper.insert(any())).thenReturn(1);
        when(stationMapper.selectById(any())).thenReturn(station);
        KdsStation saved = service.save(5, station);
        assertEquals("MEAT", saved.getCode());
    }

    @Test
    @DisplayName("新增未传 code：非标准屏用 screen_tag 大写")
    void saveWithoutCodeUsesScreenTagUppercase() {
        KdsStation station = new KdsStation();
        station.setScreen_tag("workflow_board");
        when(stationMapper.insert(any())).thenReturn(1);
        when(stationMapper.selectById(any())).thenReturn(station);
        KdsStation saved = service.save(5, station);
        assertEquals("WORKFLOWBOARD", saved.getCode());
    }

    @Test
    @DisplayName("更新未传 code：保留原 code 不覆盖")
    void updateWithoutCodeKeepsExistingCode() {
        KdsStation station = new KdsStation();
        station.setId(10L);
        KdsStation existing = new KdsStation();
        existing.setId(10L);
        existing.setShop_id(5);
        existing.setCode("ORIGINAL");
        when(stationMapper.selectById(10L)).thenReturn(existing);
        service.save(5, station);
        assertEquals("ORIGINAL", station.getCode());
        verify(stationMapper).updateById(station);
    }

    @Test
    @DisplayName("defaultCode 映射与兜底")
    void defaultCodeMapping() {
        assertEquals("MEAT", KdsStationService.defaultCode("meat_grill", null));
        assertEquals("EXP", KdsStationService.defaultCode("expedition", null));
        assertEquals("WORKFLOWBOARD", KdsStationService.defaultCode("workflow_board", null));
        assertEquals("AB1", KdsStationService.defaultCode(null, "AB1 档口"));
        assertThrows(IllegalArgumentException.class, () -> KdsStationService.defaultCode(null, "中文名"));
        assertThrows(IllegalArgumentException.class, () -> KdsStationService.defaultCode(null, null));
    }
}
