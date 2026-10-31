package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.KdsBoardMergeRules;
import com.lanf.kds.KdsWorkflow;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsAdvanceRequestContext;
import com.lanf.kds.support.KdsPushPayloadBuilder;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.*;
import java.time.LocalDate;
import java.time.ZoneId;

/**
 * 统一工作流看板：配菜 → 制作 → 传菜 → 已完成（兼容抓串闸门与旧 item_status）。
 */
@Service
public class KdsWorkflowService {

    private static final Logger log = LoggerFactory.getLogger(KdsWorkflowService.class);

    @Autowired
    private KdsOverviewBoardService overviewBoardService;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsLackService lackService;
    @Autowired
    private KdsFlowBatchService flowBatchService;
    @Autowired
    private KdsWorkflowHoldService holdService;
    @Autowired
    private KdsServePrintService servePrintService;
    @Autowired
    private KdsStatsService statsService;
    @Autowired
    private com.lanf.service.IOperationLogService operationLogService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private CashierKdsProjectionService projectionService;

    public Map<String, Object> buildBoard(KdsDevice device, String queue, String view, String dining,
                                          String extra, String keyword, String sort) {
        return buildBoard(device, queue, view, dining, extra, keyword, sort, null);
    }

    public Map<String, Object> buildBoard(KdsDevice device, String queue, String view, String dining,
                                          String extra, String keyword, String sort, String mergeRulesRaw) {
        return buildBoard(device, queue, view, dining, extra, keyword, sort, mergeRulesRaw, null);
    }

    public Map<String, Object> buildBoard(KdsDevice device, String queue, String view, String dining,
                                          String extra, String keyword, String sort, String mergeRulesRaw,
                                          String splitPackTakeoutRaw) {
        int shopId = device.getShop_id();
        String q = KdsWorkflowQueue.normalize(queue);
        boolean splitPackTakeout = KdsBoardMergeRules.parseSplitPackTakeoutFlag(splitPackTakeoutRaw);
        KdsShopConfig shopCfg = configService.getOrDefault(shopId);
        KdsBoardMergeRules mergeRules = KdsBoardMergeRules.resolve(mergeRulesRaw, q, splitPackTakeout, shopCfg);
        Map<String, Object> board = overviewBoardService.buildBoard(
                shopId,
                KdsWorkflowQueue.toOverviewLegacyQueue(q),
                dining,
                normalizeView(view),
                extra,
                keyword,
                mergeRules,
                deviceService.screenTagsOf(device));
        decorateBoard(board, device, q, view, dining, extra, keyword, sort, mergeRules);
        return board;
    }

    public Map<String, Integer> countQueues(int shopId) {
        Map<String, Integer> counts = new LinkedHashMap<>();
        counts.put(KdsWorkflowQueue.PENDING_PREP, countTickets(shopId, KdsWorkflowQueue.PENDING_PREP));
        counts.put(KdsWorkflowQueue.PENDING_COOK, countTickets(shopId, KdsWorkflowQueue.PENDING_COOK));
        counts.put(KdsWorkflowQueue.READY_SERVE, countTickets(shopId, KdsWorkflowQueue.READY_SERVE));
        counts.put(KdsWorkflowQueue.DONE, countTickets(shopId, KdsWorkflowQueue.DONE));
        return counts;
    }

