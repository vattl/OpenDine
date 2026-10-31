package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsBoardMergeRules;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.KdsWorkflow;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.delivery.CashierKdsDeliveryException;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.entity.Shop;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopBusinessWindowResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.util.StringUtils;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * KDS V2 协议服务：实现与 kds_app 客户端强类型契约 100% 对齐的 API。
 */
@Service
public class KdsWorkflowV2Service {

    private static final Logger log = LoggerFactory.getLogger(KdsWorkflowV2Service.class);
    private static final ZoneId SHOP_ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter HH_MM = DateTimeFormatter.ofPattern("HH:mm");

    @Autowired
    private KdsWorkflowService workflowService;
    @Autowired
    private KdsOverviewBoardService overviewBoardService;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IDishService dishService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsTicketFlagService ticketFlagService;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsStatsService statsService;
    @Autowired
    private JdbcTemplate jdbc;
    @Autowired(required = false)
    private IShopService shopService;
    @Autowired(required = false)
    private KdsOrderHook kdsOrderHook;

    @Autowired(required = false)
    private KdsV2CommandLedger commandLedger;
    @Autowired(required = false)
    private KdsV2EventStore eventStore;
    @Autowired
    private com.lanf.service.impl.OrderDetailRefundService orderDetailRefundService;
    @Autowired(required = false)
    private com.lanf.controller.OrderController orderController;
    @Autowired
    private com.fasterxml.jackson.databind.ObjectMapper objectMapper;

    private final ConcurrentHashMap<Integer, AtomicInteger> seqByShop = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Integer, LinkedList<Map<String, Object>>> eventLogByShop = new ConcurrentHashMap<>();

    private void appendEventLog(int shopId, Map<String, Object> envelope) {
        if (eventStore != null) {
            // T007: 当持久化 eventStore 存在时，t_kds_v2_event + archive 为唯一事件真源；
            // 杜绝堆内存重复存储事件日志，避免长期运行内存泄漏。
            return;
        }
        LinkedList<Map<String, Object>> logList = eventLogByShop.computeIfAbsent(shopId, k -> new LinkedList<>());
        synchronized (logList) {
            logList.addLast(envelope);
            while (logList.size() > 500) {
                logList.removeFirst();
            }
        }
    }

    public int getNextEventSeq(int shopId) {
        if (eventStore != null) {
            return (int) eventStore.nextSequence(shopId);
        }
        return seqByShop.computeIfAbsent(shopId, k -> new AtomicInteger(1)).getAndIncrement();
    }

    public int getCurrentEventSeq(int shopId) {
        if (eventStore != null) {
            return (int) eventStore.currentSequence(shopId);
        }
        AtomicInteger seq = seqByShop.get(shopId);
        return seq != null ? seq.get() : 0;
    }

    /**
     * 计算当前门店当前活动营业班次的起始时间（[当前班次起始日 settle_time]）。
     * 若未配置 settle_time 或异常，兜底为 24 小时前。
     */
    public Date businessDayStart(int shopId) {
        if (shopId <= 0 || shopService == null) {
            return new Date(System.currentTimeMillis() - 24L * 3600 * 1000);
        }
        try {
            Shop shop = shopService.getById(shopId);
            if (shop != null && StringUtils.hasText(shop.getSettle_time())) {
                return ShopBusinessWindowResolver.operationalWindow(shop)[0];
            }
        } catch (Exception ignore) {
        }
        return new Date(System.currentTimeMillis() - 24L * 3600 * 1000);
    }

    /**
     * 自动归档上一营业班次之前创建、且仍处于未归档(archived=0)的遗留工单。
     * 由后台定时任务异步执行，严禁在 GET bootstrap 请求中执行写 SQL。
     */
    public int archiveStalePastDayTickets(int shopId, Date bizDayStart) {
        if (shopId <= 0 || bizDayStart == null || jdbc == null) return 0;
        try {
            return jdbc.update("UPDATE t_kds_ticket SET archived = 1, updated_at = NOW() WHERE shop_id = ? AND created_at < ? AND archived = 0",
                    shopId, bizDayStart);
        } catch (Exception e) {
            log.warn("[kds/v2] auto archive stale tickets failed shop={}: {}", shopId, e.getMessage());
            return 0;
        }
    }

    /**
     * 批量补偿当前营业班次内已接单但因档口缺失等原因遗漏工单的活动订单。
     * 采用单条批量反连接 SQL，杜绝逐单循环 selectCount N+1 查询。
     * 由后台定时/修复 worker 异步执行，严禁在 GET bootstrap 客户端读取热路径中执行。
     */
    public int compensateMissingTicketsForActiveOrdersBatch(int shopId, Date bizDayStart) {
        if (shopId <= 0 || bizDayStart == null || jdbc == null || orderService == null || kdsOrderHook == null) return 0;
        try {
            String sql = "SELECT o.id FROM t_order o " +
                    "LEFT JOIN t_kds_ticket t ON o.id = t.order_id AND t.shop_id = o.shop_id AND t.item_status != 'VOID' " +
                    "WHERE o.shop_id = ? AND o.order_time >= ? AND o.order_receiving = 'rec_order' AND o.transac_status != 'cancelled' " +
                    "AND t.id IS NULL";
            List<Integer> missingOrderIds = jdbc.queryForList(sql, Integer.class, shopId, bizDayStart);
            if (missingOrderIds == null || missingOrderIds.isEmpty()) {
                return 0;
            }
            List<Order> missingOrders = orderService.listByIds(missingOrderIds);
            for (Order o : missingOrders) {
                kdsOrderHook.ensureTicketsForAcceptedOrder(o);
            }
            return missingOrders.size();
        } catch (Exception e) {
            log.warn("[kds/v2] batch compensate missing tickets failed shop={}: {}", shopId, e.getMessage());
            return 0;
        }
    }

    /**
     * 1. GET /kds/v2/bootstrap (纯只读热路径，无任何写 SQL，无 N+1 查询)
     */
    public Map<String, Object> buildBootstrap(KdsDevice device) {
        int shopId = device.getShop_id();
        long snapshotSequence = eventStore != null ? eventStore.currentSequence(shopId) : getCurrentEventSeq(shopId);
        boolean prepEnabled = configService.isPrepWorkflowEnabled(shopId, device.getStation_id());
        Set<String> screenTags = deviceService.screenTagsOf(device);
        Date bizDayStart = businessDayStart(shopId);

        // 1. 查询当前门店当前活动营业日内所有有效工单（未废弃，且在当前营业班次窗口内且未归档）
        QueryWrapper<KdsTicket> qw = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("screen_tag", screenTags)
                .ne("item_status", KdsItemStatus.VOID)
                .eq("archived", 0)
                .ge("created_at", bizDayStart);
        List<KdsTicket> tickets = ticketMapper.selectList(qw);

        Set<Integer> detailIds = new HashSet<>();
        Set<Integer> orderIds = new HashSet<>();
        for (KdsTicket t : tickets) {
            if (t.getDetail_id() != null) detailIds.add(t.getDetail_id());
            if (t.getOrder_id() != null) orderIds.add(t.getOrder_id());
        }

        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream().collect(HashMap::new, (m, d) -> m.put(d.getId(), d), HashMap::putAll);
        Map<Integer, Order> orderMap = orderIds.isEmpty() ? Collections.emptyMap()
                : orderService.listByIds(orderIds).stream().collect(HashMap::new, (m, o) -> m.put(o.getId(), o), HashMap::putAll);

        // 2. 按 detail_id 选取主工单
        Map<Integer, KdsTicket> primaryByDetail = new LinkedHashMap<>();
        for (KdsTicket t : tickets) {
            if (t.getDetail_id() == null) continue;
            primaryByDetail.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
        }

        // 3. 构建规范化的 lines 并分配到对应 queues
        List<Map<String, Object>> pendingPrepLines = new ArrayList<>();
        List<Map<String, Object>> pendingCookLines = new ArrayList<>();
        List<Map<String, Object>> readyServeLines = new ArrayList<>();
        List<Map<String, Object>> doneLines = new ArrayList<>();

        for (KdsTicket t : primaryByDetail.values()) {
            OrderDetail detail = detailMap.get(t.getDetail_id());
            Order order = orderMap.get(t.getOrder_id());
            if (detail == null || order == null) continue;

            // 过滤已取消订单
            if ("cancelled".equalsIgnoreCase(order.getTransac_status())) {
                continue;
            }

            Map<String, Object> canonicalLine = buildCanonicalLine(t, order, detail, prepEnabled);
            int prepRemaining = (int) canonicalLine.get("prep_remaining");
            int cookRemaining = (int) canonicalLine.get("cook_remaining");
            int readyRemaining = (int) canonicalLine.get("ready_remaining");

            // 联动订单清台/离店状态：已清台订单（off_order）不再流入待配、待烤或待传等在制活动队列
            boolean isOrderOff = "off_order".equalsIgnoreCase(order.getOrder_receiving());

            if (isOrderOff) {
                canonicalLine.put("workflow_queue", KdsWorkflowQueue.DONE);
                canonicalLine.put("prep_remaining", 0);
                canonicalLine.put("cook_remaining", 0);
                canonicalLine.put("ready_remaining", 0);
                doneLines.add(canonicalLine);
            } else if (prepRemaining > 0 && prepEnabled) {
                pendingPrepLines.add(canonicalLine);
            } else if (cookRemaining > 0) {
                pendingCookLines.add(canonicalLine);
            } else if (readyRemaining > 0) {
                readyServeLines.add(canonicalLine);
            } else {
                doneLines.add(canonicalLine);
            }
        }

        Map<String, List<Map<String, Object>>> queues = new LinkedHashMap<>();
        queues.put(KdsWorkflowQueue.PENDING_PREP, pendingPrepLines);
        queues.put(KdsWorkflowQueue.PENDING_COOK, pendingCookLines);
        queues.put(KdsWorkflowQueue.READY_SERVE, readyServeLines);
        queues.put(KdsWorkflowQueue.DONE, doneLines);

        // 4. queue_counts
        Map<String, Integer> queueCounts = overviewBoardService.countWorkflowQueues(shopId, "all", null, null, screenTags);

        // 5. fixed_catalog: 当前门店上架菜品
        List<Map<String, Object>> catalog = loadFixedCatalog(shopId);

        // 6. order_details: 活动订单明细
        List<Map<String, Object>> orderDetails = buildOrderDetailsList(orderMap.values(), detailMap.values(), primaryByDetail);

        // 7. config, stats, permissions
        Map<String, Object> config = new LinkedHashMap<>();
        config.put("enable_prep_workflow", prepEnabled);
        config.put("kds_mode", configService.getOrDefault(shopId).getKds_mode());

        Map<String, Object> permissions = new LinkedHashMap<>();
        permissions.put("visible_queues", KdsWorkflow.visibleQueues(device, prepEnabled));
        permissions.put("allowed_commands", Arrays.asList(
                "advance_item", "advance_order", "revoke_item", "lack_item",
                "refund_item", "rush_item", "rush_order", "hold_item",
                "release_item", "complete_order", "archive_order", "archive_clear"
        ));

        Map<String, Object> bootstrapData = new LinkedHashMap<>();
        bootstrapData.put("protocol_version", 2);
        bootstrapData.put("event_seq", snapshotSequence);
        bootstrapData.put("shop_id", shopId);
        bootstrapData.put("queues", queues);
        bootstrapData.put("queue_counts", queueCounts);
        bootstrapData.put("stats", statsService.todayStats(shopId));
        bootstrapData.put("fixed_catalog", catalog);
        bootstrapData.put("order_details", orderDetails);
        bootstrapData.put("config", config);
        bootstrapData.put("permissions", permissions);

        return bootstrapData;
    }

