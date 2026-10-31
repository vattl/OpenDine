package com.lanf.kds.delivery;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.realtime.CashierEventWebSocketHub;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.TransactionDefinition;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

@Service
public class CashierKdsProjectionService {
    /** Permanent data/contract failures must not retry forever or block later intents. */
    private static final long MAX_DURABLE_ATTEMPTS = 20L;
    private static final Logger log = LoggerFactory.getLogger(CashierKdsProjectionService.class);
    /** 云端 → 收银端 明细制作状态增量下行事件类型（D025）。 */
    public static final String EVENT_TYPE_LINE_STATUS = "ORDER_LINE_STATUS_CHANGED";
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final CashierEventWebSocketHub wakeHub;
    private final TransactionTemplate requiresNew;
    private final TransactionTemplate required;
    private final CashierKdsProjectionPublishRetry publishRetry;

    public CashierKdsProjectionService(JdbcTemplate jdbc, ObjectMapper objectMapper,
                                       CashierEventWebSocketHub wakeHub,
                                       PlatformTransactionManager transactionManager,
                                       CashierKdsProjectionPublishRetry publishRetry) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.wakeHub = wakeHub;
        this.publishRetry = publishRetry;
        this.requiresNew = new TransactionTemplate(transactionManager);
        this.requiresNew.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.required = new TransactionTemplate(transactionManager);
    }

    /** Record before source commit; only the asynchronous wakeup runs after commit. */
    public void publishAfterCommit(final int orderId, final String eventType, final String originChannel,
                                   final String originDeviceCode, Collection<Integer> changedDetailIds) {
        required.execute(status -> {
            org.springframework.jdbc.support.GeneratedKeyHolder key = new org.springframework.jdbc.support.GeneratedKeyHolder();
            String changed = changedDetailIds == null ? null : json(new ArrayList<>(changedDetailIds));
            jdbc.update(connection -> {
                java.sql.PreparedStatement statement = connection.prepareStatement(
                        "INSERT INTO t_kds_projection_intent(order_id,event_type,origin_channel,origin_device_code,changed_detail_ids_json) VALUES (?,?,?,?,?)",
                        new String[]{"id"});
                statement.setInt(1, orderId);
                statement.setString(2, eventType == null ? "ORDER_UPDATED" : eventType);
                statement.setString(3, originChannel);
                statement.setString(4, originDeviceCode);
                statement.setString(5, changed);
                return statement;
            }, key);
            String id = Objects.requireNonNull(key.getKey()).toString();
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { publishRetry.submit(orderId, () -> processIntent(id)); }
            });
            return null;
        });
    }

    /** Commit automatic acceptance and its intent together, without moving network printing into this transaction. */
    public boolean persistAcceptedOrder(int orderId, java.util.function.BooleanSupplier update) {
        return Boolean.TRUE.equals(required.execute(status -> {
            if (!update.getAsBoolean()) {
                status.setRollbackOnly();
                return false;
            }
            publishAfterCommit(orderId, "ORDER_ACCEPTED", null, null, null);
            return true;
        }));
    }

    /** Polling is only a wakeup: rejected work remains in the database without a time-window cutoff. */
    public void dispatchPendingIntents() {
        List<Map<String, Object>> pending = jdbc.queryForList(
                "SELECT id,order_id FROM t_kds_projection_intent WHERE next_attempt_ms<=? ORDER BY next_attempt_ms,id LIMIT 32",
                System.currentTimeMillis());
        for (Map<String, Object> row : pending) {
            String id = row.get("id").toString();
            if (!publishRetry.submit(((Number) row.get("order_id")).intValue(), () -> processIntent(id))) break;
        }
    }

    void processIntent(String id) {
        try {
            requiresNew.execute(status -> {
                List<Map<String, Object>> rows = jdbc.queryForList(
                        "SELECT * FROM t_kds_projection_intent WHERE id=? AND next_attempt_ms<=? FOR UPDATE",
                        id, System.currentTimeMillis());
                if (rows.isEmpty()) return null;
                Map<String, Object> row = rows.get(0);
                int orderId = ((Number) row.get("order_id")).intValue();
                // Keep an order's hints in insertion order; defer instead of busy-waiting on a predecessor.
                List<Long> earlier = jdbc.queryForList("SELECT id FROM t_kds_projection_intent WHERE order_id=? AND id<? LIMIT 1",
                        Long.class, orderId, id);
                if (!earlier.isEmpty()) throw new IllegalStateException("earlier projection intent pending");
                String changed = (String) row.get("changed_detail_ids_json");
                List<Integer> details = null;
                if (changed != null) {
                    try { details = objectMapper.readValue(changed, new com.fasterxml.jackson.core.type.TypeReference<List<Integer>>() { }); }
                    catch (java.io.IOException ex) { throw new IllegalStateException("invalid projection intent", ex); }
                }
                Long cursor = publish(orderId, (String) row.get("event_type"), (String) row.get("origin_channel"),
                        (String) row.get("origin_device_code"), details);
                if (cursor == null) {
                    OrderSnapshot source = loadOrder(orderId);
                    if (source != null && !isKitchenRelevant(source, (String) row.get("event_type"))) {
                        // 订单尚未接单：这是加菜时 publishAfterCommit 与 fulfillAddedDishes 之间的
                        // 竞态窗口，属于短暂状态，用 OrderNotYetAcceptedException 告知 catch 块
                        // 使用短间隔（3 s）重试，而非 30 s 惩罚延迟。
                        throw new OrderNotYetAcceptedException();
                    }
                }
                jdbc.update("DELETE FROM t_kds_projection_intent WHERE id=?", id);
                return null;
            });
        } catch (OrderNotYetAcceptedException notYet) {
            // 短暂状态：接单流程正在异步执行中，3 秒后让 poller 再试一次即可。
            requiresNew.execute(status -> {
                int updated = jdbc.update(
                        "UPDATE t_kds_projection_intent SET next_attempt_ms=CASE WHEN attempts+1>=? THEN ? ELSE ? END,attempts=attempts+1 WHERE id=?",
                        MAX_DURABLE_ATTEMPTS, Long.MAX_VALUE, System.currentTimeMillis() + 3_000L, id);
                if (updated > 0) {
                    Integer attempts = jdbc.queryForObject("SELECT attempts FROM t_kds_projection_intent WHERE id=?", Integer.class, id);
                    if (attempts != null && attempts >= MAX_DURABLE_ATTEMPTS) {
                        log.error("[cashier-kds-delivery] projection intent moved to terminal retry state id={} attempts={}; manual replay required", id, attempts);
                    }
                }
                return null;
            });
            log.info("[cashier-kds-delivery] intent {} deferred 3 s: order not yet accepted, will retry shortly", id);
        } catch (Exception ex) {
            // A failed publish has rolled back before changing retry state; never delete failed work.
            requiresNew.execute(status -> {
                int updated = jdbc.update(
                        "UPDATE t_kds_projection_intent SET next_attempt_ms=CASE WHEN attempts+1>=? THEN ? ELSE ? END,attempts=attempts+1 WHERE id=?",
                        MAX_DURABLE_ATTEMPTS, Long.MAX_VALUE, System.currentTimeMillis() + 30_000L, id);
                if (updated > 0) {
                    Integer attempts = jdbc.queryForObject("SELECT attempts FROM t_kds_projection_intent WHERE id=?", Integer.class, id);
                    if (attempts != null && attempts >= MAX_DURABLE_ATTEMPTS) {
                        log.error("[cashier-kds-delivery] projection intent moved to terminal retry state id={} attempts={}; manual replay required", id, attempts);
                    }
                }
                return null;
            });
            log.warn("[cashier-kds-delivery] durable intent {} deferred: {}", id, ex.getClass().getSimpleName());
        }
    }

    /** 加菜时 ORDER_UPDATED intent 在接单完成前触发的短暂状态信号，用于区分硬失败。 */
    private static final class OrderNotYetAcceptedException extends RuntimeException {
        OrderNotYetAcceptedException() { super(null, null, true, false); }
    }


    @Transactional
    public Long publish(int orderId, String eventType, String originChannel,
                        String originDeviceCode, Collection<Integer> changedDetailIds) {
        OrderSnapshot order = loadOrder(orderId);
        if (order == null || order.shopId <= 0 || !isKitchenRelevant(order, eventType)) return null;

        jdbc.update("INSERT IGNORE INTO t_kds_order_projection "
                        + "(order_id,shop_id,projection_version,state,source_channel,payload_json,payload_hash) "
                        + "VALUES (?,?,0,'INIT',?,'{}','0000000000000000000000000000000000000000000000000000000000000000')",
                order.id, order.shopId, inferSource(order, originChannel));
        Map<String, Object> current = jdbc.queryForMap(
                "SELECT projection_version,payload_hash,source_channel FROM t_kds_order_projection "
                        + "WHERE order_id=? FOR UPDATE", order.id);
        long oldVersion = ((Number) current.get("projection_version")).longValue();
        String source = oldVersion > 0 ? String.valueOf(current.get("source_channel"))
                : inferSource(order, originChannel);
        String state = projectionState(order, eventType);
        List<Map<String, Object>> lines = loadLines(order.id, state, order.shopId);
        Map<String, Object> material = projectionMaterial(order, state, source, originDeviceCode, lines);
        String materialJson = json(material);
        String hash = sha256(materialJson);
        if (hash.equals(String.valueOf(current.get("payload_hash")))) return null;

        long version = oldVersion + 1;
        long occurredAtMs = System.currentTimeMillis();
        material.put("projectionVersion", version);
        material.put("updatedAtMs", occurredAtMs);
        String payloadJson = json(material);
        String eventId = UUID.randomUUID().toString();
        String changedJson = changedDetailIds == null ? null : json(new ArrayList<>(changedDetailIds));
        long cursor;
        try {
            jdbc.update("INSERT INTO t_kds_delivery_event "
                            + "(event_id,shop_id,order_id,projection_version,event_type,origin_channel,origin_device_code,"
                            + "changed_detail_ids_json,payload_json,occurred_at_ms) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    eventId, order.shopId, order.id, version, normalizeEventType(eventType, state), source,
                    trimToNull(originDeviceCode), changedJson, payloadJson, occurredAtMs);
            cursor = jdbc.queryForObject("SELECT id FROM t_kds_delivery_event WHERE event_id=?", Long.class, eventId);
        } catch (DuplicateKeyException duplicate) {
            return jdbc.queryForObject("SELECT id FROM t_kds_delivery_event WHERE order_id=? AND projection_version=?",
                    Long.class, order.id, version);
        }
        jdbc.update("UPDATE t_kds_order_projection SET shop_id=?,projection_version=?,state=?,source_channel=?,"
                        + "payload_json=?,payload_hash=?,last_event_cursor=?,updated_at=NOW() WHERE order_id=?",
                order.shopId, version, state, source, payloadJson, hash, cursor, order.id);
        wakeAfterCommit(order.shopId, cursor);
        log.info("[cashier-kds-delivery] event persisted shop={} cursor={} order={} version={} type={}",
                order.shopId, cursor, order.id, version, normalizeEventType(eventType, state));
        return cursor;
    }


    /**
     * D025：发布明细级制作状态增量（ORDER_LINE_STATUS_CHANGED）。
     *
     * 复用 t_kds_delivery_event + cursor + WS 唤醒通道；不触碰 t_kds_order_projection
     * （订单级投影的 payload_hash/version 保持独立）。发布失败仅记录日志，不阻断调用方主事务。
     *
     * @param deltas 本次变更的明细状态集合（至少 1 条）
     */
    public void publishLineStatus(int shopId, int orderId, Collection<LineStatusDelta> deltas) {
        if (deltas == null || deltas.isEmpty()) {
            return;
        }
        try {
            OrderSnapshot order = loadOrder(orderId);
            if (order == null || order.shopId <= 0 || order.shopId != shopId) {
                log.warn("[cashier-kds-delivery] line-status skip: order not found or shop mismatch shop={} order={}",
                        shopId, orderId);
                return;
            }
            List<Map<String, Object>> lines = new ArrayList<>();
            List<Integer> detailIds = new ArrayList<>();
            for (LineStatusDelta d : deltas) {
                lines.add(d.toMap());
                detailIds.add(d.detailId);
            }
            Map<String, Object> material = new LinkedHashMap<>();
            material.put("eventType", EVENT_TYPE_LINE_STATUS);
            material.put("orderId", order.id);
            material.put("orderNo", order.orderNo);
            material.put("shopId", order.shopId);
            material.put("occurredAtMs", System.currentTimeMillis());
            material.put("lines", lines);
            String eventId = UUID.randomUUID().toString();
            jdbc.update("INSERT INTO t_kds_delivery_event "
                            + "(event_id,shop_id,order_id,projection_version,event_type,origin_channel,origin_device_code,"
                            + "changed_detail_ids_json,payload_json,occurred_at_ms) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    eventId, order.shopId, order.id, 0L, EVENT_TYPE_LINE_STATUS, "KDS_LINE_STATUS", null,
                    json(detailIds), json(material), System.currentTimeMillis());
            long cursor = jdbc.queryForObject("SELECT id FROM t_kds_delivery_event WHERE event_id=?",
                    Long.class, eventId);
            wakeAfterCommit(order.shopId, cursor);
            log.info("[cashier-kds-delivery] line-status persisted shop={} cursor={} order={} lines={}",
                    order.shopId, cursor, order.id, lines.size());
        } catch (Exception ex) {
            // 辅助同步：发布失败不阻断划菜/催菜/超时主事务，由收银端 bootstrap/营业日快照兜底。
            log.warn("[cashier-kds-delivery] line-status publish failed shop={} order={}: {}",
                    shopId, orderId, ex.getMessage());
        }
    }

    /**
     * 明细制作状态增量（D025 载荷模型）。updatedAtMs 供收银端做新旧裁决（本地新则忽略）。
     */
    public static final class LineStatusDelta {
        public final int detailId;
        public final int itemStatus;
        public final int prepQuantity;
        public final int cookedQuantity;
        public final int servedQuantity;
        public final int rushFlag;
        public final int overdueFlag;
        public final int addDishFlag;
        public final int archived;
        public final long updatedAtMs;

        public LineStatusDelta(int detailId, int itemStatus, int prepQuantity, int cookedQuantity,
                               int servedQuantity, int rushFlag, int overdueFlag, int addDishFlag,
                               int archived, long updatedAtMs) {
            this.detailId = detailId;
            this.itemStatus = itemStatus;
            this.prepQuantity = prepQuantity;
            this.cookedQuantity = cookedQuantity;
            this.servedQuantity = servedQuantity;
            this.rushFlag = rushFlag;
            this.overdueFlag = overdueFlag;
            this.addDishFlag = addDishFlag;
            this.archived = archived;
            this.updatedAtMs = updatedAtMs;
        }

        public static LineStatusDelta from(KdsTicket t, Integer detailId) {
            int dId = detailId != null && detailId > 0 ? detailId : (t.getDetail_id() != null ? t.getDetail_id() : 0);
            long updated = t.getUpdated_at() != null ? t.getUpdated_at().getTime() : System.currentTimeMillis();
            return new LineStatusDelta(dId,
                    t.getItem_status() != null ? t.getItem_status() : KdsItemStatus.PENDING,
                    nz(t.getPrep_quantity()), nz(t.getCooked_quantity()), nz(t.getServed_quantity()),
                    nz(t.getRush_flag()), nz(t.getOverdue_flag()), nz(t.getAdd_dish_flag()),
                    nz(t.getArchived()), updated);
        }

        private static int nz(Integer v) {
            return v != null ? v : 0;
        }

        public Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("detailId", detailId);
            m.put("itemStatus", itemStatus);
            m.put("prepQuantity", prepQuantity);
            m.put("cookedQuantity", cookedQuantity);
            m.put("servedQuantity", servedQuantity);
            m.put("rushFlag", rushFlag);
            m.put("overdueFlag", overdueFlag);
            m.put("addDishFlag", addDishFlag);
            m.put("archived", archived);
            m.put("updatedAtMs", updatedAtMs);
            return m;
        }
    }

    public Map<String, Object> findProjection(int shopId, int orderId) {
        List<String> payloads = jdbc.queryForList("SELECT payload_json FROM t_kds_order_projection "
                + "WHERE shop_id=? AND order_id=?", String.class, shopId, orderId);
        if (payloads.isEmpty()) return null;
        try { return objectMapper.readValue(payloads.get(0), LinkedHashMap.class); }
        catch (Exception ex) { throw new IllegalStateException("invalid KDS projection JSON", ex); }
    }

    private OrderSnapshot loadOrder(int orderId) {
        List<OrderSnapshot> rows = jdbc.query("SELECT id,order_no,shop_id,table_number,number_of_diners,remark,"
                        + "openid,merchantId,dineInOrTakeOut,order_receiving,transac_status,order_time "
                        + "FROM t_order WHERE id=?", (rs, rowNum) -> {
            OrderSnapshot s = new OrderSnapshot();
            s.id = rs.getInt("id"); s.orderNo = rs.getString("order_no");
            s.shopId = rs.getInt("shop_id"); s.tableNumber = rs.getString("table_number");
            s.diners = rs.getInt("number_of_diners"); s.remark = rs.getString("remark");
            s.openid = rs.getString("openid"); s.merchantId = rs.getString("merchantId");
            s.fulfillment = rs.getString("dineInOrTakeOut"); s.acceptance = rs.getString("order_receiving");
            s.transactionStatus = rs.getString("transac_status");
            Date created = rs.getTimestamp("order_time"); s.createdAtMs = created == null ? 0 : created.getTime();
            return s;
        }, orderId);
        if (!rows.isEmpty()) return rows.get(0);

        List<Map<String, Object>> projections = jdbc.queryForList(
                "SELECT shop_id, source_channel, payload_json FROM t_kds_order_projection WHERE order_id=?", orderId);
        if (!projections.isEmpty()) {
            try {
                @SuppressWarnings("unchecked")
                Map<String, Object> map = objectMapper.readValue(
                        String.valueOf(projections.get(0).get("payload_json")), LinkedHashMap.class);
                OrderSnapshot s = new OrderSnapshot();
                s.id = orderId;
                s.shopId = ((Number) projections.get(0).get("shop_id")).intValue();
                s.orderNo = (String) map.get("orderNo");
                s.tableNumber = (String) map.get("tableNumber");
                s.diners = map.get("numberOfDiners") instanceof Number ? ((Number) map.get("numberOfDiners")).intValue() : 1;
                s.remark = (String) map.get("orderRemark");
                s.fulfillment = (String) map.get("fulfillmentType");
                s.acceptance = "cancelled";
                s.transactionStatus = "cancelled";
                s.createdAtMs = map.get("createdAtMs") instanceof Number ? ((Number) map.get("createdAtMs")).longValue() : System.currentTimeMillis();
                return s;
            } catch (Exception ignored) {
            }
        }
        return null;
    }

    private boolean isPrepWorkflowEnabled(int shopId) {
        if (shopId <= 0) return true;
        try {
            List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT enable_prep_workflow, skewer_gate FROM t_kds_shop_config WHERE shop_id=?", shopId);
            if (!rows.isEmpty()) {
                Object prep = rows.get(0).get("enable_prep_workflow");
                if (prep instanceof Number) {
                    return ((Number) prep).intValue() == 1;
                }
                Object skewer = rows.get(0).get("skewer_gate");
                if (skewer instanceof Number) {
                    return ((Number) skewer).intValue() != 0;
                }
            }
        } catch (Exception ignored) {
        }
        return true;
    }

    private List<Map<String, Object>> loadLines(int orderId, String orderState, int shopId) {
        boolean prepEnabled = isPrepWorkflowEnabled(shopId);

        // 先批量查当前订单所有 KDS 工单（t_kds_ticket），按 detail_id 取最新状态。
        // 用于计算每个明细的真实队列位置，避免加菜投影把已制作/已出餐菜品回退到 pending_prep。
        Map<Integer, Map<String, Object>> ticketByDetail = new java.util.LinkedHashMap<>();
        List<Map<String, Object>> tickets = jdbc.queryForList(
                "SELECT detail_id, " +
                "MAX(item_status) as item_status, " +
                "SUM(COALESCE(prep_quantity, 0)) as prep_quantity, " +
                "SUM(COALESCE(cooked_quantity, 0)) as cooked_quantity, " +
                "SUM(COALESCE(served_quantity, 0)) as served_quantity " +
                "FROM t_kds_ticket WHERE order_id=? GROUP BY detail_id", orderId);
        for (Map<String, Object> t : tickets) {
            Integer detailId = t.get("detail_id") instanceof Number
                    ? ((Number) t.get("detail_id")).intValue() : null;
            if (detailId != null) ticketByDetail.put(detailId, t);
        }

        List<Map<String, Object>> lines = jdbc.query("SELECT id,dish_id,name,selectedSpicy,unit,quantity,refunded_quantity,line_status,"
                        + "line_type,client_line_id,combo_id,combo_instance_id,parent_detail_id,cid,remark "
                        + "FROM t_order_detail WHERE mId=? ORDER BY id", (rs, rowNum) -> {
            int detailId = rs.getInt("id");
            int remaining = Math.max(0, rs.getInt("quantity"));
            int refunded = Math.max(0, rs.getInt("refunded_quantity"));
            String lineStatus = rs.getString("line_status");
            boolean refundedLine = "refunded".equalsIgnoreCase(lineStatus);
            int original = originalQuantity(remaining, refunded, refundedLine);

            // 计算真实队列位置：优先读 t_kds_ticket，无工单（新菜）回退到默认起点
            String wq;
            int prepRemaining, cookRemaining, readyRemaining;
            if ("VOIDED".equals(orderState) || refundedLine) {
                wq = "done";
                prepRemaining = 0;
                cookRemaining = 0;
                readyRemaining = 0;
            } else {
                Map<String, Object> ticket = ticketByDetail.get(detailId);
                if (ticket == null) {
                    // 无工单：这是本次加菜新增的菜品，从队列起点开始
                    wq = prepEnabled ? "pending_prep" : "pending_cook";
                    prepRemaining = remaining;
                    cookRemaining = remaining;
                    readyRemaining = remaining;
                } else {
                    int itemStatus = ticket.get("item_status") instanceof Number
                            ? ((Number) ticket.get("item_status")).intValue() : 0;
                    int cookedQty = ticket.get("cooked_quantity") instanceof Number
                            ? ((Number) ticket.get("cooked_quantity")).intValue() : 0;
                    int servedQty = ticket.get("served_quantity") instanceof Number
                            ? ((Number) ticket.get("served_quantity")).intValue() : 0;
                    int prepQty = ticket.get("prep_quantity") instanceof Number
                            ? ((Number) ticket.get("prep_quantity")).intValue() : 0;
                    // item_status: PENDING=0, COOKING=1, DONE=2, VOID=3
                    if (itemStatus >= 2 /* DONE or VOID */) {
                        wq = "done";
                        prepRemaining = 0;
                        cookRemaining = 0;
                        readyRemaining = 0;
                    } else if (servedQty >= remaining) {
                        // 全部已传菜
                        wq = "done";
                        prepRemaining = 0;
                        cookRemaining = 0;
                        readyRemaining = 0;
                    } else if (cookedQty >= remaining) {
                        // 已全部完成制作，待传菜
                        wq = "ready_serve";
                        prepRemaining = 0;
                        cookRemaining = 0;
                        readyRemaining = Math.max(0, remaining - servedQty);
                    } else if (!prepEnabled || prepQty >= remaining) {
                        // 配菜已完成或不启用配菜，正在制作中
                        wq = "pending_cook";
                        int cooked = Math.max(0, Math.min(cookedQty, remaining));
                        prepRemaining = 0;
                        cookRemaining = Math.max(0, remaining - cooked);
                        readyRemaining = Math.max(0, remaining - servedQty);
                    } else {
                        // 仍在配菜阶段
                        int prep = Math.max(0, Math.min(prepQty, remaining));
                        int cooked = Math.max(0, Math.min(cookedQty, remaining));
                        wq = prep == 0 ? (prepEnabled ? "pending_prep" : "pending_cook") : "pending_prep";
                        prepRemaining = Math.max(0, remaining - prep);
                        cookRemaining = Math.max(0, remaining - cooked);
                        readyRemaining = Math.max(0, remaining - servedQty);
                    }
                }
            }

            Map<String, Object> line = new java.util.LinkedHashMap<>();
            line.put("detailId", detailId);
            Integer dishId = (Integer) rs.getObject("dish_id");
            line.put("dishId", dishId == null ? 0 : dishId);
            line.put("dishName", rs.getString("name"));
            line.put("specification", rs.getString("selectedSpicy"));
            line.put("unit", rs.getString("unit"));
            line.put("quantity", Math.max(1, original));
            line.put("refundedQuantity", refundedLine ? Math.max(refunded, original) : refunded);
            line.put("remainingQuantity", "VOIDED".equals(orderState) || refundedLine ? 0 : remaining);
            line.put("prepRemaining", prepRemaining);
            line.put("prep_remaining", prepRemaining);
            line.put("cookRemaining", cookRemaining);
            line.put("cook_remaining", cookRemaining);
            line.put("readyRemaining", readyRemaining);
            line.put("ready_remaining", readyRemaining);
            line.put("lineStatus", "VOIDED".equals(orderState) ? "CANCELLED" : (refundedLine ? "REFUNDED" : "NORMAL"));
            line.put("lineType", normalizeLineType(rs.getString("line_type")));
            line.put("clientLineId", rs.getString("client_line_id"));
            line.put("comboId", rs.getObject("combo_id"));
            line.put("comboInstanceId", rs.getString("combo_instance_id"));
            line.put("parentDetailId", rs.getObject("parent_detail_id"));
            line.put("categoryId", rs.getString("cid"));
            line.put("workflowQueue", wq);
            line.put("workflow_queue", wq);
            line.put("remark", rs.getString("remark"));
            line.put("rushed", false);
            return line;
        }, orderId);

        if (!lines.isEmpty()) return lines;

        if ("VOIDED".equals(orderState)) {
            List<String> payloads = jdbc.queryForList(
                    "SELECT payload_json FROM t_kds_order_projection WHERE order_id=?", String.class, orderId);
            if (!payloads.isEmpty()) {
                try {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> map = objectMapper.readValue(payloads.get(0), LinkedHashMap.class);
                    Object oldLines = map.get("lines");
                    if (oldLines instanceof List) {
                        List<Map<String, Object>> fallback = new ArrayList<>();
                        for (Object o : (List<?>) oldLines) {
                            if (o instanceof Map) {
                                @SuppressWarnings("unchecked")
                                Map<String, Object> l = new LinkedHashMap<>((Map<String, Object>) o);
                                l.put("remainingQuantity", 0);
                                l.put("lineStatus", "CANCELLED");
                                fallback.add(l);
                            }
                        }
                        return fallback;
                    }
                } catch (Exception ignored) {
                }
            }
        }
        return lines;
    }

    private Map<String, Object> projectionMaterial(OrderSnapshot order, String state, String source,
                                                    String sourceDeviceCode, List<Map<String, Object>> lines) {
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("orderId", order.id); p.put("orderNo", order.orderNo); p.put("shopId", order.shopId);
        p.put("state", state); p.put("sourceChannel", source); p.put("sourceDeviceCode", trimToNull(sourceDeviceCode));
        p.put("fulfillmentType", normalizeFulfillment(order.fulfillment)); p.put("tableNumber", order.tableNumber);
        p.put("numberOfDiners", order.diners); p.put("orderRemark", order.remark);
        p.put("acceptanceStatus", order.acceptance); p.put("createdAtMs", Math.max(1, order.createdAtMs));
        p.put("lines", lines);
        return p;
    }

    private void wakeAfterCommit(final int shopId, final long cursor) {
        Runnable wake = () -> wakeHub.broadcastWake(shopId, cursor);
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { wake.run(); }
            });
        } else wake.run();
    }

    private String json(Object value) {
        try { return objectMapper.writeValueAsString(value); }
        catch (JsonProcessingException ex) { throw new IllegalStateException("cannot serialize KDS projection", ex); }
    }
    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format("%02x", b & 0xff));
            return out.toString();
        } catch (Exception ex) { throw new IllegalStateException(ex); }
    }
    private static boolean isKitchenRelevant(OrderSnapshot o, String requestedEventType) {
        return "ORDER_CANCELLED".equalsIgnoreCase(requestedEventType)
                || "ORDER_CLOSED".equalsIgnoreCase(requestedEventType)
                || "rec_order".equalsIgnoreCase(o.acceptance)
                || "off_order".equalsIgnoreCase(o.acceptance)
                || "cancelled".equalsIgnoreCase(o.acceptance)
                || "cancelled".equalsIgnoreCase(o.transactionStatus);
    }
    private static String projectionState(OrderSnapshot o, String requestedEventType) {
        if ("ORDER_CANCELLED".equalsIgnoreCase(requestedEventType)
                || "cancelled".equalsIgnoreCase(o.acceptance)
                || "cancelled".equalsIgnoreCase(o.transactionStatus)) {
            return "VOIDED";
        }
        if ("ORDER_CLOSED".equalsIgnoreCase(requestedEventType) || "off_order".equalsIgnoreCase(o.acceptance)) {
            return "CLOSED";
        }
        return "READY";
    }
    private static String inferSource(OrderSnapshot o, String requested) {
        if (requested != null && Arrays.asList("POS", "CASHIER", "MINI_PROGRAM", "ADMIN", "THIRD_PARTY").contains(requested)) {
            return "CASHIER".equals(requested) ? "POS" : requested;
        }
        if ("cashier_system".equals(o.openid)) return "POS";
        if (o.merchantId != null && !o.merchantId.trim().isEmpty() && !"1".equals(o.merchantId.trim())) return "THIRD_PARTY";
        return "MINI_PROGRAM";
    }
    private static String normalizeEventType(String type, String state) {
        if ("VOIDED".equals(state)) return "ORDER_CANCELLED";
        if ("CLOSED".equals(state)) return "ORDER_CLOSED";
        if ("READY".equals(state) && ("ORDER_READY".equals(type) || "ORDER_ACCEPTED".equals(type) || type == null)) {
            return "ORDER_ACCEPTED";
        }
        return type == null ? "ORDER_UPDATED" : type;
    }
    private static String normalizeFulfillment(String raw) {
        if (raw == null) return "DINE_IN";
        if (raw.contains("打包") || raw.toLowerCase(Locale.ROOT).contains("take")) return "TAKEOUT";
        if (raw.contains("外卖") || raw.toLowerCase(Locale.ROOT).contains("delivery")) return "DELIVERY";
        return "DINE_IN";
    }
    private static String normalizeLineType(String raw) {
        if ("combo_header".equalsIgnoreCase(raw)) return "COMBO_HEADER";
        if ("combo_component".equalsIgnoreCase(raw)) return "COMBO_COMPONENT";
        return "NORMAL";
    }
    static int originalQuantity(int storedQuantity, int refundedQuantity, boolean fullyRefunded) {
        int stored = Math.max(0, storedQuantity);
        int refunded = Math.max(0, refundedQuantity);
        int original = fullyRefunded ? Math.max(stored, refunded) : stored + refunded;
        return Math.max(1, original);
    }
    private static String trimToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }
    private static final class OrderSnapshot {
        int id; int shopId; int diners; long createdAtMs;
        String orderNo; String tableNumber; String remark; String openid; String merchantId;
        String fulfillment; String acceptance; String transactionStatus;
    }
}