    /**
     * 冷启动多队列 bootstrap：一次拉取多个兄弟队列 board，替代并行 N 次单队列 board。
     * 未传 queues 时默认设备可见队列（visible_queues）。
     */
    public Map<String, Object> buildBootstrap(KdsDevice device, String queuesRaw, String view, String dining,
                                              String extra, String keyword, String sort, String mergeRulesRaw,
                                              String splitPackTakeoutRaw) {
        boolean prepEnabled = configService.isPrepWorkflowEnabled(device.getShop_id(), device.getStation_id());
        List<String> queues = new ArrayList<>();
        if (StringUtils.hasText(queuesRaw)) {
            for (String p : queuesRaw.split("[,;\\s]+")) {
                if (StringUtils.hasText(p)) {
                    String q = KdsWorkflowQueue.normalize(p.trim());
                    if (!prepEnabled && KdsWorkflowQueue.PENDING_PREP.equals(q)) {
                        continue;
                    }
                    if (!queues.contains(q)) {
                        queues.add(q);
                    }
                }
            }
        }
        if (queues.isEmpty()) {
            queues.addAll(KdsWorkflow.visibleQueues(device, prepEnabled));
        }
        Map<String, Object> boards = new LinkedHashMap<>();
        for (String q : queues) {
            if (!KdsWorkflow.canAccessQueue(device, q, prepEnabled)) {
                continue;
            }
            boards.put(q, buildBoard(device, q, view, dining, extra, keyword, sort, mergeRulesRaw, splitPackTakeoutRaw));
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("screen_tag", KdsScreenTag.WORKFLOW_BOARD);
        result.put("queues", boards);
        result.put("workflows", KdsWorkflow.resolveForDevice(device, prepEnabled));
        result.put("visible_queues", KdsWorkflow.visibleQueues(device, prepEnabled));
        result.put("queue_counts", overviewBoardService.countWorkflowQueues(device.getShop_id(), dining, extra, keyword,
                deviceService.screenTagsOf(device)));
        result.put("enable_prep_workflow", prepEnabled);
        return result;
    }

    /**
     * reconcile / 单队列快照：返回 workflow_queue==queue 的全量行（含 done_line=1），
     * 供前端 replaceQueueLines 整表替换；行与 KdsWorkflowLine 同构。
     * extra/keyword 与 board 同口径过滤。
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> listOrderItems(KdsDevice device, String queue, String dining, String extra, String keyword) {
        String q = KdsWorkflowQueue.normalize(queue);
        // view=order 时 order_cards[].items[] 为该单全量明细（含 done_line=1 及其它流程行，含真实 workflow_queue）
        Map<String, Object> board = buildBoard(device, q, "order", dining, extra, keyword, null, null, null);
        List<Map<String, Object>> items = new ArrayList<>();
        Object cardsObj = board.get("order_cards");
        if (cardsObj instanceof List) {
            for (Object c : (List<?>) cardsObj) {
                if (!(c instanceof Map)) {
                    continue;
                }
                Object cardItems = ((Map<String, Object>) c).get("items");
                if (cardItems instanceof List) {
                    for (Object it : (List<?>) cardItems) {
                        if (it instanceof Map) {
                            items.add((Map<String, Object>) it);
                        }
                    }
                }
            }
        }
        // 仅保留当前队列的行（含 done_line=1），与 reconcile 语义一致
        items.removeIf(it -> {
            Object wq = it.get("workflow_queue");
            return wq != null && !q.equals(wq.toString());
        });
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("queue", q);
        result.put("count", items.size());
        result.put("items", items);
        return result;
    }

    /**
     * 快速划单（v1.2.145 fast patch）：与 advance-item 等价的推进，但返回最小 patch。
     * 以工单 updated_at 毫秒作为 row_version 做乐观锁（KdsTicket 暂无独立 row_version 列）；
     * 客户端传入的 row_version 与当前不一致时抛出 OptimisticLockException。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> statusUpdateFast(int shopId, int detailId, String fromQueue, int quantity, Long rowVersion) {
        return statusUpdateFast(shopId, detailId, fromQueue, quantity, rowVersion, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> statusUpdateFast(int shopId, int detailId, String fromQueue, int quantity, Long rowVersion,
                                                KdsAdvanceRequestContext requestContext) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        if (rowVersion != null) {
            KdsTicket current = findActiveTicket(shopId, detailId, q);
            long currentVersion = current != null && current.getUpdated_at() != null
                    ? current.getUpdated_at().getTime() : 0L;
            if (current == null || currentVersion != rowVersion) {
                throw new OptimisticLockException("数据已被更新，请刷新后重试");
            }
        }
        Map<String, Object> advanceResult = advanceDetail(
                shopId, detailId, q, quantity > 0 ? quantity : 1, rowVersion, requestContext);
        KdsTicket ticket = findActiveTicket(shopId, detailId, KdsWorkflowQueue.nextAfter(q));
        if (ticket == null) {
            ticket = findActiveTicket(shopId, detailId, q);
        }
        Map<String, Object> patch = new LinkedHashMap<>();
        patch.put("detail_id", detailId);
        patch.put("from_queue", advanceResult.get("from_queue"));
        patch.put("to_queue", advanceResult.get("to_queue"));
        patch.put("workflow_queue", advanceResult.get("to_queue"));
        patch.put("advanced_quantity", advanceResult.get("advanced_quantity"));
        patch.put("remaining_quantity", advanceResult.get("remaining_quantity"));
        patch.put("prep_quantity", advanceResult.get("prep_quantity"));
        patch.put("cooked_quantity", advanceResult.get("cooked_quantity"));
        patch.put("served_quantity", advanceResult.get("served_quantity"));
        patch.put("item_status", advanceResult.get("item_status"));
        patch.put("archived", advanceResult.get("archived"));
        patch.put("row_version", ticket != null && ticket.getUpdated_at() != null ? ticket.getUpdated_at().getTime() : null);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("fast", 1);
        result.put("detail_id", detailId);
        result.put("patch", patch);
        result.put("row_version", patch.get("row_version"));
        return result;
    }

    /** 乐观锁冲突（code=5001）。 */
    public static final class OptimisticLockException extends RuntimeException {
        public OptimisticLockException(String message) {
            super(message);
        }
    }

    /**
     * 归档工单完成时刻追溯：按归档（updated_at 代理 archived_at）倒序分页查询 archived=1 工单。
     * 默认仅当前营业日（open_time 起点，门店配置优先，默认 16:00）；before 为分页游标（毫秒时间戳或 ISO date-time）。
     * 注意：KdsTicket 暂无 archived_at/served_at/completed_wait_seconds 列，related 字段以现有时间列代理。
     */
    public Map<String, Object> archivedHistory(int shopId, int limit, String before, Integer detailId, Integer orderId) {
        int lim = limit > 0 ? Math.min(limit, 200) : 50;
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("archived", 1);
        if (detailId != null && detailId > 0) {
            q.eq("detail_id", detailId);
        }
        if (orderId != null && orderId > 0) {
            q.eq("order_id", orderId);
        }
        Date beforeDate = parseCursor(before);
        if (beforeDate != null) {
            q.lt("updated_at", beforeDate);
        } else {
            q.ge("updated_at", businessDayStart(shopId));
        }
        q.orderByDesc("updated_at").last("LIMIT " + (lim + 1));
        List<KdsTicket> tickets = ticketMapper.selectList(q);
        boolean hasMore = tickets != null && tickets.size() > lim;
        if (hasMore) {
            tickets = tickets.subList(0, lim);
        }
        Set<Integer> detailIds = new LinkedHashSet<>();
        if (tickets != null) {
            for (KdsTicket t : tickets) {
                if (t.getDetail_id() != null) {
                    detailIds.add(t.getDetail_id());
                }
            }
        }
        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream()
                .collect(java.util.stream.Collectors.toMap(OrderDetail::getId, d -> d, (a, b) -> a));
        List<Map<String, Object>> items = new ArrayList<>();
        String nextBefore = null;
        if (tickets != null) {
            for (KdsTicket t : tickets) {
                OrderDetail d = t.getDetail_id() != null ? detailMap.get(t.getDetail_id()) : null;
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("ticket_id", t.getId());
                row.put("detail_id", t.getDetail_id());
                row.put("order_id", t.getOrder_id());
                row.put("order_no", t.getOrder_no());
                row.put("screen_tag", t.getScreen_tag());
                row.put("name", d != null ? d.getName() : null);
                row.put("dish_id", d != null ? d.getDish_id() : null);
                row.put("line_quantity", d != null ? KdsTicketQuantityUtil.lineQuantity(d.getQuantity()) : null);
                row.put("archived", t.getArchived());
                row.put("created_at", t.getCreated_at());
                row.put("done_at", t.getDone_at());
                row.put("cooked_at", t.getDone_at());
                row.put("archived_at", t.getUpdated_at());
                if (t.getDone_at() != null && t.getCreated_at() != null) {
                    row.put("completed_wait_seconds", (int) ((t.getDone_at().getTime() - t.getCreated_at().getTime()) / 1000));
                }
                items.add(row);
                if (t.getUpdated_at() != null) {
                    nextBefore = String.valueOf(t.getUpdated_at().getTime());
                }
            }
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("items", items);
        result.put("count", items.size());
        result.put("limit", lim);
        result.put("next_before", hasMore ? nextBefore : null);
        return result;
    }

    /**
     * 设备级手动清空已归档工单（功能需求 F-SYNC-05）。
     * 删除本店 archived=1 且已完成的工单，记操作日志。返回删除条数。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> archiveClear(int shopId, String deviceCode) {
        int deleted = ticketMapper.delete(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("archived", 1)
                .eq("item_status", KdsItemStatus.DONE));
        try {
            operationLogService.recordSystem(shopId, "kds", "archive_clear",
                    deviceCode != null ? deviceCode : "unknown", "deleted=" + deleted);
        } catch (Exception e) {
            // 日志失败不阻断清空
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("cleared", deleted);
        result.put("shop_id", shopId);
        return result;
    }

    private static Date parseCursor(String before) {
        if (!StringUtils.hasText(before)) {
            return null;
        }
        String s = before.trim();
        try {
            return new Date(Long.parseLong(s));
        } catch (NumberFormatException ignore) {
            // fall through to ISO parse
        }
        try {
            return Date.from(java.time.Instant.parse(s));
        } catch (Exception e) {
            return null;
        }
    }

    /** 当前营业班次起点：当前班次起始日 settle_time。 */
    private Date businessDayStart(int shopId) {
        Shop shop = shopId > 0 ? shopService.getById(shopId) : null;
        return ShopBusinessWindowResolver.operationalWindow(shop)[0];
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> advanceDetail(int shopId, int detailId, String fromQueue, int quantity) {
        return advanceDetail(shopId, detailId, fromQueue, quantity, null, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> advanceDetail(int shopId, int detailId, String fromQueue, int quantity,
                                             Long rowVersion, KdsAdvanceRequestContext requestContext) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        int qty = quantity > 0 ? quantity : 1;
        KdsTicket current = findActiveTicket(shopId, detailId, q);
        if (current == null) {
            List<KdsTicket> tickets = ticketsByDetail(shopId, detailId);
            if (!tickets.isEmpty()) {
                KdsTicket pastTicket = tickets.get(0);
                OrderDetail d = orderDetailService.getById(detailId);
                int lQty = d != null ? KdsTicketQuantityUtil.lineQuantity(d.getQuantity()) : 1;
                if (KdsTicketQuantityUtil.isPastQueue(pastTicket, lQty, q)) {
                    String currentQueue = KdsTicketQuantityUtil.resolveCurrentQueue(pastTicket, lQty);
                    log.info("[kds] advanceDetail idempotent: detail {} in shop {} already passed {} (current={})",
                            detailId, shopId, q, currentQueue);
                    return advanceResult(detailId, pastTicket.getOrder_id(), q, currentQueue, qty, 0, 0, pastTicket);
                }
            }
        }
        validateAdvanceContext(shopId, detailId, current, q, requestContext);
        validateRowVersion(current, rowVersion);
        if (KdsWorkflowQueue.PENDING_PREP.equals(q)) {
            return advancePrep(shopId, detailId, q, qty);
        }
        KdsTicket ticket = current;
        if (ticket == null) {
            throw new IllegalArgumentException("工单不存在或不在当前队列");
        }
        if (KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            return advanceCook(shopId, detailId, ticket, q, qty);
        }
        if (KdsWorkflowQueue.READY_SERVE.equals(q)) {
            return advanceServe(shopId, ticket, detailId, q, qty);
        }
        throw new IllegalArgumentException("已完成队列不可推进");
    }

    /**
     * 按下单时间 FIFO 跨多条明细推进（用于合并菜品组一次配 N 串）。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> advanceFifo(int shopId, String fromQueue, int quantity, List<Integer> detailIds) {
        return advanceFifo(shopId, fromQueue, quantity, detailIds, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> advanceFifo(int shopId, String fromQueue, int quantity, List<Integer> detailIds,
                                           KdsAdvanceRequestContext requestContext) {
        if (detailIds == null || detailIds.isEmpty()) {
            throw new IllegalArgumentException("detail_ids 不能为空");
        }
        String q = KdsWorkflowQueue.normalize(fromQueue);
        int remaining = quantity > 0 ? quantity : 1;
        List<Integer> ordered = sortDetailIdsByFifo(shopId, detailIds);
        List<Map<String, Object>> items = new ArrayList<>();
        int advancedTotal = 0;
        for (Integer detailId : ordered) {
            if (remaining <= 0) {
                break;
            }
            OrderDetail d = orderDetailService.getById(detailId);
            if (isDishHeld(d) && (KdsWorkflowQueue.PENDING_PREP.equals(q)
                    || KdsWorkflowQueue.PENDING_COOK.equals(q)
                    || KdsWorkflowQueue.READY_SERVE.equals(q))) {
                continue;
            }
            Map<String, Object> one = advanceDetail(shopId, detailId, q, remaining, null, requestContext);
            int advanced = intValue(one.get("advanced_quantity"), 0);
            if (advanced <= 0) {
                continue;
            }
            advancedTotal += advanced;
            remaining -= advanced;
            items.add(one);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("from_queue", q);
        result.put("to_queue", KdsWorkflowQueue.nextAfter(q));
        result.put("requested_quantity", quantity);
        result.put("advanced_quantity", advancedTotal);
        result.put("remaining_request", Math.max(0, remaining));
        result.put("items", items);
        return result;
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> reportLack(int shopId, int detailId, String fromQueue, Integer quantity, String remark) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        if (!KdsWorkflowQueue.PENDING_PREP.equals(q) && !KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            throw new IllegalArgumentException("缺货仅支持待配菜/待制作队列");
        }
        KdsTicket ticket = findActiveTicket(shopId, detailId, q);
        if (ticket == null) {
            throw new IllegalArgumentException("工单不存在或不在当前队列");
        }
        return lackService.reportLack(shopId, detailId, quantity, ticket.getScreen_tag(), remark, true);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> revokeDetail(int shopId, int detailId, String fromQueue, int quantity) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        if (!KdsWorkflowQueue.PENDING_COOK.equals(q)
                && !KdsWorkflowQueue.READY_SERVE.equals(q)
                && !KdsWorkflowQueue.DONE.equals(q)) {
            throw new IllegalArgumentException("撤销仅支持待制作、待传菜或已完成队列");
        }
        OrderDetail detail = requireActiveDetail(detailId);
        int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        KdsTicket ticket = KdsWorkflowQueue.DONE.equals(q)
                ? findTicketWithServedQuantity(shopId, detailId)
                : findActiveTicket(shopId, detailId, q);
        if (ticket == null) {
            throw new IllegalArgumentException("工单不存在或不在当前队列");
        }
        flowBatchService.ensureInitialized(ticket, lineQty);
        int qty = quantity > 0 ? quantity : 1;
        int revoked;
        String toQueue;
        if (KdsWorkflowQueue.DONE.equals(q)) {
            revoked = flowBatchService.revokeServe(shopId, ticket.getId(), qty);
            toQueue = KdsWorkflowQueue.READY_SERVE;
            if (revoked > 0) {
                reopenOrderAfterCompletedRevoke(shopId, ticket.getOrder_id());
            }
        } else if (KdsWorkflowQueue.READY_SERVE.equals(q)) {
            revoked = flowBatchService.revokeCook(shopId, ticket.getId(), qty);
            toQueue = KdsWorkflowQueue.PENDING_COOK;
        } else {
            revoked = flowBatchService.revokePrep(shopId, ticket.getId(), qty);
            toQueue = KdsWorkflowQueue.PENDING_PREP;
        }
        ticket = ticketMapper.selectById(ticket.getId());
        int remaining = KdsWorkflowQueue.DONE.equals(q)
                ? KdsTicketQuantityUtil.servedQuantity(ticket)
                : KdsWorkflowQueue.READY_SERVE.equals(q)
                    ? KdsTicketQuantityUtil.serveRemaining(ticket, lineQty)
                    : KdsTicketQuantityUtil.cookRemaining(ticket, lineQty);
        pushWorkflowQuantity(shopId, ticket, detailId, lineQty, toQueue);
        if (ticket != null) {
            try {
                if (ticket.getOrder_id() != null) {
                    projectionService.publishLineStatus(shopId, ticket.getOrder_id(),
                            Collections.singletonList(
                                    CashierKdsProjectionService.LineStatusDelta.from(ticket, detailId)));
                }
            } catch (Exception ex) {
                log.warn("[kds] revoke line-status publish failed shop={} detailId={}: {}",
                        shopId, detailId, ex.getMessage());
            }
        }
        return advanceResult(detailId, ticket.getOrder_id(), q, toQueue, qty, revoked, remaining, ticket);
    }

    /**
     * 整单完成会把订单头置为 off_order；显式从已完成回撤时必须同步恢复，
     * 否则 V2 bootstrap 会依据 off_order 再次把该菜品强制归入 done。
     */
    private void reopenOrderAfterCompletedRevoke(int shopId, Integer orderId) {
        if (orderId == null) {
            return;
        }
        orderService.update(new UpdateWrapper<Order>()
                .eq("id", orderId)
                .eq("shop_id", shopId)
                .eq("order_receiving", "off_order")
                .set("order_receiving", "rec_order")
                .set("off_time", null));
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> holdDetail(int shopId, int detailId) {
        return holdService.hold(shopId, detailId);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> releaseDetail(int shopId, int detailId) {
        return holdService.release(shopId, detailId);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> refundDish(int shopId, int detailId, String fromQueue, Integer quantity, String remark) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        if (!KdsWorkflowQueue.PENDING_PREP.equals(q) && !KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            throw new IllegalArgumentException("退菜仅支持待配菜/待制作队列");
        }
        KdsTicket ticket = findActiveTicket(shopId, detailId, q);
        if (ticket == null) {
            throw new IllegalArgumentException("工单不存在或不在当前队列");
        }
        return lackService.refundDish(shopId, detailId, quantity, ticket.getScreen_tag(), remark);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> advanceOrder(int shopId, int orderId, String fromQueue) {
        String q = KdsWorkflowQueue.normalize(fromQueue);
        List<KdsTicket> tickets = ticketsForOrderQueue(shopId, orderId, q);
        Set<Integer> detailIds = new LinkedHashSet<>();
        for (KdsTicket t : tickets) {
            if (t.getDetail_id() != null) {
                detailIds.add(t.getDetail_id());
            }
        }
        int updated = 0;
        int advancedQuantity = 0;
        int skipped = 0;
        List<Map<String, Object>> items = new ArrayList<>();
        for (Integer detailId : detailIds) {
            OrderDetail d = orderDetailService.getById(detailId);
            if (isDishHeld(d) && (KdsWorkflowQueue.PENDING_PREP.equals(q)
                    || KdsWorkflowQueue.PENDING_COOK.equals(q)
                    || KdsWorkflowQueue.READY_SERVE.equals(q))) {
                skipped++;
                continue;
            }
            int lineQty = lineQuantity(detailId);
            KdsTicket active = findActiveTicket(shopId, detailId, q);
            if (active == null) {
                skipped++;
                continue;
            }
            int remaining = KdsTicketQuantityUtil.displayQuantity(active, lineQty, q);
            if (remaining <= 0) {
                skipped++;
                continue;
            }
            Map<String, Object> one = advanceDetail(shopId, detailId, q, remaining);
            int advanced = intValue(one.get("advanced_quantity"), 0);
            if (advanced <= 0) {
                skipped++;
                continue;
            }
            updated++;
            advancedQuantity += advanced;
            items.add(one);
        }
        if (updated == 0 && detailIds.isEmpty()) {
            Order order = orderService.getById(orderId);
            if (order != null && order.getShop_id() != null && order.getShop_id() == shopId) {
                log.info("[kds] advanceOrder idempotent: order {} in shop {} has no remaining items in queue {}",
                        orderId, shopId, q);
                Map<String, Object> result = new LinkedHashMap<>();
                result.put("order_id", orderId);
                result.put("from_queue", q);
                result.put("to_queue", KdsWorkflowQueue.nextAfter(q));
                result.put("updated", 0);
                result.put("advanced_quantity", 0);
                result.put("skipped", 0);
                result.put("items", Collections.emptyList());
                return result;
            }
            throw new IllegalArgumentException("订单在当前队列无待推进明细");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("order_id", orderId);
        result.put("from_queue", q);
        result.put("to_queue", KdsWorkflowQueue.nextAfter(q));
        result.put("updated", updated);
        result.put("advanced_quantity", advancedQuantity);
        result.put("skipped", skipped);
        result.put("items", items);
        return result;
    }

    private int countTickets(int shopId, String queue) {
        QueryWrapper<KdsTicket> qw = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("screen_tag", KdsScreenTag.PRODUCTION_GRILL_TAGS);
        KdsWorkflowQueue.applyTicketFilter(qw, queue);
        List<KdsTicket> tickets = ticketMapper.selectList(qw);
        if (tickets == null || tickets.isEmpty()) {
            return 0;
        }
        Set<Integer> detailIds = tickets.stream().map(KdsTicket::getDetail_id).filter(Objects::nonNull)
                .collect(java.util.stream.Collectors.toSet());
        Map<Integer, OrderDetail> details = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream()
                .collect(java.util.stream.Collectors.toMap(OrderDetail::getId, d -> d));
        int sum = 0;
        for (KdsTicket t : tickets) {
            OrderDetail d = details.get(t.getDetail_id());
            int lineQty = d != null ? KdsTicketQuantityUtil.lineQuantity(d.getQuantity()) : 1;
            if (KdsTicketQuantityUtil.hasQueueWork(t, lineQty, queue)) {
                sum += KdsTicketQuantityUtil.displayQuantity(t, lineQty, queue);
            }
        }
        return sum;
    }

    private void decorateBoard(Map<String, Object> board, KdsDevice device, String queue, String view,
                               String dining, String extra, String keyword, String sort,
                               KdsBoardMergeRules mergeRules) {
        int shopId = device.getShop_id();
        boolean prepEnabled = configService.isPrepWorkflowEnabled(shopId, device.getStation_id());
        board.put("screen_tag", KdsScreenTag.WORKFLOW_BOARD);
        board.put("workflows", KdsWorkflow.resolveForDevice(device, prepEnabled));
        board.put("visible_queues", KdsWorkflow.visibleQueues(device, prepEnabled));
        board.put("enable_prep_workflow", prepEnabled);
        board.put("queue", queue);
        board.put("view", normalizeView(view));
        board.put("dining", StringUtils.hasText(dining) ? dining : "all");
        board.put("sort", StringUtils.hasText(sort) ? sort : "fifo");
        board.put("merge_rules", mergeRules != null ? mergeRules.toList() : Collections.emptyList());
        board.put("split_pack_takeout", mergeRules != null && mergeRules.isSplitPackTakeout() ? 1 : 0);
        board.put("cross_order_merge", mergeRules != null && mergeRules.isCrossOrder() ? 1 : 0);
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        board.put("merge_same_dish", cfg.getMerge_same_dish() != null ? cfg.getMerge_same_dish() : 1);
        board.put("pack_inline_merge", cfg.getPack_inline_merge() != null ? cfg.getPack_inline_merge() : 1);
        board.put("combo_merge", cfg.getCombo_merge() != null ? cfg.getCombo_merge() : 1);
        board.put("extra", parseExtra(extra));
        board.put("keyword", keyword);
        board.put("queue_counts", overviewBoardService.countWorkflowQueues(shopId, dining, extra, keyword));
        board.put("kds_mode", configService.getOrDefault(shopId).getKds_mode());
        board.put("skewer_gate", configService.isSkewerGateEnabled(shopId) ? 1 : 0);
        board.putIfAbsent("extra_counts", new LinkedHashMap<String, Integer>());
        board.putIfAbsent("dining_counts", new LinkedHashMap<String, Integer>());
        board.put("stats", statsService.todayStats(shopId));
        mergeSummaryQueueCounts(board);
    }

    @SuppressWarnings("unchecked")
    private void mergeSummaryQueueCounts(Map<String, Object> board) {
        Object summaryObj = board.get("summary");
        if (!(summaryObj instanceof Map)) {
            return;
        }
        Map<String, Object> summary = (Map<String, Object>) summaryObj;
        Object qcObj = board.get("queue_counts");
        if (!(qcObj instanceof Map)) {
            return;
        }
        Map<String, ?> qc = (Map<String, ?>) qcObj;
        summary.put("pending_prep_count", qc.get(KdsWorkflowQueue.PENDING_PREP));
        summary.put("pending_cook_count", qc.get(KdsWorkflowQueue.PENDING_COOK));
        summary.put("ready_serve_count", qc.get(KdsWorkflowQueue.READY_SERVE));
        summary.put("done_count", qc.get(KdsWorkflowQueue.DONE));
    }

    private Map<String, Object> advancePrep(int shopId, int detailId, String fromQueue, int quantity) {
        OrderDetail detail = requireActiveDetail(detailId);
        int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        List<KdsTicket> tickets = activeTicketsForDetail(shopId, detailId, fromQueue);
        if (tickets.isEmpty()) {
            throw new IllegalArgumentException("工单不存在或不在待配菜队列");
        }
        KdsTicket ref = tickets.get(0);
        flowBatchService.ensureInitialized(ref, lineQty);
        int qty = quantity > 0 ? quantity : 1;
        int moved = flowBatchService.advancePrep(shopId, ref.getId(), qty);
        ref = ticketMapper.selectById(ref.getId());
        int prepLeft = KdsTicketQuantityUtil.prepRemaining(ref, lineQty);
        String toQueue = prepLeft > 0 ? KdsWorkflowQueue.PENDING_PREP : KdsWorkflowQueue.PENDING_COOK;
        pushWorkflowQuantity(shopId, ref, detailId, lineQty, toQueue);
        Set<String> screens = new LinkedHashSet<>();
        for (KdsTicket t : tickets) {
            if (StringUtils.hasText(t.getScreen_tag())) {
                screens.add(t.getScreen_tag());
            }
        }
        Order order = ref.getOrder_id() != null ? orderService.getById(ref.getOrder_id()) : null;
        for (String screen : screens) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("detail_id", detailId);
            payload.put("order_id", ref.getOrder_id());
            payload.put("prep_quantity", KdsTicketQuantityUtil.prepQuantity(ref));
            payload.put("workflow_queue", toQueue);
            KdsPushPayloadBuilder.enrichOrder(payload, order);
            KdsPushPayloadBuilder.enrichDetail(payload, detail);
            pushService.newOrder(shopId, screen, payload);
        }
        return advanceAndPublish(shopId, detailId, ref,
                advanceResult(detailId, ref.getOrder_id(), fromQueue, toQueue, qty, moved, prepLeft, ref));
    }

    private Map<String, Object> advanceCook(int shopId, int detailId, KdsTicket ticket, String fromQueue, int quantity) {
        OrderDetail detail = requireActiveDetail(detailId);
        int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        flowBatchService.ensureInitialized(ticket, lineQty);
        int qty = quantity > 0 ? quantity : 1;
        int moved = flowBatchService.advanceCook(shopId, ticket.getId(), qty);
        ticket = ticketMapper.selectById(ticket.getId());
        int cookLeft = KdsTicketQuantityUtil.cookRemaining(ticket, lineQty);
        String toQueue = KdsTicketQuantityUtil.serveRemaining(ticket, lineQty) > 0
                ? KdsWorkflowQueue.READY_SERVE : KdsWorkflowQueue.PENDING_COOK;
        pushWorkflowQuantity(shopId, ticket, detailId, lineQty, toQueue);
        return advanceAndPublish(shopId, detailId, ticket,
                advanceResult(detailId, ticket.getOrder_id(), fromQueue, toQueue, qty, moved, cookLeft, ticket));
    }

    private Map<String, Object> advanceServe(int shopId, KdsTicket ticket, int detailId, String fromQueue, int quantity) {
        OrderDetail detail = requireActiveDetail(detailId);
        int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        flowBatchService.ensureInitialized(ticket, lineQty);
        int qty = quantity > 0 ? quantity : 1;
        int moved = flowBatchService.advanceServe(shopId, ticket.getId(), qty);
        ticket = ticketMapper.selectById(ticket.getId());
        String toQueue = ticket.getArchived() != null && ticket.getArchived() == 1
                ? KdsWorkflowQueue.DONE : KdsWorkflowQueue.READY_SERVE;
        pushWorkflowQuantity(shopId, ticket, detailId, lineQty, toQueue);
        if (moved > 0) {
            long transitionVersion = ticket.getUpdated_at() != null
                    ? ticket.getUpdated_at().getTime() : System.nanoTime();
            servePrintService.printDetailLine(shopId, detailId, moved, transitionVersion);
        }
        return advanceAndPublish(shopId, detailId, ticket,
                advanceResult(detailId, ticket.getOrder_id(), fromQueue, toQueue, qty, moved,
                        Math.max(0, KdsTicketQuantityUtil.serveRemaining(ticket, lineQty)), ticket));
    }

    private void pushWorkflowQuantity(int shopId, KdsTicket ticket, int detailId, int lineQty, String workflowQueue) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_id", ticket.getOrder_id());
        payload.put("detail_id", detailId);
        payload.put("prep_quantity", KdsTicketQuantityUtil.prepQuantity(ticket));
        payload.put("cooked_quantity", KdsTicketQuantityUtil.cookedQuantity(ticket, lineQty));
        payload.put("served_quantity", KdsTicketQuantityUtil.servedQuantity(ticket));
        payload.put("prep_remaining", KdsTicketQuantityUtil.prepRemaining(ticket, lineQty));
        payload.put("cook_remaining", KdsTicketQuantityUtil.cookRemaining(ticket, lineQty));
        payload.put("serve_remaining", KdsTicketQuantityUtil.serveRemaining(ticket, lineQty));
        payload.put("workflow_queue", workflowQueue);
        payload.put("archived", ticket.getArchived());
        OrderDetail detail = orderDetailService.getById(detailId);
        Order order = detail != null && detail.getMId() != null ? orderService.getById(detail.getMId()) : null;
        KdsPushPayloadBuilder.enrichOrder(payload, order);
        KdsPushPayloadBuilder.enrichDetail(payload, detail);
        pushService.updateOrder(shopId, KdsScreenTag.WORKFLOW_BOARD, payload);
    }

    private KdsTicket findActiveTicket(int shopId, int detailId, String queue) {
        List<KdsTicket> tickets = activeTicketsForDetail(shopId, detailId, queue);
        return tickets.isEmpty() ? null : tickets.get(0);
    }

    private KdsTicket findTicketWithServedQuantity(int shopId, int detailId) {
        for (KdsTicket ticket : ticketsByDetail(shopId, detailId)) {
            if (KdsTicketQuantityUtil.servedQuantity(ticket) > 0) {
                return ticket;
            }
        }
        return null;
    }

    private static boolean isDishHeld(OrderDetail detail) {
        return KdsWorkflowHoldService.isHold(detail);
    }

    private void validateAdvanceContext(int shopId, int detailId, KdsTicket ticket, String fromQueue,
                                        KdsAdvanceRequestContext context) {
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null || OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
            throw staleWorkOrder("detail_refunded_or_missing");
        }
        if (isDishHeld(detail) && (KdsWorkflowQueue.PENDING_PREP.equals(fromQueue)
                || KdsWorkflowQueue.PENDING_COOK.equals(fromQueue)
                || KdsWorkflowQueue.READY_SERVE.equals(fromQueue))) {
            throw new IllegalArgumentException("菜品处于等叫状态，请先起菜");
        }
        int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
        if (ticket == null || ticket.getShop_id() == null || ticket.getShop_id() != shopId
                || Integer.valueOf(KdsItemStatus.VOID).equals(ticket.getItem_status())
                || !KdsTicketQuantityUtil.hasQueueWork(ticket, lineQty, fromQueue)) {
            throw staleWorkOrder("not_in_from_queue");
        }
        if (context == null || !context.hasAnyExpectation()) return;

        Order order = detail.getMId() != null ? orderService.getById(detail.getMId()) : null;
        if (order == null && ticket.getOrder_id() != null) order = orderService.getById(ticket.getOrder_id());
        Integer actualOrderId = detail.getMId() != null ? detail.getMId() : ticket.getOrder_id();
        if (context.getExpectedOrderId() != null && !context.getExpectedOrderId().equals(actualOrderId)) {
            throw staleWorkOrder("order_mismatch");
        }
        String actualTable = order != null && StringUtils.hasText(order.getTable_number())
                ? order.getTable_number().trim() : null;
        if (StringUtils.hasText(context.getExpectedTableNumber())
                && !context.getExpectedTableNumber().equals(actualTable)) {
            throw staleWorkOrder("table_mismatch");
        }
        String actualDish = StringUtils.hasText(detail.getName()) ? detail.getName().trim() : null;
        if (StringUtils.hasText(context.getExpectedDishName())
                && !context.getExpectedDishName().equals(actualDish)) {
            throw staleWorkOrder("dish_mismatch");
        }
    }

    private static void validateRowVersion(KdsTicket ticket, Long expected) {
        if (expected == null) return;
        long actual = ticket != null && ticket.getUpdated_at() != null ? ticket.getUpdated_at().getTime() : 0L;
        if (ticket == null || actual != expected) throw staleWorkOrder("version_mismatch");
    }

    private static OptimisticLockException staleWorkOrder(String reason) {
        return new OptimisticLockException("工单已被更新，请刷新后重试: " + reason);
    }

    private List<KdsTicket> activeTicketsForDetail(int shopId, int detailId, String queue) {
        OrderDetail detail = orderDetailService.getById(detailId);
        int lineQty = detail != null ? KdsTicketQuantityUtil.lineQuantity(detail.getQuantity()) : 1;
        List<KdsTicket> tickets = ticketsByDetail(shopId, detailId);
        List<KdsTicket> out = new ArrayList<>();
        for (KdsTicket t : tickets) {
            if (KdsTicketQuantityUtil.hasQueueWork(t, lineQty, queue)) {
                out.add(t);
            }
        }
        return out;
    }

    private List<KdsTicket> ticketsByDetail(int shopId, int detailId) {
        return ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("detail_id", detailId)
                .ne("item_status", KdsItemStatus.VOID));
    }

    private List<Integer> sortDetailIdsByFifo(int shopId, List<Integer> detailIds) {
        Map<Integer, Long> fifo = new HashMap<>();
        for (Integer detailId : detailIds) {
            if (detailId == null) {
                continue;
            }
            List<KdsTicket> tickets = ticketsByDetail(shopId, detailId);
            long min = tickets.stream()
                    .map(KdsTicket::getCreated_at)
                    .filter(Objects::nonNull)
                    .mapToLong(Date::getTime)
                    .min().orElse(Long.MAX_VALUE);
            fifo.put(detailId, min);
        }
        List<Integer> ordered = new ArrayList<>(fifo.keySet());
        ordered.sort(Comparator.comparingLong(fifo::get));
        return ordered;
    }

    private OrderDetail requireActiveDetail(int detailId) {
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null) {
            throw new IllegalArgumentException("明细不存在");
        }
        return detail;
    }

    private List<KdsTicket> ticketsForOrderQueue(int shopId, int orderId, String queue) {
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("order_id", orderId);
        KdsWorkflowQueue.applyTicketFilter(q, queue);
        return ticketMapper.selectList(q);
    }

    private int lineQuantity(int detailId) {
        OrderDetail d = orderDetailService.getById(detailId);
        if (d == null || !StringUtils.hasText(d.getQuantity())) {
            return 1;
        }
        try {
            return Math.max(1, (int) Math.round(Double.parseDouble(d.getQuantity().trim())));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    /**
     * D025：队列推进后发布明细制作状态下行（ORDER_LINE_STATUS_CHANGED）。
     * 失败仅记录日志，不阻断推进主事务；由收银端 bootstrap/营业日快照兜底。
     */
    private Map<String, Object> advanceAndPublish(int shopId, int detailId, KdsTicket ticket,
                                                  Map<String, Object> result) {
        if (ticket != null && result != null) {
            try {
                Object orderId = result.get("order_id");
                if (orderId instanceof Number) {
                    projectionService.publishLineStatus(shopId, ((Number) orderId).intValue(),
                            Collections.singletonList(
                                    CashierKdsProjectionService.LineStatusDelta.from(ticket, detailId)));
                }
            } catch (Exception ex) {
                log.warn("[kds] line-status publish failed shop={} detailId={}: {}",
                        shopId, detailId, ex.getMessage());
            }
        }
        return result;
    }
    private static Map<String, Object> advanceResult(Integer detailId, Integer orderId, String fromQueue, String toQueue,
                                                     int requested, int advanced, int remaining, KdsTicket ticket) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("detail_id", detailId);
        result.put("order_id", orderId);
        result.put("from_queue", fromQueue);
        result.put("to_queue", toQueue);
        result.put("requested_quantity", requested);
        result.put("advanced_quantity", advanced);
        result.put("remaining_quantity", remaining);
        result.put("workflow_queue", toQueue);
        if (ticket != null) {
            result.put("ticket_id", ticket.getId());
            result.put("prep_quantity", ticket.getPrep_quantity());
            result.put("cooked_quantity", ticket.getCooked_quantity());
            result.put("served_quantity", ticket.getServed_quantity());
            result.put("archived", ticket.getArchived());
            result.put("item_status", ticket.getItem_status());
        }
        return result;
    }

    private static String normalizeView(String view) {
        return "order".equalsIgnoreCase(view) ? "order" : "dish";
    }

    private static List<String> parseExtra(String extra) {
        if (!StringUtils.hasText(extra)) {
            return Collections.emptyList();
        }
        List<String> out = new ArrayList<>();
        for (String p : extra.split("[,;\\s]+")) {
            if (StringUtils.hasText(p)) {
                out.add(p.trim());
            }
        }
        return out;
    }

    private static int intValue(Object v, int def) {
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        if (v != null) {
            try {
                return Integer.parseInt(v.toString().trim());
            } catch (NumberFormatException ignore) {
                return def;
            }
        }
        return def;
    }
}
