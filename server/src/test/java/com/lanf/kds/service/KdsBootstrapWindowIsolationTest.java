package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class KdsBootstrapWindowIsolationTest {

    private KdsWorkflowV2Service workflowV2Service;
    private KdsOverviewBoardService overviewBoardService;
    private KdsTicketMapper ticketMapper;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private IShopService shopService;
    private KdsDeviceService deviceService;
    private KdsConfigService configService;
    private IDishService dishService;
    private KdsStatsService statsService;
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        workflowV2Service = new KdsWorkflowV2Service();
        overviewBoardService = new KdsOverviewBoardService();

        ticketMapper = mock(KdsTicketMapper.class);
        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        shopService = mock(IShopService.class);
        deviceService = mock(KdsDeviceService.class);
        configService = mock(KdsConfigService.class);
        dishService = mock(IDishService.class);
        statsService = mock(KdsStatsService.class);
        jdbcTemplate = mock(JdbcTemplate.class);

        // Setup workflowV2Service
        ReflectionTestUtils.setField(workflowV2Service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(workflowV2Service, "orderService", orderService);
        ReflectionTestUtils.setField(workflowV2Service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(workflowV2Service, "shopService", shopService);
        ReflectionTestUtils.setField(workflowV2Service, "deviceService", deviceService);
        ReflectionTestUtils.setField(workflowV2Service, "configService", configService);
        ReflectionTestUtils.setField(workflowV2Service, "dishService", dishService);
        ReflectionTestUtils.setField(workflowV2Service, "statsService", statsService);
        ReflectionTestUtils.setField(workflowV2Service, "jdbc", jdbcTemplate);
        ReflectionTestUtils.setField(workflowV2Service, "overviewBoardService", overviewBoardService);

        // Setup overviewBoardService
        ReflectionTestUtils.setField(overviewBoardService, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(overviewBoardService, "orderService", orderService);
        ReflectionTestUtils.setField(overviewBoardService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(overviewBoardService, "shopService", shopService);
        ReflectionTestUtils.setField(overviewBoardService, "configService", configService);
        ReflectionTestUtils.setField(overviewBoardService, "dishService", dishService);
        ReflectionTestUtils.setField(overviewBoardService, "flowBatchService", mock(KdsFlowBatchService.class));
        ReflectionTestUtils.setField(overviewBoardService, "servingDurationService", mock(KdsDishServingDurationService.class));

        Shop shop = new Shop();
        shop.setId(1);
        shop.setSettle_time("05:00");
        when(shopService.getById(1)).thenReturn(shop);

        KdsShopConfig cfg = new KdsShopConfig();
        cfg.setSla_minutes(15);
        when(configService.getOrDefault(anyInt())).thenReturn(cfg);
        when(deviceService.screenTagsOf(any())).thenReturn(Collections.singleton("meat_grill"));
        when(dishService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(Collections.emptyList());
        when(statsService.todayStats(anyInt())).thenReturn(Collections.emptyMap());
    }

    @Test
    @DisplayName("V2 Bootstrap: 查询工单必须包含 created_at >= bizDayStart 条件")
    void testBootstrapIncludesCreatedAtCondition() {
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setStation_id(1L);

        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());

        workflowV2Service.buildBootstrap(device);

        ArgumentCaptor<QueryWrapper<KdsTicket>> captor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(ticketMapper, atLeastOnce()).selectList(captor.capture());

        QueryWrapper<KdsTicket> qw = captor.getAllValues().get(0);
        String sql = qw.getSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("created_at >="), "Query must restrict tickets by created_at >= bizDayStart, actual SQL: " + sql);

        // 负向校验：buildBootstrap 必须为纯只读操作，严禁触发任何 UPDATE/INSERT 写 SQL
        verify(jdbcTemplate, never()).update(anyString(), any(Object[].class));
    }

    @Test
    @DisplayName("V2 Bootstrap: 纯读化负向保证，零写操作且不随订单数线性增加查询")
    void testBootstrapIsPureReadOnlyWithConstantQueries() {
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setStation_id(1L);

        // 构造 500 个工单场景
        List<KdsTicket> mockTickets = new ArrayList<>();
        List<Order> mockOrders = new ArrayList<>();
        List<OrderDetail> mockDetails = new ArrayList<>();
        for (int i = 1; i <= 500; i++) {
            KdsTicket t = new KdsTicket();
            t.setId((long) i);
            t.setOrder_id(i);
            t.setDetail_id(i);
            t.setScreen_tag("meat_grill");
            t.setItem_status(KdsItemStatus.PENDING);
            t.setCreated_at(new Date());
            mockTickets.add(t);

            Order o = new Order();
            o.setId(i);
            o.setTransac_status("unsettled");
            o.setOrder_receiving("rec_order");
            mockOrders.add(o);

            OrderDetail d = new OrderDetail();
            d.setId(i);
            d.setMId(i);
            d.setQuantity("1");
            mockDetails.add(d);
        }

        when(ticketMapper.selectList(any())).thenReturn(mockTickets);
        when(orderService.listByIds(anyCollection())).thenReturn(mockOrders);
        when(orderDetailService.listByIds(anyCollection())).thenReturn(mockDetails);

        long start = System.currentTimeMillis();
        Map<String, Object> bootstrap = workflowV2Service.buildBootstrap(device);
        long elapsed = System.currentTimeMillis() - start;

        assertNotNull(bootstrap);
        assertTrue(elapsed < 500, "500 订单本地 buildBootstrap 耗时应在 500ms 预算内，实际: " + elapsed + "ms");

        // 负向校验：绝无任何 UPDATE 或 INSERT 执行
        verify(jdbcTemplate, never()).update(anyString(), any(Object[].class));
        verify(ticketMapper, never()).insert(any());
        verify(ticketMapper, never()).update(any(), any());
        verify(ticketMapper, never()).selectCount(any());

        // 查询次数严格为常数级（bootstrap 批量 listByIds 1 次 + 4 个队列各 1 次，共 5 次批量调用，绝无逐单循环）
        verify(orderService, times(5)).listByIds(anyCollection());
        verify(orderDetailService, times(5)).listByIds(anyCollection());
    }

    @Test
    @DisplayName("后台维护: 缺票自愈采用单条批量反连接 SQL，杜绝 N+1 逐单 selectCount")
    void testCompensateMissingTicketsBatchUsesSingleAntiJoin() {
        Date bizDayStart = new Date();
        when(jdbcTemplate.queryForList(anyString(), eq(Integer.class), eq(1), eq(bizDayStart)))
                .thenReturn(Collections.singletonList(888));

        Order missingOrder = new Order();
        missingOrder.setId(888);
        when(orderService.listByIds(Collections.singletonList(888))).thenReturn(Collections.singletonList(missingOrder));
        KdsOrderHook orderHook = mock(KdsOrderHook.class);
        ReflectionTestUtils.setField(workflowV2Service, "kdsOrderHook", orderHook);

        int count = workflowV2Service.compensateMissingTicketsForActiveOrdersBatch(1, bizDayStart);

        assertEquals(1, count);
        verify(orderHook, times(1)).ensureTicketsForAcceptedOrder(missingOrder);
        // 验证执行的是 LEFT JOIN ... t.id IS NULL 批量反连接 SQL
        ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
        verify(jdbcTemplate).queryForList(sqlCaptor.capture(), eq(Integer.class), eq(1), eq(bizDayStart));
        assertTrue(sqlCaptor.getValue().contains("LEFT JOIN t_kds_ticket"));
        assertTrue(sqlCaptor.getValue().contains("t.id IS NULL"));
    }

    @Test
    @DisplayName("V2 Bootstrap: 已取消订单 (cancelled) 必须从所有活动队列和订单明细中彻底剔除")
    void testBootstrapExcludesCancelledOrders() {
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setStation_id(1L);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(101L);
        ticket.setOrder_id(201);
        ticket.setDetail_id(301);
        ticket.setScreen_tag("meat_grill");
        ticket.setItem_status(KdsItemStatus.PENDING);
        ticket.setCreated_at(new Date());

        Order order = new Order();
        order.setId(201);
        order.setTransac_status("cancelled"); // 已取消
        order.setOrder_receiving("rec_order");

        OrderDetail detail = new OrderDetail();
        detail.setId(301);
        detail.setMId(201);
        detail.setQuantity("2");

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderService.listByIds(anyCollection())).thenReturn(Collections.singletonList(order));
        when(orderDetailService.listByIds(anyCollection())).thenReturn(Collections.singletonList(detail));

        Map<String, Object> bootstrap = workflowV2Service.buildBootstrap(device);
        @SuppressWarnings("unchecked")
        Map<String, List<Map<String, Object>>> queues = (Map<String, List<Map<String, Object>>>) bootstrap.get("queues");

        assertEquals(0, queues.get(KdsWorkflowQueue.PENDING_COOK).size(), "Cancelled order should not be in pending_cook");
        assertEquals(0, queues.get(KdsWorkflowQueue.PENDING_PREP).size(), "Cancelled order should not be in pending_prep");
        assertEquals(0, queues.get(KdsWorkflowQueue.READY_SERVE).size(), "Cancelled order should not be in ready_serve");
        assertEquals(0, queues.get(KdsWorkflowQueue.DONE).size(), "Cancelled order should not be in done");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> details = (List<Map<String, Object>>) bootstrap.get("order_details");
        assertEquals(0, details.size(), "Cancelled order should not appear in order_details");
    }

    @Test
    @DisplayName("V2 Bootstrap: 已清台订单 (off_order) 强制归入已完成队列，不流入待烤/待配/待传活动队列")
    void testBootstrapForcesOffOrderToDone() {
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setStation_id(1L);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(102L);
        ticket.setOrder_id(202);
        ticket.setDetail_id(302);
        ticket.setScreen_tag("meat_grill");
        ticket.setItem_status(KdsItemStatus.PENDING); // 未划菜
        ticket.setCooked_quantity(0);
        ticket.setCreated_at(new Date());

        Order order = new Order();
        order.setId(202);
        order.setTransac_status("settled");
        order.setOrder_receiving("off_order"); // 已结账清台

        OrderDetail detail = new OrderDetail();
        detail.setId(302);
        detail.setMId(202);
        detail.setQuantity("3");

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderService.listByIds(anyCollection())).thenReturn(Collections.singletonList(order));
        when(orderDetailService.listByIds(anyCollection())).thenReturn(Collections.singletonList(detail));

        Map<String, Object> bootstrap = workflowV2Service.buildBootstrap(device);
        @SuppressWarnings("unchecked")
        Map<String, List<Map<String, Object>>> queues = (Map<String, List<Map<String, Object>>>) bootstrap.get("queues");

        assertEquals(0, queues.get(KdsWorkflowQueue.PENDING_COOK).size(), "Off-order must not be in pending_cook");
        assertEquals(0, queues.get(KdsWorkflowQueue.PENDING_PREP).size(), "Off-order must not be in pending_prep");
        assertEquals(0, queues.get(KdsWorkflowQueue.READY_SERVE).size(), "Off-order must not be in ready_serve");
        assertEquals(1, queues.get(KdsWorkflowQueue.DONE).size(), "Off-order must be safely placed in done");

        Map<String, Object> doneLine = queues.get(KdsWorkflowQueue.DONE).get(0);
        assertEquals(0, doneLine.get("cook_remaining"));
        assertEquals(0, doneLine.get("prep_remaining"));
        assertEquals(0, doneLine.get("ready_remaining"));
        assertEquals(KdsWorkflowQueue.DONE, doneLine.get("workflow_queue"));
    }

    @Test
    @DisplayName("V2 Bootstrap: 已完成回撤并恢复接单状态后重新进入待传菜")
    void testBootstrapShowsReopenedCompletedItemInReadyServe() {
        KdsDevice device = new KdsDevice();
        device.setShop_id(1);
        device.setStation_id(1L);

        KdsTicket ticket = new KdsTicket();
        ticket.setId(103L);
        ticket.setOrder_id(203);
        ticket.setDetail_id(303);
        ticket.setScreen_tag("meat_grill");
        ticket.setItem_status(KdsItemStatus.DONE);
        ticket.setPrep_quantity(2);
        ticket.setCooked_quantity(2);
        ticket.setServed_quantity(1);
        ticket.setArchived(0);
        ticket.setCreated_at(new Date());

        Order order = new Order();
        order.setId(203);
        order.setTransac_status("settled");
        order.setOrder_receiving("rec_order");

        OrderDetail detail = new OrderDetail();
        detail.setId(303);
        detail.setMId(203);
        detail.setQuantity("2");

        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(ticket));
        when(orderService.listByIds(anyCollection())).thenReturn(Collections.singletonList(order));
        when(orderDetailService.listByIds(anyCollection())).thenReturn(Collections.singletonList(detail));

        Map<String, Object> bootstrap = workflowV2Service.buildBootstrap(device);
        @SuppressWarnings("unchecked")
        Map<String, List<Map<String, Object>>> queues =
                (Map<String, List<Map<String, Object>>>) bootstrap.get("queues");

        assertEquals(1, queues.get(KdsWorkflowQueue.READY_SERVE).size());
        assertEquals(0, queues.get(KdsWorkflowQueue.DONE).size());
        Map<String, Object> line = queues.get(KdsWorkflowQueue.READY_SERVE).get(0);
        assertEquals(1, line.get("ready_remaining"));
        assertEquals(KdsWorkflowQueue.READY_SERVE, line.get("workflow_queue"));
    }

    @Test
    @DisplayName("OverviewBoard: 在制队列查询强制包含 created_at >= bizDayStart 条件")
    void testOverviewBoardIncludesCreatedAtCondition() {
        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());

        overviewBoardService.buildBoard(1, "pending_cook", "all", "dish", null);

        ArgumentCaptor<QueryWrapper<KdsTicket>> captor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(ticketMapper, atLeastOnce()).selectList(captor.capture());

        QueryWrapper<KdsTicket> qw = captor.getAllValues().get(0);
        String sql = qw.getSqlSegment();
        assertNotNull(sql);
        assertTrue(sql.contains("created_at >="), "Active board query must contain created_at >= condition, got: " + sql);
    }
}
