package com.lanf.kds;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsFlowBatch;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsDeviceMapper;
import com.lanf.kds.mapper.KdsFlowBatchMapper;
import com.lanf.kds.mapper.KdsShopConfigMapper;
import com.lanf.kds.mapper.KdsStationMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsFlowBatchService;
import com.lanf.kds.service.KdsOrderStatusAggregator;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class KdsPrepWorkflowToggleTest {

    @Test
    void workflowResolution_whenPrepDisabled_excludesPrep() {
        KdsDevice device = new KdsDevice();
        device.setScreen_tag(KdsScreenTag.WORKFLOW_BOARD);

        // Prep disabled
        List<String> workflowsDisabled = KdsWorkflow.resolveForDevice(device, false);
        assertEquals(Arrays.asList("cook", "serve"), workflowsDisabled);
        assertFalse(workflowsDisabled.contains("prep"));

        List<String> queuesDisabled = KdsWorkflow.visibleQueues(device, false);
        assertEquals(Arrays.asList("pending_cook", "ready_serve", "done"), queuesDisabled);
        assertFalse(queuesDisabled.contains("pending_prep"));

        assertFalse(KdsWorkflow.canAccessQueue(device, "pending_prep", false));
        assertTrue(KdsWorkflow.canAccessQueue(device, "pending_cook", false));
        assertTrue(KdsWorkflow.canAccessQueue(device, "ready_serve", false));

        // Prep enabled
        List<String> workflowsEnabled = KdsWorkflow.resolveForDevice(device, true);
        assertEquals(Arrays.asList("prep", "cook", "serve"), workflowsEnabled);
        assertTrue(workflowsEnabled.contains("prep"));

        List<String> queuesEnabled = KdsWorkflow.visibleQueues(device, true);
        assertEquals(Arrays.asList("pending_prep", "pending_cook", "ready_serve", "done"), queuesEnabled);
        assertTrue(queuesEnabled.contains("pending_prep"));

        assertTrue(KdsWorkflow.canAccessQueue(device, "pending_prep", true));
    }

    @Test
    void configService_prepWorkflowEnabledHierarchy() {
        KdsConfigService configService = new KdsConfigService();
        KdsShopConfigMapper shopMapper = mock(KdsShopConfigMapper.class);
        KdsStationMapper stationMapper = mock(KdsStationMapper.class);
        ReflectionTestUtils.setField(configService, "shopConfigMapper", shopMapper);
        ReflectionTestUtils.setField(configService, "stationMapper", stationMapper);

        KdsShopConfig shopCfg = new KdsShopConfig();
        shopCfg.setShop_id(1);
        shopCfg.setEnable_prep_workflow(0);
        when(shopMapper.selectById(1)).thenReturn(shopCfg);

        // 1. Shop disabled, no station -> false
        assertFalse(configService.isPrepWorkflowEnabled(1));
        assertFalse(configService.isPrepWorkflowEnabled(1, null));

        // 2. Station explicitly enabled -> overrides shop -> true
        KdsStation station1 = new KdsStation();
        station1.setId(10L);
        station1.setEnable_prep_workflow(1);
        when(stationMapper.selectById(10L)).thenReturn(station1);
        assertTrue(configService.isPrepWorkflowEnabled(1, 10L));

        // 3. Shop enabled, Station explicitly disabled -> overrides shop -> false
        shopCfg.setEnable_prep_workflow(1);
        KdsStation station2 = new KdsStation();
        station2.setId(20L);
        station2.setEnable_prep_workflow(0);
        when(stationMapper.selectById(20L)).thenReturn(station2);
        assertFalse(configService.isPrepWorkflowEnabled(1, 20L));

        // 4. Station null -> inherits shop enabled -> true
        KdsStation station3 = new KdsStation();
        station3.setId(30L);
        station3.setEnable_prep_workflow(null);
        when(stationMapper.selectById(30L)).thenReturn(station3);
        assertTrue(configService.isPrepWorkflowEnabled(1, 30L));
    }

    @Test
    void deviceService_enrichWorkflowsRespectsPrepDisabled() {
        KdsDeviceService deviceService = new KdsDeviceService();
        ReflectionTestUtils.setField(deviceService,"workflowStore",mock(com.lanf.kds.service.KdsWorkflowStore.class));
        KdsConfigService configService = mock(KdsConfigService.class);
        KdsDeviceMapper deviceMapper = mock(KdsDeviceMapper.class);
        ReflectionTestUtils.setField(deviceService, "configService", configService);
        ReflectionTestUtils.setField(deviceService, "deviceMapper", deviceMapper);

        when(configService.isPrepWorkflowEnabled(1, null)).thenReturn(false);

        KdsDevice device = new KdsDevice();
        device.setId(100L);
        device.setShop_id(1);
        device.setScreen_tag(KdsScreenTag.WORKFLOW_BOARD);

        KdsDevice enriched = deviceService.enrichWorkflows(device);
        assertNotNull(enriched);
        assertEquals(Arrays.asList("cook", "serve"), enriched.getWorkflows());
        assertFalse(enriched.getWorkflows().contains("prep"));
    }

    @Test
    void flowBatchService_initForTicket_whenPrepDisabled_startsAtPendingCook() {
        KdsFlowBatchService flowBatchService = new KdsFlowBatchService();
        KdsFlowBatchMapper batchMapper = mock(KdsFlowBatchMapper.class);
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        KdsConfigService configService = mock(KdsConfigService.class);
        KdsOrderStatusAggregator aggregator = mock(KdsOrderStatusAggregator.class);

        ReflectionTestUtils.setField(flowBatchService, "batchMapper", batchMapper);
        ReflectionTestUtils.setField(flowBatchService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(flowBatchService, "configService", configService);
        ReflectionTestUtils.setField(flowBatchService, "orderStatusAggregator", aggregator);

        when(configService.isPrepWorkflowEnabled(1, 10L)).thenReturn(false);
        when(batchMapper.selectCount(any())).thenReturn(0);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(500L);
        ticket.setShop_id(1);
        ticket.setStation_id(10L);
        ticket.setDetail_id(101);
        ticket.setOrder_id(201);
        ticket.setOrder_no("ORD-001");
        ticket.setPrep_quantity(3);
        ticket.setCooked_quantity(0);
        ticket.setServed_quantity(0);
        when(ticketMapper.selectById(500L)).thenReturn(ticket);

        KdsFlowBatch mockBatch = new KdsFlowBatch();
        mockBatch.setId(1L);
        mockBatch.setTicket_id(500L);
        mockBatch.setQuantity(3);
        mockBatch.setQueue_status(KdsFlowBatchStatus.PENDING_COOK);
        mockBatch.setPrep_at(new Date());
        when(batchMapper.selectList(any())).thenReturn(Collections.singletonList(mockBatch));

        Order order = new Order();
        order.setId(201);
        order.setDineInOrTakeOut("堂食");

        OrderDetail detail = new OrderDetail();
        detail.setId(101);
        detail.setQuantity("3");

        flowBatchService.initForTicket(ticket, order, detail, 3);

        ArgumentCaptor<KdsFlowBatch> batchCaptor = ArgumentCaptor.forClass(KdsFlowBatch.class);
        verify(batchMapper).insert(batchCaptor.capture());
        KdsFlowBatch inserted = batchCaptor.getValue();

        assertEquals(KdsFlowBatchStatus.PENDING_COOK, inserted.getQueue_status());
        assertNotNull(inserted.getPrep_at());
        assertEquals(3, inserted.getQuantity());

        // Verify remaining calculation after ticket aggregates sync
        assertEquals(3, ticket.getPrep_quantity());
        assertEquals(0, ticket.getCooked_quantity());
        assertEquals(0, KdsTicketQuantityUtil.prepRemaining(ticket, 3));
        assertEquals(3, KdsTicketQuantityUtil.cookRemaining(ticket, 3));
    }

    @Test
    void flowBatchService_initForTicket_whenPrepEnabled_startsAtPendingPrep() {
        KdsFlowBatchService flowBatchService = new KdsFlowBatchService();
        KdsFlowBatchMapper batchMapper = mock(KdsFlowBatchMapper.class);
        KdsTicketMapper ticketMapper = mock(KdsTicketMapper.class);
        KdsConfigService configService = mock(KdsConfigService.class);
        KdsOrderStatusAggregator aggregator = mock(KdsOrderStatusAggregator.class);

        ReflectionTestUtils.setField(flowBatchService, "batchMapper", batchMapper);
        ReflectionTestUtils.setField(flowBatchService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(flowBatchService, "configService", configService);
        ReflectionTestUtils.setField(flowBatchService, "orderStatusAggregator", aggregator);

        when(configService.isPrepWorkflowEnabled(1, 10L)).thenReturn(true);
        when(batchMapper.selectCount(any())).thenReturn(0);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(501L);
        ticket.setShop_id(1);
        ticket.setStation_id(10L);
        ticket.setDetail_id(102);
        ticket.setOrder_id(202);
        ticket.setOrder_no("ORD-002");
        ticket.setPrep_quantity(0);
        ticket.setCooked_quantity(0);
        ticket.setServed_quantity(0);
        when(ticketMapper.selectById(501L)).thenReturn(ticket);

        KdsFlowBatch mockBatch = new KdsFlowBatch();
        mockBatch.setId(2L);
        mockBatch.setTicket_id(501L);
        mockBatch.setQuantity(2);
        mockBatch.setQueue_status(KdsFlowBatchStatus.PENDING_PREP);
        when(batchMapper.selectList(any())).thenReturn(Collections.singletonList(mockBatch));

        Order order = new Order();
        order.setId(202);
        order.setDineInOrTakeOut("堂食");

        OrderDetail detail = new OrderDetail();
        detail.setId(102);
        detail.setQuantity("2");

        flowBatchService.initForTicket(ticket, order, detail, 2);

        ArgumentCaptor<KdsFlowBatch> batchCaptor = ArgumentCaptor.forClass(KdsFlowBatch.class);
        verify(batchMapper).insert(batchCaptor.capture());
        KdsFlowBatch inserted = batchCaptor.getValue();

        assertEquals(KdsFlowBatchStatus.PENDING_PREP, inserted.getQueue_status());
        assertNull(inserted.getPrep_at());
        assertEquals(2, inserted.getQuantity());

        // Verify remaining calculation after ticket aggregates sync
        assertEquals(0, ticket.getPrep_quantity());
        assertEquals(0, ticket.getCooked_quantity());
        assertEquals(2, KdsTicketQuantityUtil.prepRemaining(ticket, 2));
        assertEquals(0, KdsTicketQuantityUtil.cookRemaining(ticket, 2));
    }
}
