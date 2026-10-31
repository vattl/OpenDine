package com.lanf.kds.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;

@Service
public class CashierKdsDeliveryService {
    private static final ZoneId SHOP_ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter HH_MM = DateTimeFormatter.ofPattern("HH:mm");
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final CashierKdsLeaseService leaseService;
    private final CashierKdsProjectionService projectionService;
    private final CashierKdsBootstrapRepair bootstrapRepair;

    public CashierKdsDeliveryService(JdbcTemplate jdbc, ObjectMapper objectMapper,
                                     CashierKdsLeaseService leaseService,
                                     CashierKdsProjectionService projectionService, CashierKdsBootstrapRepair bootstrapRepair) {
        this.jdbc = jdbc; this.objectMapper = objectMapper; this.leaseService = leaseService;
        this.projectionService = projectionService; this.bootstrapRepair=bootstrapRepair;
    }

    public Map<String, Object> bootstrap(int shopId, String device, long epoch, String token,
                                         String pageToken, int limit) {
        leaseService.recordBootstrapPage(shopId,device,epoch,token,0,false);
        int pageSize = Math.max(1, Math.min(100, limit));
        bootstrapRepair.ensureReady(shopId);
        Page page = pageToken == null || pageToken.trim().isEmpty()
                ? new Page(leaseService.head(shopId), 0, System.currentTimeMillis() + 600_000L)
                : parsePage(pageToken, shopId, epoch, token);
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT order_id,payload_json FROM t_kds_order_projection "
                        + "WHERE shop_id=? AND state='READY' AND projection_version>0 AND payload_json!='{}' "
                        + "AND COALESCE(last_event_cursor,0)<=? AND order_id>? "
                        + "ORDER BY order_id LIMIT ?", shopId, page.baseCursor, page.lastOrderId, pageSize + 1);
        boolean complete = rows.size() <= pageSize;
        if (!complete) rows = new ArrayList<>(rows.subList(0, pageSize));
        List<Map<String, Object>> orders = new ArrayList<>();
        long lastOrderId = page.lastOrderId;
        for (Map<String, Object> row : rows) {
            lastOrderId = ((Number) row.get("order_id")).longValue();
            Map<String, Object> proj = readJson(String.valueOf(row.get("payload_json")));
            if (proj != null && !proj.isEmpty() && proj.containsKey("orderId")) {
                orders.add(proj);
            }
        }
        leaseService.recordBootstrapPage(shopId,device,epoch,token,page.baseCursor,complete);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("snapshotToken", signPage(new Page(page.baseCursor, 0, page.expiresAtMs), shopId, epoch, token));
        data.put("baseCursor", page.baseCursor);
        data.put("nextPageToken", complete ? null : signPage(new Page(page.baseCursor, lastOrderId, page.expiresAtMs), shopId, epoch, token));
        data.put("complete", complete); data.put("orders", orders);
        return data;
    }

    /** 完整营业日订单快照：用于 KDS 对账、时序展示和明细回撤定位。 */
    @Transactional
    public Map<String, Object> businessDayOrders(int shopId, String device, long epoch, String token,
                                                  String cursor, int limit) {
        leaseService.validateForUpdate(shopId, device, epoch, token);
        BusinessWindow window = businessWindow(shopId);
        int pageSize = Math.max(1, Math.min(200, limit));
        LocalDateTime afterTime = null;
        long afterId = 0;
        if (cursor != null && !cursor.trim().isEmpty()) {
            try {
                String raw = cursor.trim();
                // ISO local timestamp itself contains ':'; the final separator
                // belongs to the numeric order id.
                int separator = raw.lastIndexOf(':');
                if (separator > 0) {
                    afterTime = LocalDateTime.parse(raw.substring(0, separator));
                    afterId = Math.max(0, Long.parseLong(raw.substring(separator + 1)));
                } else {
                    // Backward compatible with the original id-only cursor.
                    afterId = Math.max(0, Long.parseLong(raw));
                }
            }
            catch (NumberFormatException ex) { throw new CashierKdsDeliveryException(400, 4000, "cursor 无效"); }
            catch (Exception ex) { throw new CashierKdsDeliveryException(400, 4000, "cursor 无效"); }
        }
        Timestamp start = Timestamp.from(window.start.atZone(SHOP_ZONE).toInstant());
        Timestamp end = Timestamp.from(window.end.atZone(SHOP_ZONE).toInstant());
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT o.*, k.kds_order_status FROM t_order o LEFT JOIN t_kds_order k ON k.order_id=o.id "
                        + "WHERE o.shop_id=? AND o.order_time>=? AND o.order_time<? "
                        + (afterTime == null ? "AND o.id>? " : "AND (o.order_time>? OR (o.order_time=? AND o.id>?)) ")
                        + "ORDER BY o.order_time ASC, o.id ASC LIMIT ?",
                afterTime == null
                        ? new Object[]{shopId, start, end, afterId, pageSize + 1}
                        : new Object[]{shopId, start, end, Timestamp.valueOf(afterTime), Timestamp.valueOf(afterTime), afterId, pageSize + 1});
        boolean complete = rows.size() <= pageSize;
        if (!complete) rows = new ArrayList<>(rows.subList(0, pageSize));
        List<Map<String, Object>> orders = new ArrayList<>();
        List<Integer> orderIds = new ArrayList<>();
        for (Map<String, Object> row : rows) orderIds.add(((Number) row.get("id")).intValue());
        Map<Integer, List<Map<String, Object>>> detailsByOrder = loadBusinessDayDetails(orderIds);
        String next = cursor;
        for (Map<String, Object> row : rows) {
            int orderId = ((Number) row.get("id")).intValue();
            Timestamp orderTime = (Timestamp) row.get("order_time");
            next = (orderTime == null ? "" : orderTime.toLocalDateTime().toString()) + ":" + orderId;
            Map<String, Object> order = new LinkedHashMap<>();
            order.put("orderId", orderId); order.put("orderNo", row.get("order_no"));
            order.put("tableNumber", row.get("table_number")); order.put("orderTime", row.get("order_time"));
            order.put("orderStatus", row.get("transac_status")); order.put("receivingStatus", row.get("order_receiving"));
            order.put("kdsOrderStatus", row.get("kds_order_status")); order.put("completedAt", row.get("off_time"));
            order.put("remark", row.get("remark")); order.put("details", detailsByOrder.getOrDefault(orderId, Collections.emptyList()));
            orders.add(order);
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("shopId", shopId); data.put("businessDay", window.businessDay.toString());
        data.put("businessDayStart", window.start.toString()); data.put("businessDayEnd", window.end.toString());
        data.put("openTime", window.open.toString()); data.put("closeTime", window.close.toString());
        data.put("orders", orders); data.put("nextCursor", complete ? null : next); data.put("complete", complete);
        return data;
    }

    private Map<Integer, List<Map<String, Object>>> loadBusinessDayDetails(List<Integer> orderIds) {
        Map<Integer, List<Map<String, Object>>> grouped = new HashMap<>();
        if (orderIds.isEmpty()) return grouped;
        String placeholders = String.join(",", Collections.nCopies(orderIds.size(), "?"));
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT mId,id,dish_id,name,selectedSpicy,unit,quantity,refunded_quantity,line_status,remark "
                        + "FROM t_order_detail WHERE mId IN (" + placeholders + ") ORDER BY mId,id ASC", orderIds.toArray());
        for (Map<String, Object> row : rows) {
            int orderId = ((Number) row.get("mId")).intValue();
            Map<String, Object> detail = new LinkedHashMap<>();
            detail.put("detailId", row.get("id")); detail.put("dishId", row.get("dish_id"));
            detail.put("dishName", row.get("name")); detail.put("specification", row.get("selectedSpicy"));
            detail.put("unit", row.get("unit")); detail.put("quantity", row.get("quantity"));
            detail.put("refundedQuantity", row.get("refunded_quantity")); detail.put("lineStatus", row.get("line_status"));
            detail.put("remark", row.get("remark")); grouped.computeIfAbsent(orderId, ignored -> new ArrayList<>()).add(detail);
        }
        return grouped;
    }

    /** Paginated history backfill, without publishing historical orders as new kitchen events. */
    @Transactional
    public Map<String, Object> businessDayOrderDetails(int shopId, String device, long epoch, String token,
                                                       String cursor, int limit) {
        Map<String, Object> data = businessDayOrders(shopId, device, epoch, token, cursor, limit);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> orders = (List<Map<String, Object>>) data.get("orders");
        List<Integer> orderIds = new ArrayList<>();
        for (Map<String, Object> order : orders) orderIds.add(((Number) order.get("orderId")).intValue());
        Map<Integer, Map<Integer, Map<String, Object>>> progressByOrder = loadLineProgress(shopId, orderIds);
        for (Map<String, Object> order : orders) {
            int orderId = ((Number) order.get("orderId")).intValue();
            String status = String.valueOf(order.get("kdsOrderStatus"));
            boolean cancelled = "cancelled".equalsIgnoreCase(String.valueOf(order.get("orderStatus")))
                    || "cancelled".equalsIgnoreCase(String.valueOf(order.get("receivingStatus")))
                    || "90".equals(status);
            boolean completed = !cancelled && ("40".equals(status)
                    || "off_order".equalsIgnoreCase(String.valueOf(order.get("receivingStatus"))));
            order.put("transactionStatus", order.get("orderStatus"));
            order.put("completed", completed);
            order.put("completedAtMs", completed ? timestampMs(order.get("completedAt")) : null);
            order.put("archived", false);
            order.put("orderStatus", cancelled ? "cancelled" : completed ? "completed" : "active");
            Map<Integer, Map<String, Object>> progress = progressByOrder.getOrDefault(orderId, Collections.emptyMap());
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> details = (List<Map<String, Object>>) order.get("details");
            for (Map<String, Object> detail : details) {
                int quantity = Integer.parseInt(String.valueOf(detail.get("quantity")));
                Map<String, Object> line = progress.get(((Number) detail.get("detailId")).intValue());
                int refundedQty = detail.get("refundedQuantity") != null ? Integer.parseInt(String.valueOf(detail.get("refundedQuantity"))) : 0;
                String lineStatus = String.valueOf(detail.get("lineStatus"));
                if ("2".equals(lineStatus) || "3".equals(lineStatus) || "4".equals(lineStatus)) refundedQty = quantity;
                refundedQty = Math.min(refundedQty, quantity);
                int activeQty = Math.max(0, quantity - refundedQty);

                int prepQty = line != null && line.get("raw_prep_quantity") != null ? ((Number) line.get("raw_prep_quantity")).intValue() : 0;
                int cookedQty = line != null && line.get("raw_cooked_quantity") != null ? ((Number) line.get("raw_cooked_quantity")).intValue() : 0;
                int servedQty = line != null && line.get("raw_served_quantity") != null ? ((Number) line.get("raw_served_quantity")).intValue() : 0;
                
                int readyRemaining = Math.max(0, activeQty - servedQty);
                int cookRemaining = Math.max(0, Math.min(readyRemaining, activeQty - cookedQty));
                // We default prepEnabled to true since we don't have the config here.
                int prepRemaining = Math.max(0, Math.min(cookRemaining, activeQty - prepQty));

                boolean done = completed || (line != null && readyRemaining == 0);
                String workflowQueue = done ? "done" : (line == null ? null : (cookRemaining == 0 ? "ready_serve" : (prepRemaining == 0 ? "pending_cook" : "pending_prep")));

                detail.put("quantity", quantity);
                detail.put("lineQuantity", quantity);
                detail.put("doneLine", done ? 1 : 0);
                detail.put("workflowQueue", workflowQueue);
                detail.put("readyRemaining", done ? 0 : readyRemaining);
                detail.put("prepRemaining", done ? 0 : prepRemaining);
                detail.put("cookRemaining", done ? 0 : cookRemaining);
            }
            order.put("lines", details);
        }
        return data;
    }

    private Map<Integer, Map<Integer, Map<String, Object>>> loadLineProgress(int shopId, List<Integer> orderIds) {
        Map<Integer, Map<Integer, Map<String, Object>>> grouped = new HashMap<>();
        if (orderIds.isEmpty()) return grouped;
        String placeholders = String.join(",", Collections.nCopies(orderIds.size(), "?"));
        List<Object> args = new ArrayList<>(); args.add(shopId); args.addAll(orderIds);
        for (Map<String, Object> row : jdbc.queryForList("SELECT order_id as cloud_order_id, detail_id as cloud_detail_id, "
                + "MAX(item_status) as item_status, "
                + "SUM(COALESCE(prep_quantity, 0)) as prep_quantity, "
                + "SUM(COALESCE(cooked_quantity, 0)) as cooked_quantity, "
                + "SUM(COALESCE(served_quantity, 0)) as served_quantity "
                + "FROM t_kds_ticket WHERE shop_id=? AND order_id IN (" + placeholders + ") GROUP BY order_id, detail_id", args.toArray())) {
            
            int itemStatus = row.get("item_status") instanceof Number ? ((Number) row.get("item_status")).intValue() : 0;
            int prep = row.get("prep_quantity") instanceof Number ? ((Number) row.get("prep_quantity")).intValue() : 0;
            int cooked = row.get("cooked_quantity") instanceof Number ? ((Number) row.get("cooked_quantity")).intValue() : 0;
            int served = row.get("served_quantity") instanceof Number ? ((Number) row.get("served_quantity")).intValue() : 0;
            
            // Note: Since we don't have lineQuantity here, we will just store the raw quantities 
            // and let the caller compute the remaining quantities.
            row.put("raw_item_status", itemStatus);
            row.put("raw_prep_quantity", prep);
            row.put("raw_cooked_quantity", cooked);
            row.put("raw_served_quantity", served);
            
            int orderId = ((Number) row.get("cloud_order_id")).intValue();
            grouped.computeIfAbsent(orderId, ignored -> new HashMap<>()).put(((Number) row.get("cloud_detail_id")).intValue(), row);
        }
        return grouped;
    }

    private BusinessWindow businessWindow(int shopId) {
        Map<String, Object> shop;
        try {
            shop = jdbc.queryForMap("SELECT open_time, close_time, settle_time FROM t_shop WHERE id=?", shopId);
        } catch (Exception ex) {
            throw new CashierKdsDeliveryException(500, 5000, "无法读取门店营业时段");
        }
        // 与报表 AnalyticsServiceImpl#resolveOpenTime/resolveSettleTime 同口径：
        //   起点 open  = open_time（空回退 16:00）；切日 settle = settle_time → close_time → 04:00
        LocalTime open = parseShopTimeOr(shop.get("open_time"), "open_time", "16:00");
        LocalTime settle = parseShopTimeOr(shop.get("settle_time"), "settle_time", null);
        if (settle == null) {
            settle = parseShopTimeOr(shop.get("close_time"), "close_time", "04:00");
        }
        LocalDateTime now = LocalDateTime.now(SHOP_ZONE);
        LocalDate today = now.toLocalDate();
        LocalDateTime todayStart = LocalDateTime.of(today, open);
        LocalDateTime start = now.isBefore(todayStart)
                ? LocalDateTime.of(today.minusDays(1), open)
                : todayStart;
        LocalDate day = start.toLocalDate();
        // 窗口 [D open, D+1 settle)：D 16:00 ~ D+1 04:00（默认口径）
        LocalDateTime end = LocalDateTime.of(day, settle).plusDays(1);
        return new BusinessWindow(day, open, settle, start, end);
    }

    private LocalTime parseShopTimeOr(Object value, String field, String fallback) {
        String text = value == null ? "" : String.valueOf(value).trim();
        if (text.length() > 5) text = text.substring(0, 5);
        if (!text.isEmpty()) {
            try { return LocalTime.parse(text, HH_MM); }
            catch (Exception ex) { throw new CashierKdsDeliveryException(500, 5000, "门店" + field + "配置无效"); }
        }
        if (fallback != null) {
            return LocalTime.parse(fallback, HH_MM);
        }
        return null;
    }

    private static final class BusinessWindow {
        final LocalDate businessDay; final LocalTime open; final LocalTime close;
        final LocalDateTime start; final LocalDateTime end;
        BusinessWindow(LocalDate businessDay, LocalTime open, LocalTime close, LocalDateTime start, LocalDateTime end) {
            this.businessDay = businessDay; this.open = open; this.close = close; this.start = start; this.end = end;
        }
    }

    @Transactional
    public Map<String, Object> events(int shopId, String device, long epoch, String token,
                                      long afterCursor, int limit) {
        CashierKdsLeaseService.LeaseContext lease = leaseService.validateForUpdate(shopId, device, epoch, token);
        long min = minCursor(shopId);
        long head = leaseService.head(shopId);
        boolean expired = afterCursor > 0 && min > 0 && afterCursor < min - 1;
        if (lease.bootstrapRequired || expired) {
            Map<String, Object> required = emptyEvents(afterCursor, head, min, true);
            return required;
        }
        int pageSize = Math.max(1, Math.min(200, limit));
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM t_kds_delivery_event "
                + "WHERE shop_id=? AND id>? ORDER BY id LIMIT ?", shopId, Math.max(0, afterCursor), pageSize);
        List<Map<String, Object>> events = new ArrayList<>();
        long next = Math.max(0, afterCursor);
        for (Map<String, Object> row : rows) {
            long cursor = ((Number) row.get("id")).longValue(); next = cursor;
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("eventId", row.get("event_id")); event.put("cursor", cursor); event.put("shopId", shopId);
            event.put("eventType", row.get("event_type")); event.put("orderId", row.get("order_id"));
            event.put("projectionVersion", row.get("projection_version")); event.put("originChannel", row.get("origin_channel"));
            event.put("originDeviceCode", row.get("origin_device_code")); event.put("occurredAtMs", row.get("occurred_at_ms"));
            event.put("changedDetailIds", readNullableArray(row.get("changed_detail_ids_json")));
            event.put("projection", readJson(String.valueOf(row.get("payload_json"))));
            events.add(event);
        }
        if (!events.isEmpty()) jdbc.update("UPDATE t_kds_delivery_consumer SET last_delivered_cursor=GREATEST(last_delivered_cursor,?),"
                + "last_seen_at=NOW() WHERE shop_id=?", next, shopId);
        Map<String, Object> data = emptyEvents(afterCursor, head, min, false);
        data.put("nextCursor", next); data.put("events", events);
        return data;
    }

    public Map<String, Object> projection(int shopId, int orderId, String device, long epoch, String token) {
        leaseService.validate(shopId, device, epoch, token);
        Map<String, Object> projection = projectionService.findProjection(shopId, orderId);
        if (projection == null) throw new CashierKdsDeliveryException(404, 4040, "订单厨房投影不存在");
        return projection;
    }

    @Transactional
    public Map<String, Object> ack(int shopId, String device, long epoch, String token, long throughCursor) {
        CashierKdsLeaseService.LeaseContext lease = leaseService.validateForUpdate(shopId, device, epoch, token);
        if (throughCursor < 0 || throughCursor > lease.lastDeliveredCursor) {
            throw new CashierKdsDeliveryException(400, 4000, "throughCursor 超出本租约已投递范围");
        }
        boolean duplicate = throughCursor <= lease.ackCursor;
        long acknowledged = Math.max(lease.ackCursor, throughCursor);
        int clearBootstrap = acknowledged >= lease.bootstrapBaseCursor ? 0 : (lease.bootstrapRequired ? 1 : 0);
        jdbc.update("UPDATE t_kds_delivery_consumer SET ack_cursor=?,bootstrap_required=?,last_seen_at=NOW() WHERE shop_id=?",
                acknowledged, clearBootstrap, shopId);
        long head = leaseService.head(shopId);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("acknowledgedCursor", acknowledged); data.put("headCursor", head); data.put("duplicate", duplicate);
        data.put("lag", countLag(shopId, acknowledged));
        return data;
    }

    public Map<String, Object> status(int shopId) {
        long head = leaseService.head(shopId); long min = minCursor(shopId);
        List<Map<String, Object>> consumers = jdbc.queryForList("SELECT device_code,authority_epoch,lease_until,ack_cursor,"
                + "bootstrap_required,last_seen_at FROM t_kds_delivery_consumer WHERE shop_id=?", shopId);
        Map<String, Object> c = consumers.isEmpty() ? Collections.emptyMap() : consumers.get(0);
        long ack = c.get("ack_cursor") instanceof Number ? ((Number) c.get("ack_cursor")).longValue() : 0;
        Timestamp until = (Timestamp) c.get("lease_until");
        Long oldest = jdbc.queryForObject("SELECT MIN(occurred_at_ms) FROM t_kds_delivery_event WHERE shop_id=? AND id>?",
                Long.class, shopId, ack);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("shopId", shopId); data.put("headCursor", head); data.put("acknowledgedCursor", ack);
        data.put("minAvailableCursor", min); data.put("lag", countLag(shopId, ack)); data.put("oldestUnackedAtMs", oldest);
        data.put("authorityOnline", until != null && until.getTime() > System.currentTimeMillis());
        data.put("deviceCode", c.get("device_code")); data.put("authorityEpoch", c.get("authority_epoch"));
        data.put("leaseUntilMs", until == null ? null : until.getTime()); data.put("snapshotRequired", c.get("bootstrap_required"));
        data.put("lastSeenAtMs", timestampMs(c.get("last_seen_at")));
        return data;
    }

    private long minCursor(int shopId) {
        Long value = jdbc.queryForObject("SELECT COALESCE(MIN(id),0) FROM t_kds_delivery_event WHERE shop_id=?", Long.class, shopId);
        return value == null ? 0 : value;
    }
    private long countLag(int shopId, long after) {
        Long value = jdbc.queryForObject("SELECT COUNT(*) FROM t_kds_delivery_event WHERE shop_id=? AND id>?", Long.class, shopId, after);
        return value == null ? 0 : value;
    }
    private Map<String, Object> emptyEvents(long after, long head, long min, boolean snapshot) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("currentCursor", head); data.put("nextCursor", Math.max(0, after)); data.put("minAvailableCursor", min);
        data.put("snapshotRequired", snapshot); data.put("events", new ArrayList<>()); return data;
    }
    private Map<String, Object> readJson(String json) {
        try { return objectMapper.readValue(json, LinkedHashMap.class); }
        catch (Exception ex) { throw new IllegalStateException("invalid KDS delivery JSON", ex); }
    }
    private Object readNullableArray(Object json) {
        if (json == null) return Collections.emptyList();
        try { return objectMapper.readValue(String.valueOf(json), ArrayList.class); }
        catch (Exception ex) { return Collections.emptyList(); }
    }
    private String signPage(Page page, int shopId, long epoch, String token) {
        String body = shopId + ":" + epoch + ":" + page.baseCursor + ":" + page.lastOrderId + ":" + page.expiresAtMs;
        String signed = body + ":" + hmac(body, token);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(signed.getBytes(StandardCharsets.UTF_8));
    }
    private Page parsePage(String encoded, int shopId, long epoch, String token) {
        try {
            String decoded = new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8);
            String[] p = decoded.split(":", -1);
            String body = String.join(":", Arrays.copyOf(p, 5));
            if (p.length != 6 || Integer.parseInt(p[0]) != shopId || Long.parseLong(p[1]) != epoch
                    || !MessageDigest.isEqual(p[5].getBytes(StandardCharsets.US_ASCII), hmac(body, token).getBytes(StandardCharsets.US_ASCII))) {
                throw new IllegalArgumentException();
            }
            Page page = new Page(Long.parseLong(p[2]), Long.parseLong(p[3]), Long.parseLong(p[4]));
            if (page.expiresAtMs < System.currentTimeMillis()) throw new IllegalArgumentException();
            return page;
        } catch (Exception ex) { throw new CashierKdsDeliveryException(400, 4000, "nextPageToken 无效或已过期"); }
    }
    private static String hmac(String value, String token) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256"); mac.init(new SecretKeySpec(token.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) { throw new IllegalStateException(ex); }
    }
    private static Long timestampMs(Object value) { return value instanceof Timestamp ? ((Timestamp) value).getTime() : null; }
    private static final class Page {
        final long baseCursor; final long lastOrderId; final long expiresAtMs;
        Page(long baseCursor, long lastOrderId, long expiresAtMs) { this.baseCursor=baseCursor; this.lastOrderId=lastOrderId; this.expiresAtMs=expiresAtMs; }
    }
}
