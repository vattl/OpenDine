package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsPushPayloadBuilder;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class KdsTicketService {

    private static final Logger log = LoggerFactory.getLogger(KdsTicketService.class);

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsRoutingService routingService;
    @Autowired
    private KdsOrderStatusAggregator orderStatusAggregator;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsLegacySyncService legacySyncService;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsTicketFlagService ticketFlagService;
    @Autowired
    private KdsFlowBatchService flowBatchService;
    @Autowired(required = false)
    private KdsWorkflowV2Service kdsWorkflowV2Service;

    @Transactional
    public void createTicketsForOrder(Order order, List<Integer> onlyDetailIds, KdsOrderHook.Trigger trigger) {
        if (order == null || order.getId() == null) {
            return;
        }
        int shopId = order.getShop_id() != null ? order.getShop_id() : 0;
        if (shopId <= 0) {
            return;
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        if (details == null || details.isEmpty()) {
            return;
        }
        Set<Integer> filter = onlyDetailIds == null ? null : onlyDetailIds.stream().collect(Collectors.toSet());
        Date now = new Date();
        boolean skewerGate = configService.isSkewerGateEnabled(shopId);
        Set<String> grillScreens = new HashSet<>();
        Map<String, List<OrderDetail>> detailsByScreen = new LinkedHashMap<>();
        List<OrderDetail> insertedDetails = new ArrayList<>();
        int insertedCount = 0;
        for (OrderDetail detail : details) {
            if (detail == null || detail.getId() == null) {
                continue;
            }
            if (filter != null && !filter.contains(detail.getId())) {
                continue;
            }
            if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
                continue;
            }
            KdsRoutingService.RouteTarget target = routingService.resolve(shopId, detail);
            if (target == null || !target.createsTicket()) {
                continue;
            }
            boolean prepEnabled = configService.isPrepWorkflowEnabled(shopId, target.stationId);
            int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
            // 使用数据库唯一约束+异常捕获处理并发，避免竞态条件
            KdsTicket ticket = new KdsTicket();
            ticket.setShop_id(shopId);
            ticket.setStation_id(target.stationId);
            ticket.setScreen_tag(target.screenTag);
            ticket.setOrder_id(order.getId());
            ticket.setOrder_no(order.getOrder_no());
            ticket.setDetail_id(detail.getId());
            ticket.setItem_status(KdsItemStatus.PENDING);
            ticket.setSkewer_picked(!prepEnabled ? 1 : (skewerGate ? 0 : 1));
            if (!prepEnabled || !skewerGate) {
                ticket.setSkewer_picked_at(now);
            }
            ticket.setRush_flag(0);
            ticket.setAdd_dish_flag(0);
            ticket.setOverdue_flag(0);
            ticket.setOrder_number_snapshot(order.getOrderNumber());
            ticketFlagService.applyAddDishFlagOnCreate(ticket, shouldMarkAddDish(trigger, detail, filter));
            ticket.setArchived(0);
            ticket.setPrep_quantity(prepEnabled ? 0 : lineQty);
            ticket.setCooked_quantity(0);
            ticket.setServed_quantity(0);
            ticket.setCreated_at(now);
            ticket.setUpdated_at(now);
            try {
                ticketMapper.insert(ticket);
                flowBatchService.initForTicket(ticket, order, detail, lineQty);
                grillScreens.add(target.screenTag);
                insertedCount++;
                insertedDetails.add(detail);
                detailsByScreen.computeIfAbsent(target.screenTag, k -> new ArrayList<>()).add(detail);
            } catch (DuplicateKeyException e) {
                // 工单已存在（detail_id+station_id唯一约束），跳过
                log.info("工单已存在，跳过创建: detailId={}, stationId={}", detail.getId(), target.stationId);
            }
        }
        int kdsStatus = orderStatusAggregator.aggregateAndSave(order.getId(), shopId, order.getOrder_no(), false);
        boolean hasActiveTickets = insertedCount > 0 || countActiveTickets(shopId, order.getId()) > 0;
        if (!hasActiveTickets) {
            log.info("[kds] 订单无可用工单，跳过 WS 推送 orderId={} orderNo={}", order.getId(), order.getOrder_no());
            return;
        }
        boolean shopPrepEnabled = configService.isPrepWorkflowEnabled(shopId);
        if (shopPrepEnabled && skewerGate) {
            pushService.newOrder(shopId, KdsScreenTag.SKEWER_AGGREGATE,
                    KdsPushPayloadBuilder.newOrder(order, kdsStatus, insertedDetails));
        } else if (!grillScreens.isEmpty()) {
            for (String screen : grillScreens) {
                List<OrderDetail> screenItems = detailsByScreen.getOrDefault(screen, Collections.emptyList());
                pushService.newOrder(shopId, screen,
                        KdsPushPayloadBuilder.newOrder(order, kdsStatus, screenItems));
            }
        } else {
            pushService.newOrder(shopId, KdsScreenTag.WORKFLOW_BOARD,
                    KdsPushPayloadBuilder.newOrder(order, kdsStatus, insertedDetails));
        }
        if (kdsWorkflowV2Service != null) {
            kdsWorkflowV2Service.broadcastOrderAccepted(order, onlyDetailIds, trigger == KdsOrderHook.Trigger.ADD_DISHES);
        }
    }

    /**
     * Returns why a detail intentionally has no station ticket, or {@code null} when it must have one.
     * Replication uses this same routing decision as ticket creation so valid non-ticket lines do not
     * become permanent synchronization conflicts.
     */
    public String ticketSkipReason(int shopId, OrderDetail detail) {
        String intrinsic = intrinsicTicketSkipReason(detail);
        if (intrinsic != null) {
            return intrinsic;
        }
        KdsRoutingService.RouteTarget target = routingService.resolve(shopId, detail);
        if (target == null) {
            return "NO_ACTIVE_ROUTE";
        }
        return target.createsTicket() ? null : "NON_TICKET_SCREEN:" + target.screenTag;
    }

    public static String intrinsicTicketSkipReason(OrderDetail detail) {
        if (detail == null) {
            return "DETAIL_MISSING";
        }
        if ("combo_header".equalsIgnoreCase(detail.getLine_type() == null ? "" : detail.getLine_type().trim())) {
            return "COMBO_HEADER";
        }
        if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
            return "REFUNDED";
        }
        return null;
    }

    private long countActiveTickets(int shopId, Integer orderId) {
        if (orderId == null) {
            return 0;
        }
        Integer n = ticketMapper.selectCount(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("order_id", orderId)
                .ne("item_status", KdsItemStatus.VOID));
        return n != null ? n.longValue() : 0;
    }

    public boolean hasActiveTicketsForOrder(int shopId, Integer orderId) {
        return countActiveTickets(shopId, orderId) > 0;
    }

    /**
     * 计算指定订单中预期应生成工单但实际未存在有效工单的明细 ID 列表（Detail 级完备性校验）
     */
    public List<Integer> findMissingTicketDetailIds(Order order) {
        if (order == null || order.getId() == null) {
            return Collections.emptyList();
        }
        int shopId = order.getShop_id() != null ? order.getShop_id() : 0;
        if (shopId <= 0) {
            return Collections.emptyList();
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        if (details == null || details.isEmpty()) {
            return Collections.emptyList();
        }
        List<KdsTicket> activeTickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("order_id", order.getId())
                .ne("item_status", KdsItemStatus.VOID));
        Set<String> existingKeys = new HashSet<>();
        if (activeTickets != null) {
            for (KdsTicket t : activeTickets) {
                if (t.getDetail_id() != null && t.getStation_id() != null) {
                    existingKeys.add(t.getDetail_id() + ":" + t.getStation_id());
                }
            }
        }
        List<Integer> missing = new ArrayList<>();
        for (OrderDetail detail : details) {
            if (detail == null || detail.getId() == null) {
                continue;
            }
            if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
                continue;
            }
            KdsRoutingService.RouteTarget target = routingService.resolve(shopId, detail);
            if (target == null || !target.createsTicket()) {
                continue;
            }
            String key = detail.getId() + ":" + target.stationId;
            if (!existingKeys.contains(key)) {
                missing.add(detail.getId());
            }
        }
        return missing;
    }

    public boolean hasMissingTicketsForOrder(Order order) {
        return !findMissingTicketDetailIds(order).isEmpty();
    }

    /** 加菜标签：仅 ADD_DISHES 触发且落在本次新增明细集合中的行打标；首单 CREATE 不打标。 */
    private static boolean shouldMarkAddDish(KdsOrderHook.Trigger trigger, OrderDetail detail, Set<Integer> newDetailIds) {
        if (detail == null || detail.getId() == null) {
            return false;
        }
        if (trigger == KdsOrderHook.Trigger.ADD_DISHES) {
            return newDetailIds == null || newDetailIds.contains(detail.getId());
        }
        if (trigger == KdsOrderHook.Trigger.CREATE) {
            return false;
        }
        return detail.getMorder_num() != null && detail.getMorder_num() > 1;
    }

    @Transactional
    public KdsTicket updateItemStatus(int shopId, int detailId, int newStatus, String screenTag, Long stationId) {
        if (!KdsItemStatus.isValid(newStatus)) {
            throw new IllegalArgumentException("无效的 item_status");
        }
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("detail_id", detailId);
        if (stationId != null) {
            q.eq("station_id", stationId);
        } else if (screenTag != null) {
            q.eq("screen_tag", screenTag);
        }
        KdsTicket ticket = ticketMapper.selectOne(q.last("LIMIT 1"));
        if (ticket == null) {
            throw new IllegalArgumentException("工单不存在");
        }
        if (screenTag != null && !screenTag.equals(ticket.getScreen_tag())) {
            throw new IllegalArgumentException("无权操作该屏工单");
        }
        if (configService.isSkewerGateEnabled(shopId)
                && (ticket.getSkewer_picked() == null || ticket.getSkewer_picked() != 1)) {
            throw new IllegalArgumentException("该菜品尚未抓串，请先在抓串屏操作「已抓齐」");
        }
        
        // 校验状态转换是否合法
        if (!isValidStatusTransition(ticket.getItem_status(), newStatus)) {
            throw new IllegalArgumentException("不允许的状态转换: " + ticket.getItem_status() + " -> " + newStatus);
        }
        
        Date now = new Date();
        ticket.setItem_status(newStatus);
        if (newStatus == KdsItemStatus.COOKING && ticket.getAccepted_at() == null) {
            ticket.setAccepted_at(now);
        }
        if (newStatus == KdsItemStatus.DONE) {
            ticket.setDone_at(now);
        }
        if (newStatus == KdsItemStatus.VOID) {
            ticket.setVoid_reason("void");
        }
        ticketFlagService.clearOverdueIfNotPending(ticket);
        ticket.setUpdated_at(now);
        ticketMapper.updateById(ticket);
        int kdsStatus = orderStatusAggregator.aggregateAndSave(ticket.getOrder_id(), shopId, ticket.getOrder_no(), false);
        legacySyncService.afterItemStatusChange(shopId, ticket.getOrder_id(), detailId, newStatus);
        Order order = ticket.getOrder_id() != null ? orderService.getById(ticket.getOrder_id()) : null;
        OrderDetail detail = orderDetailService.getById(detailId);
        Map<String, Object> payload = KdsPushPayloadBuilder.itemStatusChange(
                order, detail, detailId, newStatus, kdsStatus, KdsTicketFlagService.toFlagPayload(ticket));
        if (newStatus == KdsItemStatus.VOID) {
            pushService.cancelItem(shopId, ticket.getScreen_tag(), payload);
        } else {
            pushService.updateOrder(shopId, ticket.getScreen_tag(), payload);
        }
        return ticket;
    }

    /**
     * 校验状态转换是否合法
     */
    private boolean isValidStatusTransition(int currentStatus, int newStatus) {
        // 如果状态相同，允许（可能是更新其他字段）
        if (currentStatus == newStatus) {
            return true;
        }
        // 状态转换矩阵
        switch (currentStatus) {
            case KdsItemStatus.PENDING: // 0 -> 1, 3
                return newStatus == KdsItemStatus.COOKING || newStatus == KdsItemStatus.VOID;
            case KdsItemStatus.COOKING: // 1 -> 2, 3
                return newStatus == KdsItemStatus.DONE || newStatus == KdsItemStatus.VOID;
            case KdsItemStatus.DONE: // 2 -> 3 (只允许作废)
                return newStatus == KdsItemStatus.VOID;
            case KdsItemStatus.VOID: // 3 -> 终态，不允许转换
                return false;
            default:
                return false;
        }
    }

    public void voidByDetailIds(int shopId, List<Integer> detailIds, String reason) {
        if (detailIds == null || detailIds.isEmpty()) {
            return;
        }
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("detail_id", detailIds));
        if (tickets.isEmpty()) {
            return;
        }
        Date now = new Date();
        Integer orderId = null;
        String orderNo = null;
        Set<String> screens = new HashSet<>();
        for (KdsTicket t : tickets) {
            t.setItem_status(KdsItemStatus.VOID);
            t.setVoid_reason(reason != null ? reason : "refund");
            t.setUpdated_at(now);
            ticketMapper.updateById(t);
            if (t.getDetail_id() != null) {
                flowBatchService.voidByDetail(shopId, t.getDetail_id(), reason != null ? reason : "refund");
            }
            orderId = t.getOrder_id();
            orderNo = t.getOrder_no();
            screens.add(t.getScreen_tag());
        }
        if (orderId != null) {
            int kdsStatus = orderStatusAggregator.aggregateAndSave(orderId, shopId, orderNo, false);
            Order order = orderService.getById(orderId);
            List<OrderDetail> voidedDetails = orderDetailService.listByIds(detailIds);
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("order_id", orderId);
            payload.put("detail_ids", detailIds);
            payload.put("kds_order_status", kdsStatus);
            KdsPushPayloadBuilder.enrichOrder(payload, order);
            List<Map<String, Object>> items = KdsPushPayloadBuilder.toItemList(voidedDetails);
            if (!items.isEmpty()) {
                payload.put("items", items);
            }
            for (String screen : screens) {
                pushService.cancelItem(shopId, screen, payload);
            }
            if (kdsWorkflowV2Service != null) {
                kdsWorkflowV2Service.broadcastItemRefunded(shopId, orderId, detailIds);
            }
        }
    }

    public List<KdsTicket> listForScreen(int shopId, String screenTag, Integer itemStatus, boolean includeArchived,
                                         int page, int pageSize) {
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("screen_tag", screenTag);
        if (!includeArchived) {
            q.eq("archived", 0);
        }
        if (itemStatus != null) {
            q.eq("item_status", itemStatus);
        } else {
            q.ne("item_status", KdsItemStatus.VOID);
        }
        q.orderByDesc("rush_flag").orderByAsc("created_at");
        int offset = Math.max(0, (page - 1) * pageSize);
        q.last("LIMIT " + offset + "," + pageSize);
        List<KdsTicket> list = ticketMapper.selectList(q);
        return list != null ? list : Collections.emptyList();
    }

}
