package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsFlowBatchStatus;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsFlowBatch;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsFlowBatchMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 美团 KDS 对齐：原始明细拆分为可核销批次，按下单/配菜时间 FCFS 流转。
 */
@Service
public class KdsFlowBatchService {

    private static final Logger log = LoggerFactory.getLogger(KdsFlowBatchService.class);

    @Autowired
    private KdsFlowBatchMapper batchMapper;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsOrderStatusAggregator orderStatusAggregator;
    @Autowired(required = false)
    private KdsConfigService configService;

    @Transactional
    public void initForTicket(KdsTicket ticket, Order order, OrderDetail detail, int lineQty) {
        if (ticket == null || ticket.getId() == null || lineQty <= 0) {
            return;
        }
        Integer existing = batchMapper.selectCount(new QueryWrapper<KdsFlowBatch>()
                .eq("ticket_id", ticket.getId()));
        if (existing != null && existing > 0) {
            return;
        }
        boolean prepEnabled = true;
        if (configService != null && ticket.getShop_id() != null) {
            prepEnabled = configService.isPrepWorkflowEnabled(ticket.getShop_id(), ticket.getStation_id());
        }
        Date now = new Date();
        KdsFlowBatch batch = new KdsFlowBatch();
        batch.setShop_id(ticket.getShop_id());
        batch.setTicket_id(ticket.getId());
        batch.setDetail_id(ticket.getDetail_id());
        batch.setOrder_id(ticket.getOrder_id());
        batch.setQuantity(lineQty);
        batch.setDining_channel(diningChannel(order));
        if (!prepEnabled) {
            batch.setQueue_status(KdsFlowBatchStatus.PENDING_COOK);
            batch.setPrep_at(now);
        } else {
            batch.setQueue_status(KdsFlowBatchStatus.PENDING_PREP);
        }
        batch.setOrder_time(ticket.getCreated_at() != null ? ticket.getCreated_at() : now);
        batch.setCreated_at(now);
        batch.setUpdated_at(now);
        batchMapper.insert(batch);
        syncTicketAggregates(ticket.getId());
    }

