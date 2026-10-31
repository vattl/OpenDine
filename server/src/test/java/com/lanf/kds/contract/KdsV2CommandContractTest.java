package com.lanf.kds.contract;

import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.controller.KdsWorkflowV2Controller;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.*;
import com.lanf.kds.util.KdsDeviceAuth;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.impl.OrderDetailRefundService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import java.sql.Timestamp;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class KdsV2CommandContractTest {

    @Mock private KdsWorkflowService workflowService;
    @Mock private KdsOverviewBoardService overviewBoardService;
    @Mock private KdsDeviceService deviceService;
    @Mock private KdsTicketMapper ticketMapper;
    @Mock private IOrderDetailService orderDetailService;
    @Mock private IOrderService orderService;
    @Mock private IDishService dishService;
    @Mock private KdsConfigService configService;
    @Mock private KdsTicketFlagService ticketFlagService;
    @Mock private KdsPushService pushService;
    @Mock private KdsStatsService statsService;
    @Mock private JdbcTemplate jdbc;
    @Mock private KdsV2CommandLedger commandLedger;
    @Mock private KdsCommandResultService commandResultService;
    @Mock private KdsV2EventStore eventStore;
    @Mock private KdsDeviceAuth deviceAuth;
    @Mock private OrderDetailRefundService orderDetailRefundService;

    private KdsWorkflowV2Service v2Service;
    private KdsWorkflowV2Controller controller;
    private KdsDevice device;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.initMocks(this);
        v2Service = new KdsWorkflowV2Service();
        ReflectionTestUtils.setField(v2Service, "workflowService", workflowService);
        ReflectionTestUtils.setField(v2Service, "overviewBoardService", overviewBoardService);
        ReflectionTestUtils.setField(v2Service, "deviceService", deviceService);
        ReflectionTestUtils.setField(v2Service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(v2Service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(v2Service, "orderService", orderService);
        ReflectionTestUtils.setField(v2Service, "dishService", dishService);
        ReflectionTestUtils.setField(v2Service, "configService", configService);
        ReflectionTestUtils.setField(v2Service, "ticketFlagService", ticketFlagService);
        ReflectionTestUtils.setField(v2Service, "pushService", pushService);
        ReflectionTestUtils.setField(v2Service, "statsService", statsService);
        ReflectionTestUtils.setField(v2Service, "jdbc", jdbc);
        ReflectionTestUtils.setField(v2Service, "commandLedger", commandLedger);
        ReflectionTestUtils.setField(v2Service, "eventStore", eventStore);
        ReflectionTestUtils.setField(v2Service, "orderDetailRefundService", orderDetailRefundService);

        controller = new KdsWorkflowV2Controller();
        ReflectionTestUtils.setField(controller, "deviceAuth", deviceAuth);
        ReflectionTestUtils.setField(controller, "v2Service", v2Service);
        ReflectionTestUtils.setField(controller, "commandLedger", commandLedger);
        ReflectionTestUtils.setField(controller, "commandResultService", commandResultService);
        MockHttpServletRequest req = new MockHttpServletRequest();
        ReflectionTestUtils.setField(controller, "request", req);

        device = new KdsDevice();
        device.setId(1L);
        device.setShop_id(10);
        device.setStation_id(1L);
        device.setDevice_code("DEV001");

        when(deviceAuth.requireDevice(any())).thenReturn(device);
        when(eventStore.nextSequence(eq(10))).thenReturn(42L);
        when(commandLedger.claim(eq(10), anyString(), anyString(), anyString(), anyString(), anyString(), any()))
                .thenReturn(KdsV2CommandLedger.Claim.execute("test-fp"));
        when(overviewBoardService.countWorkflowQueues(anyInt(), anyString(), any(), any(), any()))
                .thenReturn(Collections.singletonMap("pending_prep", 1));
        when(jdbc.queryForObject(contains("SELECT revision FROM t_order"),
                eq(Long.class), anyInt())).thenReturn(3L);
    }

    private KdsTicket createTicket(int id, int detailId, int orderId, long revision) {
        KdsTicket t = new KdsTicket();
        t.setId((long) id);
        t.setDetail_id(detailId);
        t.setOrder_id(orderId);
        t.setShop_id(10);
        t.setScreen_tag("workflow_board");
        t.setItem_status(KdsItemStatus.DONE);
        t.setCreated_at(new Timestamp(1000000L));
        t.setUpdated_at(new Timestamp(1234567L));
        t.setRow_version(revision);
        t.setOrder_revision(3L);
        return t;
    }

    private OrderDetail createDetail(int id, int orderId, String name, int qty) {
        OrderDetail d = new OrderDetail();
        d.setId(id);
        d.setMId(orderId);
        d.setDish_id(101);
        d.setName(name);
        d.setQuantity(String.valueOf(qty));
        d.setRefunded_quantity(0);
        d.setUnit("份");
        d.setLine_status("normal");
        return d;
    }

    private Order createOrder(int id, String orderNo, long payTime) {
        Order o = new Order();
        o.setId(id);
        o.setOrder_no(orderNo);
        o.setTable_number("A1");
        o.setDineInOrTakeOut("dine_in");
        o.setPay_time(new Timestamp(payTime));
        o.setOrder_time(new Timestamp(payTime - 5000));
        return o;
    }

    @Test
    void advanceItemWithMismatchedExpectedRevisionThrowsOptimisticLockException() {
        KdsTicket t = createTicket(1, 101, 201, 12345000L);
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(t));

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-1");
        req.put("type", "advance_item");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_prep");
        req.put("target", target);
        req.put("expected_revision", 999999L); // Wrong revision

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(409, response.getStatus());
        assertEquals(4090, result.get("code"));
        assertTrue(result.get("msg").toString().contains("版本冲突"));
        verify(commandResultService).saveResultInNewTransaction(eq(10), eq("cmd-1"), eq("DEV001"),
                eq("KDS"), eq("advance_item"), eq("2.0"), same(req),
                eq(409), eq(4090), contains("版本冲突"));
    }

    @Test
    void advanceItemWithMatchingExpectedRevisionSucceeds() {
        KdsTicket t = createTicket(1, 101, 201, 12345000L);
        long canonicalRev = 12345000L;
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(t));

        OrderDetail d = createDetail(101, 201, "羊肉串", 2);
        Order o = createOrder(201, "ORD202609130001", 12340000L);
        when(orderDetailService.listByIds(any())).thenReturn(Collections.singletonList(d));
        when(orderService.listByIds(any())).thenReturn(Collections.singletonList(o));
        when(orderService.getById(eq(201))).thenReturn(o);

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-2");
        req.put("type", "advance_item");
        req.put("actor_id", "spoofed-admin");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_prep");
        req.put("target", target);
        req.put("expected_revision", canonicalRev);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(200, response.getStatus());
        assertEquals(0, result.get("code"));
        verify(workflowService).advanceDetail(eq(10), eq(101), anyString(), eq(1));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = result.containsKey("data") && result.get("data") instanceof Map
                ? (Map<String, Object>) result.get("data")
                : result;
        assertEquals("cmd-2", data.get("command_id"));
        assertEquals(42L, data.get("event_seq"));
        verify(commandLedger).claim(eq(10), eq("cmd-2"), eq("DEV001"),
                eq("KDS"), eq("advance_item"), eq("2.0"), same(req));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> patches = (List<Map<String, Object>>) data.get("patches");
        assertFalse(patches.isEmpty());
        Map<String, Object> patch = patches.get(0);
        assertEquals(101, patch.get("detail_id"));

        @SuppressWarnings("unchecked")
        Map<String, Object> line = (Map<String, Object>) patch.get("line");
        assertNotNull(line);
        assertEquals(101, line.get("cloud_detail_id"));
        assertEquals(201, line.get("cloud_order_id"));
        assertEquals(10, line.get("serving_duration_minutes"));
        assertEquals(canonicalRev, line.get("local_revision"));
        assertNotNull(data.get("order_summary"));
    }

    @Test
    void advanceMergedItemsWithExpectedRevisionsValidatesAndAdvancesFifo() {
        KdsTicket t1 = createTicket(1, 101, 201, 10000000L);
        KdsTicket t2 = createTicket(2, 102, 201, 20000000L);
        long rev1 = 10000000L;
        long rev2 = 20000000L;

        when(ticketMapper.selectList(any())).thenReturn(Arrays.asList(t1, t2));
        OrderDetail d1 = createDetail(101, 201, "羊肉串", 2);
        OrderDetail d2 = createDetail(102, 201, "羊肉串", 3);
        Order o = createOrder(201, "ORD202609130001", 12340000L);
        when(orderDetailService.listByIds(any())).thenReturn(Arrays.asList(d1, d2));
        when(orderService.listByIds(any())).thenReturn(Collections.singletonList(o));
        when(orderService.getById(eq(201))).thenReturn(o);

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-3");
        req.put("type", "advance_item");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_ids", Arrays.asList(101, 102));
        target.put("from_queue", "pending_prep");
        req.put("target", target);
        req.put("quantity", 3);

        Map<String, Object> payload = new HashMap<>();
        Map<String, Object> expectedRevs = new HashMap<>();
        expectedRevs.put("101", rev1);
        expectedRevs.put("102", rev2);
        payload.put("expected_revisions", expectedRevs);
        req.put("payload", payload);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(200, response.getStatus());
        assertEquals(0, result.get("code"));
        verify(workflowService).advanceFifo(eq(10), anyString(), eq(3), eq(Arrays.asList(101, 102)));
    }

    @Test
    void advanceOrderWithMismatchedOrderRevisionFailsWith4090() {
        Order o = createOrder(201, "ORD202609130001", 12340000L);
        when(orderService.getById(eq(201))).thenReturn(o);

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-4");
        req.put("type", "advance_order");
        Map<String, Object> target = new HashMap<>();
        target.put("order_id", 201);
        target.put("from_queue", "pending_prep");
        req.put("target", target);
        req.put("expected_revision", 88888L); // Wrong order revision

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(409, response.getStatus());
        assertEquals(4090, result.get("code"));
        assertTrue(result.get("msg").toString().contains("版本冲突"));
    }

    @Test
    void lackItemWithSetSoldOutUpdatesDishSoldOut() {
        KdsTicket t = createTicket(1, 101, 201, 10000000L);
        when(ticketMapper.selectList(any())).thenReturn(Collections.singletonList(t));
        OrderDetail d = createDetail(101, 201, "烤韭菜", 1);
        d.setDish_id(55);
        when(orderDetailService.getById(eq(101))).thenReturn(d);
        when(orderDetailService.listByIds(any())).thenReturn(Collections.singletonList(d));
        Order o = createOrder(201, "ORD202609130001", 12340000L);
        when(orderService.listByIds(any())).thenReturn(Collections.singletonList(o));
        when(orderService.getById(eq(201))).thenReturn(o);

        Dish dish = new Dish();
        dish.setId(55);
        dish.setName("烤韭菜");
        dish.setSold_out(0);
        when(dishService.getById(eq(55))).thenReturn(dish);

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-5");
        req.put("type", "lack_item");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_cook");
        req.put("target", target);
        req.put("expected_revision", 10000000L);
        Map<String, Object> payload = new HashMap<>();
        payload.put("remark", "售罄缺货");
        payload.put("set_sold_out", true);
        req.put("payload", payload);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(200, response.getStatus());
        assertEquals(0, result.get("code"));
        verify(workflowService).reportLack(eq(10), eq(101), anyString(), eq(1), eq("售罄缺货"));
        assertEquals(1, dish.getSold_out());
        verify(dishService).updateById(eq(dish));
    }

    @Test
    void invalidCommandArgumentsReturn4000() {
        Map<String, Object> req = new HashMap<>();
        // missing command_id
        req.put("type", "advance_item");

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(400, response.getStatus());
        assertEquals(4000, result.get("code"));
    }

    @Test
    void kdsDeviceEndpointRejectsPosFinancialCommandsBeforeServiceExecution() {
        KdsWorkflowV2Service service = mock(KdsWorkflowV2Service.class);
        ReflectionTestUtils.setField(controller, "v2Service", service);
        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-pos-add");
        req.put("type", "pos_add_dishes");

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(403, response.getStatus());
        assertEquals(4030, result.get("code"));
        verifyNoInteractions(service);
    }

    @Test
    void prepOnlyDeviceCannotExecuteCookQueueCommand() {
        device.setWorkflows(Collections.singletonList("prep"));
        KdsWorkflowV2Service service = mock(KdsWorkflowV2Service.class);
        ReflectionTestUtils.setField(controller, "v2Service", service);
        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-cook-from-prep-device");
        req.put("type", "advance_item");
        req.put("expected_revision", 1L);
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_cook");
        req.put("target", target);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(403, response.getStatus());
        assertEquals(4030, result.get("code"));
        verifyNoInteractions(service);
    }

    @Test
    void posRefundDomainRejectsOrderFromAnotherShop() {
        OrderDetail detail = createDetail(501, 601, "跨店菜品", 1);
        Order foreignOrder = createOrder(601, "FOREIGN-ORDER", 12340000L);
        foreignOrder.setShop_id(11);
        when(orderDetailService.getById(501)).thenReturn(detail);
        when(orderService.getById(601)).thenReturn(foreignOrder);

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-cross-shop-refund");
        req.put("type", "pos_refund_dish");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 501);
        req.put("target", target);

        IllegalArgumentException error = assertThrows(
                IllegalArgumentException.class,
                () -> v2Service.executeCommand(device, req));

        assertTrue(error.getMessage().contains("门店"));
        verifyNoInteractions(orderDetailRefundService);
    }

    @Test
    void reusedCommandIdWithDifferentPayloadReturns409Conflict() {
        when(commandLedger.claim(eq(10), anyString(), anyString(), anyString(),
                anyString(), anyString(), any()))
                .thenThrow(new KdsV2CommandConflictException(
                        "command_id was already used with different command data"));

        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-conflict");
        req.put("type", "advance_item");
        req.put("expected_revision", 1L);
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_cook");
        req.put("target", target);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(409, response.getStatus());
        assertEquals(4090, result.get("code"));
        verifyNoInteractions(workflowService);
    }

    @Test
    void itemCommandWithoutExpectedRevisionReturns4000BeforeMutation() {
        Map<String, Object> req = new HashMap<>();
        req.put("command_id", "cmd-missing-revision");
        req.put("type", "advance_item");
        Map<String, Object> target = new HashMap<>();
        target.put("detail_id", 101);
        target.put("from_queue", "pending_prep");
        req.put("target", target);

        MockHttpServletResponse response = new MockHttpServletResponse();
        R result = controller.commands(req, response);

        assertEquals(400, response.getStatus());
        assertEquals(4000, result.get("code"));
        verifyNoInteractions(workflowService);
    }

    @Test
    void buildCanonicalLineContainsAllRequiredAndExtendedFields() {
        KdsTicket t = createTicket(1, 101, 201, 12345000L);
        t.setRush_flag(1);
        OrderDetail d = createDetail(101, 201, "烤牛肉", 4);
        d.setSelectedSpicy("微辣");
        d.setRemark("少盐");
        d.setCombo_id(99L);
        Order o = createOrder(201, "ORD202609130001", 12340000L);

        Map<String, Object> line = v2Service.buildCanonicalLine(t, o, d, true);

        assertEquals(101, line.get("detail_id"));
        assertEquals(201, line.get("order_id"));
        assertEquals(101, line.get("cloud_detail_id"));
        assertEquals(201, line.get("cloud_order_id"));
        assertEquals(10, line.get("serving_duration_minutes"));
        assertEquals(12345000L, line.get("local_revision"));
        assertEquals(3L, line.get("order_revision"));
        assertEquals("烤牛肉", line.get("dish_name"));
        assertEquals("ORD202609130001", line.get("order_no"));
        assertEquals(4, line.get("line_quantity"));
        assertEquals(0, line.get("refunded_quantity"));
        assertEquals(true, line.get("rushed"));
        assertEquals(false, line.get("lacked"));
        assertEquals(false, line.get("removed"));
        assertEquals("dine_in", line.get("fulfillment_bucket"));
        assertEquals("dine_in", line.get("fulfillment_channel"));
        assertEquals(true, line.get("is_combo"));
        assertEquals(true, line.get("combo"));
        assertEquals(true, line.get("set_meal"));
        assertEquals(99L, line.get("combo_id"));
    }
}
