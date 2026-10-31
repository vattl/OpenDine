package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsStationMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.sql.Timestamp;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class KdsBusinessDayOrdersFixTest {

    @InjectMocks
    private KdsWorkflowV2Service workflowV2Service;

    private JdbcTemplate jdbc;
    private List<Map<String, Object>> currentOrderRows = new ArrayList<>();
    private List<Map<String, Object>> currentDetailRows = new ArrayList<>();
    @Mock
    private KdsTicketMapper ticketMapper;
    @Mock
    private IOrderService orderService;
    @Mock
    private IOrderDetailService orderDetailService;
    @Mock
    private IDishService dishService;
    @Mock
    private KdsConfigService configService;
    @Mock
    private KdsDeviceService deviceService;
    @Mock
    private KdsOverviewBoardService overviewBoardService;
    @Mock
    private KdsStatsService statsService;
    @Mock
    private KdsOrderHook kdsOrderHook;
    @Mock
    private KdsStationMapper stationMapper;

    private KdsStationService stationService;

    @BeforeEach
    void setUp() {
        stationService = new KdsStationService();
        ReflectionTestUtils.setField(stationService, "stationMapper", stationMapper);

        currentOrderRows = new ArrayList<>();
        currentDetailRows = new ArrayList<>();

        jdbc = mock(JdbcTemplate.class, invocation -> {
            String methodName = invocation.getMethod().getName();
            if ("queryForMap".equals(methodName)) {
                Map<String, Object> shopRow = new HashMap<>();
                shopRow.put("open_time", "05:00");
                shopRow.put("close_time", "04:00");
                shopRow.put("settle_time", "05:00");
                return shopRow;
            }
            if ("queryForList".equals(methodName)) {
                String sql = invocation.getArgument(0, String.class);
                if (sql != null && sql.contains("FROM t_order_detail")) {
                    return currentDetailRows;
                }
                if (sql != null && sql.contains("FROM t_order o")) {
                    return currentOrderRows;
                }
                return Collections.emptyList();
            }
            if ("update".equals(methodName)) {
                return 1;
            }
            return org.mockito.Mockito.RETURNS_DEFAULTS.answer(invocation);
        });

        ReflectionTestUtils.setField(workflowV2Service, "jdbc", jdbc);
        ReflectionTestUtils.setField(workflowV2Service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(workflowV2Service, "orderService", orderService);
        ReflectionTestUtils.setField(workflowV2Service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(workflowV2Service, "dishService", dishService);
        ReflectionTestUtils.setField(workflowV2Service, "configService", configService);
        ReflectionTestUtils.setField(workflowV2Service, "deviceService", deviceService);
        ReflectionTestUtils.setField(workflowV2Service, "overviewBoardService", overviewBoardService);
        ReflectionTestUtils.setField(workflowV2Service, "statsService", statsService);
        ReflectionTestUtils.setField(workflowV2Service, "kdsOrderHook", kdsOrderHook);

        KdsShopConfig kdsConfig = new KdsShopConfig();
        kdsConfig.setKds_mode("standard");
        org.mockito.Mockito.lenient().when(configService.getOrDefault(anyInt())).thenReturn(kdsConfig);
        org.mockito.Mockito.lenient().when(dishService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class))).thenReturn(Collections.emptyList());
        org.mockito.Mockito.lenient().when(overviewBoardService.countWorkflowQueues(anyInt(), any(), any(), any(), any())).thenReturn(new HashMap<>());
        org.mockito.Mockito.lenient().when(statsService.todayStats(anyInt())).thenReturn(new HashMap<>());
    }

    @Test
    @DisplayName("测试未结账在制订单：明细绝对不标记为 done，doneLine=0")
    void testActiveOrderDetailsNotMarkedAsDone() {
        int shopId = 1;
        KdsDevice device = new KdsDevice();
        device.setId(15L);
        device.setShop_id(shopId);

        // 模拟未完成订单 13719
        Map<String, Object> orderRow = new HashMap<>();
        orderRow.put("id", 13719);
        orderRow.put("order_no", "ORD13719");
        orderRow.put("table_number", "24");
        orderRow.put("order_time", new Timestamp(System.currentTimeMillis() - 60000));
        orderRow.put("off_time", null); // 未离店清台
        orderRow.put("transac_status", "unsettled"); // 未结账
        orderRow.put("order_receiving", "rec_order");
        orderRow.put("kds_order_status", null);
        orderRow.put("dineInOrTakeOut", "dine_in");

        // 模拟订单明细
        Map<String, Object> detailRow = new HashMap<>();
        detailRow.put("mId", 13719);
        detailRow.put("id", 56566);
        detailRow.put("dish_id", 17);
        detailRow.put("name", "油边王");
        detailRow.put("selectedSpicy", "不辣");
        detailRow.put("unit", "串");
        detailRow.put("quantity", "2");
        detailRow.put("refunded_quantity", 0);
        detailRow.put("line_status", "normal");
        detailRow.put("remark", "");

        currentOrderRows = Collections.singletonList(orderRow);
        currentDetailRows = Collections.singletonList(detailRow);

        // 无工单或工单处于在制状态
        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> result = workflowV2Service.getBusinessDayOrders(device, null, 200);

        List<Map<String, Object>> orders = (List<Map<String, Object>>) result.get("orders");
        assertNotNull(orders);
        assertEquals(1, orders.size());
        Map<String, Object> order = orders.get(0);
        assertEquals(false, order.get("completed"));
        assertEquals("active", order.get("status"));
        assertEquals("active", order.get("workflow_queue"));

        List<Map<String, Object>> details = (List<Map<String, Object>>) order.get("details");
        assertEquals(1, details.size());
        Map<String, Object> d = details.get(0);

        // 核心断言：未完成订单的明细绝不能是 done！
        assertEquals(0, d.get("done_line"), "未结账新单 done_line 必须为 0");
        assertEquals(0, d.get("doneLine"), "未结账新单 doneLine 必须为 0");
        assertNotEquals("done", d.get("workflow_queue"), "未结账新单 workflow_queue 绝不能为 done");
        assertNotEquals("done", d.get("workflowQueue"), "未结账新单 workflowQueue 绝不能为 done");
        assertEquals(2, d.get("cook_remaining"));
        assertEquals(2, d.get("ready_remaining"));
    }

    @Test
    @DisplayName("测试已清台完成订单：明细正常标记为 done，doneLine=1")
    void testCompletedOrderDetailsMarkedAsDone() {
        int shopId = 1;
        KdsDevice device = new KdsDevice();
        device.setId(15L);
        device.setShop_id(shopId);

        Map<String, Object> orderRow = new HashMap<>();
        orderRow.put("id", 13715);
        orderRow.put("order_no", "ORD13715");
        orderRow.put("table_number", "666");
        orderRow.put("order_time", new Timestamp(System.currentTimeMillis() - 3600000));
        orderRow.put("off_time", new Timestamp(System.currentTimeMillis() - 1800000)); // 已清台
        orderRow.put("transac_status", "success");
        orderRow.put("order_receiving", "off_order");
        orderRow.put("kds_order_status", "40");
        orderRow.put("dineInOrTakeOut", "dine_in");

        Map<String, Object> detailRow = new HashMap<>();
        detailRow.put("mId", 13715);
        detailRow.put("id", 56500);
        detailRow.put("dish_id", 17);
        detailRow.put("name", "烤羊肉串");
        detailRow.put("quantity", "5");
        detailRow.put("refunded_quantity", 0);
        detailRow.put("line_status", "normal");

        currentOrderRows = Collections.singletonList(orderRow);
        currentDetailRows = Collections.singletonList(detailRow);

        Map<String, Object> result = workflowV2Service.getBusinessDayOrders(device, null, 200);

        List<Map<String, Object>> orders = (List<Map<String, Object>>) result.get("orders");
        assertNotNull(orders);
        assertEquals(1, orders.size());
        Map<String, Object> order = orders.get(0);
        assertEquals(true, order.get("completed"));
        assertEquals("done", order.get("status"));

        List<Map<String, Object>> details = (List<Map<String, Object>>) order.get("details");
        Map<String, Object> d = details.get(0);
        assertEquals(1, d.get("done_line"));
        assertEquals(1, d.get("doneLine"));
        assertEquals("done", d.get("workflow_queue"));
        assertEquals("done", d.get("workflowQueue"));
        assertEquals(0, d.get("ready_remaining"));
        assertEquals(0, d.get("cook_remaining"));
    }

    @Test
    @DisplayName("测试档口空时自动自愈初始化五屏")
    void testStationAutoHealWhenEmpty() {
        int shopId = 1;
        when(stationMapper.selectCount(any())).thenReturn(0);

        KdsStation createdMeatStation = new KdsStation();
        createdMeatStation.setId(201L);
        createdMeatStation.setShop_id(shopId);
        createdMeatStation.setScreen_tag("meat_grill");
        createdMeatStation.setEnabled(1);

        AtomicInteger queryCount = new AtomicInteger();
        when(stationMapper.selectOne(any())).thenAnswer(inv -> {
            // 前 7 次（初查 + 6 个 seed 查询）返回 null，最后一次重新查询返回创建好的档口
            if (queryCount.incrementAndGet() > 7) {
                return createdMeatStation;
            }
            return null;
        });

        KdsStation found = stationService.findByScreenTag(shopId, "meat_grill");

        assertNotNull(found);
        assertEquals(201L, found.getId());
        assertEquals("meat_grill", found.getScreen_tag());
        verify(stationMapper, atLeast(1)).insert(any());
    }

    @Test
    @DisplayName("测试 buildBootstrap 遇到未建单的活动已接单订单时触发自动补偿")
    void testBootstrapCompensatesMissingTicketsForActiveOrders() {
        int shopId = 1;
        KdsDevice device = new KdsDevice();
        device.setId(15L);
        device.setShop_id(shopId);

        Order activeOrder = new Order();
        activeOrder.setId(13719);
        activeOrder.setShop_id(shopId);
        activeOrder.setOrder_no("ORD13719");
        activeOrder.setOrder_receiving("rec_order");
        activeOrder.setTransac_status("unsettled");

        when(orderService.list(any(com.baomidou.mybatisplus.core.conditions.Wrapper.class)))
                .thenReturn(Collections.singletonList(activeOrder));
        when(ticketMapper.selectCount(any())).thenReturn(0); // 发现缺失工单
        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(deviceService.screenTagsOf(any())).thenReturn(Collections.singleton("workflow_board"));

        workflowV2Service.buildBootstrap(device);

        // CP1 / KDS-CA-1.3: bootstrap 必须为严格纯读操作，禁止在读请求生命周期中触发写事务补偿建单
        verify(kdsOrderHook, never()).ensureTicketsForAcceptedOrder(any());
    }
}