    /**
     * 构建满足客户端 22 个必填字段强校验规范的明细行
     */
    public Map<String, Object> buildCanonicalLine(KdsTicket t, Order order, OrderDetail detail, boolean prepEnabled) {
        int lineQuantity = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        int refundedQty = detail.getRefunded_quantity() != null ? detail.getRefunded_quantity() : 0;
        if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
            refundedQty = lineQuantity;
        }
        refundedQty = Math.min(refundedQty, lineQuantity);
        int activeQty = Math.max(0, lineQuantity - refundedQty);

        int prepQty = KdsTicketQuantityUtil.prepQuantity(t);
        int cookedQty = KdsTicketQuantityUtil.cookedQuantity(t, lineQuantity);
        int servedQty = KdsTicketQuantityUtil.servedQuantity(t);

        // 约束：prep_remaining <= cook_remaining <= ready_remaining <= line_quantity - refunded_quantity
        int readyRemaining = Math.max(0, activeQty - servedQty);
        int cookRemaining = Math.max(0, Math.min(readyRemaining, activeQty - cookedQty));
        int prepRemaining = prepEnabled ? Math.max(0, Math.min(cookRemaining, activeQty - prepQty)) : 0;

        String workflowQueue;
        if (readyRemaining == 0) {
            workflowQueue = KdsWorkflowQueue.DONE;
        } else if (cookRemaining == 0) {
            workflowQueue = KdsWorkflowQueue.READY_SERVE;
        } else if (prepRemaining == 0) {
            workflowQueue = KdsWorkflowQueue.PENDING_COOK;
        } else {
            workflowQueue = KdsWorkflowQueue.PENDING_PREP;
        }

        long localRevision = resolveTicketRevision(t);
        long orderRevision = resolveOrderRevision(t);
        long createdAtMs = t.getCreated_at() != null ? t.getCreated_at().getTime()
                : (order.getOrder_time() != null ? order.getOrder_time().getTime() : System.currentTimeMillis());
        if (createdAtMs <= 0) createdAtMs = 1L;

        String fulfillmentBucket = mapFulfillmentBucket(order.getDineInOrTakeOut());

        Map<String, Object> line = new LinkedHashMap<>();
        line.put("detail_id", detail.getId());
        line.put("order_id", order.getId());
        line.put("dish_id", detail.getDish_id() != null && detail.getDish_id() > 0 ? detail.getDish_id() : 1);
        line.put("dish_name", StringUtils.hasText(detail.getName()) ? detail.getName().trim() : "菜品");
        line.put("line_quantity", lineQuantity);
        line.put("refunded_quantity", refundedQty);
        line.put("prep_remaining", prepRemaining);
        line.put("cook_remaining", cookRemaining);
        line.put("ready_remaining", readyRemaining);
        line.put("local_revision", localRevision);
        line.put("order_revision", orderRevision);
        line.put("fulfillment_bucket", fulfillmentBucket);
        line.put("fulfillment_channel", fulfillmentBucket);
        line.put("table_number", order.getTable_number());
        line.put("order_no", StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no().trim() : "ORD" + order.getId());
        line.put("specification", detail.getSelectedSpicy());
        line.put("unit", StringUtils.hasText(detail.getUnit()) ? detail.getUnit().trim() : "份");
        line.put("remark", detail.getRemark());
        line.put("created_at_ms", createdAtMs);
        line.put("held", "mis_order".equals(detail.getOrder_rece()));
        line.put("rushed", t.getRush_flag() != null && t.getRush_flag() == 1);
        line.put("lacked", OrderDetailLineStatus.isRefunded(detail.getLine_status()));
        line.put("removed", OrderDetailLineStatus.isRefunded(detail.getLine_status()));
        line.put("workflow_queue", workflowQueue);
        line.put("cloud_order_id", order.getId());
        line.put("cloud_detail_id", detail.getId());
        line.put("serving_duration_minutes", 10);
        Long completedAtMs = null;
        if (readyRemaining == 0 && t.getUpdated_at() != null) {
            completedAtMs = t.getUpdated_at().getTime();
        } else if (order != null && order.getOff_time() != null) {
            completedAtMs = order.getOff_time().getTime();
        }
        if (completedAtMs != null) {
            line.put("completed_at_ms", completedAtMs);
        }
        boolean isCombo = (detail.getCombo_id() != null && detail.getCombo_id() > 0)
                || "combo_header".equalsIgnoreCase(detail.getLine_type())
                || "combo_component".equalsIgnoreCase(detail.getLine_type());
        line.put("is_combo", isCombo);
        line.put("combo", isCombo);
        line.put("set_meal", isCombo);
        if (detail.getCombo_id() != null && detail.getCombo_id() > 0) {
            line.put("combo_id", detail.getCombo_id());
        }

