package com.lanf.kds.replication;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Dish;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.kds.service.KdsTicketService;
import com.lanf.kds.support.KdsCloudReplicationContext;
import com.lanf.kds.support.KdsOrderAcceptance;
import com.lanf.kds.service.KdsDishAvailabilityService;
import com.lanf.kds.service.KdsCashierAuthorityService;
import com.lanf.kds.service.KdsLackService;
import com.lanf.kds.service.KdsReplicatedCommandRecorder;
import com.lanf.entity.Order;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.order.OrderDetailQuantityParser;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.impl.OrderDetailRefundService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.Set;

@Service
public class KdsReplicationService {

    private static final Logger log = LoggerFactory.getLogger(KdsReplicationService.class);
    public static final String CASHIER_DEVICE_HEADER = "X-Cashier-Device-Code";
    public static final String CLIENT_VERSION_HEADER = "X-Client-Version";
    public static final String EVENT_SOURCE_HEADER = "X-Event-Source";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final TransactionTemplate tx;
    private final OrderController orderController;
    private final IDishService dishService;
    private final IOrderDetailService orderDetailService;
    private final KdsDishAvailabilityService availabilityService;
    private final KdsCashierAuthorityService authorityService;
    private final KdsReplicationAuditService auditService;
    private final KdsLackService lackService;
    private final IOrderService orderService;
    private final OrderDetailRefundService orderDetailRefundService;
    private final KdsReplicatedCommandRecorder replicatedCommandRecorder;

    @Autowired
    private KdsTicketService ticketService;

