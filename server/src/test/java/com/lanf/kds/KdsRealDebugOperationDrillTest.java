package com.lanf.kds;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.kds.service.KdsTicketService;
import com.lanf.kds.service.KdsWorkflowService;
import com.lanf.kds.service.KdsWorkflowV2Service;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.test.web.servlet.MockMvc;

import javax.sql.DataSource;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Opt-in drill against the populated local debug MySQL database.
 *
 * The whole drill runs in one Spring test transaction and is always rolled back.
 * It deliberately uses existing paid orders and the production KDS services; no
 * fake order, ticket, command ledger, or event store is substituted.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("debug")
@Transactional
@EnabledIfEnvironmentVariable(named = "RUN_REAL_KDS_OPERATION_DRILL", matches = "(?i)true")
class KdsRealDebugOperationDrillTest {

    private static final int SHOP_ID = 1;

    @Autowired
    private DataSource dataSource;
    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsWorkflowV2Service workflowV2Service;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void realBoundDeviceProxyLoginUsesCloudBindingAndRejectsDisabledDevice() throws Exception {
        assertSafeRollbackBoundary();

        KdsDevice bound = deviceService.listByShop(SHOP_ID).stream()
                .filter(device -> Integer.valueOf(1).equals(device.getEnabled()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("debug 库需要至少一个同店已启用 KDS 设备"));

        KdsDevice loggedIn = deviceService.loginBoundDevice(
                SHOP_ID,
                bound.getDevice_code(),
                bound.getDevice_name(),
                "workflow_board",
                bound.getScreen_tags(),
                null);

        assertNotNull(loggedIn);
        assertNotNull(loggedIn.getDevice_token());
        KdsDevice authenticated = deviceService.findByToken(loggedIn.getDevice_token());
        assertNotNull(authenticated);
        assertEquals(bound.getId(), authenticated.getId());
        assertNull(deviceService.loginBoundDevice(
                SHOP_ID + 1,
                bound.getDevice_code(),
                bound.getDevice_name(),
                "workflow_board",
                bound.getScreen_tags(),
                null), "同一设备码不得被其他门店代理登录");

        deviceService.unbind(SHOP_ID, bound.getDevice_code());
        assertNull(deviceService.loginBoundDevice(
                SHOP_ID,
                bound.getDevice_code(),
                bound.getDevice_name(),
                "workflow_board",
                bound.getScreen_tags(),
                null), "禁用设备不得被代理登录重新启用");
    }

    @Test
    void realDebugDataSupportsAllCoreOperationsLostResponsesReplayAndConflicts() throws Exception {
        assertSafeRollbackBoundary();

        Order order = selectRealOrder("success", 2);
        List<KdsTicket> tickets = distinctActiveTickets(order.getId());
        assertTrue(tickets.size() >= 2,
                "真实已支付订单至少需要两个可路由明细来隔离催菜和撤回演练");

        KdsDevice device = drillDevice(tickets.get(0));

        KdsTicket rushTicket = tickets.get(0);
        long rushRevision = revision(rushTicket.getDetail_id());
        Map<String, Object> rush = command("rush_item", rushTicket, rushRevision,
                initialQueue(rushTicket));
        executeAndDiscardResponse(device, rush);
        Map<String, Object> rushResolution = resolveThroughController(
                device, String.valueOf(rush.get("command_id")));
        assertEquals("APPLIED", rushResolution.get("status"));
        @SuppressWarnings("unchecked")
        Map<String, Object> rushApplied = (Map<String, Object>) rushResolution.get("result");
        assertApplied(rushApplied);
        long rushedRevision = revision(rushTicket.getDetail_id());
        assertTrue(rushedRevision > rushRevision, "催菜必须推进云端明细 revision");

        Map<String, Object> rushReplay = executeThroughController(device, rush);
        assertEquals(Boolean.TRUE, rushReplay.get("duplicate"));
        assertEquals(rushedRevision, revision(rushTicket.getDetail_id()),
                "同 command_id 重放不得二次修改业务状态");

        KdsTicket revokeTicket = tickets.get(1);
        String revokeQueue = initialQueue(revokeTicket);
        if ("pending_prep".equals(revokeQueue)) {
            Map<String, Object> advance = command("advance_item", revokeTicket,
                    revision(revokeTicket.getDetail_id()), revokeQueue);
            assertApplied(executeThroughController(device, advance));
            revokeQueue = "pending_cook";
        }
        long revokeRevision = revision(revokeTicket.getDetail_id());
        Map<String, Object> revoke = command("revoke_item", revokeTicket,
                revokeRevision, revokeQueue);
        executeAndDiscardResponse(device, revoke);
        Map<String, Object> revokeResolution = resolveThroughController(
                device, String.valueOf(revoke.get("command_id")));
        assertEquals("APPLIED", revokeResolution.get("status"));
        @SuppressWarnings("unchecked")
        Map<String, Object> revokeApplied = (Map<String, Object>) revokeResolution.get("result");
        assertApplied(revokeApplied);
        long revokedRevision = revision(revokeTicket.getDetail_id());
        Map<String, Object> revokeReplay = executeThroughController(device, revoke);
        assertEquals(Boolean.TRUE, revokeReplay.get("duplicate"));
        assertEquals(revokedRevision, revision(revokeTicket.getDetail_id()));
        assertStaleRejected(device, command("revoke_item", revokeTicket,
                revokeRevision, revokeQueue));

        Order advanceOrder = selectRealOrder("success", 1);
        KdsTicket advanceTicket = distinctActiveTickets(advanceOrder.getId()).get(0);
        String advanceQueue = initialQueue(advanceTicket);
        long advanceRevision = revision(advanceTicket.getDetail_id());
        Map<String, Object> advance = command("advance_item", advanceTicket,
                advanceRevision, advanceQueue);
        executeAndDiscardResponse(device, advance);
        Map<String, Object> advanceResolution = resolveThroughController(
                device, String.valueOf(advance.get("command_id")));
        assertEquals("APPLIED", advanceResolution.get("status"));
        @SuppressWarnings("unchecked")
        Map<String, Object> advanceApplied = (Map<String, Object>) advanceResolution.get("result");
        assertApplied(advanceApplied);
        long advancedRevision = revision(advanceTicket.getDetail_id());
        assertTrue(advancedRevision > advanceRevision, "划菜必须推进云端明细 revision");
        assertEquals(Boolean.TRUE, executeThroughController(device, advance).get("duplicate"));
        assertEquals(advancedRevision, revision(advanceTicket.getDetail_id()));
        assertStaleRejected(device, command("advance_item", advanceTicket,
                advanceRevision, advanceQueue));

        Order unsettledOrder = selectRealOrder("unsettled", 2);
        List<KdsTicket> unsettledTickets = distinctActiveTickets(unsettledOrder.getId());
        assertTrue(unsettledTickets.size() >= 2,
                "真实未支付订单至少需要两个可路由明细隔离加菜和退菜演练");

        KdsTicket addSource = unsettledTickets.get(0);
        int detailsBeforeAdd = detailCount(unsettledOrder.getId());
        Map<String, Object> addDishes = posAddDishesCommand(unsettledOrder, addSource);
        executeAndDiscardResponse(device, addDishes);
        Map<String, Object> addResolution = resolveThroughController(
                device, String.valueOf(addDishes.get("command_id")));
        assertEquals("APPLIED", addResolution.get("status"));
        @SuppressWarnings("unchecked")
        Map<String, Object> addApplied = (Map<String, Object>) addResolution.get("result");
        assertApplied(addApplied);
        int detailsAfterAdd = detailCount(unsettledOrder.getId());
        assertEquals(detailsBeforeAdd + 1, detailsAfterAdd, "加菜必须新增一个真实订单明细");
        assertEquals(Boolean.TRUE, executeThroughController(device, addDishes).get("duplicate"));
        assertEquals(detailsAfterAdd, detailCount(unsettledOrder.getId()),
                "同 command_id 重放加菜不得再次新增明细");
        Map<String, Object> conflictingAdd = posAddDishesCommand(unsettledOrder, addSource);
        conflictingAdd.put("command_id", addDishes.get("command_id"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> conflictingGoods = (List<Map<String, Object>>)
                ((Map<String, Object>) conflictingAdd.get("payload")).get("goods_list");
        conflictingGoods.get(0).put("quantity", "2");
        assertCommandFingerprintConflict(device, conflictingAdd);

        KdsTicket refundTicket = unsettledTickets.get(1);
        long refundRevision = revision(refundTicket.getDetail_id());
        Map<String, Object> refund = command("refund_item", refundTicket,
                refundRevision, initialQueue(refundTicket));
        refund.put("quantity", lineQuantity(refundTicket.getDetail_id()));
        executeAndDiscardResponse(device, refund);
        Map<String, Object> refundResolution = resolveThroughController(
                device, String.valueOf(refund.get("command_id")));
        assertEquals("APPLIED", refundResolution.get("status"));
        @SuppressWarnings("unchecked")
        Map<String, Object> refundApplied = (Map<String, Object>) refundResolution.get("result");
        assertApplied(refundApplied);
        assertTrue(hasRemovedPatch(refundApplied, refundTicket.getDetail_id()),
                "全量退菜必须返回 removed patch，避免客户端保留幽灵菜品");
        long refundedRevision = revision(refundTicket.getDetail_id());
        Map<String, Object> refundReplay = executeThroughController(device, refund);
        assertEquals(Boolean.TRUE, refundReplay.get("duplicate"));
        assertEquals(refundedRevision, revision(refundTicket.getDetail_id()));
        Map<String, Object> staleRefund = command("refund_item", refundTicket,
                refundRevision, initialQueue(refundTicket));
        staleRefund.put("quantity", lineQuantity(refundTicket.getDetail_id()));
        assertStaleRejected(device, staleRefund);

        Map<String, Object> staleRush = command("rush_item", rushTicket, rushRevision,
                initialQueue(rushTicket));
        assertThrows(KdsWorkflowService.OptimisticLockException.class,
                () -> workflowV2Service.executeCommand(device, staleRush),
                "旧 revision 必须被云端权威拒绝");
    }

    private void assertSafeRollbackBoundary() throws Exception {
        assertTrue(TransactionSynchronizationManager.isActualTransactionActive(),
                "真实数据演练必须在 Spring 回滚事务内运行");
        try (Connection connection = dataSource.getConnection()) {
            String catalog = connection.getCatalog();
            assertNotNull(catalog);
            assertTrue(catalog.startsWith("db_diancan_debug"),
                    "拒绝在非 debug 数据库运行真实数据演练: " + catalog);
        }
    }

    private Order selectRealOrder(String transactionStatus, int minimumDetails) {
        List<Integer> ids = jdbc.queryForList(
                "SELECT o.id FROM t_order o "
                        + "JOIN t_order_detail d ON d.mId=o.id "
                        + "LEFT JOIN t_kds_ticket k ON k.shop_id=o.shop_id AND k.detail_id=d.id "
                        + "WHERE o.shop_id=? AND o.transac_status=? AND k.id IS NULL "
                        + "AND (d.line_status IS NULL OR d.line_status NOT IN ('REFUNDED','CANCELLED')) "
                        + "GROUP BY o.id HAVING COUNT(*)>=? ORDER BY o.id DESC LIMIT 20",
                Integer.class, SHOP_ID, transactionStatus, minimumDetails);
        for (Integer id : ids) {
            Order order = orderService.getById(id);
            if (order == null) continue;
            ticketService.createTicketsForOrder(order, null, KdsOrderHook.Trigger.CREATE);
            if (distinctActiveTickets(id).size() >= minimumDetails) return order;
        }
        fail("debug 库没有满足演练条件的真实订单: status=" + transactionStatus
                + ", minimumDetails=" + minimumDetails);
        return null;
    }

    private List<KdsTicket> distinctActiveTickets(int orderId) {
        List<KdsTicket> rows = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", SHOP_ID)
                .eq("order_id", orderId)
                .eq("archived", 0)
                .orderByAsc("id"));
        Map<Integer, KdsTicket> byDetail = new LinkedHashMap<>();
        for (KdsTicket ticket : rows) {
            if (ticket.getDetail_id() != null
                    && !Integer.valueOf(KdsItemStatus.VOID).equals(ticket.getItem_status())) {
                byDetail.putIfAbsent(ticket.getDetail_id(), ticket);
            }
        }
        return new ArrayList<>(byDetail.values());
    }

    private KdsDevice drillDevice(KdsTicket ticket) {
        return deviceService.bind(SHOP_ID,
                "KDS-REAL-ROLLBACK-" + UUID.randomUUID(),
                "真实数据回滚演练", ticket.getScreen_tag());
    }

    private Map<String, Object> executeThroughController(KdsDevice device,
                                                         Map<String, Object> command) throws Exception {
        String json = mockMvc.perform(post("/kds/v2/commands")
                        .header("X-Kds-Device-Token", device.getDevice_token())
                        .contentType("application/json")
                        .content(objectMapper.writeValueAsString(command)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readValue(json, new TypeReference<Map<String, Object>>() { });
    }

    private void executeAndDiscardResponse(KdsDevice device,
                                           Map<String, Object> command) throws Exception {
        mockMvc.perform(post("/kds/v2/commands")
                        .header("X-Kds-Device-Token", device.getDevice_token())
                        .contentType("application/json")
                        .content(objectMapper.writeValueAsString(command)))
                .andExpect(status().isOk());
    }

    private Map<String, Object> resolveThroughController(KdsDevice device,
                                                         String commandId) throws Exception {
        String json = mockMvc.perform(get("/kds/v2/commands/{commandId}", commandId)
                        .header("X-Kds-Device-Token", device.getDevice_token()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readValue(json, new TypeReference<Map<String, Object>>() { });
    }

    private void assertCommandFingerprintConflict(KdsDevice device,
                                                  Map<String, Object> command) throws Exception {
        mockMvc.perform(post("/kds/v2/commands")
                        .header("X-Kds-Device-Token", device.getDevice_token())
                        .contentType("application/json")
                        .content(objectMapper.writeValueAsString(command)))
                .andExpect(status().isConflict())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers
                        .jsonPath("$.code").value(4090));
    }

    private void assertStaleRejected(KdsDevice device, Map<String, Object> command) {
        assertThrows(KdsWorkflowService.OptimisticLockException.class,
                () -> workflowV2Service.executeCommand(device, command),
                "旧 revision 必须被云端权威拒绝: " + command.get("type"));
    }

    private Map<String, Object> command(String type, KdsTicket ticket,
                                        long expectedRevision, String fromQueue) {
        Map<String, Object> target = new LinkedHashMap<>();
        target.put("order_id", ticket.getOrder_id());
        target.put("detail_id", ticket.getDetail_id());
        target.put("from_queue", fromQueue);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("command_id", "real-drill-" + UUID.randomUUID());
        body.put("type", type);
        body.put("expected_revision", expectedRevision);
        body.put("quantity", 1);
        body.put("target", target);
        body.put("payload", new LinkedHashMap<String, Object>());
        return body;
    }

    private Map<String, Object> posAddDishesCommand(Order order, KdsTicket sourceTicket) {
        Map<String, Object> source = jdbc.queryForMap(
                "SELECT dish_id,name,unit,total_price,cid,remark,selectedSpicy "
                        + "FROM t_order_detail WHERE id=?",
                sourceTicket.getDetail_id());
        assertNotNull(source.get("dish_id"), "真实加菜来源明细必须关联 dish_id");

        Map<String, Object> goods = new LinkedHashMap<>();
        goods.put("dish_id", source.get("dish_id"));
        goods.put("name", source.get("name"));
        goods.put("quantity", "1");
        goods.put("unit", source.get("unit"));
        goods.put("total_price", source.get("total_price"));
        goods.put("cid", source.get("cid"));
        goods.put("remark", source.get("remark"));
        goods.put("selectedSpicy", source.get("selectedSpicy"));

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_no", order.getOrder_no());
        payload.put("table_number", order.getTable_number());
        payload.put("goods_list", new ArrayList<>(java.util.Collections.singletonList(goods)));

        Map<String, Object> target = new LinkedHashMap<>();
        target.put("order_id", order.getId());
        target.put("order_no", order.getOrder_no());

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("command_id", "real-drill-" + UUID.randomUUID());
        body.put("type", "pos_add_dishes");
        body.put("target", target);
        body.put("payload", payload);
        return body;
    }

    private int detailCount(int orderId) {
        Integer value = jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_order_detail WHERE mId=?", Integer.class, orderId);
        return value != null ? value : 0;
    }

    private long revision(int detailId) {
        Long value = jdbc.queryForObject(
                "SELECT MAX(row_version) FROM t_kds_ticket WHERE shop_id=? AND detail_id=?",
                Long.class, SHOP_ID, detailId);
        assertNotNull(value, "KDS 工单必须有持久 revision");
        return value;
    }

    private String initialQueue(KdsTicket ticket) {
        int prep = ticket.getPrep_quantity() != null ? ticket.getPrep_quantity() : 0;
        return prep > 0 ? "pending_cook" : "pending_prep";
    }

    private int lineQuantity(int detailId) {
        String quantity = jdbc.queryForObject(
                "SELECT quantity FROM t_order_detail WHERE id=?", String.class, detailId);
        return KdsTicketQuantityUtil.lineQuantity(quantity);
    }

    private void assertApplied(Map<String, Object> result) {
        assertEquals(Boolean.FALSE, result.get("duplicate"));
        assertTrue(result.get("event_seq") instanceof Number);
        assertTrue(result.get("patches") instanceof List);
    }

    @SuppressWarnings("unchecked")
    private boolean hasRemovedPatch(Map<String, Object> result, int detailId) {
        Object raw = result.get("patches");
        if (!(raw instanceof List<?>)) return false;
        for (Object item : (List<?>) raw) {
            if (!(item instanceof Map<?, ?>)) continue;
            Map<String, Object> patch = (Map<String, Object>) item;
            Object id = patch.get("detail_id");
            if (id instanceof Number && ((Number) id).intValue() == detailId
                    && Boolean.TRUE.equals(patch.get("removed"))) {
                return true;
            }
        }
        return false;
    }
}