        return line;
    }

    private String mapFulfillmentBucket(String dineInOrTakeOut) {
        if (!StringUtils.hasText(dineInOrTakeOut)) return "dine_in";
        String t = dineInOrTakeOut.trim().toLowerCase(Locale.ROOT);
        if ("takeout".equals(t) || "waimai".equals(t) || "外卖".equals(dineInOrTakeOut.trim())) return "takeout";
        if ("pack".equals(t) || "打包".equals(dineInOrTakeOut.trim())) return "pack";
        if ("pickup".equals(t) || "自提".equals(dineInOrTakeOut.trim())) return "pickup";
        if ("delivery".equals(t) || "配送".equals(dineInOrTakeOut.trim())) return "delivery";
        return "dine_in";
    }

    private KdsTicket pickPrimaryTicket(KdsTicket a, KdsTicket b) {
        if (a == null) return b;
        if (b == null) return a;
        int scoreA = ticketProgressScore(a);
        int scoreB = ticketProgressScore(b);
        if (scoreA != scoreB) return scoreA >= scoreB ? a : b;
        Date ca = a.getCreated_at();
        Date cb = b.getCreated_at();
        if (ca != null && cb != null && !ca.equals(cb)) return ca.before(cb) ? a : b;
        long idA = a.getId() != null ? a.getId() : 0L;
        long idB = b.getId() != null ? b.getId() : 0L;
        return idA <= idB ? a : b;
    }

    private static int ticketProgressScore(KdsTicket t) {
        if (t == null) return 0;
        return KdsTicketQuantityUtil.prepQuantity(t)
                + (t.getCooked_quantity() != null ? t.getCooked_quantity() : 0)
                + KdsTicketQuantityUtil.servedQuantity(t);
    }

    private List<Map<String, Object>> loadFixedCatalog(int shopId) {
        List<Dish> dishes = dishService.list(new QueryWrapper<Dish>().orderByAsc("sorting", "id"));
        List<Map<String, Object>> list = new ArrayList<>();
        if (dishes != null) {
            for (Dish d : dishes) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("dish_id", d.getId());
                item.put("dish_name", d.getName());
                item.put("unit", StringUtils.hasText(d.getUnit()) ? d.getUnit() : "份");
                item.put("sequence", d.getSorting() != null ? d.getSorting() : 0);
                item.put("id", d.getId());
                item.put("category_id", d.getTypeId());
                item.put("category_name", d.getType() != null ? d.getType().getLabel() : "");
                item.put("sold_out", d.getSold_out() != null && d.getSold_out() == 1);
                list.add(item);
            }
        }
        return list;
    }

    private List<Map<String, Object>> buildOrderDetailsList(Collection<Order> orders, Collection<OrderDetail> details, Map<Integer, KdsTicket> tickets) {
        Map<Integer, Order> orderMap = new HashMap<>();
        for (Order o : orders) orderMap.put(o.getId(), o);

        List<Map<String, Object>> list = new ArrayList<>();
        for (OrderDetail d : details) {
            Order o = orderMap.get(d.getMId());
            if (o == null) continue;
            if ("cancelled".equalsIgnoreCase(o.getTransac_status())) {
                continue;
            }
            int lineQty = KdsTicketQuantityUtil.lineQuantity(d.getQuantity());
            int refunded = d.getRefunded_quantity() != null ? d.getRefunded_quantity() : 0;
            if (OrderDetailLineStatus.isRefunded(d.getLine_status())) refunded = lineQty;
            refunded = Math.min(refunded, lineQty);
            int remaining = Math.max(0, lineQty - refunded);

            String status = OrderDetailLineStatus.isRefunded(d.getLine_status()) ? "refunded"
                    : (refunded > 0 ? "partially_refunded" : "active");
            boolean removed = "refunded".equals(status);

            KdsTicket t = tickets.get(d.getId());
            boolean rushed = t != null && t.getRush_flag() != null && t.getRush_flag() == 1;

            Map<String, Object> od = new LinkedHashMap<>();
            od.put("order_id", o.getId());
            od.put("order_no", StringUtils.hasText(o.getOrder_no()) ? o.getOrder_no().trim() : "ORD" + o.getId());
            od.put("table_number", o.getTable_number() != null ? o.getTable_number() : "");
            od.put("fulfillment_type", mapFulfillmentBucket(o.getDineInOrTakeOut()));
            od.put("order_remark", o.getRemark() != null ? o.getRemark() : "");
            od.put("detail_id", d.getId());
            od.put("dish_id", d.getDish_id() != null && d.getDish_id() > 0 ? d.getDish_id() : 1);
            od.put("dish_name", StringUtils.hasText(d.getName()) ? d.getName().trim() : "菜品");
            od.put("specification", d.getSelectedSpicy() != null ? d.getSelectedSpicy() : "");
            od.put("unit", StringUtils.hasText(d.getUnit()) ? d.getUnit().trim() : "份");
            od.put("quantity", lineQty);
            od.put("refunded_quantity", refunded);
            od.put("remaining_quantity", remaining);
            od.put("status", status);
            od.put("removed", removed);
            od.put("remark", d.getRemark() != null ? d.getRemark() : "");
            od.put("order_rushed", rushed);

            list.add(od);
        }
        return list;
    }

    /**
     * 2. POST /kds/v2/commands
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> executeCommand(KdsDevice device, Map<String, Object> reqBody) {
        String commandId = (String) reqBody.get("command_id");
        if (!StringUtils.hasText(commandId)) {
            throw new IllegalArgumentException("command_id 不能为空");
        }
        commandId = commandId.trim();

        String type = (String) reqBody.get("type");
        if (!StringUtils.hasText(type)) {
            throw new IllegalArgumentException("type 不能为空");
        }

        long now = System.currentTimeMillis();
        int shopId = device.getShop_id();
        // Audit identity is an authentication result, never client-controlled input.
        String actorId = device.getDevice_code() != null
                ? device.getDevice_code() : String.valueOf(device.getId());
        
        KdsV2CommandLedger.Claim claim = commandLedger != null ? 
            commandLedger.claim(shopId, commandId, actorId, "KDS", type, "2.0", reqBody) : null;
            
        if (claim != null && !claim.shouldExecute()) {
            Map<String, Object> dupResult = claim.getResult();
            dupResult.put("duplicate", true);
            return dupResult;
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> target = (Map<String, Object>) reqBody.get("target");
        if (target == null) target = Collections.emptyMap();

        Integer detailId = asInt(target.get("detail_id"));
        Integer orderId = asInt(target.get("order_id"));
        String fromQueue = (String) target.get("from_queue");
        Integer quantity = asInt(reqBody.get("quantity"));
        int qty = (quantity != null && quantity > 0) ? quantity : 1;

        List<Integer> targetDetailIds = new ArrayList<>();
        Object rawDetailIds = target.get("detail_ids");
        if (rawDetailIds instanceof Collection<?>) {
            for (Object item : (Collection<?>) rawDetailIds) {
                Integer did = asInt(item);
                if (did != null && did > 0) targetDetailIds.add(did);
            }
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) reqBody.get("payload");
        if (payload == null) payload = Collections.emptyMap();
        String remark = (String) payload.get("remark");
        Boolean setSoldOut = payload.get("set_sold_out") instanceof Boolean ? (Boolean) payload.get("set_sold_out") : null;

        Long expectedRevision = asLong(reqBody.get("expected_revision"));
        if (expectedRevision == null) {
            expectedRevision = asLong(payload.get("expected_revision"));
        }

        Map<Integer, Long> expectedRevisions = new LinkedHashMap<>();
        Object rawRevs = payload.get("expected_revisions");
        if (rawRevs instanceof Map<?, ?>) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) rawRevs).entrySet()) {
                Integer dId = asInt(entry.getKey());
                Long rev = asLong(entry.getValue());
                if (dId != null && rev != null) {
                    expectedRevisions.put(dId, rev);
                }
            }
        }

        boolean archiveClear = "archive_clear".equals(type);
        boolean isPosCommand = "pos_add_dishes".equals(type) || "addDishes".equals(type)
                || "pos_refund_dish".equals(type) || "refundDish".equals(type);
        boolean mergedDetailCommand = !archiveClear && !isPosCommand && targetDetailIds.size() > 1;
        boolean orderCommand = Arrays.asList(
                "advance_order", "rush_order", "complete_order", "archive_order").contains(type);
        if (mergedDetailCommand) {
            if (expectedRevision != null) {
                throw new IllegalArgumentException(
                        "expected_revision 仅适用于单明细；合并明细请使用 payload.expected_revisions");
            }
            Set<Integer> uniqueTargets = new LinkedHashSet<>(targetDetailIds);
            if (uniqueTargets.size() != targetDetailIds.size()
                    || !expectedRevisions.keySet().equals(uniqueTargets)) {
                throw new IllegalArgumentException(
                        "expected_revisions 必须且只能覆盖 target.detail_ids");
            }
        } else if (!archiveClear && !isPosCommand && expectedRevision == null) {
            throw new IllegalArgumentException(orderCommand
                    ? "订单命令必须提供 expected_revision"
                    : "明细命令必须提供 expected_revision");
        }

        // 乐观锁版本校验
        if (!expectedRevisions.isEmpty()) {
            List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", shopId).in("detail_id", expectedRevisions.keySet())
                    .last("FOR UPDATE"));
            Map<Integer, KdsTicket> primaryTickets = new HashMap<>();
            for (KdsTicket t : tickets) {
                if (t.getDetail_id() != null) {
                    primaryTickets.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
                }
            }
            for (Map.Entry<Integer, Long> entry : expectedRevisions.entrySet()) {
                Integer dId = entry.getKey();
                Long expRev = entry.getValue();
                KdsTicket t = primaryTickets.get(dId);
                if (t == null || !matchesRevision(t, expRev)) {
                    throw new KdsWorkflowService.OptimisticLockException("明细 [" + dId + "] 版本冲突，请刷新后重试");
                }
            }
        }

        if (expectedRevision != null) {
            if (orderId != null && (type.startsWith("advance_order") || type.startsWith("rush_order")
                    || type.startsWith("complete_order") || type.startsWith("archive_order"))) {
                Order o = orderService.getById(orderId);
                if (o == null || !matchesOrderRevision(shopId, orderId, expectedRevision)) {
                    throw new KdsWorkflowService.OptimisticLockException("订单 [" + orderId + "] 版本冲突，请刷新后重试");
                }
            } else if (detailId != null && !isPosCommand) {
                Integer targetDid = detailId;
                if ((targetDid == null || targetDid <= 0) && !targetDetailIds.isEmpty()) {
                    targetDid = targetDetailIds.get(0);
                }
                if (targetDid != null && targetDid > 0) {
                    List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                            .eq("shop_id", shopId).eq("detail_id", targetDid)
                            .last("FOR UPDATE"));
                    KdsTicket primary = null;
                    for (KdsTicket t : tickets) {
                        primary = pickPrimaryTicket(primary, t);
                    }
                    if (primary == null || !matchesRevision(primary, expectedRevision)) {
                        throw new KdsWorkflowService.OptimisticLockException("明细 [" + targetDid + "] 版本冲突，请刷新后重试");
                    }
                }
            }
        }

        List<Integer> affectedDetailIds = new ArrayList<>();
        List<Integer> affectedOrderIds = new ArrayList<>();

        switch (type) {
            case "pos_add_dishes":
            case "addDishes": {
                if (orderController == null) throw new IllegalStateException("orderController not injected");
                try {
                    Map<String, Object> sourceMap = (payload != null && !payload.isEmpty()) ? payload : reqBody;
                    String orderNo = (String) sourceMap.get("order_no");
                    if (orderNo == null && target != null) {
                        orderNo = (String) target.get("order_no");
                    }
                    String tableNumber = (String) sourceMap.get("table_number");
                    Object gl = sourceMap.get("goods_list");
                    if (orderNo == null || gl == null || !(gl instanceof List)) {
                        throw new IllegalArgumentException("订单号与菜品列表不能为空");
                    }
                    QueryWrapper<Order> existingQuery = new QueryWrapper<Order>().eq("order_no", orderNo);
                    if (Integer.valueOf(1).equals(shopId)) {
                        existingQuery.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
                    } else {
                        existingQuery.eq("shop_id", shopId);
                    }
                    Order existing = orderService.getOne(existingQuery.orderByDesc("id").last("LIMIT 1"));
                    if (existing == null) {
                        throw new IllegalArgumentException("订单不存在");
                    }

                    @SuppressWarnings("unchecked")
                    List<Map<String, Object>> goodsListMap = (List<Map<String, Object>>) gl;
                    List<OrderDetail> goodsList = new ArrayList<>();
                    double addAmount = 0;
                    for (Map<String, Object> m : goodsListMap) {
                        OrderDetail d = new OrderDetail();
                        Object rawDishId = m.get("dish_id") != null ? m.get("dish_id") : m.get("mId");
                        if (rawDishId != null) {
                            try {
                                d.setDish_id(Integer.parseInt(rawDishId.toString().trim()));
                            } catch (Exception ignored) {}
                        }
                        d.setName(m.get("name") != null ? m.get("name").toString() : null);
                        Object qtyObj = m.get("quantity");
                        d.setQuantity(qtyObj != null ? qtyObj.toString() : "1");
                        d.setUnit(m.get("unit") != null ? m.get("unit").toString() : null);
                        Object tp = m.get("total_price");
                        double price = tp != null ? Double.parseDouble(tp.toString()) : 0;
                        d.setTotal_price(price);
                        d.setCid(m.get("cid") != null ? m.get("cid").toString() : null);
                        d.setRemark(m.get("remark") != null ? m.get("remark").toString() : null);
                        if (m.get("selectedSpicy") != null) {
                            d.setSelectedSpicy(m.get("selectedSpicy").toString());
                        }
                        goodsList.add(d);
                        addAmount += price;
                    }

                    OrderDTO dto = new OrderDTO();
                    dto.setOrder_no(orderNo);
                    dto.setTable_number(existing.getTable_number() != null ? existing.getTable_number() : tableNumber);
                    dto.setOrderNumber(existing.getOrderNumber() != null ? existing.getOrderNumber() : 1);
                    dto.setSett_amount(addAmount);
                    dto.setRemark(sourceMap.get("remark") != null ? (String) sourceMap.get("remark") : null);
                    dto.setGoods_list(goodsList);
                    dto.setOpenid(existing.getOpenid());
                    dto.setMerchantId("1");
                    dto.setShop_id(shopId);

                    com.lanf.entity.R addRes = orderController.addDishes(dto, null);
                    Object resCode = addRes.get("code");
                    int code = resCode instanceof Number ? ((Number) resCode).intValue() : 0;
                    if (code != 0 && code != 200) {
                        throw new IllegalArgumentException(String.valueOf(addRes.get("msg")));
                    }
                    affectedOrderIds.add(existing.getId());
                } catch (IllegalArgumentException e) {
                    throw e;
                } catch (Exception e) {
                    throw new IllegalArgumentException("addDishes failed: " + e.getMessage());
                }
                break;
            }
            case "pos_refund_dish":
            case "refundDish": {
                if (orderDetailRefundService == null) throw new IllegalStateException("orderDetailRefundService not injected");
                Integer targetDid = detailId;
                if (targetDid == null && payload != null) {
                    targetDid = asInt(payload.get("detail_id"));
                }
                if (targetDid == null && target != null) {
                    targetDid = asInt(target.get("detail_id"));
                }
                if (targetDid == null || targetDid <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                OrderDetail existingDetail = orderDetailService.getById(targetDid);
                if (existingDetail == null) throw new IllegalArgumentException("该订单详情不存在");
                Order order = orderService.getById(existingDetail.getMId());
                if (order == null) throw new IllegalArgumentException("关联订单不存在");
                if (!Integer.valueOf(shopId).equals(order.getShop_id())) {
                    throw new IllegalArgumentException("订单不属于当前门店");
                }

                String rawStockAction = (String) (payload != null && payload.containsKey("stock_action")
                        ? payload.get("stock_action") : reqBody.get("stock_action"));
                com.lanf.order.RefundStockAction stockAction = com.lanf.order.RefundStockAction.from(
                        rawStockAction, com.lanf.order.RefundStockAction.RESTORE);

                String rRemark = remark != null ? remark : (payload != null && payload.get("reason") != null ? String.valueOf(payload.get("reason")) : "POS 退菜");
                orderDetailRefundService.refundFullLine(existingDetail, order, stockAction, actorId, rRemark);

                affectedDetailIds.add(targetDid);
                affectedOrderIds.add(order.getId());
                break;
            }
            case "advance_item": {
                if (targetDetailIds.size() > 1) {
                    String q = KdsWorkflowQueue.normalize(fromQueue);
                    workflowService.advanceFifo(shopId, q, qty, targetDetailIds);
                    affectedDetailIds.addAll(targetDetailIds);
                } else {
                    Integer targetDid = detailId;
                    if ((targetDid == null || targetDid <= 0) && !targetDetailIds.isEmpty()) {
                        targetDid = targetDetailIds.get(0);
                    }
                    if (targetDid == null || targetDid <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                    String q = KdsWorkflowQueue.normalize(fromQueue);
                    try {
                        workflowService.advanceDetail(shopId, targetDid, q, qty);
                    } catch (KdsWorkflowService.OptimisticLockException e) {
                        OrderDetail d = orderDetailService.getById(targetDid);
                        if (d != null && OrderDetailLineStatus.isRefunded(d.getLine_status())) {
                            log.info("[kds/v2] advance_item detail {} already refunded, self-healing with removed patch", targetDid);
                        } else {
                            throw e;
                        }
                    }
                    affectedDetailIds.add(targetDid);
                }
                break;
            }
            case "advance_order": {
                if (orderId == null || orderId <= 0) throw new IllegalArgumentException("order_id 不能为空");
                String q = KdsWorkflowQueue.normalize(fromQueue);
                workflowService.advanceOrder(shopId, orderId, q);
                affectedOrderIds.add(orderId);
                break;
            }
            case "revoke_item": {
                if (detailId == null || detailId <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                String q = KdsWorkflowQueue.normalize(fromQueue);
                workflowService.revokeDetail(shopId, detailId, q, qty);
                affectedDetailIds.add(detailId);
                break;
            }
            case "lack_item": {
                if (detailId == null || detailId <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                String q = KdsWorkflowQueue.normalize(fromQueue);
                workflowService.reportLack(shopId, detailId, q, qty, remark);
                affectedDetailIds.add(detailId);
                if (Boolean.TRUE.equals(setSoldOut)) {
                    OrderDetail d = orderDetailService.getById(detailId);
                    if (d != null && d.getDish_id() != null && d.getDish_id() > 0) {
                        Dish dish = dishService.getById(d.getDish_id());
                        if (dish != null) {
                            dish.setSold_out(1);
                            dishService.updateById(dish);
                        }
                    }
                }
                break;
            }
            case "refund_item": {
                if (detailId == null || detailId <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                String q = KdsWorkflowQueue.normalize(fromQueue);
                workflowService.refundDish(shopId, detailId, q, qty, remark);
                affectedDetailIds.add(detailId);
                if (Boolean.TRUE.equals(setSoldOut)) {
                    OrderDetail d = orderDetailService.getById(detailId);
                    if (d != null && d.getDish_id() != null && d.getDish_id() > 0) {
                        Dish dish = dishService.getById(d.getDish_id());
                        if (dish != null) {
                            dish.setSold_out(1);
                            dishService.updateById(dish);
                        }
                    }
                }
                break;
            }
            case "rush_item": {
                if (orderId == null || orderId <= 0) {
                    if (detailId != null && detailId > 0) {
                        OrderDetail d = orderDetailService.getById(detailId);
                        if (d != null && d.getMId() != null) orderId = d.getMId();
                    }
                }
                if (orderId == null || orderId <= 0) throw new IllegalArgumentException("order_id 不能为空");
                ticketFlagService.rushOrder(shopId, orderId, detailId);
                if (detailId != null && detailId > 0) affectedDetailIds.add(detailId);
                else affectedOrderIds.add(orderId);
                break;
            }
            case "rush_order": {
                if (orderId == null || orderId <= 0) throw new IllegalArgumentException("order_id 不能为空");
                ticketFlagService.rushOrder(shopId, orderId, null);
                affectedOrderIds.add(orderId);
                break;
            }
            case "hold_item": {
                if (detailId == null || detailId <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                workflowService.holdDetail(shopId, detailId);
                affectedDetailIds.add(detailId);
                break;
            }
            case "release_item": {
                if (detailId == null || detailId <= 0) throw new IllegalArgumentException("detail_id 不能为空");
                workflowService.releaseDetail(shopId, detailId);
                affectedDetailIds.add(detailId);
                break;
            }
            case "complete_order": {
                if (orderId == null || orderId <= 0) throw new IllegalArgumentException("order_id 不能为空");
                workflowService.advanceOrder(shopId, orderId, KdsWorkflowQueue.READY_SERVE);
                affectedOrderIds.add(orderId);
                break;
            }
            case "archive_order": {
                if (orderId == null || orderId <= 0) throw new IllegalArgumentException("order_id 不能为空");
                ticketMapper.update(null, new UpdateWrapper<KdsTicket>()
                        .eq("shop_id", shopId).eq("order_id", orderId).set("archived", 1));
                affectedOrderIds.add(orderId);
                break;
            }
            case "archive_clear": {
                workflowService.archiveClear(shopId, device.getDevice_code());
                break;
            }
            default:
                throw new IllegalArgumentException("未知的命令类型: " + type);
        }

        // 收集变更涉及的所有明细
        if (!affectedOrderIds.isEmpty()) {
            List<OrderDetail> ods = orderDetailService.list(new QueryWrapper<OrderDetail>().in("mId", affectedOrderIds));
            if (ods != null) {
                for (OrderDetail od : ods) affectedDetailIds.add(od.getId());
            }
        }

        // 构建 patches
        boolean prepEnabled = configService.isPrepWorkflowEnabled(shopId, device.getStation_id());
        List<Map<String, Object>> patches = new ArrayList<>();
        Map<Integer, OrderDetail> dMap = new HashMap<>();
        Map<Integer, Order> oMap = new HashMap<>();
        Map<Integer, KdsTicket> tMap = new HashMap<>();

        if (!affectedDetailIds.isEmpty()) {
            List<OrderDetail> ods = orderDetailService.listByIds(affectedDetailIds);
            Set<Integer> oIds = new HashSet<>();
            for (OrderDetail d : ods) {
                dMap.put(d.getId(), d);
                if (d.getMId() != null) oIds.add(d.getMId());
            }
            if (!oIds.isEmpty()) {
                for (Order o : orderService.listByIds(oIds)) {
                    oMap.put(o.getId(), o);
                }
            }

            // 云端直连与 LAN 复制共用持久单调版本。业务变更成功后、构建
            // patch 前递增；事务回滚时版本与业务状态一起回滚。
            ticketMapper.update(null, new UpdateWrapper<KdsTicket>()
                    .eq("shop_id", shopId).in("detail_id", affectedDetailIds)
                    .setSql("row_version = row_version + 1"));
            if (!oIds.isEmpty()) {
                jdbc.update("UPDATE t_kds_order SET revision = revision + 1, updated_at = NOW() WHERE shop_id = ? AND order_id IN (" +
                        String.join(",", Collections.nCopies(oIds.size(), "?")) + ")",
                        org.springframework.util.ObjectUtils.toObjectArray(
                                java.util.stream.Stream.concat(java.util.stream.Stream.of(shopId), oIds.stream()).toArray()));
                
                if (shouldAdvanceOrderRevisionInWorkflow(type)) {
                    jdbc.update("UPDATE t_order SET revision = revision + 1 WHERE shop_id = ? AND id IN (" +
                            String.join(",", Collections.nCopies(oIds.size(), "?")) + ")",
                            org.springframework.util.ObjectUtils.toObjectArray(
                                    java.util.stream.Stream.concat(java.util.stream.Stream.of(shopId), oIds.stream()).toArray()));
                }
            }

            List<KdsTicket> tList = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", shopId).in("detail_id", affectedDetailIds));
            for (KdsTicket t : tList) {
                if (t.getDetail_id() != null) {
                    tMap.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
                }
            }

            for (Integer dId : affectedDetailIds) {
                OrderDetail d = dMap.get(dId);
                if (d == null) continue;
                Order o = oMap.get(d.getMId());
                if (o == null) continue;
                KdsTicket t = tMap.get(dId);

                boolean removed = OrderDetailLineStatus.isRefunded(d.getLine_status())
                        || (t != null && Integer.valueOf(KdsItemStatus.VOID).equals(t.getItem_status()));

                Map<String, Object> patch = new LinkedHashMap<>();
                patch.put("detail_id", dId);
                patch.put("removed", removed);
                if (!removed && t != null) {
                    patch.put("line", buildCanonicalLine(t, o, d, prepEnabled));
                }
                patches.add(patch);
            }
        }

        // 构建活动订单明细列表 (order_details) 与订单摘要 (order_summary)
        Set<Integer> summaryOrderIds = new LinkedHashSet<>(affectedOrderIds);
        for (OrderDetail d : dMap.values()) {
            if (d.getMId() != null) summaryOrderIds.add(d.getMId());
        }
        if (orderId != null) summaryOrderIds.add(orderId);

        List<Map<String, Object>> orderDetails = Collections.emptyList();
        Map<String, Object> orderSummary = null;

        if (!summaryOrderIds.isEmpty()) {
            for (Integer sOid : summaryOrderIds) {
                if (!oMap.containsKey(sOid)) {
                    Order so = orderService.getById(sOid);
                    if (so != null) oMap.put(so.getId(), so);
                }
            }
            List<OrderDetail> allDetails = orderDetailService.list(new QueryWrapper<OrderDetail>().in("mId", summaryOrderIds));
            List<KdsTicket> allTickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", shopId).in("order_id", summaryOrderIds));
            Map<Integer, KdsTicket> allTicketMap = new HashMap<>();
            for (KdsTicket t : allTickets) {
                if (t.getDetail_id() != null) {
                    allTicketMap.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
                }
            }
            orderDetails = buildOrderDetailsList(oMap.values(), allDetails != null ? allDetails : Collections.emptyList(), allTicketMap);

            Integer targetSummaryOrderId = orderId;
            if (targetSummaryOrderId == null && summaryOrderIds.size() == 1) {
                targetSummaryOrderId = summaryOrderIds.iterator().next();
            }
            if (targetSummaryOrderId != null) {
                Order so = oMap.get(targetSummaryOrderId);
                if (so != null) {
                    orderSummary = new LinkedHashMap<>();
                    orderSummary.put("order_id", so.getId());
                    orderSummary.put("order_no", StringUtils.hasText(so.getOrder_no()) ? so.getOrder_no().trim() : "ORD" + so.getId());
                    long oRev = resolveOrderRevisionForOrder(allTickets, so.getId());
                    orderSummary.put("order_revision", oRev);
                    orderSummary.put("table_number", so.getTable_number() != null ? so.getTable_number() : "");
                    orderSummary.put("status", so.getOff_time() != null ? "done" : "active");
                }
            }
        }

        long newSeq = eventStore != null ? eventStore.nextSequence(shopId) : getNextEventSeq(shopId);
        Map<String, Integer> queueCounts = overviewBoardService.countWorkflowQueues(
                shopId, "all", null, null, deviceService.screenTagsOf(device));

        Map<String, Object> commandResult = new LinkedHashMap<>();
        commandResult.put("command_id", commandId);
        commandResult.put("duplicate", false);
        commandResult.put("event_seq", newSeq);
        commandResult.put("patches", patches);
        commandResult.put("queue_counts", queueCounts);
        if (!orderDetails.isEmpty()) {
            commandResult.put("order_details", orderDetails);
        }
        if (orderSummary != null) {
            commandResult.put("order_summary", orderSummary);
        }

        // 与业务状态同事务持久化稳定响应；失败会连同命令 claim 一起回滚。
        if (commandLedger != null) {
            commandLedger.complete(shopId, commandId, commandResult);
        }

        // 存入增量事件日志
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("protocol_version", 2);
        envelope.put("event_seq", newSeq);
        envelope.put("event_id", "cmd:" + commandId);
        envelope.put("command_id", commandId);
        envelope.put("schema_version", "2.0");
        envelope.put("type", type);
        envelope.put("shop_id", shopId);
        envelope.put("occurred_at_ms", now);
        envelope.put("patches", patches);
        envelope.put("queue_counts", queueCounts);
        if (!orderDetails.isEmpty()) {
            envelope.put("order_details", orderDetails);
        }
        if (orderSummary != null) {
            envelope.put("order_summary", orderSummary);
        }
        envelope.put("actor_id", actorId);

        publishEnvelope(shopId, envelope);

        return commandResult;
    }

    public void publishEnvelope(int shopId, Map<String, Object> envelope) {
        addAuditMetadata(shopId, envelope);
        Runnable publishAfterCommit = () -> {
            appendEventLog(shopId, envelope);
            if (pushService != null) {
                try {
                    pushService.broadcastV2Envelope(shopId, envelope);
                } catch (RuntimeException pushFailure) {
                    // WebSocket is only the fast path. The durable event has
                    // already been stored and remains recoverable via /changes.
                    log.warn("[kds/v2] volatile websocket push failed; durable changes recovery remains available shopId={} eventId={}: {}",
                            shopId, envelope.get("event_id"), pushFailure.getMessage(), pushFailure);
                }
            }
        };
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            // The durable event and its cursor belong to the same transaction
            // as the business mutation and command-ledger completion. Only
            // volatile in-process delivery is deferred until commit.
            if (eventStore != null) {
                eventStore.append(shopId, envelope);
            }
            try {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        publishAfterCommit.run();
                    }
                });
            } catch (IllegalStateException syncNotAvailable) {
                log.warn("[kds/v2] transaction synchronization not available; falling back to direct push: {}",
                        syncNotAvailable.getMessage());
                publishAfterCommit.run();
            }
        } else {
            if (eventStore != null) {
                eventStore.append(shopId, envelope);
            }
            publishAfterCommit.run();
        }
    }

    private void addAuditMetadata(int shopId, Map<String, Object> envelope) {
        Object rawEventId = envelope.get("event_id");
        String eventId = rawEventId != null ? rawEventId.toString() : "unknown";
        envelope.putIfAbsent("command_id", "event:" + eventId);
        envelope.putIfAbsent("schema_version", "2.0");

        if (!envelope.containsKey("entity_id")) {
            Object orderId = envelope.get("cloud_order_id");
            if (orderId == null && envelope.get("order_summary") instanceof Map<?, ?>) {
                orderId = ((Map<?, ?>) envelope.get("order_summary")).get("order_id");
            }
            Object detailId = firstPatchValue(envelope, "detail_id");
            envelope.put("entity_id", orderId != null
                    ? "order:" + orderId
                    : detailId != null ? "detail:" + detailId : "shop:" + shopId);
        }

        if (!envelope.containsKey("business_revision")) {
            Long revision = null;
            if (envelope.get("order_summary") instanceof Map<?, ?>) {
                revision = asLong(((Map<?, ?>) envelope.get("order_summary")).get("order_revision"));
            }
            if (revision == null) revision = maxPatchRevision(envelope);
            if (revision == null) revision = asLong(envelope.get("config_version"));
            if (revision == null) revision = asLong(envelope.get("event_seq"));
            envelope.put("business_revision", revision != null ? revision : 0L);
        }
    }

    private static Object firstPatchValue(Map<String, Object> envelope, String key) {
        Object rawPatches = envelope.get("patches");
        if (!(rawPatches instanceof Collection<?>)) return null;
        for (Object rawPatch : (Collection<?>) rawPatches) {
            if (rawPatch instanceof Map<?, ?> && ((Map<?, ?>) rawPatch).get(key) != null) {
                return ((Map<?, ?>) rawPatch).get(key);
            }
        }
        return null;
    }

    private static Long maxPatchRevision(Map<String, Object> envelope) {
        Object rawPatches = envelope.get("patches");
        if (!(rawPatches instanceof Collection<?>)) return null;
        Long maximum = null;
        for (Object rawPatch : (Collection<?>) rawPatches) {
            if (!(rawPatch instanceof Map<?, ?>)) continue;
            Object rawLine = ((Map<?, ?>) rawPatch).get("line");
            if (!(rawLine instanceof Map<?, ?>)) continue;
            Long revision = asLong(((Map<?, ?>) rawLine).get("order_revision"));
            if (revision == null) revision = asLong(((Map<?, ?>) rawLine).get("local_revision"));
            if (revision != null && (maximum == null || revision > maximum)) maximum = revision;
        }
        return maximum;
    }



    /**
     * 云端接单 / 加菜后向直连 V2 KDS 广播标准 Envelope 契约
     */
    public void broadcastOrderAccepted(Order order, List<Integer> detailIds, boolean isAddDishes) {
        if (order == null || order.getId() == null || order.getShop_id() == null) {
            return;
        }
        int shopId = order.getShop_id();
        try {
            List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", shopId)
                    .eq("order_id", order.getId())
                    .ne("item_status", KdsItemStatus.VOID));
            if (tickets == null || tickets.isEmpty()) {
                log.info("[kds/v2] broadcastOrderAccepted skip: no active tickets orderId={}", order.getId());
                return;
            }

            List<OrderDetail> allDetails = orderDetailService.list(new QueryWrapper<OrderDetail>()
                    .eq("mId", order.getId()));
            if (allDetails == null || allDetails.isEmpty()) {
                return;
            }

            Map<Integer, OrderDetail> detailMap = new HashMap<>();
            for (OrderDetail d : allDetails) {
                if (d != null && d.getId() != null) {
                    detailMap.put(d.getId(), d);
                }
            }

            // 每个 detailId 选取主 ticket
            Map<Integer, KdsTicket> primaryByDetail = new HashMap<>();
            for (KdsTicket t : tickets) {
                if (t.getDetail_id() == null) continue;
                primaryByDetail.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
            }

            boolean prepEnabled = configService.isPrepWorkflowEnabled(shopId);
            List<Map<String, Object>> patches = new ArrayList<>();
            for (Map.Entry<Integer, KdsTicket> entry : primaryByDetail.entrySet()) {
                OrderDetail d = detailMap.get(entry.getKey());
                if (d == null) continue;
                KdsTicket t = entry.getValue();
                Map<String, Object> canonicalLine = buildCanonicalLine(t, order, d, prepEnabled);
                Map<String, Object> patch = new LinkedHashMap<>();
                patch.put("detail_id", d.getId());
                patch.put("order_id", order.getId());
                patch.put("workflow_queue", canonicalLine.get("workflow_queue"));
                patch.put("removed", false);
                patch.put("line", canonicalLine);
                patches.add(patch);
            }

            if (patches.isEmpty()) {
                return;
            }

            List<Map<String, Object>> orderDetails = buildOrderDetailsList(
                    Collections.singletonList(order), allDetails, primaryByDetail);

            int eventSeq = getNextEventSeq(shopId);
            Map<String, Integer> queueCounts = overviewBoardService.countWorkflowQueues(
                    shopId, "all", null, null, null);

            String eventType = isAddDishes ? "order_updated" : "order_accepted";
            String eventId = (isAddDishes ? "add:" : "order:") + order.getId() + ":" + eventSeq;

            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("protocol_version", 2);
            envelope.put("event_seq", eventSeq);
            envelope.put("event_id", eventId);
            envelope.put("type", eventType);
            envelope.put("shop_id", shopId);
            envelope.put("occurred_at_ms", System.currentTimeMillis());
            envelope.put("patches", patches);
            envelope.put("order_details", orderDetails);
            envelope.put("queue_counts", queueCounts);
            envelope.put("cloud_order_id", order.getId());
            envelope.put("cloud_order_no", order.getOrder_no());
            
            String actorId = "system";
            if (StringUtils.hasText(order.getOpenid())) {
                actorId = "user:" + order.getOpenid();
            } else if (order.getShop_id() != null) {
                actorId = "shop:" + order.getShop_id();
            }
            envelope.put("actor_id", actorId);

            publishEnvelope(shopId, envelope);
            log.info("[kds/v2] broadcastOrderAccepted success shopId={} orderId={} type={} seq={}",
                    shopId, order.getId(), eventType, eventSeq);
        } catch (Exception e) {
            log.error("[kds/v2] broadcastOrderAccepted failed; rolling back source transaction orderId={}: {}",
                    order.getId(), e.getMessage(), e);
            throw new IllegalStateException("KDS 订单事件写入失败，已回滚订单事务", e);
        }
    }

    /**
     * 云端订单取消后向直连 V2 KDS 广播 removed:true 的 patches
     */
    public void broadcastOrderCancelled(int shopId, Order order) {
        if (order == null || order.getId() == null) {
            return;
        }
        try {
            List<OrderDetail> allDetails = orderDetailService.list(new QueryWrapper<OrderDetail>()
                    .eq("mId", order.getId()));
            List<Map<String, Object>> patches = new ArrayList<>();
            if (allDetails != null) {
                for (OrderDetail d : allDetails) {
                    if (d == null || d.getId() == null) continue;
                    Map<String, Object> patch = new LinkedHashMap<>();
                    patch.put("detail_id", d.getId());
                    patch.put("order_id", order.getId());
                    patch.put("removed", true);
                    patches.add(patch);
                }
            }
            if (patches.isEmpty()) {
                List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                        .eq("shop_id", shopId)
                        .eq("order_id", order.getId()));
                if (tickets != null) {
                    Set<Integer> seen = new HashSet<>();
                    for (KdsTicket t : tickets) {
                        if (t.getDetail_id() != null && seen.add(t.getDetail_id())) {
                            Map<String, Object> patch = new LinkedHashMap<>();
                            patch.put("detail_id", t.getDetail_id());
                            patch.put("order_id", order.getId());
                            patch.put("removed", true);
                            patches.add(patch);
                        }
                    }
                }
            }

            List<Map<String, Object>> orderDetails = new ArrayList<>();
            if (allDetails != null) {
                for (OrderDetail d : allDetails) {
                    if (d == null || d.getId() == null) continue;
                    int lineQty = KdsTicketQuantityUtil.lineQuantity(d.getQuantity());
                    Map<String, Object> od = new LinkedHashMap<>();
                    od.put("order_id", order.getId());
                    od.put("order_no", StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no().trim() : "ORD" + order.getId());
                    od.put("table_number", order.getTable_number() != null ? order.getTable_number() : "");
                    od.put("fulfillment_type", mapFulfillmentBucket(order.getDineInOrTakeOut()));
                    od.put("order_remark", order.getRemark() != null ? order.getRemark() : "");
                    od.put("detail_id", d.getId());
                    od.put("dish_id", d.getDish_id() != null && d.getDish_id() > 0 ? d.getDish_id() : 1);
                    od.put("dish_name", StringUtils.hasText(d.getName()) ? d.getName().trim() : "菜品");
                    od.put("specification", d.getSelectedSpicy() != null ? d.getSelectedSpicy() : "");
                    od.put("unit", StringUtils.hasText(d.getUnit()) ? d.getUnit().trim() : "份");
                    od.put("quantity", lineQty);
                    od.put("refunded_quantity", lineQty);
                    od.put("remaining_quantity", 0);
                    od.put("status", "refunded");
                    od.put("removed", true);
                    od.put("remark", d.getRemark() != null ? d.getRemark() : "");
                    od.put("order_rushed", false);
                    orderDetails.add(od);
                }
            }

            int eventSeq = getNextEventSeq(shopId);
            Map<String, Integer> queueCounts = overviewBoardService.countWorkflowQueues(
                    shopId, "all", null, null, null);

            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("protocol_version", 2);
            envelope.put("event_seq", eventSeq);
            envelope.put("event_id", "cancel:" + order.getId() + ":" + eventSeq);
            envelope.put("type", "order_cancelled");
            envelope.put("shop_id", shopId);
            envelope.put("occurred_at_ms", System.currentTimeMillis());
            envelope.put("patches", patches);
            envelope.put("order_details", orderDetails);
            envelope.put("queue_counts", queueCounts);
            envelope.put("cloud_order_id", order.getId());
            envelope.put("cloud_order_no", order.getOrder_no());
            
            String actorId = "system";
            if (StringUtils.hasText(order.getOpenid())) {
                actorId = "user:" + order.getOpenid();
            } else if (order.getShop_id() != null) {
                actorId = "shop:" + order.getShop_id();
            }
            envelope.put("actor_id", actorId);

            publishEnvelope(shopId, envelope);
            log.info("[kds/v2] broadcastOrderCancelled success shopId={} orderId={} seq={}", shopId, order.getId(), eventSeq);
        } catch (Exception e) {
            log.warn("[kds/v2] broadcastOrderCancelled failed orderId={}: {}", order.getId(), e.getMessage(), e);
        }
    }

    /**
     * 云端退菜后向直连 V2 KDS 广播 removed:true 的明细 patches
     */
    public void broadcastItemRefunded(int shopId, Integer orderId, List<Integer> detailIds) {
        if (detailIds == null || detailIds.isEmpty()) {
            return;
        }
        try {
            List<OrderDetail> refundedDetails = orderDetailService.listByIds(detailIds);
            if (refundedDetails == null || refundedDetails.isEmpty()) {
                return;
            }

            Integer effectiveOrderId = orderId;
            if (effectiveOrderId == null && refundedDetails.get(0).getMId() != null) {
                effectiveOrderId = refundedDetails.get(0).getMId();
            }

            List<Map<String, Object>> patches = new ArrayList<>();
            for (OrderDetail d : refundedDetails) {
                if (d == null || d.getId() == null) continue;
                Map<String, Object> patch = new LinkedHashMap<>();
                patch.put("detail_id", d.getId());
                patch.put("order_id", d.getMId() != null ? d.getMId() : effectiveOrderId);
                patch.put("removed", true);
                patches.add(patch);
            }

            List<Map<String, Object>> orderDetails = Collections.emptyList();
            if (effectiveOrderId != null) {
                Order order = orderService.getById(effectiveOrderId);
                if (order != null) {
                    List<OrderDetail> allOrderDetails = orderDetailService.list(new QueryWrapper<OrderDetail>()
                            .eq("mId", effectiveOrderId));
                    List<KdsTicket> activeTickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                            .eq("shop_id", shopId)
                            .eq("order_id", effectiveOrderId)
                            .ne("item_status", KdsItemStatus.VOID));
                    Map<Integer, KdsTicket> ticketMap = new HashMap<>();
                    if (activeTickets != null) {
                        for (KdsTicket t : activeTickets) {
                            if (t.getDetail_id() != null) {
                                ticketMap.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
                            }
                        }
                    }
                    if (allOrderDetails != null) {
                        orderDetails = buildOrderDetailsList(Collections.singletonList(order), allOrderDetails, ticketMap);
                    }
                }
            }

            int eventSeq = getNextEventSeq(shopId);
            Map<String, Integer> queueCounts = overviewBoardService.countWorkflowQueues(
                    shopId, "all", null, null, null);

            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("protocol_version", 2);
            envelope.put("event_seq", eventSeq);
            envelope.put("event_id", "refund:" + (effectiveOrderId != null ? effectiveOrderId : shopId) + ":" + eventSeq);
            envelope.put("type", "item_refunded");
            envelope.put("shop_id", shopId);
            envelope.put("occurred_at_ms", System.currentTimeMillis());
            envelope.put("patches", patches);
            envelope.put("order_details", orderDetails);
            envelope.put("queue_counts", queueCounts);
            if (effectiveOrderId != null) {
                envelope.put("cloud_order_id", effectiveOrderId);
            }
            envelope.put("actor_id", "shop:" + shopId);

            publishEnvelope(shopId, envelope);
            log.info("[kds/v2] broadcastItemRefunded success shopId={} orderId={} details={} seq={}",
                    shopId, effectiveOrderId, detailIds, eventSeq);
        } catch (Exception e) {
            log.warn("[kds/v2] broadcastItemRefunded failed detailIds={}: {}", detailIds, e.getMessage(), e);
        }
    }

    /**
     * 门店配置变更向直连 V2 KDS 广播 config_changed 信封
     */
    public void broadcastConfigChanged(int shopId, Map<String, Object> payload) {
        try {
            int eventSeq = getNextEventSeq(shopId);
            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("protocol_version", 2);
            envelope.put("event_seq", eventSeq);
            envelope.put("event_id", "cfg:" + shopId + ":" + eventSeq);
            envelope.put("type", "config_changed");
            envelope.put("shop_id", shopId);
            envelope.put("occurred_at_ms", System.currentTimeMillis());
            envelope.put("patches", Collections.emptyList());
            envelope.put("queue_counts", overviewBoardService.countWorkflowQueues(shopId, "all", null, null, null));
            if (payload != null && payload.containsKey("config_version")) {
                envelope.put("config_version", payload.get("config_version"));
            }
            envelope.put("actor_id", "shop:" + shopId);
            publishEnvelope(shopId, envelope);
            log.info("[kds/v2] broadcastConfigChanged success shopId={} seq={}", shopId, eventSeq);
        } catch (Exception e) {
            log.warn("[kds/v2] broadcastConfigChanged failed shopId={}: {}", shopId, e.getMessage(), e);
        }
    }

    /**
     * 3. GET /kds/v2/changes?after_seq=xxx
     */
    @Transactional(readOnly = true)
    public Map<String, Object> getChanges(KdsDevice device, long afterSeq) {
        int shopId = device.getShop_id();
        if (eventStore != null) {
            KdsV2EventStore.ChangeBatch batch = eventStore.changes(shopId, afterSeq);
            Map<String, Object> res = new LinkedHashMap<>();
            res.put("protocol_version", 2);
            res.put("shop_id", shopId);
            res.put("event_seq", batch.getCurrentSequence());
            res.put("snapshot_required", batch.isSnapshotRequired());
            res.put("events", batch.getEvents());
            return res;
        }

        int currentSeq = getCurrentEventSeq(shopId);
        LinkedList<Map<String, Object>> logList = eventLogByShop.computeIfAbsent(shopId, k -> new LinkedList<>());
        List<Map<String, Object>> matchedEvents = new ArrayList<>();
        boolean snapshotRequired = false;

        synchronized (logList) {
            if (!logList.isEmpty()) {
                int minSeq = (int) logList.getFirst().get("event_seq");
                if (afterSeq < minSeq - 1) {
                    snapshotRequired = true;
                } else {
                    for (Map<String, Object> evt : logList) {
                        int seq = (int) evt.get("event_seq");
                        if (seq > afterSeq) {
                            matchedEvents.add(evt);
                        }
                    }
                }
            } else if (afterSeq < currentSeq) {
                snapshotRequired = true;
            }
        }

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("protocol_version", 2);
        res.put("shop_id", shopId);
        res.put("event_seq", currentSeq);
        res.put("snapshot_required", snapshotRequired);
        res.put("events", matchedEvents);
        return res;
    }

    public Map<String, Object> resolveCommand(KdsDevice device, String commandId) {
        if (commandLedger != null) {
            return commandLedger.resolve(device.getShop_id(), commandId == null ? null : commandId.trim());
        }
        Map<String, Object> resolution = new LinkedHashMap<>();
        resolution.put("protocol_version", 2);
        resolution.put("command_id", commandId);
        resolution.put("status", "NOT_FOUND");
        return resolution;
    }

    /**
     * 4. GET /kds/v2/business-day/orders?after_id=xxx&limit=xxx
     */
    public Map<String, Object> getBusinessDayOrders(KdsDevice device, Integer afterId, int limit) {
        return getBusinessDayOrders(device.getShop_id(), afterId, limit);
    }

    public Map<String, Object> getBusinessDayOrders(int shopId, Integer afterId, int limit) {
        if (shopId <= 0) throw new IllegalArgumentException("shopId is required");
        int pageSize = Math.max(1, Math.min(200, limit));
        long after = afterId != null ? Math.max(0, afterId.longValue()) : 0;

        BusinessWindow window = resolveBusinessWindow(shopId);
        Timestamp start = Timestamp.from(window.start.atZone(SHOP_ZONE).toInstant());
        Timestamp end = Timestamp.from(window.end.atZone(SHOP_ZONE).toInstant());

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT o.*, k.kds_order_status FROM t_order o LEFT JOIN t_kds_order k ON k.order_id=o.id "
                        + "WHERE o.shop_id=? AND o.order_time>=? AND o.order_time<? AND o.id>? "
                        + "ORDER BY o.id ASC LIMIT ?",
                shopId, start, end, after, pageSize + 1
        );

        boolean complete = rows.size() <= pageSize;
        if (!complete) rows = new ArrayList<>(rows.subList(0, pageSize));

        List<Integer> orderIds = new ArrayList<>();
        Map<Integer, Boolean> orderCompletedMap = new HashMap<>();
        for (Map<String, Object> row : rows) {
            int orderId = ((Number) row.get("id")).intValue();
            orderIds.add(orderId);

            Timestamp offTime = (Timestamp) row.get("off_time");
            String transacStatus = (String) row.get("transac_status");
            String receivingStatus = (String) row.get("order_receiving");
            String kdsStatus = String.valueOf(row.get("kds_order_status"));

            boolean cancelled = "cancelled".equalsIgnoreCase(transacStatus)
                    || "cancelled".equalsIgnoreCase(receivingStatus)
                    || "90".equals(kdsStatus);
            boolean completed = !cancelled && ("40".equals(kdsStatus)
                    || "off_order".equalsIgnoreCase(receivingStatus)
                    || offTime != null);
            orderCompletedMap.put(orderId, completed);
        }

        Map<Integer, List<Map<String, Object>>> detailsByOrder = loadBusinessDayDetails(orderIds, orderCompletedMap, shopId);

        List<Map<String, Object>> orders = new ArrayList<>();
        int maxId = (int) after;
        for (Map<String, Object> row : rows) {
            int orderId = ((Number) row.get("id")).intValue();
            if (orderId > maxId) maxId = orderId;

            Timestamp orderTime = (Timestamp) row.get("order_time");
            Timestamp offTime = (Timestamp) row.get("off_time");
            String transacStatus = (String) row.get("transac_status");
            String receivingStatus = (String) row.get("order_receiving");
            String kdsStatus = String.valueOf(row.get("kds_order_status"));

            boolean cancelled = "cancelled".equalsIgnoreCase(transacStatus)
                    || "cancelled".equalsIgnoreCase(receivingStatus)
                    || "90".equals(kdsStatus);
            boolean completed = !cancelled && ("40".equals(kdsStatus)
                    || "off_order".equalsIgnoreCase(receivingStatus)
                    || offTime != null);

            String fulfillment = mapFulfillmentBucket((String) row.get("dineInOrTakeOut"));

            Map<String, Object> orderMap = new LinkedHashMap<>();
            orderMap.put("order_id", orderId);
            orderMap.put("order_no", row.get("order_no"));
            orderMap.put("table_number", row.get("table_number") != null ? row.get("table_number") : "");
            orderMap.put("fulfillment_type", fulfillment);
            orderMap.put("fulfillment_channel", fulfillment);
            orderMap.put("order_remark", row.get("remark") != null ? row.get("remark") : "");
            orderMap.put("created_at_ms", orderTime != null ? orderTime.getTime() : 0L);
            orderMap.put("completed_at_ms", completed && offTime != null ? offTime.getTime() : 0L);
            orderMap.put("completed", completed);
            orderMap.put("status", completed ? "done" : (cancelled ? "cancelled" : "active"));
            orderMap.put("workflow_queue", completed ? "done" : "active");
            orderMap.put("details", detailsByOrder.getOrDefault(orderId, Collections.emptyList()));

            orders.add(orderMap);
        }

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("business_day", window.businessDay.toString());
        data.put("business_day_start_ms", window.start.atZone(SHOP_ZONE).toInstant().toEpochMilli());
        data.put("business_day_end_ms", window.end.atZone(SHOP_ZONE).toInstant().toEpochMilli());
        data.put("orders", orders);
        data.put("complete", complete);
        data.put("next_after_id", complete ? null : maxId);
        
        long currentSeq = eventStore != null ? eventStore.currentSequence(shopId) : getCurrentEventSeq(shopId);
        data.put("event_seq", currentSeq);

        return data;
    }

    private Map<Integer, List<Map<String, Object>>> loadBusinessDayDetails(
            List<Integer> orderIds, Map<Integer, Boolean> orderCompletedMap, int shopId) {
        Map<Integer, List<Map<String, Object>>> grouped = new HashMap<>();
        if (orderIds.isEmpty()) return grouped;

        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("order_id", orderIds)
                .ne("item_status", KdsItemStatus.VOID));
        Map<Integer, KdsTicket> ticketByDetail = new HashMap<>();
        if (tickets != null) {
            for (KdsTicket t : tickets) {
                if (t.getDetail_id() != null) {
                    ticketByDetail.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
                }
            }
        }

        String placeholders = String.join(",", Collections.nCopies(orderIds.size(), "?"));
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT mId,id,dish_id,name,selectedSpicy,unit,quantity,refunded_quantity,line_status,remark "
                        + "FROM t_order_detail WHERE mId IN (" + placeholders + ") ORDER BY mId,id ASC", orderIds.toArray());
        for (Map<String, Object> row : rows) {
            int orderId = ((Number) row.get("mId")).intValue();
            int detailId = ((Number) row.get("id")).intValue();
            int qty = KdsTicketQuantityUtil.lineQuantity(String.valueOf(row.get("quantity")));
            int ref = row.get("refunded_quantity") instanceof Number ? ((Number) row.get("refunded_quantity")).intValue() : 0;
            if (OrderDetailLineStatus.isRefunded((String) row.get("line_status"))) ref = qty;
            ref = Math.min(ref, qty);
            int activeQty = Math.max(0, qty - ref);

            boolean orderCompleted = Boolean.TRUE.equals(orderCompletedMap.get(orderId));
            KdsTicket t = ticketByDetail.get(detailId);
            boolean isDone;
            int readyRemaining;
            int cookRemaining;
            int prepRemaining;
            String queue;

            if (orderCompleted) {
                isDone = true;
                readyRemaining = 0;
                cookRemaining = 0;
                prepRemaining = 0;
                queue = "done";
            } else if (t != null) {
                int prepQty = KdsTicketQuantityUtil.prepQuantity(t);
                int cookedQty = KdsTicketQuantityUtil.cookedQuantity(t, qty);
                int servedQty = KdsTicketQuantityUtil.servedQuantity(t);

                readyRemaining = Math.max(0, activeQty - servedQty);
                cookRemaining = Math.max(0, Math.min(readyRemaining, activeQty - cookedQty));
                prepRemaining = Math.max(0, Math.min(cookRemaining, activeQty - prepQty));
                isDone = (t.getArchived() != null && t.getArchived() == 1)
                        || (activeQty > 0 && servedQty >= activeQty)
                        || readyRemaining == 0;
                if (isDone) {
                    queue = "done";
                    readyRemaining = 0;
                    cookRemaining = 0;
                    prepRemaining = 0;
                } else if (cookRemaining == 0) {
                    queue = "ready_serve";
                } else if (prepRemaining == 0) {
                    queue = "pending_cook";
                } else {
                    queue = "pending_prep";
                }
            } else {
                isDone = false;
                readyRemaining = activeQty;
                cookRemaining = activeQty;
                prepRemaining = 0;
                queue = "pending_cook";
            }

            Map<String, Object> detail = new LinkedHashMap<>();
            detail.put("detail_id", detailId);
            detail.put("dish_id", row.get("dish_id") != null ? row.get("dish_id") : 1);
            detail.put("dish_name", row.get("name"));
            detail.put("specification", row.get("selectedSpicy") != null ? row.get("selectedSpicy") : "");
            detail.put("unit", row.get("unit") != null ? row.get("unit") : "份");
            detail.put("quantity", qty);
            detail.put("refunded_quantity", ref);
            detail.put("remaining_quantity", activeQty);
            detail.put("remark", row.get("remark") != null ? row.get("remark") : "");

            // 对齐收银端 LAN 与 API 契约 §9.1.1 行级队列标记
            detail.put("done_line", isDone ? 1 : 0);
            detail.put("doneLine", isDone ? 1 : 0);
            detail.put("workflow_queue", queue);
            detail.put("workflowQueue", queue);
            detail.put("ready_remaining", readyRemaining);
            detail.put("readyRemaining", readyRemaining);
            detail.put("cook_remaining", cookRemaining);
            detail.put("cookRemaining", cookRemaining);
            detail.put("prep_remaining", prepRemaining);
            detail.put("prepRemaining", prepRemaining);

            grouped.computeIfAbsent(orderId, ignored -> new ArrayList<>()).add(detail);
        }
        return grouped;
    }

    private BusinessWindow resolveBusinessWindow(int shopId) {
        Map<String, Object> shop;
        try {
            shop = jdbc.queryForMap("SELECT open_time, close_time, settle_time FROM t_shop WHERE id=?", shopId);
        } catch (Exception ex) {
            throw new CashierKdsDeliveryException(500, 5000, "无法读取门店营业时段");
        }
        LocalTime open = parseShopTimeOr(shop.get("open_time"), "16:00");
        LocalTime settle = parseShopTimeOr(shop.get("settle_time"), null);
        if (settle == null) {
            settle = parseShopTimeOr(shop.get("close_time"), "04:00");
        }
        LocalDateTime now = LocalDateTime.now(SHOP_ZONE);
        LocalDate today = now.toLocalDate();
        LocalDateTime todayStart = LocalDateTime.of(today, open);
        LocalDateTime start = now.isBefore(todayStart)
                ? LocalDateTime.of(today.minusDays(1), open)
                : todayStart;
        LocalDate day = start.toLocalDate();
        LocalDateTime end = LocalDateTime.of(day, settle).plusDays(1);
        return new BusinessWindow(day, open, settle, start, end);
    }

    private LocalTime parseShopTimeOr(Object value, String fallback) {
        String text = value == null ? "" : String.valueOf(value).trim();
        if (text.length() > 5) text = text.substring(0, 5);
        if (!text.isEmpty()) {
            try { return LocalTime.parse(text, HH_MM); }
            catch (Exception ignored) { }
        }
        if (fallback != null) {
            return LocalTime.parse(fallback, HH_MM);
        }
        return null;
    }

    private static final class BusinessWindow {
        final LocalDate businessDay;
        final LocalTime open;
        final LocalTime close;
        final LocalDateTime start;
        final LocalDateTime end;

        BusinessWindow(LocalDate businessDay, LocalTime open, LocalTime close, LocalDateTime start, LocalDateTime end) {
            this.businessDay = businessDay;
            this.open = open;
            this.close = close;
            this.start = start;
            this.end = end;
        }
    }

    private static Integer asInt(Object v) {
        if (v instanceof Number) return ((Number) v).intValue();
        if (v != null) {
            try { return Integer.parseInt(v.toString().trim()); }
            catch (NumberFormatException ignored) {}
        }
        return null;
    }

    private static Long asLong(Object v) {
        if (v instanceof Number) return ((Number) v).longValue();
        if (v != null) {
            try { return Long.parseLong(v.toString().trim()); }
            catch (NumberFormatException ignored) {}
        }
        return null;
    }

    static boolean shouldAdvanceOrderRevisionInWorkflow(String commandType) {
        return !"pos_add_dishes".equals(commandType) && !"addDishes".equals(commandType);
    }

    private long resolveTicketRevision(KdsTicket t) {
        if (t == null) return 1L;
        Long revision = t.getRow_version();
        return revision == null || revision <= 0 ? 1L : revision;
    }

    private long resolveOrderRevision(KdsTicket t) {
        if (t == null) return 1L;
        Long revision = t.getOrder_revision();
        return revision == null || revision <= 0 ? 1L : revision;
    }

    private long resolveOrderRevisionForOrder(Collection<KdsTicket> tickets, Integer orderId) {
        if (orderId == null) return 1L;
        long observed = 0L;
        if (tickets != null) {
            for (KdsTicket ticket : tickets) {
                if (orderId.equals(ticket.getOrder_id()) && ticket.getOrder_revision() != null) {
                    observed = Math.max(observed, ticket.getOrder_revision());
                }
            }
        }
        if (observed > 0) return observed;
        return getOrderRevision(orderId);
    }
    
    private long getOrderRevision(Integer orderId) {
        try {
            Long rev = jdbc.queryForObject("SELECT revision FROM t_order WHERE id = ?", Long.class, orderId);
            if (rev == null || rev <= 0) {
                throw new KdsV2StorageException("canonical order revision is missing for order " + orderId);
            }
            return rev;
        } catch (Exception e) {
            if (e instanceof KdsV2StorageException) throw (KdsV2StorageException) e;
            throw new KdsV2StorageException(
                    "canonical order revision could not be loaded for order " + orderId, e);
        }
    }

    private boolean matchesRevision(KdsTicket t, Long expectedRevision) {
        if (expectedRevision == null) return true;
        return expectedRevision == resolveTicketRevision(t);
    }

    private boolean matchesOrderRevision(int shopId, int orderId, Long expectedRevision) {
        if (expectedRevision == null) return true;
        return expectedRevision == getOrderRevision(orderId);
    }

}