    @Autowired
    public KdsReplicationService(JdbcTemplate jdbc,
                                 ObjectMapper objectMapper,
                                 PlatformTransactionManager transactionManager,
                                 OrderController orderController,
                                 IDishService dishService,
                                 IOrderDetailService orderDetailService,
                                 KdsDishAvailabilityService availabilityService,
                                 KdsCashierAuthorityService authorityService,
                                 KdsReplicationAuditService auditService,
                                 KdsLackService lackService,
                                 IOrderService orderService,
                                 OrderDetailRefundService orderDetailRefundService,
                                 @Autowired(required = false) KdsReplicatedCommandRecorder replicatedCommandRecorder) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.tx = new TransactionTemplate(transactionManager);
        this.orderController = orderController;
        this.dishService = dishService;
        this.orderDetailService = orderDetailService;
        this.availabilityService = availabilityService;
        this.authorityService = authorityService;
        this.auditService = auditService;
        this.lackService = lackService;
        this.orderService = orderService;
        this.orderDetailRefundService = orderDetailRefundService;
        this.replicatedCommandRecorder = replicatedCommandRecorder;
    }

    public KdsReplicationService(JdbcTemplate jdbc,
                                 ObjectMapper objectMapper,
                                 PlatformTransactionManager transactionManager,
                                 OrderController orderController,
                                 IDishService dishService,
                                 IOrderDetailService orderDetailService,
                                 KdsDishAvailabilityService availabilityService,
                                 KdsCashierAuthorityService authorityService,
                                 KdsReplicationAuditService auditService,
                                 KdsLackService lackService,
                                 IOrderService orderService,
                                 OrderDetailRefundService orderDetailRefundService) {
        this(jdbc, objectMapper, transactionManager, orderController, dishService,
                orderDetailService, availabilityService, authorityService, auditService,
                lackService, orderService, orderDetailRefundService, null);
    }

    public KdsReplicationService(JdbcTemplate jdbc,
                                 ObjectMapper objectMapper,
                                 PlatformTransactionManager transactionManager,
                                 OrderController orderController,
                                 IDishService dishService,
                                 IOrderDetailService orderDetailService,
                                 KdsDishAvailabilityService availabilityService,
                                 KdsCashierAuthorityService authorityService,
                                 KdsReplicationAuditService auditService,
                                 KdsLackService lackService) {
        this(jdbc, objectMapper, transactionManager, orderController, dishService,
                orderDetailService, availabilityService, authorityService, auditService, lackService, null, null, null);
    }

    public KdsReplicationOutcome accept(Integer shopId,
                                        KdsReplicationEventRequest request,
                                        HttpServletRequest servletRequest) {
        StoredEvent durableEvent = null;
        try {
            validateEnvelope(shopId, request, servletRequest);
            if (!allowsLegacyReplication(shopId)) {
                throw new KdsReplicationException(
                        "shop is cloud-authoritative; legacy state replication is disabled");
            }
            StoredEvent event = tx.execute(status -> capture(shopId, request, servletRequest));
            durableEvent = event;
            if (event == null) {
                return KdsReplicationOutcome.failure("event capture failed");
            }
            if (KdsReplicationPolicy.ORDER_CREATED.equals(event.eventType)) {
                log.warn("[kds-replication-legacy] event_type=order_created shop_id={} client_version={} source={} event_id={}",
                        shopId, header(servletRequest, CLIENT_VERSION_HEADER, "unknown"),
                        header(servletRequest, EVENT_SOURCE_HEADER, "unknown"), event.eventId);
            }
            if (isAcknowledged(event.status)) {
                return acknowledged(event, true);
            }
            KdsReplicationOutcome outcome = tx.execute(status -> apply(event.id, shopId, servletRequest));
            if (outcome != null && outcome.getBusinessCode() == 0
                    && KdsReplicationPolicy.ORDER_CREATED.equals(event.eventType)) {
                drainPending(shopId, event.aggregateKey, servletRequest);
            }
            return outcome != null ? outcome : KdsReplicationOutcome.failure("event processing failed");
        } catch (KdsReplicationAuthorizationException ex) {
            log.warn("[kds-replication] publisher rejected event_id={}: {}", safeEventId(request), ex.getMessage());
            return KdsReplicationOutcome.forbidden(ex.getMessage());
        } catch (IllegalArgumentException ex) {
            if (durableEvent != null) markError(durableEvent.eventId, shopId, 4000, ex.getMessage());
            return KdsReplicationOutcome.invalid(ex.getMessage());
        } catch (KdsReplicationException ex) {
            if (durableEvent != null) markError(durableEvent.eventId, shopId, 4091, ex.getMessage());
            log.warn("[kds-replication] business conflict event_id={}: {}", safeEventId(request), ex.getMessage());
            return KdsReplicationOutcome.conflict(ex.getMessage(), eventRef(request));
        } catch (Exception ex) {
            if (durableEvent != null) markError(durableEvent.eventId, shopId, 5000, "temporary cloud failure");
            log.error("[kds-replication] temporary failure event_id={}", safeEventId(request), ex);
            return KdsReplicationOutcome.failure("temporary cloud failure");
        }
    }

    private boolean allowsLegacyReplication(Integer shopId) {
        if (shopId == null || shopId <= 0) return false;
        List<String> modes = jdbc.query(
                "SELECT authority_mode FROM t_kds_shop_authority WHERE shop_id=?",
                (rs, rowNum) -> rs.getString(1), shopId);
        return modes.size() == 1 && "legacy".equalsIgnoreCase(modes.get(0));
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> deadLetters(int shopId, int limit) {
        int bounded = Math.max(1, Math.min(limit, 100));
        return jdbc.queryForList("SELECT event_id,event_type,aggregate_key,status,error_code,error_message,retry_count,"
                        + "created_at,updated_at,dead_lettered_at,resolution_action,replacement_event_id "
                        + "FROM t_kds_replication_event WHERE shop_id=? AND status IN ('dead_letter','failed') "
                        + "ORDER BY updated_at DESC,id DESC LIMIT ?", shopId, bounded);
    }

    @Transactional
    public KdsReplicationOutcome retryDeadLetter(int shopId, String eventId, HttpServletRequest request) {
        if (!allowsLegacyReplication(shopId)) {
            return KdsReplicationOutcome.conflict(
                    "shop is cloud-authoritative; legacy state replication is disabled",
                    eventRef(eventId));
        }
        Long id = deadLetterId(shopId, eventId);
        jdbc.update("UPDATE t_kds_replication_event SET status='received',retry_count=retry_count+1,updated_at=NOW() WHERE id=?", id);
        auditService.record(shopId, eventId, "retry_requested", null, null, request);
        KdsReplicationOutcome outcome = tx.execute(status -> apply(id, shopId, request));
        auditService.record(shopId, eventId, "retry_completed", null, null, request);
        log.info("[kds-replication-metric] action=retry shop_id={} event_id={} outcome={}",
                shopId, eventId, outcome != null ? outcome.getBusinessCode() : 5000);
        return outcome != null ? outcome : KdsReplicationOutcome.failure("event processing failed");
    }

    @Transactional
    public KdsReplicationOutcome replaceDeadLetter(int shopId, String eventId,
                                                    KdsReplicationEventRequest replacement,
                                                    HttpServletRequest request) {
        deadLetterId(shopId, eventId);
        if (replacement == null || eventId.equals(replacement.getEventId())) {
            return KdsReplicationOutcome.invalid("replacement requires a new event_id");
        }
        auditService.record(shopId, eventId, "replace_requested", null,
                replacement != null ? replacement.getEventId() : null, request);
        KdsReplicationOutcome outcome = accept(shopId, replacement, request);
        if (outcome.getBusinessCode() == 0) {
            jdbc.update("UPDATE t_kds_replication_event SET status='replaced',resolution_action='replace',"
                            + "replacement_event_id=?,resolved_at=NOW(),updated_at=NOW() WHERE shop_id=? AND event_id=?",
                    replacement.getEventId(), shopId, eventId);
            auditService.record(shopId, eventId, "replace_completed", null, replacement.getEventId(), request);
        }
        return outcome;
    }

    @Transactional
    public Map<String, Object> discardDeadLetter(int shopId, String eventId, String reason,
                                                 HttpServletRequest request) {
        deadLetterId(shopId, eventId);
        auditService.record(shopId, eventId, "discard_requested", reason, null, request);
        jdbc.update("UPDATE t_kds_replication_event SET status='discarded',resolution_action='discard',"
                        + "resolution_reason=?,resolved_at=NOW(),updated_at=NOW() WHERE shop_id=? AND event_id=?",
                truncate(reason, 500), shopId, eventId);
        auditService.record(shopId, eventId, "discard_completed", reason, null, request);
        Map<String, Object> data = eventRef(eventId);
        data.put("discarded", true);
        return data;
    }

    private Long deadLetterId(int shopId, String eventId) {
        if (!StringUtils.hasText(eventId)) throw new IllegalArgumentException("eventId is required");
        List<Long> ids = jdbc.queryForList("SELECT id FROM t_kds_replication_event "
                        + "WHERE shop_id=? AND event_id=? AND status IN ('dead_letter','failed') FOR UPDATE",
                Long.class, shopId, eventId.trim());
        if (ids.isEmpty()) throw new IllegalArgumentException("dead letter not found");
        return ids.get(0);
    }

    private void validateEnvelope(Integer shopId, KdsReplicationEventRequest request,
                                  HttpServletRequest servletRequest) {
        if (shopId == null || shopId <= 0) {
            throw new IllegalArgumentException("X-Shop-Id is required");
        }
        if (request == null || !StringUtils.hasText(request.getEventId())
                || request.getEventId().trim().length() > 128) {
            throw new IllegalArgumentException("event_id is required and must not exceed 128 characters");
        }
        request.setEventId(request.getEventId().trim());
        request.setEventType(KdsReplicationPolicy.normalizeEventType(request.getEventType()));
        if (!KdsReplicationPolicy.isSupportedType(request.getEventType())) {
            throw new IllegalArgumentException("unsupported event_type");
        }
        KdsReplicationPolicy.localOrderId(request.getAggregateKey());
        if (request.getOccurredAtMs() == null || request.getOccurredAtMs() <= 0) {
            throw new IllegalArgumentException("occurred_at_ms must be a positive integer");
        }
        if (request.getPayload() == null || !request.getPayload().isObject()) {
            throw new IllegalArgumentException("payload must be an object");
        }
        long localOrderId = KdsReplicationPolicy.ORDER_CREATED.equals(request.getEventType())
                ? requiredLong(request.getPayload(), "local_order_id")
                : stateOrderId(request.getPayload());
        KdsReplicationPolicy.requireAggregateOrder(request.getAggregateKey(), localOrderId);
        JsonNode payloadShop = request.getPayload().get("shop_id");
        if (payloadShop != null && (!payloadShop.isIntegralNumber() || !payloadShop.canConvertToInt()
                || payloadShop.asInt() != shopId)) {
            throw new IllegalArgumentException("payload shop_id must be an integer matching X-Shop-Id");
        }
        if (KdsReplicationPolicy.ORDER_CREATED.equals(request.getEventType())) {
            validateOrderCreatedPayload(request.getPayload(), shopId);
        } else if (KdsReplicationPolicy.KDS_ADVANCE_ITEM.equals(request.getEventType())) {
            validateAdvanceItemPayload(request.getPayload());
        } else {
            validateStateChangedPayload(request.getPayload());
        }
        String publisher = cashierDeviceCode(servletRequest);
        String payloadDevice = text(request.getPayload(), "device_code");
        if (KdsReplicationPolicy.KDS_STATE_CHANGED.equals(request.getEventType())
                && payloadDevice != null && !publisher.equals(payloadDevice)) {
            throw new KdsReplicationAuthorizationException(
                    "X-Cashier-Device-Code must match payload.device_code");
        }
    }

    private static void validateOrderCreatedPayload(JsonNode payload, int shopId) {
        if (requiredLong(payload, "shop_id") != shopId) {
            throw new IllegalArgumentException("payload shop_id must match X-Shop-Id");
        }
        requiredLong(payload, "created_at_ms");
        fulfillment(text(payload, "fulfillment_type"));
        JsonNode lines = payload.get("lines");
        if (lines == null || !lines.isArray() || lines.size() == 0) {
            throw new IllegalArgumentException("payload.lines must not be empty");
        }
        for (JsonNode line : lines) {
            requiredLong(line, "local_detail_id");
            positiveInt(line, "dish_id");
            positiveInt(line, "quantity");
        }
    }

    private static void validateAdvanceItemPayload(JsonNode payload) {
        String operationId = text(payload, "operation_id");
        if (!StringUtils.hasText(operationId) || operationId.length() > 128) {
            throw new IllegalArgumentException("operation_id is required and must not exceed 128 characters");
        }
        requiredLong(payload, "detail_id");
        requiredLong(payload, "local_revision");
        nonNegativeInt(payload, "prep_remaining");
        nonNegativeInt(payload, "cook_remaining");
        nonNegativeInt(payload, "ready_remaining");
        JsonNode doneLine = payload.get("done_line");
        if (doneLine == null || !doneLine.isIntegralNumber()
                || (doneLine.asInt() != 0 && doneLine.asInt() != 1)) {
            throw new IllegalArgumentException("done_line must be 0 or 1");
        }
        if (payload.has("remaining_quantity")) {
            nonNegativeInt(payload, "remaining_quantity");
        }
    }

    private static void validateStateChangedPayload(JsonNode payload) {
        String operationType = text(payload, "operation_type");
        if (!StringUtils.hasText(operationType) || operationType.length() > 40) {
            throw new IllegalArgumentException("operation_type is required and must not exceed 40 characters");
        }
        KdsReplicationPolicy.requireOperationType(operationType);
        if (isPatchStatePayload(payload)) {
            validatePatchStatePayload(payload);
            return;
        }
        replicationOrderId(payload);
        requiredLong(payload, "order_revision");
        String deviceCode = text(payload, "device_code");
        if (!StringUtils.hasText(deviceCode) || deviceCode.length() > 64) {
            throw new IllegalArgumentException("device_code is required and must not exceed 64 characters");
        }
        JsonNode orders = payload.get("orders");
        JsonNode lines = payload.get("lines");
        JsonNode availability = payload.get("dish_availability");
        if (orders == null || !orders.isArray() || orders.size() != 1 || lines == null || !lines.isArray() || lines.size() == 0
                || availability == null || !availability.isArray()) {
            throw new IllegalArgumentException("orders must contain exactly one snapshot; lines and dish_availability must be arrays");
        }
        long localOrderId = replicationOrderId(payload);
        boolean formalIds = !payload.hasNonNull("local_order_id");
        long orderRevision = requiredLong(payload, "order_revision");
        for (JsonNode order : orders) {
            if (replicationOrderId(order) != localOrderId
                    || (formalIds && requiredLong(order, "order_id") != localOrderId)) {
                throw new IllegalArgumentException("orders may only contain the envelope aggregate");
            }
            if (requiredLong(order, "order_revision") != orderRevision) {
                throw new IllegalArgumentException("orders[].order_revision must equal the envelope order_revision");
            }
        }
        Set<Long> uniqueLineIds = new HashSet<>();
        for (JsonNode line : lines) {
            validateStateLineSnapshot(line, localOrderId, orderRevision, formalIds, uniqueLineIds);
        }
        for (JsonNode dish : availability) {
            positiveInt(dish, "dish_id");
            requiredLong(dish, "availability_revision");
            if (dish.has("stock") && !dish.get("stock").isNull()) nullableStockInt(dish, "stock");
            if (dish.has("sold_out") && !dish.get("sold_out").isBoolean()
                    && !(dish.get("sold_out").isIntegralNumber()
                    && (dish.get("sold_out").asInt() == 0 || dish.get("sold_out").asInt() == 1))) {
                throw new IllegalArgumentException("sold_out must be boolean or 0/1");
            }
        }
    }

    /**
     * 新版补丁式 kds_state_changed：payload 携带 patches[]（正式 ID 行补丁，字段与 KdsV2LinePatch 对齐），
     * 不再携带 orders/lines/dish_availability 全量快照。event_seq/command_id 由收银端保证幂等与有序。
     */
    private static boolean isPatchStatePayload(JsonNode payload) {
        if (payload == null || !payload.has("patches")) {
            return false;
        }
        JsonNode lines = payload.get("lines");
        return lines == null || !lines.isArray();
    }

    private static long patchStateOrderId(JsonNode payload) {
        JsonNode patches = payload.get("patches");
        if (patches == null || !patches.isArray() || patches.size() == 0) {
            throw new IllegalArgumentException("patches must not be empty");
        }
        return requiredLong(patches.get(0), "order_id");
    }

    private static void validatePatchStatePayload(JsonNode payload) {
        JsonNode patches = payload.get("patches");
        if (patches == null || !patches.isArray() || patches.size() == 0) {
            throw new IllegalArgumentException("patches must not be empty");
        }
        long orderId = requiredLong(patches.get(0), "order_id");
        long orderRevision = requiredLong(patches.get(0), "order_revision");
        Set<Long> uniqueLineIds = new HashSet<>();
        for (JsonNode patch : patches) {
            validateStateLineSnapshot(patch, orderId, orderRevision, true, uniqueLineIds);
        }
    }

    private static void validateStateLineSnapshot(JsonNode line, long orderId, long orderRevision,
                                                  boolean formalIds, Set<Long> uniqueLineIds) {
        long lineId = replicationDetailId(line);
        if (!uniqueLineIds.add(lineId)) {
            throw new IllegalArgumentException("lines must not contain duplicate local_detail_id values");
        }
        // 混合 id：正式行带 detail_id；未映射行（本地加菜）可仅携带 local_detail_id 别名
        if (formalIds && line.hasNonNull("detail_id") && requiredLong(line, "detail_id") != lineId) {
            throw new IllegalArgumentException("lines[].detail_id must equal local_detail_id");
        }
        if (formalIds && !line.hasNonNull("detail_id") && !line.hasNonNull("local_detail_id")) {
            throw new IllegalArgumentException("lines[] must carry detail_id or local_detail_id");
        }
        if (replicationOrderId(line) != orderId
                || (formalIds && requiredLong(line, "order_id") != orderId)) {
            throw new IllegalArgumentException("lines may only contain the envelope aggregate");
        }
        positiveInt(line, "dish_id");
        requiredText(line, "dish_name");
        int lineQuantity = positiveInt(line, "line_quantity");
        int refundedQuantity = nonNegativeInt(line, "refunded_quantity");
        if (refundedQuantity > lineQuantity) {
            throw new IllegalArgumentException("refunded_quantity must not exceed line_quantity");
        }
        requiredLong(line, "local_revision");
        if (requiredLong(line, "order_revision") != orderRevision) {
            throw new IllegalArgumentException("lines[].order_revision must equal the envelope order_revision");
        }
        int visible = lineQuantity - refundedQuantity;
        int prepRemaining = boundedInt(line, "prep_remaining", visible);
        int cookRemaining = boundedInt(line, "cook_remaining", visible);
        int readyRemaining = boundedInt(line, "ready_remaining", visible);
        if (prepRemaining > cookRemaining || cookRemaining > readyRemaining) {
            throw new IllegalArgumentException("remaining quantities must satisfy prep <= cook <= ready");
        }
        requireFulfillmentBucket(line);
        requiredNullableText(line, "table_number");
        requiredText(line, "order_no");
        requiredNullableText(line, "specification");
        requiredNullableText(line, "unit");
        requiredNullableText(line, "remark");
        requiredLong(line, "created_at_ms");
        for (String flag : new String[]{"held", "rushed", "lacked", "removed"}) requiredBoolean(line, flag);
    }

    private StoredEvent capture(int shopId, KdsReplicationEventRequest request, HttpServletRequest servletRequest) {
        String publisherDeviceCode = cashierDeviceCode(servletRequest);
        requireAuthorizedPublisher(shopId, publisherDeviceCode);
        String operationId = text(request.getPayload(), "operation_id");
        if (!StringUtils.hasText(operationId)) {
            // 新版补丁式事件以 command_id 作为操作幂等键
            operationId = text(request.getPayload(), "command_id");
        }
        String requestFingerprint = KdsReplicationFingerprint.compute(objectMapper, shopId, request.getEventType(),
                request.getAggregateKey(), request.getOccurredAtMs(), publisherDeviceCode, request.getPayload());
        try {
            jdbc.update("INSERT INTO t_kds_replication_event "
                            + "(event_id,shop_id,event_type,aggregate_key,occurred_at_ms,operation_id,local_revision,payload_json,publisher_device_code,request_fingerprint,status) "
                            + "VALUES (?,?,?,?,?,?,?,?,?,?, 'received')",
                    request.getEventId(), shopId, request.getEventType(), request.getAggregateKey(),
                    request.getOccurredAtMs(), operationId, nullableLong(request.getPayload(), "local_revision"),
                    json(request.getPayload()), publisherDeviceCode, requestFingerprint);
        } catch (DuplicateKeyException ignored) {
            // The subsequent locked read returns the first durable result for either idempotency key.
        }
        List<StoredEvent> rows = jdbc.query("SELECT id,shop_id,event_id,event_type,aggregate_key,occurred_at_ms,status,result_json,payload_json,publisher_device_code,request_fingerprint "
                        + "FROM t_kds_replication_event WHERE event_id=? OR (shop_id=? AND operation_id IS NOT NULL AND operation_id=?) "
                        + "ORDER BY id LIMIT 2 FOR UPDATE",
                (rs, rowNum) -> new StoredEvent(rs.getLong("id"), rs.getInt("shop_id"), rs.getString("event_id"),
                        rs.getString("event_type"), rs.getString("aggregate_key"), rs.getString("status"),
                        rs.getString("result_json"), rs.getString("payload_json"), rs.getLong("occurred_at_ms"),
                        rs.getString("publisher_device_code"), rs.getString("request_fingerprint")),
                request.getEventId(), shopId, operationId != null ? operationId : "");
        if (rows.isEmpty()) {
            throw new IllegalStateException("captured event cannot be read");
        }
        if (rows.size() != 1) {
            throw new KdsReplicationException("idempotency keys resolve to different stored events");
        }
        StoredEvent stored = rows.get(0);
        String storedFingerprint = stored.requestFingerprint;
        if (!StringUtils.hasText(storedFingerprint)) {
            String storedPublisher = StringUtils.hasText(stored.publisherDeviceCode)
                    ? stored.publisherDeviceCode : publisherDeviceCode;
            storedFingerprint = KdsReplicationFingerprint.compute(objectMapper, stored.shopId, stored.eventType,
                    stored.aggregateKey, stored.occurredAtMs, storedPublisher, parse(stored.payloadJson));
            jdbc.update("UPDATE t_kds_replication_event SET publisher_device_code=COALESCE(publisher_device_code,?),"
                            + "request_fingerprint=? WHERE id=? AND request_fingerprint IS NULL",
                    storedPublisher, storedFingerprint, stored.id);
        }
        if (!requestFingerprint.equals(storedFingerprint)) {
            throw new KdsReplicationException("idempotency key was already used for a different request");
        }
        return stored;
    }

    private KdsReplicationOutcome apply(long eventRowId, int shopId, HttpServletRequest servletRequest) {
        StoredEvent event = eventById(eventRowId);
        requireAuthorizedPublisher(shopId, cashierDeviceCode(servletRequest));
        if (isAcknowledged(event.status)) {
            return acknowledged(event, true);
        }
        ensureAggregate(shopId, event.aggregateKey);
        if (KdsReplicationPolicy.ORDER_CREATED.equals(event.eventType)) {
            return applyOrderCreated(event, shopId, servletRequest);
        }
        if (KdsReplicationPolicy.KDS_STATE_CHANGED.equals(event.eventType)) {
            return applyStateChanged(event, shopId, cashierDeviceCode(servletRequest));
        }
        return applyAdvanceItem(event, shopId);
    }

    private KdsReplicationOutcome applyStateChanged(StoredEvent event, int shopId, String publisherDeviceCode) {
        JsonNode payload = parse(event.payloadJson);
        boolean patchMode = isPatchStatePayload(payload);
        String payloadDevice = text(payload, "device_code");
        if (payloadDevice != null && !publisherDeviceCode.equals(payloadDevice)) {
            throw new KdsReplicationAuthorizationException(
                    "X-Cashier-Device-Code must match stored payload.device_code");
        }
        JsonNode lines = patchMode ? payload.get("patches") : payload.get("lines");
        long localOrderId = patchMode ? requiredLong(lines.get(0), "order_id") : replicationOrderId(payload);
        long orderRevision = patchMode ? requiredLong(lines.get(0), "order_revision") : requiredLong(payload, "order_revision");
        List<Map<String, Object>> orderMaps = jdbc.queryForList(
                "SELECT cloud_order_id,cloud_order_no FROM t_kds_replication_order_map "
                        + "WHERE shop_id=? AND local_order_id=? FOR UPDATE", shopId, localOrderId);
        if (patchMode) {
            // §4.1：云端出生订单（正式 id）必须直接受理，不得要求 order_created 前置；
            // 仅当订单在云端不存在（本地出生订单的 order_created 未到达）时才挂起
            if (!formalOrderExists(shopId, localOrderId)) {
                return markPending(event, "order mapping is not available");
            }
            ensureFormalOrderMapping(shopId, localOrderId, event.aggregateKey);
            orderMaps = jdbc.queryForList(
                    "SELECT cloud_order_id,cloud_order_no FROM t_kds_replication_order_map "
                            + "WHERE shop_id=? AND local_order_id=? FOR UPDATE", shopId, localOrderId);
        } else if (orderMaps.isEmpty() && !payload.hasNonNull("local_order_id")) {
            ensureFormalMappings(shopId, localOrderId, lines, event.aggregateKey);
            orderMaps = jdbc.queryForList(
                    "SELECT cloud_order_id,cloud_order_no FROM t_kds_replication_order_map "
                            + "WHERE shop_id=? AND local_order_id=? FOR UPDATE", shopId, localOrderId);
        }
        if (!payload.hasNonNull("local_order_id") && !orderMaps.isEmpty()
                && ((Number) orderMaps.get(0).get("cloud_order_id")).longValue() != localOrderId) {
            throw new KdsReplicationException("formal order ID conflicts with an existing legacy mapping");
        }
        if (orderMaps.isEmpty()) {
            return markPending(event, "order mapping is not available");
        }
        Map<Long, Map<String, Object>> mappings = new LinkedHashMap<>();
        List<Map<String, Object>> mappedRows = jdbc.queryForList(
                "SELECT dm.local_detail_id,dm.cloud_order_id,dm.cloud_detail_id,dm.last_local_revision,om.cloud_order_no,"
                        + "ls.payload_json previous_payload_json "
                        + "FROM t_kds_replication_detail_map dm JOIN t_kds_replication_order_map om "
                        + "ON om.shop_id=dm.shop_id AND om.local_order_id=dm.local_order_id "
                        + "LEFT JOIN t_kds_replication_line_state ls ON ls.shop_id=dm.shop_id "
                        + "AND ls.local_detail_id=dm.local_detail_id "
                        + "WHERE dm.shop_id=? AND dm.local_order_id=? ORDER BY dm.local_detail_id FOR UPDATE",
                shopId, localOrderId);
        List<Long> incomingIds = new ArrayList<>();
        for (JsonNode line : lines) incomingIds.add(replicationDetailId(line));
        Set<Long> mappedIds = new HashSet<>();
        for (Map<String, Object> row : mappedRows) {
            long id = ((Number) row.get("local_detail_id")).longValue();
            if (!payload.hasNonNull("local_order_id")
                    && (((Number) row.get("cloud_order_id")).longValue() != localOrderId
                    || ((Number) row.get("cloud_detail_id")).longValue() != id)) {
                throw new KdsReplicationException("formal detail ID conflicts with an existing legacy mapping");
            }
            mappedIds.add(id);
            mappings.put(id, row);
        }
        // §4.2（v1.1 修订）：复制通道不新建明细。未映射行仅允许按正式 id 补建既有明细的映射；
        // 仍无法映射的行（如携带 local_detail_id 的本地加菜行）属载荷非法，返回 4000——
        // 加菜/减菜必须走订单 API + delivery 下行。
        boolean formalMappingAdded = false;
        for (JsonNode line : lines) {
            long lineId = replicationDetailId(line);
            if (mappings.containsKey(lineId)) continue;
            if (ensureFormalMapping(shopId, localOrderId, lineId, event.aggregateKey)) {
                formalMappingAdded = true;
                continue;
            }
            throw new IllegalArgumentException("lines must completely and exclusively cover mapped order details");
        }
        if (formalMappingAdded) {
            List<Map<String, Object>> refreshed = jdbc.queryForList(
                    "SELECT dm.local_detail_id,dm.cloud_order_id,dm.cloud_detail_id,dm.last_local_revision,om.cloud_order_no,"
                            + "ls.payload_json previous_payload_json "
                            + "FROM t_kds_replication_detail_map dm JOIN t_kds_replication_order_map om "
                            + "ON om.shop_id=dm.shop_id AND om.local_order_id=dm.local_order_id "
                            + "LEFT JOIN t_kds_replication_line_state ls ON ls.shop_id=dm.shop_id "
                            + "AND ls.local_detail_id=dm.local_detail_id "
                            + "WHERE dm.shop_id=? AND dm.local_order_id=? ORDER BY dm.local_detail_id FOR UPDATE",
                    shopId, localOrderId);
            for (Map<String, Object> row : refreshed) {
                long id = ((Number) row.get("local_detail_id")).longValue();
                mappings.putIfAbsent(id, row);
                mappedIds.add(id);
            }
        }
        // 全量快照模式要求完整排他覆盖；补丁模式只携带变更行，天然是部分集合
        if (!patchMode) {
            KdsReplicationPolicy.requireCompleteDetailSet(mappedIds, incomingIds);
        }
        Long current = jdbc.queryForObject("SELECT last_order_revision FROM t_kds_replication_aggregate "
                + "WHERE shop_id=? AND aggregate_key=?", Long.class, shopId, event.aggregateKey);
        if (KdsReplicationPolicy.revisionDecision(current != null ? current : 0L, orderRevision)
                == KdsReplicationPolicy.RevisionDecision.IGNORE_OLD) {
            Map<String, Object> data = baseResult(event.eventId, false);
            data.put("ignored_old_revision", true);
            data.put("order_revision", orderRevision);
            acknowledge(event.id, "ignored", data);
            return KdsReplicationOutcome.ok(data);
        }
        if ("refund_item".equals(text(payload, "operation_type"))) {
            applyRefundEffects(shopId, lines, mappings, Collections.emptySet());
        }
        for (JsonNode line : lines) {
            Map<String, Object> mapping = mappings.get(replicationDetailId(line));
            if (mapping == null) {
                throw new KdsReplicationException("line references unmapped detail");
            }
            applyStateLine(shopId, localOrderId, line, mapping);
        }
        if (payload.hasNonNull("orders")) {
            for (JsonNode order : payload.get("orders")) {
                jdbc.update("INSERT INTO t_kds_replication_order_state "
                                + "(shop_id,local_order_id,order_revision,payload_json) VALUES (?,?,?,?) "
                                + "ON DUPLICATE KEY UPDATE order_revision=VALUES(order_revision),payload_json=VALUES(payload_json),updated_at=NOW()",
                        shopId, localOrderId, orderRevision, json(order));
            }
        }
        applyAvailability(shopId, payload);
        jdbc.update("UPDATE t_kds_replication_aggregate SET last_order_revision=?,last_occurred_at_ms=?,updated_at=NOW() "
                        + "WHERE shop_id=? AND aggregate_key=?",
                orderRevision, occurredAt(event.id), shopId, event.aggregateKey);
        Map<String, Object> orderMap = orderMaps.get(0);
        updateCloudOrderProjection(shopId, localOrderId,
                ((Number) orderMap.get("cloud_order_id")).intValue(), String.valueOf(orderMap.get("cloud_order_no")));
        Map<String, Object> data = baseResult(event.eventId, false);
        data.put("order_revision", orderRevision);
        data.put("cloud_order_id", orderMap.get("cloud_order_id"));
        // §4.2/§3.3：ACK 携带明细映射，收银端据此把未映射行的本地 id 回写为正式 detail_id
        data.put("detail_mappings", detailMappings(shopId, localOrderId));
        String commandId = text(payload, "command_id");
        Map<String, Object> commandResult = recordReplicatedCommandIfPresent(
                shopId, event.requestFingerprint, event.occurredAtMs, payload, lines);
        if (commandResult != null) {
            data.put("command_id", commandId);
            data.put("kds_event_seq", commandResult.get("event_seq"));
        }
        acknowledge(event.id, "applied", data);
        JsonNode availabilityNode = payload.get("dish_availability");
        log.info("[kds-replication-metric] outcome=applied event_type=kds_state_changed shop_id={} lines={} availability={}",
                shopId, lines.size(), availabilityNode != null ? availabilityNode.size() : 0);
        return KdsReplicationOutcome.ok(data);
    }

    Map<String, Object> recordReplicatedCommandIfPresent(int shopId,
                                                          String requestFingerprint,
                                                          long occurredAtMs,
                                                          JsonNode payload,
                                                          JsonNode lines) {
        String commandId = text(payload, "command_id");
        if (!StringUtils.hasText(commandId) || replicatedCommandRecorder == null) {
            return null;
        }
        return replicatedCommandRecorder.recordApplied(
                shopId, commandId, requestFingerprint,
                text(payload, "operation_type"), occurredAtMs, lines);
    }

    private KdsReplicationOutcome markPending(StoredEvent event, String reason) {
        jdbc.update("UPDATE t_kds_replication_event SET status='pending',error_code=4090,error_message=?,updated_at=NOW() WHERE id=?",
                reason, event.id);
        // §4.4：4090 响应携带缺失前置的具体键，便于收银端诊断页直接展示卡点
        Map<String, Object> data = eventRef(event.eventId);
        data.put("missing_aggregate", event.aggregateKey);
        data.put("reason", reason);
        return KdsReplicationOutcome.pending("aggregate prerequisite has not arrived", data);
    }

    /** Applies only the cumulative refund delta; repeated/old snapshots therefore cannot restore stock twice. */
    private void applyRefundEffects(int shopId, JsonNode lines, Map<Long, Map<String, Object>> mappings,
                                    Set<Long> createdFromSnapshot) {
        for (JsonNode line : lines) {
            long lineId = replicationDetailId(line);
            Map<String, Object> mapping = mappings.get(lineId);
            int incoming = nonNegativeInt(line, "refunded_quantity");
            int previous = 0;
            Object previousJson = mapping.get("previous_payload_json");
            if (previousJson != null) {
                previous = parse(String.valueOf(previousJson)).path("refunded_quantity").asInt(0);
            }
            int delta = KdsReplicationPolicy.refundDelta(previous, incoming);
            if (delta > 0) {
                // 快照建行的明细：退菜终态已在创建时物化，且云端从未为其扣减库存——不得再走退菜服务回退库存
                if (createdFromSnapshot.contains(lineId)) {
                    continue;
                }
                int cloudDetailId = ((Number) mapping.get("cloud_detail_id")).intValue();
                if (orderDetailRefundService != null && orderService != null) {
                    OrderDetail detail = orderDetailService.getById(cloudDetailId);
                    if (detail != null) {
                        Order order = orderService.getById(detail.getMId());
                        if (order != null) {
                            int currentQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
                            if (delta >= currentQty) {
                                orderDetailRefundService.refundFullLine(detail, order);
                            } else {
                                orderDetailRefundService.refundPartial(detail, order, delta);
                            }
                        }
                    }
                } else if (lackService != null) {
                    lackService.refundDish(shopId, cloudDetailId, delta,
                            text(line, "workflow_queue"), text(line, "remark"), false);
                }
            }
        }
    }

    private void applyStateLine(int shopId, long localOrderId, JsonNode line, Map<String, Object> mapping) {
        long localDetailId = replicationDetailId(line);
        long revision = requiredLong(line, "local_revision");
        long orderRevision = line.has("order_revision") ? requiredLong(line, "order_revision") : 1L;
        long current = ((Number) mapping.get("last_local_revision")).longValue();
        int cloudOrderId = ((Number) mapping.get("cloud_order_id")).intValue();
        int cloudDetailId = ((Number) mapping.get("cloud_detail_id")).intValue();
        OrderDetail detail = orderDetailService.getById(cloudDetailId);
        if (detail == null) throw new KdsReplicationException("mapped cloud detail no longer exists");
        int quantity = positiveInt(line, "line_quantity") - nonNegativeInt(line, "refunded_quantity");
        int prepRemaining = boundedInt(line, "prep_remaining", quantity);
        int cookRemaining = boundedInt(line, "cook_remaining", quantity);
        int readyRemaining = boundedInt(line, "ready_remaining", quantity);
        boolean removed = line.path("removed").asBoolean(false);
        KdsReplicationPolicy.LineProgress progress = KdsReplicationPolicy.lineProgress(
                quantity, prepRemaining, cookRemaining, readyRemaining, removed || readyRemaining == 0);

        if (KdsReplicationPolicy.revisionDecision(current, revision) == KdsReplicationPolicy.RevisionDecision.IGNORE_OLD) {
            List<Map<String, Object>> tickets = jdbc.queryForList(
                    "SELECT prep_quantity, cooked_quantity, served_quantity, item_status, row_version, order_revision FROM t_kds_ticket WHERE shop_id=? AND detail_id=?",
                    shopId, cloudDetailId);
            if (!tickets.isEmpty()) {
                Map<String, Object> t = tickets.get(0);
                int currentPrep = t.get("prep_quantity") instanceof Number ? ((Number) t.get("prep_quantity")).intValue() : 0;
                int currentCooked = t.get("cooked_quantity") instanceof Number ? ((Number) t.get("cooked_quantity")).intValue() : 0;
                int currentServed = t.get("served_quantity") instanceof Number ? ((Number) t.get("served_quantity")).intValue() : 0;
                int currentItemStatus = t.get("item_status") instanceof Number ? ((Number) t.get("item_status")).intValue() : 0;
                boolean currentVoid = currentItemStatus == KdsItemStatus.VOID;
                boolean currentDone = currentItemStatus == KdsItemStatus.DONE;

                // 检查不可逆分叉冲突
                if ((removed && (currentServed > 0 || currentDone)) || (currentVoid && (progress.getCooked() > 0 || progress.getServed() > 0))) {
                    String reason = String.format("Conflict fork on detail %d: removed=%b, currentServed=%d, currentDone=%b, currentVoid=%b, incomingCooked=%d",
                            cloudDetailId, removed, currentServed, currentDone, currentVoid, progress.getCooked());
                    if (auditService != null) {
                        auditService.record(shopId, "order:" + localOrderId, "conflict_fork", reason, null, null);
                    }
                    throw new KdsReplicationConflictException(reason);
                }

                // 检查单调推进
                if (!removed && !currentVoid && KdsReplicationPolicy.hasMonotonicProgress(
                        currentPrep, currentCooked, currentServed,
                        progress.getPrep(), progress.getCooked(), progress.getServed())) {
                    int mergedPrep = Math.max(currentPrep, progress.getPrep());
                    int mergedCooked = Math.max(currentCooked, progress.getCooked());
                    int mergedServed = Math.max(currentServed, progress.getServed());
                    boolean completed = readyRemaining == 0 || mergedServed >= quantity;
                    int status = completed ? KdsItemStatus.DONE : (mergedPrep + mergedCooked + mergedServed > 0 ? KdsItemStatus.COOKING : KdsItemStatus.PENDING);
                    long newRev = Math.max(current, revision) + 1;
                    long newOrderRev = Math.max(t.get("order_revision") instanceof Number ? ((Number) t.get("order_revision")).longValue() : 0L, orderRevision);

                    jdbc.update("UPDATE t_kds_ticket SET prep_quantity=?,cooked_quantity=?,served_quantity=?,item_status=?,archived=?,row_version=?,order_revision=?,updated_at=NOW() WHERE shop_id=? AND detail_id=?",
                            mergedPrep, mergedCooked, mergedServed, status, completed ? 1 : 0, newRev, newOrderRev, shopId, cloudDetailId);

                    jdbc.update("INSERT INTO t_kds_replication_line_state "
                                    + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,workflow_queue,prep_remaining,cook_remaining,ready_remaining,remaining_quantity,local_revision,payload_json) "
                                    + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE workflow_queue=VALUES(workflow_queue),prep_remaining=VALUES(prep_remaining),cook_remaining=VALUES(cook_remaining),ready_remaining=VALUES(ready_remaining),remaining_quantity=VALUES(remaining_quantity),local_revision=VALUES(local_revision),payload_json=VALUES(payload_json),updated_at=NOW()",
                            shopId, localOrderId, localDetailId, cloudOrderId, cloudDetailId, text(line, "workflow_queue"),
                            prepRemaining, cookRemaining, readyRemaining, nullableLong(line, "remaining_quantity"), newRev, json(line));
                    jdbc.update("UPDATE t_kds_replication_detail_map SET last_local_revision=?,updated_at=NOW() WHERE shop_id=? AND local_detail_id=?",
                            newRev, shopId, localDetailId);
                    return;
                }
            }
            return;
        }

        int status = removed ? KdsItemStatus.VOID : readyRemaining == 0 ? KdsItemStatus.DONE
                : (progress.getPrep() + progress.getCooked() + progress.getServed() > 0 ? KdsItemStatus.COOKING : KdsItemStatus.PENDING);
        int affected = jdbc.update("UPDATE t_kds_ticket SET prep_quantity=?,cooked_quantity=?,served_quantity=?,item_status=?,archived=?,row_version=?,order_revision=?,updated_at=NOW() WHERE shop_id=? AND detail_id=?",
                progress.getPrep(), progress.getCooked(), progress.getServed(), status,
                (removed || readyRemaining == 0) ? 1 : 0, revision, orderRevision, shopId, cloudDetailId);
        if (affected == 0 && !ticketExists(shopId, cloudDetailId)
                && ensureTicketForProgress(shopId, cloudOrderId, cloudDetailId, detail)) {
            affected = jdbc.update("UPDATE t_kds_ticket SET prep_quantity=?,cooked_quantity=?,served_quantity=?,item_status=?,archived=?,row_version=?,order_revision=?,updated_at=NOW() WHERE shop_id=? AND detail_id=?",
                    progress.getPrep(), progress.getCooked(), progress.getServed(), status,
                    (removed || readyRemaining == 0) ? 1 : 0, revision, orderRevision, shopId, cloudDetailId);
            if (affected == 0 && !ticketExists(shopId, cloudDetailId)) {
                throw missingTicketConflict(shopId, cloudOrderId, cloudDetailId);
            }
        }
        jdbc.update("INSERT INTO t_kds_replication_line_state "
                        + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,workflow_queue,prep_remaining,cook_remaining,ready_remaining,remaining_quantity,local_revision,payload_json) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE workflow_queue=VALUES(workflow_queue),prep_remaining=VALUES(prep_remaining),cook_remaining=VALUES(cook_remaining),ready_remaining=VALUES(ready_remaining),remaining_quantity=VALUES(remaining_quantity),local_revision=VALUES(local_revision),payload_json=VALUES(payload_json),updated_at=NOW()",
                shopId, localOrderId, localDetailId, cloudOrderId, cloudDetailId, text(line, "workflow_queue"),
                prepRemaining, cookRemaining, readyRemaining, nullableLong(line, "remaining_quantity"), revision, json(line));
        jdbc.update("UPDATE t_kds_replication_detail_map SET last_local_revision=?,updated_at=NOW() WHERE shop_id=? AND local_detail_id=?",
                revision, shopId, localDetailId);
    }

    private void applyAvailability(int shopId, JsonNode payload) {
        String operationType = text(payload, "operation_type");
        JsonNode availability = payload.get("dish_availability");
        if (availability == null || !availability.isArray()) {
            return; // 补丁式事件不携带库存快照
        }
        for (JsonNode dish : availability) {
            int dishId = positiveInt(dish, "dish_id");
            long revision = requiredLong(dish, "availability_revision");
            List<Long> current = jdbc.queryForList("SELECT availability_revision FROM t_kds_replication_inventory_state "
                    + "WHERE shop_id=? AND dish_id=? FOR UPDATE", Long.class, shopId, dishId);
            if (!current.isEmpty() && revision <= current.get(0)) continue;
            Integer stock = dish.has("stock") && !dish.get("stock").isNull() ? nullableStockInt(dish, "stock") : null;
            Integer soldOut = dish.has("sold_out") ? (dish.get("sold_out").asBoolean(false) ? 1 : 0) : null;
            jdbc.update("INSERT INTO t_kds_replication_inventory_state (shop_id,dish_id,availability_revision,stock,sold_out,payload_json) "
                            + "VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE availability_revision=VALUES(availability_revision),stock=VALUES(stock),sold_out=VALUES(sold_out),payload_json=VALUES(payload_json),updated_at=NOW()",
                    shopId, dishId, revision, stock, soldOut, json(dish));
            if ("lack_item".equals(operationType) || "refund_item".equals(operationType)) {
                availabilityService.applySnapshot(shopId, dishId, stock, soldOut, operationType);
            }
        }
    }

    private KdsReplicationOutcome applyOrderCreated(StoredEvent event, int shopId,
                                                    HttpServletRequest servletRequest) {
        JsonNode payload = parse(event.payloadJson);
        long localOrderId = requiredLong(payload, "local_order_id");
        List<Map<String, Object>> mapped = jdbc.queryForList(
                "SELECT cloud_order_id,cloud_order_no FROM t_kds_replication_order_map "
                        + "WHERE shop_id=? AND local_order_id=? FOR UPDATE", shopId, localOrderId);
        if (!mapped.isEmpty()) {
            Map<String, Object> data = baseResult(event.eventId, true);
            data.putAll(mapped.get(0));
            data.put("detail_mappings", detailMappings(shopId, localOrderId));
            acknowledge(event.id, "applied", data);
            return KdsReplicationOutcome.ok(data);
        }

        JsonNode lines = payload.get("lines");
        if (lines == null || !lines.isArray() || lines.size() == 0) {
            throw new IllegalArgumentException("payload.lines must not be empty");
        }
        List<Long> localDetailIds = new ArrayList<>();
        OrderDTO dto = buildOrder(shopId, payload, lines, localDetailIds);
        R created;
        try (KdsCloudReplicationContext.Scope ignored = KdsCloudReplicationContext.open()) {
            created = orderController.create(dto, servletRequest);
        }
        Object code = created != null ? created.get("code") : null;
        if (!(code instanceof Number) || ((Number) code).intValue() != 0 || dto.getId() == null) {
            throw new KdsReplicationException(created != null && created.get("msg") != null
                    ? String.valueOf(created.get("msg")) : "cloud order creation rejected");
        }
        List<OrderDetail> cloudDetails = orderDetailService.list(new QueryWrapper<OrderDetail>()
                .eq("mId", dto.getId()).orderByAsc("id"));
        List<OrderDetail> matched = matchCloudDetails(lines, cloudDetails);
        if (matched.size() != localDetailIds.size()) {
            throw new KdsReplicationException("cloud detail mapping is incomplete");
        }
        Long createdAt = nullableLong(payload, "created_at_ms");
        if (createdAt != null) {
            jdbc.update("UPDATE t_order SET order_time=? WHERE id=? AND shop_id=?",
                    new Date(createdAt), dto.getId(), shopId);
        }
        jdbc.update("INSERT INTO t_kds_replication_order_map "
                        + "(shop_id,local_order_id,aggregate_key,local_order_no,cloud_order_id,cloud_order_no) VALUES (?,?,?,?,?,?)",
                shopId, localOrderId, event.aggregateKey, text(payload, "order_no"), dto.getId(), dto.getOrder_no());
        List<Map<String, Object>> detailMappings = new ArrayList<>();
        for (int i = 0; i < localDetailIds.size(); i++) {
            OrderDetail detail = matched.get(i);
            jdbc.update("INSERT INTO t_kds_replication_detail_map "
                            + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,last_local_revision) "
                            + "VALUES (?,?,?,?,?,0)",
                    shopId, localOrderId, localDetailIds.get(i), dto.getId(), detail.getId());
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("local_detail_id", localDetailIds.get(i));
            item.put("cloud_detail_id", detail.getId());
            detailMappings.add(item);
        }
        Map<String, Object> data = baseResult(event.eventId, false);
        data.put("cloud_order_id", dto.getId());
        data.put("cloud_order_no", dto.getOrder_no());
        data.put("detail_mappings", detailMappings);
        acknowledge(event.id, "applied", data);
        jdbc.update("UPDATE t_kds_replication_aggregate SET order_created_applied=1,last_occurred_at_ms=?,updated_at=NOW() "
                + "WHERE shop_id=? AND aggregate_key=?", occurredAt(event.id), shopId, event.aggregateKey);
        return KdsReplicationOutcome.ok(data);
    }

    private KdsReplicationOutcome applyAdvanceItem(StoredEvent event, int shopId) {
        JsonNode payload = parse(event.payloadJson);
        long localOrderId = requiredLong(payload, "order_id");
        long localDetailId = requiredLong(payload, "detail_id");
        long revision = requiredLong(payload, "local_revision");
        List<Map<String, Object>> mappings = jdbc.queryForList(
                "SELECT dm.cloud_order_id,dm.cloud_detail_id,dm.last_local_revision,om.cloud_order_no "
                        + "FROM t_kds_replication_detail_map dm JOIN t_kds_replication_order_map om "
                        + "ON om.shop_id=dm.shop_id AND om.local_order_id=dm.local_order_id "
                        + "WHERE dm.shop_id=? AND dm.local_order_id=? AND dm.local_detail_id=? FOR UPDATE",
                shopId, localOrderId, localDetailId);
        if (mappings.isEmpty() && "formal".equals(text(payload, "id_namespace"))
                && ensureFormalMapping(shopId, localOrderId, localDetailId, event.aggregateKey)) {
            mappings = jdbc.queryForList(
                    "SELECT dm.cloud_order_id,dm.cloud_detail_id,dm.last_local_revision,om.cloud_order_no "
                            + "FROM t_kds_replication_detail_map dm JOIN t_kds_replication_order_map om "
                            + "ON om.shop_id=dm.shop_id AND om.local_order_id=dm.local_order_id "
                            + "WHERE dm.shop_id=? AND dm.local_order_id=? AND dm.local_detail_id=? FOR UPDATE",
                    shopId, localOrderId, localDetailId);
        }
        if (mappings.isEmpty()) {
            jdbc.update("UPDATE t_kds_replication_event SET status='pending',error_code=4090,error_message=?,updated_at=NOW() WHERE id=?",
                    "order/detail mapping is not available", event.id);
            return KdsReplicationOutcome.pending("aggregate prerequisite has not arrived", eventRef(event.eventId));
        }
        Map<String, Object> mapping = mappings.get(0);
        if ("formal".equals(text(payload, "id_namespace"))
                && (((Number) mapping.get("cloud_order_id")).longValue() != localOrderId
                || ((Number) mapping.get("cloud_detail_id")).longValue() != localDetailId)) {
            throw new KdsReplicationException("formal IDs conflict with an existing legacy mapping");
        }
        long currentRevision = ((Number) mapping.get("last_local_revision")).longValue();
        if (KdsReplicationPolicy.revisionDecision(currentRevision, revision)
                == KdsReplicationPolicy.RevisionDecision.IGNORE_OLD) {
            Map<String, Object> data = baseResult(event.eventId, false);
            data.put("ignored_old_revision", true);
            data.put("local_revision", revision);
            acknowledge(event.id, "ignored", data);
            return KdsReplicationOutcome.ok(data);
        }
        int cloudOrderId = ((Number) mapping.get("cloud_order_id")).intValue();
        int cloudDetailId = ((Number) mapping.get("cloud_detail_id")).intValue();
        OrderDetail detail = orderDetailService.getById(cloudDetailId);
        if (detail == null) {
            throw new KdsReplicationException("mapped cloud detail no longer exists");
        }
        int quantity = parseQuantity(detail.getQuantity());
        int prepRemaining = boundedInt(payload, "prep_remaining", quantity);
        int cookRemaining = boundedInt(payload, "cook_remaining", quantity);
        int readyRemaining = boundedInt(payload, "ready_remaining", quantity);
        boolean done = payload.path("done_line").asInt(0) == 1;
        KdsReplicationPolicy.LineProgress progress = KdsReplicationPolicy.lineProgress(
                quantity, prepRemaining, cookRemaining, readyRemaining, done);
        int prep = progress.getPrep();
        int cooked = progress.getCooked();
        int served = progress.getServed();
        boolean completed = done || served >= quantity;
        int itemStatus = completed ? KdsItemStatus.DONE
                : (prep > 0 || cooked > 0 || served > 0 ? KdsItemStatus.COOKING : KdsItemStatus.PENDING);
        int affected = jdbc.update("UPDATE t_kds_ticket SET prep_quantity=?,cooked_quantity=?,served_quantity=?,item_status=?,archived=?,row_version=?,"
                        + "done_at=CASE WHEN ?=1 THEN COALESCE(done_at,NOW()) ELSE done_at END,updated_at=NOW() "
                        + "WHERE shop_id=? AND detail_id=?",
                prep, cooked, served, itemStatus, completed ? 1 : 0, revision, completed ? 1 : 0, shopId, cloudDetailId);
        if (affected == 0 && !ticketExists(shopId, cloudDetailId)
                && ensureTicketForProgress(shopId, cloudOrderId, cloudDetailId, detail)) {
            affected = jdbc.update("UPDATE t_kds_ticket SET prep_quantity=?,cooked_quantity=?,served_quantity=?,item_status=?,archived=?,row_version=?,"
                            + "done_at=CASE WHEN ?=1 THEN COALESCE(done_at,NOW()) ELSE done_at END,updated_at=NOW() "
                            + "WHERE shop_id=? AND detail_id=?",
                    prep, cooked, served, itemStatus, completed ? 1 : 0, revision, completed ? 1 : 0, shopId, cloudDetailId);
            if (affected == 0 && !ticketExists(shopId, cloudDetailId)) {
                throw missingTicketConflict(shopId, cloudOrderId, cloudDetailId);
            }
        }
        jdbc.update("INSERT INTO t_kds_replication_line_state "
                        + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,workflow_queue,"
                        + "prep_remaining,cook_remaining,ready_remaining,remaining_quantity,local_revision,payload_json) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE workflow_queue=VALUES(workflow_queue),"
                        + "prep_remaining=VALUES(prep_remaining),cook_remaining=VALUES(cook_remaining),"
                        + "ready_remaining=VALUES(ready_remaining),remaining_quantity=VALUES(remaining_quantity),"
                        + "local_revision=VALUES(local_revision),payload_json=VALUES(payload_json),updated_at=NOW()",
                shopId, localOrderId, localDetailId, cloudOrderId, cloudDetailId, text(payload, "workflow_queue"),
                prepRemaining, cookRemaining, readyRemaining, nullableLong(payload, "remaining_quantity"), revision, json(payload));
        jdbc.update("UPDATE t_kds_replication_detail_map SET last_local_revision=?,updated_at=NOW() "
                + "WHERE shop_id=? AND local_detail_id=?", revision, shopId, localDetailId);
        updateCloudOrderProjection(shopId, localOrderId, cloudOrderId, String.valueOf(mapping.get("cloud_order_no")));
        Map<String, Object> data = baseResult(event.eventId, false);
        data.put("cloud_order_id", cloudOrderId);
        data.put("cloud_detail_id", cloudDetailId);
        data.put("local_revision", revision);
        acknowledge(event.id, "applied", data);
        return KdsReplicationOutcome.ok(data);
    }

    /**
     * A progress event is allowed to repair a missing ticket only for an accepted cloud order.
     * The subsequent UPDATE is the authoritative proof that the ticket was actually rebuilt.
     */
    void rebuildMissingTicket(int shopId, int cloudOrderId, int cloudDetailId) {
        if (ticketService == null || orderService == null) {
            throw new KdsReplicationException("KDS ticket rebuild service is unavailable");
        }
        Order order = orderService.getById(cloudOrderId);
        if (order == null || order.getShop_id() == null || order.getShop_id() != shopId) {
            throw new KdsReplicationException("mapped cloud order is unavailable for ticket rebuild");
        }
        if (!KdsOrderAcceptance.isAccepted(order)) {
            throw new KdsReplicationException("cannot rebuild KDS ticket for an unaccepted order");
        }
        ticketService.createTicketsForOrder(order, Collections.singletonList(cloudDetailId), KdsOrderHook.Trigger.MANUAL);
        log.info("[kds-replication] rebuilt missing ticket shop_id={} order_id={} detail_id={}",
                shopId, cloudOrderId, cloudDetailId);
    }

    boolean ensureTicketForProgress(int shopId, int cloudOrderId, int cloudDetailId, OrderDetail detail) {
        String skipReason = ticketService != null ? ticketService.ticketSkipReason(shopId, detail) : null;
        if (skipReason != null) {
            log.info("[kds-replication] progress persisted without station ticket shop_id={} order_id={} detail_id={} reason={}",
                    shopId, cloudOrderId, cloudDetailId, skipReason);
            return false;
        }
        rebuildMissingTicket(shopId, cloudOrderId, cloudDetailId);
        if (!ticketExists(shopId, cloudDetailId)) {
            throw missingTicketConflict(shopId, cloudOrderId, cloudDetailId);
        }
        return true;
    }

    private KdsReplicationException missingTicketConflict(int shopId, int cloudOrderId, int cloudDetailId) {
        return new KdsReplicationException("KDS ticket rebuild produced no ticket"
                + " [shopId=" + shopId + ", orderId=" + cloudOrderId + ", detailId=" + cloudDetailId + "]");
    }

    boolean ticketExists(int shopId, int cloudDetailId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_kds_ticket WHERE shop_id=? AND detail_id=?",
                Integer.class, shopId, cloudDetailId);
        return count != null && count > 0;
    }

    private OrderDTO buildOrder(int shopId, JsonNode payload, JsonNode lines, List<Long> localDetailIds) {
        JsonNode rootCloud = payload.path("cloud_payload");
        OrderDTO dto = rootCloud.isObject() ? objectMapper.convertValue(rootCloud, OrderDTO.class) : new OrderDTO();
        dto.setId(null);
        dto.setOrder_no(null);
        dto.setShop_id(shopId);
        dto.setTable_number(text(payload, "table_number"));
        dto.setNumber_of_diners(text(payload, "number_of_diners"));
        dto.setRemark(text(payload, "remark"));
        dto.setDineInOrTakeOut(fulfillment(text(payload, "fulfillment_type")));
        dto.setMerchantId("1");
        dto.setOpenid(cloudText(payload, "openid", "cashier-replication-shop-" + shopId));
        Long createdAt = nullableLong(payload, "created_at_ms");
        if (createdAt != null) {
            dto.setOrder_time(new Date(createdAt));
        }
        List<OrderDetail> details = new ArrayList<>();
        BigDecimal total = BigDecimal.ZERO;
        for (JsonNode line : lines) {
            long localDetailId = localDetailId(line);
            if (localDetailId <= 0 || localDetailIds.contains(localDetailId)) {
                throw new IllegalArgumentException("each line requires a unique positive local_detail_id/detail_id/id");
            }
            localDetailIds.add(localDetailId);
            JsonNode cloud = line.path("cloud_payload");
            OrderDetail detail = cloud.isObject() ? objectMapper.convertValue(cloud, OrderDetail.class) : new OrderDetail();
            detail.setId(null);
            detail.setMId(null);
            detail.setMorder_no(null);
            int dishId = line.path("dish_id").asInt(detail.getDish_id() != null ? detail.getDish_id() : 0);
            Dish dish = dishId > 0 ? dishService.getById(dishId) : null;
            if (dish == null) {
                throw new IllegalArgumentException("dish_id does not exist: " + dishId);
            }
            if (dish.getUnitprice() == null) {
                throw new IllegalArgumentException("dish has no unit price: " + dishId);
            }
            int quantity = positiveInt(line, "quantity");
            detail.setDish_id(dishId);
            detail.setName(dish.getName());
            detail.setUnit(firstText(text(line, "unit"), dish.getUnit()));
            detail.setSelectedSpicy(firstText(detail.getSelectedSpicy(), text(line, "specification")));
            detail.setCid(detail.getCid() != null ? detail.getCid() : String.valueOf(dish.getTypeId()));
            detail.setQuantity(String.valueOf(quantity));
            if (detail.getTotal_price() == null) {
                detail.setTotal_price(BigDecimal.valueOf(dish.getUnitprice()).multiply(BigDecimal.valueOf(quantity))
                        .setScale(2, RoundingMode.HALF_UP).doubleValue());
            }
            total = total.add(BigDecimal.valueOf(detail.getTotal_price()));
            details.add(detail);
        }
        dto.setGoods_list(details);
        dto.setSett_amount(total.setScale(2, RoundingMode.HALF_UP).doubleValue());
        return dto;
    }

    private List<OrderDetail> matchCloudDetails(JsonNode lines, List<OrderDetail> cloudDetails) {
        List<OrderDetail> remaining = new ArrayList<>(cloudDetails);
        List<OrderDetail> result = new ArrayList<>();
        for (JsonNode line : lines) {
            int dishId = line.path("dish_id").asInt(0);
            OrderDetail match = null;
            for (OrderDetail candidate : remaining) {
                if (candidate.getDish_id() != null && candidate.getDish_id() == dishId) {
                    match = candidate;
                    break;
                }
            }
            if (match == null) {
                throw new KdsReplicationException("cannot map local line to cloud detail for dish_id=" + dishId);
            }
            remaining.remove(match);
            result.add(match);
        }
        return result;
    }

    private void drainPending(int shopId, String aggregateKey, HttpServletRequest request) {
        List<Long> ids = jdbc.queryForList("SELECT id FROM t_kds_replication_event "
                        + "WHERE shop_id=? AND aggregate_key=? AND status='pending' ORDER BY occurred_at_ms,id",
                Long.class, shopId, aggregateKey);
        for (Long id : ids) {
            try {
                tx.execute(status -> apply(id, shopId, request));
            } catch (Exception ex) {
                log.warn("[kds-replication] pending event remains queued id={}: {}", id, ex.getMessage());
                break;
            }
        }
    }

    private void updateCloudOrderProjection(int shopId, long localOrderId, int cloudOrderId, String cloudOrderNo) {
        Map<String, Object> progress = jdbc.queryForMap(
                "SELECT COUNT(*) total_lines,"
                        + "SUM(CASE WHEN s.local_revision IS NOT NULL THEN 1 ELSE 0 END) state_lines,"
                        + "SUM(CASE WHEN s.ready_remaining=0 THEN 1 ELSE 0 END) done_lines,"
                        + "SUM(CASE WHEN s.local_revision IS NOT NULL AND (s.prep_remaining<dqty.qty OR s.cook_remaining<dqty.qty OR s.ready_remaining<dqty.qty) THEN 1 ELSE 0 END) progress_lines "
                        + "FROM t_kds_replication_detail_map dm "
                        + "JOIN (SELECT id,CAST(quantity AS UNSIGNED) qty FROM t_order_detail) dqty ON dqty.id=dm.cloud_detail_id "
                        + "LEFT JOIN t_kds_replication_line_state s ON s.shop_id=dm.shop_id AND s.local_detail_id=dm.local_detail_id "
                        + "WHERE dm.shop_id=? AND dm.local_order_id=?",
                shopId, localOrderId);
        int total = number(progress.get("total_lines"));
        int done = number(progress.get("done_lines"));
        int progressed = number(progress.get("progress_lines"));
        int status = total > 0 && done == total ? 40 : done > 0 ? 30 : progressed > 0 ? 20 : 10;
        jdbc.update("INSERT INTO t_kds_order (order_id,shop_id,order_no,kds_order_status,created_at,updated_at) "
                        + "VALUES (?,?,?,?,NOW(),NOW()) ON DUPLICATE KEY UPDATE kds_order_status=VALUES(kds_order_status),updated_at=NOW()",
                cloudOrderId, shopId, cloudOrderNo, status);
        if (status == 40) {
            jdbc.update("UPDATE t_order SET order_receiving='off_order', off_time=IFNULL(off_time, NOW()) "
                            + "WHERE id=? AND shop_id=? AND order_receiving='rec_order' "
                            + "AND (transac_status IS NULL OR transac_status!='cancelled')",
                    cloudOrderId, shopId);
        }
    }

    private static int number(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    private void ensureAggregate(int shopId, String aggregateKey) {
        jdbc.update("INSERT IGNORE INTO t_kds_replication_aggregate (shop_id,aggregate_key) VALUES (?,?)",
                shopId, aggregateKey);
        jdbc.queryForObject("SELECT aggregate_key FROM t_kds_replication_aggregate "
                + "WHERE shop_id=? AND aggregate_key=? FOR UPDATE", String.class, shopId, aggregateKey);
    }

    private StoredEvent eventById(long id) {
        return jdbc.queryForObject("SELECT id,shop_id,event_id,event_type,aggregate_key,occurred_at_ms,status,result_json,payload_json,publisher_device_code,request_fingerprint "
                        + "FROM t_kds_replication_event WHERE id=? FOR UPDATE",
                (rs, rowNum) -> new StoredEvent(rs.getLong("id"), rs.getInt("shop_id"), rs.getString("event_id"),
                        rs.getString("event_type"), rs.getString("aggregate_key"), rs.getString("status"),
                        rs.getString("result_json"), rs.getString("payload_json"), rs.getLong("occurred_at_ms"),
                        rs.getString("publisher_device_code"), rs.getString("request_fingerprint")), id);
    }

    private void acknowledge(long id, String status, Map<String, Object> data) {
        jdbc.update("UPDATE t_kds_replication_event SET status=?,result_json=?,error_code=NULL,error_message=NULL,"
                        + "applied_at=COALESCE(applied_at,NOW()),updated_at=NOW() WHERE id=?",
                status, json(data), id);
    }

    private KdsReplicationOutcome acknowledged(StoredEvent event, boolean duplicate) {
        Map<String, Object> data = event.resultJson != null ? map(event.resultJson) : baseResult(event.eventId, duplicate);
        data.put("duplicate", duplicate);
        return KdsReplicationOutcome.ok(data);
    }

    private void markError(String eventId, Integer shopId, int errorCode, String message) {
        if (!StringUtils.hasText(eventId) || shopId == null) {
            return;
        }
        try {
            String targetStatus = errorCode == 5000 ? "failed" : "dead_letter";
            tx.executeWithoutResult(status -> jdbc.update("UPDATE t_kds_replication_event "
                    + "SET status=?,error_code=?,error_message=?,dead_lettered_at=CASE WHEN ?='dead_letter' THEN COALESCE(dead_lettered_at,NOW()) ELSE dead_lettered_at END,updated_at=NOW() "
                    + "WHERE event_id=? AND shop_id=? AND status NOT IN ('applied','ignored','discarded','replaced')",
                    targetStatus, errorCode, truncate(message, 500), targetStatus, eventId, shopId));
        } catch (Exception ignored) {
            log.warn("[kds-replication] failed event could not be marked event_id={}", eventId);
        }
    }

    private List<Map<String, Object>> detailMappings(int shopId, long localOrderId) {
        return jdbc.queryForList("SELECT local_detail_id,cloud_detail_id FROM t_kds_replication_detail_map "
                + "WHERE shop_id=? AND local_order_id=? ORDER BY local_detail_id", shopId, localOrderId);
    }

    private void ensureFormalMappings(int shopId, long orderId, JsonNode lines, String aggregateKey) {
        List<Long> detailIds = new ArrayList<>();
        for (JsonNode line : lines) detailIds.add(replicationDetailId(line));
        ensureFormalOrderMapping(shopId, orderId, aggregateKey);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id FROM t_order_detail WHERE mId=? ORDER BY id", orderId);
        Set<Long> owned = new HashSet<>();
        for (Map<String, Object> row : rows) owned.add(((Number) row.get("id")).longValue());
        if (!owned.equals(new HashSet<>(detailIds))) {
            throw new KdsReplicationException("lines must completely cover formal order details");
        }
        for (Long detailId : detailIds) insertFormalDetailMapping(shopId, orderId, detailId);
    }

    /**
     * §4.2：为「已知正式订单 + 携带 local_detail_id 的未映射行」按快照语义创建云端正式明细
     * （云端出生订单上的本地加菜行）。价格按门店覆盖价兜底总部价计算；已退/已移除的行直接物化
     * 为 refunded 终态。此类明细云端从未扣减库存，创建时不做任何库存动作。
     *
     * @return 与 mappedRows 同形的映射行（last_local_revision=0，无 previous_payload_json）
     */
    private Map<String, Object> createFormalDetailFromSnapshot(int shopId, long cloudOrderId,
                                                               String cloudOrderNo, JsonNode line) {
        long localLineId = replicationDetailId(line);
        int dishId = positiveInt(line, "dish_id");
        List<Map<String, Object>> dishRows = jdbc.queryForList(
                "SELECT d.typeId, COALESCE(ds.unitprice, d.unitprice) AS price FROM t_dish d "
                        + "LEFT JOIN t_dish_shop ds ON ds.dish_id=d.id AND ds.shop_id=? WHERE d.id=?",
                shopId, dishId);
        if (dishRows.isEmpty()) {
            throw new IllegalArgumentException("lines[].dish_id does not exist in cloud catalog");
        }
        int lineQty = positiveInt(line, "line_quantity");
        int refunded = nonNegativeInt(line, "refunded_quantity");
        int remain = lineQty - refunded;
        boolean removed = line.path("removed").asBoolean(false);
        Object priceObj = dishRows.get(0).get("price");
        double unitPrice = priceObj != null ? ((Number) priceObj).doubleValue() : 0d;

        OrderDetail detail = new OrderDetail();
        detail.setMId((int) cloudOrderId);
        detail.setName(text(line, "dish_name"));
        detail.setQuantity(String.valueOf(remain));
        detail.setUnit(text(line, "unit"));
        detail.setTotal_price(Math.round(unitPrice * remain * 100) / 100.0);
        detail.setMorder_no(cloudOrderNo);
        Object typeId = dishRows.get(0).get("typeId");
        detail.setCid(typeId != null ? String.valueOf(typeId) : null);
        detail.setDish_id(dishId);
        detail.setRefunded_quantity(refunded);
        detail.setRemark(text(line, "remark"));
        if (remain == 0 || removed) {
            detail.setLine_status(OrderDetailLineStatus.REFUNDED);
            detail.setOrder_rece(OrderDetailLineStatus.REFUNDED);
        }
        orderDetailService.save(detail);
        jdbc.update("INSERT INTO t_kds_replication_detail_map "
                        + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,last_local_revision) "
                        + "VALUES (?,?,?,?,?,0)",
                shopId, cloudOrderId, localLineId, cloudOrderId, detail.getId());
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("local_detail_id", localLineId);
        row.put("cloud_order_id", cloudOrderId);
        row.put("cloud_detail_id", detail.getId().longValue());
        row.put("last_local_revision", 0L);
        row.put("cloud_order_no", cloudOrderNo);
        row.put("previous_payload_json", null);
        return row;
    }

    private boolean ensureFormalMapping(int shopId, long orderId, long detailId, String aggregateKey) {
        if (!formalOrderExists(shopId, orderId)) return false;
        ensureFormalOrderMapping(shopId, orderId, aggregateKey);
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_order_detail WHERE id=? AND mId=?", Integer.class, detailId, orderId);
        if (count == null || count != 1) return false;
        insertFormalDetailMapping(shopId, orderId, detailId);
        return true;
    }

    private void ensureFormalOrderMapping(int shopId, long orderId, String aggregateKey) {
        List<Map<String, Object>> orders = jdbc.queryForList(
                "SELECT order_no FROM t_order WHERE id=? AND shop_id=? FOR UPDATE", orderId, shopId);
        if (orders.isEmpty()) throw new KdsReplicationException("formal order does not belong to the current shop");
        String orderNo = String.valueOf(orders.get(0).get("order_no"));
        jdbc.update("INSERT IGNORE INTO t_kds_replication_order_map "
                        + "(shop_id,local_order_id,aggregate_key,local_order_no,cloud_order_id,cloud_order_no) "
                        + "VALUES (?,?,?,?,?,?)",
                shopId, orderId, aggregateKey, orderNo, orderId, orderNo);
    }

    private boolean formalOrderExists(int shopId, long orderId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM t_order WHERE id=? AND shop_id=?", Integer.class, orderId, shopId);
        return count != null && count == 1;
    }

    private void insertFormalDetailMapping(int shopId, long orderId, long detailId) {
        jdbc.update("INSERT IGNORE INTO t_kds_replication_detail_map "
                        + "(shop_id,local_order_id,local_detail_id,cloud_order_id,cloud_detail_id,last_local_revision) "
                        + "VALUES (?,?,?,?,?,0)",
                shopId, orderId, detailId, orderId, detailId);
    }

    private long occurredAt(long id) {
        return jdbc.queryForObject("SELECT occurred_at_ms FROM t_kds_replication_event WHERE id=?", Long.class, id);
    }

    private static boolean isAcknowledged(String status) {
        return "applied".equals(status) || "ignored".equals(status)
                || "discarded".equals(status) || "replaced".equals(status);
    }

    private static Map<String, Object> baseResult(String eventId, boolean duplicate) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("event_id", eventId);
        data.put("accepted", true);
        data.put("duplicate", duplicate);
        return data;
    }

    private static Map<String, Object> eventRef(KdsReplicationEventRequest request) {
        return eventRef(request != null ? request.getEventId() : null);
    }

    private static Map<String, Object> eventRef(String eventId) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("event_id", eventId);
        data.put("accepted", false);
        return data;
    }

    private static String safeEventId(KdsReplicationEventRequest request) {
        return request != null && StringUtils.hasText(request.getEventId()) ? request.getEventId() : "<missing>";
    }

    private static String cashierDeviceCode(HttpServletRequest request) {
        String value = request != null ? request.getHeader(CASHIER_DEVICE_HEADER) : null;
        if (!StringUtils.hasText(value) || value.trim().length() > 64) {
            throw new KdsReplicationAuthorizationException(
                    CASHIER_DEVICE_HEADER + " is required and must not exceed 64 characters");
        }
        return value.trim();
    }

    private static String header(HttpServletRequest request, String name, String fallback) {
        String value = request != null ? request.getHeader(name) : null;
        return StringUtils.hasText(value) ? truncate(value.trim(), 128) : fallback;
    }

    private void requireAuthorizedPublisher(int shopId, String publisherDeviceCode) {
        try {
            authorityService.requirePrimaryPublisher(shopId, publisherDeviceCode);
        } catch (KdsReplicationException ex) {
            throw new KdsReplicationAuthorizationException(ex.getMessage());
        }
    }

    private static long requiredLong(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || !value.isIntegralNumber() || !value.canConvertToLong() || value.asLong() <= 0) {
            throw new IllegalArgumentException(field + " must be a positive integer");
        }
        return value.asLong();
    }

    private static long stateOrderId(JsonNode payload) {
        return isPatchStatePayload(payload) ? patchStateOrderId(payload) : replicationOrderId(payload);
    }

    private static long replicationOrderId(JsonNode node) {
        return node != null && node.hasNonNull("local_order_id")
                ? requiredLong(node, "local_order_id") : requiredLong(node, "order_id");
    }

    private static long replicationDetailId(JsonNode node) {
        return node != null && node.hasNonNull("local_detail_id")
                ? requiredLong(node, "local_detail_id") : requiredLong(node, "detail_id");
    }

    private static int nonNegativeInt(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || !value.isIntegralNumber() || !value.canConvertToInt() || value.asInt() < 0) {
            throw new IllegalArgumentException(field + " must be a non-negative integer");
        }
        return value.asInt();
    }

    /**
     * 库存快照值：允许 -1 作为「不限量」哨兵（与 t_dish_shop.stock 内部语义一致），其余必须为非负整数。
     * 收银端可能直接外发本地库存值，云端宽容接收；新客户端应优先省略或置 null。
     */
    private static Integer nullableStockInt(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || value.isNull()) {
            return null;
        }
        if (!value.isIntegralNumber() || !value.canConvertToInt() || value.asInt() < -1) {
            throw new IllegalArgumentException(field + " must be a non-negative integer or -1 (unlimited)");
        }
        return value.asInt();
    }

    private static Long nullableLong(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        return value != null && value.canConvertToLong() ? value.asLong() : null;
    }

    private static int positiveInt(JsonNode node, String field) {
        long value = requiredLong(node, field);
        if (value > Integer.MAX_VALUE) {
            throw new IllegalArgumentException(field + " is too large");
        }
        return (int) value;
    }

    private static int boundedInt(JsonNode node, String field, int max) {
        JsonNode value = node.get(field);
        if (value == null || !value.isIntegralNumber() || !value.canConvertToInt()
                || value.asInt() < 0 || value.asInt() > max) {
            throw new IllegalArgumentException(field + " must be between 0 and line quantity");
        }
        return value.asInt();
    }

    private static String requiredText(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || !value.isTextual() || !StringUtils.hasText(value.asText())) {
            throw new IllegalArgumentException(field + " must be a non-empty string");
        }
        return value.asText();
    }

    private static void requiredNullableText(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || (!value.isNull() && !value.isTextual())) {
            throw new IllegalArgumentException(field + " must be present and be a string or null");
        }
    }

    private static boolean requiredBoolean(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        if (value == null || !value.isBoolean()) {
            throw new IllegalArgumentException(field + " must be boolean");
        }
        return value.asBoolean();
    }

    private static String requireFulfillmentBucket(JsonNode line) {
        String value = requiredText(line, "fulfillment_bucket");
        if (!java.util.Arrays.asList("dine_in", "takeout", "pickup", "pack", "delivery").contains(value)) {
            throw new IllegalArgumentException("fulfillment_bucket must be a canonical LAN v2 value");
        }
        return value;
    }

    private static long localDetailId(JsonNode line) {
        for (String field : new String[]{"local_detail_id", "detail_id", "id"}) {
            Long value = nullableLong(line, field);
            if (value != null) return value;
        }
        JsonNode cloud = line.path("cloud_payload");
        for (String field : new String[]{"local_detail_id", "detail_id", "id"}) {
            Long value = nullableLong(cloud, field);
            if (value != null) return value;
        }
        return -1;
    }

    private static int parseQuantity(String quantity) {
        try {
            int value = new BigDecimal(quantity).intValueExact();
            if (value > 0) return value;
        } catch (Exception ignored) {
        }
        throw new KdsReplicationException("mapped cloud detail quantity is invalid");
    }

    private static String fulfillment(String value) {
        if ("dine_in".equalsIgnoreCase(value)) return "\u5802\u98df";
        if ("takeout".equalsIgnoreCase(value)) return "\u6253\u5305";
        if ("delivery".equalsIgnoreCase(value)) return "\u5916\u5356";
        throw new IllegalArgumentException("fulfillment_type must be dine_in, takeout, or delivery");
    }

    private static String firstText(String... values) {
        for (String value : values) if (StringUtils.hasText(value)) return value;
        return null;
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node != null ? node.get(field) : null;
        return value != null && !value.isNull() ? value.asText() : null;
    }

    private static String cloudText(JsonNode payload, String field, String fallback) {
        String direct = text(payload, field);
        if (StringUtils.hasText(direct)) return direct;
        String nested = text(payload.path("cloud_payload"), field);
        return StringUtils.hasText(nested) ? nested : fallback;
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("stored event payload is invalid", ex);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> map(String json) {
        try {
            return objectMapper.readValue(json, LinkedHashMap.class);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("stored event result is invalid", ex);
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("event JSON serialization failed", ex);
        }
    }

    private static String truncate(String value, int max) {
        if (value == null) return null;
        return value.length() <= max ? value : value.substring(0, max);
    }

    private static final class StoredEvent {
        private final long id;
        private final int shopId;
        private final String eventId;
        private final String eventType;
        private final String aggregateKey;
        private final String status;
        private final String resultJson;
        private final String payloadJson;
        private final long occurredAtMs;
        private final String publisherDeviceCode;
        private final String requestFingerprint;

        private StoredEvent(long id, int shopId, String eventId, String eventType, String aggregateKey,
                            String status, String resultJson, String payloadJson, long occurredAtMs,
                            String publisherDeviceCode, String requestFingerprint) {
            this.id = id;
            this.shopId = shopId;
            this.eventId = eventId;
            this.eventType = eventType;
            this.aggregateKey = aggregateKey;
            this.status = status;
            this.resultJson = resultJson;
            this.payloadJson = payloadJson;
            this.occurredAtMs = occurredAtMs;
            this.publisherDeviceCode = publisherDeviceCode;
            this.requestFingerprint = requestFingerprint;
        }
    }
}
