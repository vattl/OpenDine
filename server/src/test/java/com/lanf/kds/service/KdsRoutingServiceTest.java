package com.lanf.kds.service;

import com.lanf.entity.OrderDetail;
import com.lanf.kds.entity.KdsDishScreen;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.mapper.KdsDishScreenMapper;
import com.lanf.kds.mapper.KdsStationCategoryMapper;
import com.lanf.service.IDishService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class KdsRoutingServiceTest {

    private KdsRoutingService service;
    private KdsDishScreenMapper dishScreenMapper;
    private KdsStationService stationService;
    private IDishService dishService;

    @BeforeEach
    void setUp() {
        service = new KdsRoutingService();
        dishScreenMapper = mock(KdsDishScreenMapper.class);
        stationService = mock(KdsStationService.class);
        dishService = mock(IDishService.class);
        ReflectionTestUtils.setField(service, "dishScreenMapper", dishScreenMapper);
        ReflectionTestUtils.setField(service, "stationCategoryMapper", mock(KdsStationCategoryMapper.class));
        ReflectionTestUtils.setField(service, "stationService", stationService);
        ReflectionTestUtils.setField(service, "configService", mock(KdsConfigService.class));
        ReflectionTestUtils.setField(service, "dishService", dishService);
    }

    @Test
    void comboHeaderIsGroupingOnlyAndDoesNotCreateProductionTicket() {
        OrderDetail header = new OrderDetail();
        header.setLine_type("combo_header");
        header.setDish_id(100);
        header.setName("双人套餐");

        assertNull(service.resolve(7, header));
        verifyNoInteractions(dishScreenMapper, stationService, dishService);
    }

    @Test
    void comboComponentRoutesByStoredDishId() {
        OrderDetail component = new OrderDetail();
        component.setLine_type("combo_component");
        component.setDish_id(201);
        component.setName("烤羊肉串");

        KdsDishScreen mapping = new KdsDishScreen();
        mapping.setShop_id(7);
        mapping.setDish_id(201);
        mapping.setScreen_tag("meat_grill");
        when(dishScreenMapper.selectOne(any())).thenReturn(mapping);

        KdsStation station = new KdsStation();
        station.setId(31L);
        station.setShop_id(7);
        station.setScreen_tag("meat_grill");
        station.setEnabled(1);
        when(stationService.findByScreenTag(7, "meat_grill")).thenReturn(station);

        KdsRoutingService.RouteTarget target = service.resolve(7, component);

        assertNotNull(target);
        assertEquals("meat_grill", target.screenTag);
        assertEquals(31L, target.stationId);
        verifyNoInteractions(dishService);
    }
}