    @Transactional
    public int advancePrep(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.PENDING_PREP, KdsFlowBatchStatus.PENDING_COOK,
                "order_time", quantity, false);
    }

    @Transactional
    public int advanceCook(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.PENDING_COOK, KdsFlowBatchStatus.READY_SERVE,
                "prep_at", quantity, false);
    }

    @Transactional
    public int advanceServe(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.READY_SERVE, KdsFlowBatchStatus.DONE,
                "cooked_at", quantity, false);
    }

    @Transactional
    public int revokeServe(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.DONE, KdsFlowBatchStatus.READY_SERVE,
                "served_at", quantity, true);
    }

    @Transactional
    public int revokeCook(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.READY_SERVE, KdsFlowBatchStatus.PENDING_COOK,
                "cooked_at", quantity, true);
    }

    @Transactional
    public int revokePrep(int shopId, long ticketId, int quantity) {
        return moveQuantity(shopId, ticketId, KdsFlowBatchStatus.PENDING_COOK, KdsFlowBatchStatus.PENDING_PREP,
                "prep_at", quantity, true);
    }

    @Transactional
    public void voidByOrderId(int shopId, int orderId, String reason) {
        Date now = new Date();
        List<KdsFlowBatch> batches = batchMapper.selectList(new QueryWrapper<KdsFlowBatch>()
                .eq("shop_id", shopId)
                .eq("order_id", orderId)
                .ne("queue_status", KdsFlowBatchStatus.VOID));
        for (KdsFlowBatch b : batches) {
            b.setQueue_status(KdsFlowBatchStatus.VOID);
            b.setVoid_reason(reason);
            b.setUpdated_at(now);
            batchMapper.updateById(b);
        }
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("order_id", orderId));
        for (KdsTicket t : tickets) {
            syncTicketAggregates(t.getId());
        }
    }

    @Transactional
    public void voidByDetail(int shopId, int detailId, String reason) {
        Date now = new Date();
        List<KdsFlowBatch> batches = batchMapper.selectList(new QueryWrapper<KdsFlowBatch>()
                .eq("shop_id", shopId)
                .eq("detail_id", detailId)
                .ne("queue_status", KdsFlowBatchStatus.VOID));
        for (KdsFlowBatch b : batches) {
            b.setQueue_status(KdsFlowBatchStatus.VOID);
            b.setVoid_reason(reason);
            b.setUpdated_at(now);
            batchMapper.updateById(b);
        }
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("detail_id", detailId));
        for (KdsTicket t : tickets) {
            syncTicketAggregates(t.getId());
        }
    }

    @Transactional
    public void clampAfterDetailChange(int shopId, int detailId, int newLineQty) {
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("detail_id", detailId)
                .ne("item_status", KdsItemStatus.VOID));
        int remaining = Math.max(0, newLineQty);
        for (KdsTicket t : tickets) {
            ensureInitialized(t, newLineQty);
            List<KdsFlowBatch> batches = listActiveBatches(t.getId());
            for (KdsFlowBatch b : batches) {
                if (remaining <= 0) {
                    b.setQueue_status(KdsFlowBatchStatus.VOID);
                    b.setVoid_reason("qty_reduce");
                } else if (b.getQuantity() > remaining) {
                    b.setQuantity(remaining);
                    remaining = 0;
                } else {
                    remaining -= b.getQuantity();
                }
                b.setUpdated_at(new Date());
                batchMapper.updateById(b);
            }
            syncTicketAggregates(t.getId());
        }
    }

    public List<KdsFlowBatch> listActiveBatches(long ticketId) {
        return batchMapper.selectList(new QueryWrapper<KdsFlowBatch>()
                .eq("ticket_id", ticketId)
                .ne("queue_status", KdsFlowBatchStatus.VOID)
                .orderByAsc("order_time")
                .orderByAsc("id"));
    }

    public boolean hasAnyBatch(long ticketId) {
        if (ticketId <= 0) {
            return false;
        }
        Integer count = batchMapper.selectCount(new QueryWrapper<KdsFlowBatch>().eq("ticket_id", ticketId));
        return count != null && count > 0;
    }

    /** 当前队列状态下批次份数合计（无批次时返回 -1 表示应回退工单字段）。 */
    public int queueBatchQuantity(long ticketId, String queueStatus) {
        if (ticketId <= 0 || queueStatus == null) {
            return -1;
        }
        if (!hasAnyBatch(ticketId)) {
            return -1;
        }
        List<KdsFlowBatch> batches = batchMapper.selectList(new QueryWrapper<KdsFlowBatch>()
                .eq("ticket_id", ticketId)
                .eq("queue_status", queueStatus));
        int sum = 0;
        for (KdsFlowBatch b : batches) {
            sum += b.getQuantity() != null ? b.getQuantity() : 0;
        }
        return sum;
    }

    public Map<String, Integer> sumDiningByStatus(long ticketId, String queueStatus) {
        Map<String, Integer> out = new LinkedHashMap<>();
        out.put("dine_in", 0);
        out.put("pack", 0);
        out.put("takeout", 0);
        List<KdsFlowBatch> batches = batchMapper.selectList(new QueryWrapper<KdsFlowBatch>()
                .eq("ticket_id", ticketId)
                .eq("queue_status", queueStatus));
        for (KdsFlowBatch b : batches) {
            String ch = b.getDining_channel() != null ? b.getDining_channel() : "dine_in";
            out.put(ch, out.getOrDefault(ch, 0) + (b.getQuantity() != null ? b.getQuantity() : 0));
        }
        return out;
    }

    public void ensureInitialized(KdsTicket ticket, int lineQty) {
        if (ticket == null || ticket.getId() == null) {
            return;
        }
        Integer count = batchMapper.selectCount(new QueryWrapper<KdsFlowBatch>().eq("ticket_id", ticket.getId()));
        if (count != null && count > 0) {
            return;
        }
        migrateFromTicketAggregates(ticket, lineQty);
    }

    private void migrateFromTicketAggregates(KdsTicket ticket, int lineQty) {
        Date now = new Date();
        String dining = resolveDiningChannel(ticket.getOrder_id());
        int prepRem = KdsTicketQuantityUtil.prepRemaining(ticket, lineQty);
        int cookRem = KdsTicketQuantityUtil.cookRemaining(ticket, lineQty);
        int serveRem = KdsTicketQuantityUtil.serveRemaining(ticket, lineQty);
        int served = KdsTicketQuantityUtil.servedQuantity(ticket);
        if (prepRem > 0) {
            insertBatch(ticket, prepRem, KdsFlowBatchStatus.PENDING_PREP, null, null, null, now, dining);
        }
        if (cookRem > 0) {
            insertBatch(ticket, cookRem, KdsFlowBatchStatus.PENDING_COOK, ticket.getSkewer_picked_at(), null, null, now, dining);
        }
        if (serveRem > 0) {
            insertBatch(ticket, serveRem, KdsFlowBatchStatus.READY_SERVE, ticket.getSkewer_picked_at(),
                    ticket.getDone_at(), null, now, dining);
        }
        if (served > 0) {
            insertBatch(ticket, served, KdsFlowBatchStatus.DONE, ticket.getSkewer_picked_at(),
                    ticket.getDone_at(), now, now, dining);
        }
        if (prepRem + cookRem + serveRem + served <= 0 && lineQty > 0) {
            insertBatch(ticket, lineQty, KdsFlowBatchStatus.PENDING_PREP, null, null, null, now, dining);
        }
        syncTicketAggregates(ticket.getId());
    }

    private String resolveDiningChannel(Integer orderId) {
        if (orderId == null) {
            return "dine_in";
        }
        Order order = orderService.getById(orderId);
        return diningChannel(order);
    }

    private int moveQuantity(int shopId, long ticketId, String fromStatus, String toStatus,
                             String sortField, int quantity, boolean reverseFifo) {
        int need = Math.max(1, quantity);
        int moved = 0;
        Date now = new Date();
        QueryWrapper<KdsFlowBatch> q = new QueryWrapper<KdsFlowBatch>()
                .eq("shop_id", shopId)
                .eq("ticket_id", ticketId)
                .eq("queue_status", fromStatus);
        if (reverseFifo) {
            if ("prep_at".equals(sortField)) {
                q.orderByDesc("prep_at").orderByDesc("id");
            } else if ("cooked_at".equals(sortField)) {
                q.orderByDesc("cooked_at").orderByDesc("id");
            } else if ("served_at".equals(sortField)) {
                q.orderByDesc("served_at").orderByDesc("id");
            } else {
                q.orderByDesc("order_time").orderByDesc("id");
            }
        } else if ("order_time".equals(sortField)) {
            q.orderByAsc("order_time").orderByAsc("id");
        } else if ("prep_at".equals(sortField)) {
            q.orderByAsc("prep_at").orderByAsc("id");
        } else {
            q.orderByAsc("cooked_at").orderByAsc("id");
        }
        List<KdsFlowBatch> batches = batchMapper.selectList(q);
        for (KdsFlowBatch b : batches) {
            if (need <= 0) {
                break;
            }
            int bq = b.getQuantity() != null ? b.getQuantity() : 0;
            if (bq <= 0) {
                continue;
            }
            int take = Math.min(need, bq);
            if (take == bq) {
                b.setQueue_status(toStatus);
                stampTransition(b, toStatus, now, reverseFifo);
                b.setUpdated_at(now);
                batchMapper.updateById(b);
            } else {
                b.setQuantity(bq - take);
                b.setUpdated_at(now);
                batchMapper.updateById(b);
                KdsFlowBatch nb = copyBatch(b, take, toStatus, now);
                stampTransition(nb, toStatus, now, reverseFifo);
                batchMapper.insert(nb);
            }
            moved += take;
            need -= take;
        }
        syncTicketAggregates(ticketId);
        return moved;
    }

    private static void stampTransition(KdsFlowBatch b, String toStatus, Date now, boolean reverse) {
        if (reverse) {
            if (KdsFlowBatchStatus.READY_SERVE.equals(toStatus)) {
                b.setServed_at(null);
            }
            if (KdsFlowBatchStatus.PENDING_COOK.equals(toStatus)) {
                b.setCooked_at(null);
                b.setServed_at(null);
            }
            if (KdsFlowBatchStatus.PENDING_PREP.equals(toStatus)) {
                b.setPrep_at(null);
                b.setCooked_at(null);
                b.setServed_at(null);
            }
            return;
        }
        if (KdsFlowBatchStatus.PENDING_COOK.equals(toStatus) && b.getPrep_at() == null) {
            b.setPrep_at(now);
        }
        if (KdsFlowBatchStatus.READY_SERVE.equals(toStatus) && b.getCooked_at() == null) {
            b.setCooked_at(now);
        }
        if (KdsFlowBatchStatus.DONE.equals(toStatus) && b.getServed_at() == null) {
            b.setServed_at(now);
        }
    }

    private KdsFlowBatch copyBatch(KdsFlowBatch src, int qty, String status, Date now) {
        KdsFlowBatch b = new KdsFlowBatch();
        b.setShop_id(src.getShop_id());
        b.setTicket_id(src.getTicket_id());
        b.setDetail_id(src.getDetail_id());
        b.setOrder_id(src.getOrder_id());
        b.setQuantity(qty);
        b.setDining_channel(src.getDining_channel());
        b.setQueue_status(status);
        b.setOrder_time(src.getOrder_time());
        b.setPrep_at(src.getPrep_at());
        b.setCooked_at(src.getCooked_at());
        b.setServed_at(src.getServed_at());
        b.setCreated_at(now);
        b.setUpdated_at(now);
        return b;
    }

    private void insertBatch(KdsTicket ticket, int qty, String status, Date prepAt, Date cookedAt, Date servedAt,
                             Date now, String diningChannel) {
        KdsFlowBatch b = new KdsFlowBatch();
        b.setShop_id(ticket.getShop_id());
        b.setTicket_id(ticket.getId());
        b.setDetail_id(ticket.getDetail_id());
        b.setOrder_id(ticket.getOrder_id());
        b.setQuantity(qty);
        b.setDining_channel(diningChannel);
        b.setQueue_status(status);
        b.setOrder_time(ticket.getCreated_at() != null ? ticket.getCreated_at() : now);
        b.setPrep_at(prepAt);
        b.setCooked_at(cookedAt);
        b.setServed_at(servedAt);
        b.setCreated_at(now);
        b.setUpdated_at(now);
        batchMapper.insert(b);
    }

    public void syncTicketAggregates(long ticketId) {
        KdsTicket ticket = ticketMapper.selectById(ticketId);
        if (ticket == null) {
            return;
        }
        List<KdsFlowBatch> batches = listActiveBatches(ticketId);
        int prepRem = 0;
        int cookRem = 0;
        int serveRem = 0;
        int served = 0;
        Date firstPrep = null;
        for (KdsFlowBatch b : batches) {
            int q = b.getQuantity() != null ? b.getQuantity() : 0;
            switch (b.getQueue_status()) {
                case KdsFlowBatchStatus.PENDING_PREP:
                    prepRem += q;
                    break;
                case KdsFlowBatchStatus.PENDING_COOK:
                    cookRem += q;
                    if (b.getPrep_at() != null && (firstPrep == null || b.getPrep_at().before(firstPrep))) {
                        firstPrep = b.getPrep_at();
                    }
                    break;
                case KdsFlowBatchStatus.READY_SERVE:
                    serveRem += q;
                    break;
                case KdsFlowBatchStatus.DONE:
                    served += q;
                    break;
                default:
                    break;
            }
        }
        int lineQty = prepRem + cookRem + serveRem + served;
        int prepQty = lineQty - prepRem;
        int cookedQty = serveRem + served;
        ticket.setPrep_quantity(prepQty);
        ticket.setCooked_quantity(cookedQty);
        ticket.setServed_quantity(served);
        if (prepQty > 0 && firstPrep != null) {
            ticket.setSkewer_picked_at(firstPrep);
            ticket.setSkewer_picked(1);
        } else if (prepRem == lineQty && lineQty > 0) {
            ticket.setSkewer_picked(0);
        }
        if (lineQty > 0 && served >= lineQty && cookedQty >= lineQty) {
            ticket.setItem_status(KdsItemStatus.DONE);
            ticket.setArchived(1);
            if (ticket.getDone_at() == null) {
                ticket.setDone_at(new Date());
            }
        } else {
            ticket.setArchived(0);
            if (prepQty > 0 || cookedQty > 0 || served > 0) {
                ticket.setItem_status(KdsItemStatus.COOKING);
            } else {
                ticket.setItem_status(KdsItemStatus.PENDING);
            }
        }
        ticket.setUpdated_at(new Date());
        ticketMapper.updateById(ticket);
        if (ticket.getOrder_id() != null && ticket.getShop_id() != null) {
            try {
                orderStatusAggregator.aggregateAndSave(
                        ticket.getOrder_id(), ticket.getShop_id(), ticket.getOrder_no(), false);
            } catch (Exception ex) {
                log.warn("[kds] 整单状态聚合失败 order_id={} ticket_id={}: {}",
                        ticket.getOrder_id(), ticketId, ex.getMessage(), ex);
            }
        }
    }

    public static String diningChannel(Order order) {
        if (order == null || order.getDineInOrTakeOut() == null) {
            return "dine_in";
        }
        String t = order.getDineInOrTakeOut().trim();
        if ("打包".equals(t)) {
            return "pack";
        }
        if ("外卖".equals(t)) {
            return "takeout";
        }
        return "dine_in";
    }

    public List<Map<String, Object>> toBatchPayload(long ticketId) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (KdsFlowBatch b : listActiveBatches(ticketId)) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("batch_id", b.getId());
            m.put("quantity", b.getQuantity());
            m.put("queue_status", b.getQueue_status());
            m.put("dining_channel", b.getDining_channel());
            m.put("order_time", b.getOrder_time());
            m.put("prep_at", b.getPrep_at());
            m.put("cooked_at", b.getCooked_at());
            out.add(m);
        }
        out.sort(Comparator.comparing(m -> String.valueOf(m.get("order_time"))));
        return out;
    }
}
