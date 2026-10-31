package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

/**
 * KDS 菜品标记（催 / 超 / 加）持久化与多屏推送。
 */
@Service
public class KdsTicketFlagService {

    private static final Logger log = LoggerFactory.getLogger(KdsTicketFlagService.class);

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsDishServingDurationService servingDurationService;
    @Autowired
    private CashierKdsProjectionService projectionService;

    /**
     * 加菜标签按「订单加菜新增明细」判定，不按整单下单轮次（orderNumber/order_number_snapshot）。
     * 创单时由 {@link #applyAddDishFlagOnCreate} 写入 {@code add_dish_flag}；历史数据可回退 {@code morder_num>1}。
     */
    public static boolean resolveAddDishFlag(KdsTicket ticket, Order order, OrderDetail detail) {
        if (ticket != null && ticket.getAdd_dish_flag() != null) {
            return ticket.getAdd_dish_flag() == 1;
        }
        return detail != null && detail.getMorder_num() != null && detail.getMorder_num() > 1;
    }

    public static int addDishFlagInt(KdsTicket ticket, Order order, OrderDetail detail) {
        return resolveAddDishFlag(ticket, order, detail) ? 1 : 0;
    }

    public static boolean resolveOverdueFlag(KdsTicket ticket, int slaSeconds, long nowMs) {
        if (ticket == null) {
            return false;
        }
        if (ticket.getOverdue_flag() != null && ticket.getOverdue_flag() == 1) {
            if (ticket.getItem_status() != null && ticket.getItem_status() == KdsItemStatus.PENDING) {
                return true;
            }
        }
        return isPastDeadline(ticket, slaSeconds, nowMs);
    }

    private static boolean isPastDeadline(KdsTicket ticket, int slaSeconds, long nowMs) {
        if (ticket == null || ticket.getItem_status() == null || ticket.getItem_status() != KdsItemStatus.PENDING) {
            return false;
        }
        if (ticket.getCreated_at() == null) {
            return false;
        }
        long waitSeconds = (nowMs - ticket.getCreated_at().getTime()) / 1000;
        return waitSeconds > slaSeconds;
    }

    public static Map<String, Object> toFlagPayload(KdsTicket t) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (t == null) {
            return m;
        }
        m.put("ticket_id", t.getId());
        m.put("order_id", t.getOrder_id());
        m.put("detail_id", t.getDetail_id());
        m.put("screen_tag", t.getScreen_tag());
        m.put("rush_flag", t.getRush_flag() != null ? t.getRush_flag() : 0);
        m.put("add_dish_flag", t.getAdd_dish_flag() != null ? t.getAdd_dish_flag() : 0);
        m.put("overdue_flag", t.getOverdue_flag() != null ? t.getOverdue_flag() : 0);
        if (t.getRush_at() != null) {
            m.put("rush_at", t.getRush_at());
        }
        if (t.getOverdue_at() != null) {
            m.put("overdue_at", t.getOverdue_at());
        }
        return m;
    }

    public void applyAddDishFlagOnCreate(KdsTicket ticket, boolean markAddDish) {
        if (ticket == null) {
            return;
        }
        ticket.setAdd_dish_flag(markAddDish ? 1 : 0);
    }

    /** 划菜等非待做状态时清除超时标记。 */
    public void clearOverdueIfNotPending(KdsTicket ticket) {
        if (ticket == null || ticket.getItem_status() == null) {
            return;
        }
        if (ticket.getItem_status() == KdsItemStatus.PENDING) {
            return;
        }
        if (ticket.getOverdue_flag() != null && ticket.getOverdue_flag() == 1) {
            ticket.setOverdue_flag(0);
            ticket.setOverdue_at(null);
        }
    }

    /**
     * 催菜：同店同单全部生产工单（跨屏）持久化 rush_flag，并 WS 广播。
     *
     * @param detailId 可选，仅催指定明细
     */
    @Transactional
    public Map<String, Object> rushOrder(int shopId, int orderId, Integer detailId) {
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("order_id", orderId)
                .ne("item_status", KdsItemStatus.VOID);
        if (detailId != null) {
            q.eq("detail_id", detailId);
        }
        List<KdsTicket> tickets = ticketMapper.selectList(q);
        if (tickets == null || tickets.isEmpty()) {
            Map<String, Object> empty = new LinkedHashMap<>();
            empty.put("updated", 0);
            empty.put("order_id", orderId);
            return empty;
        }
        Date now = new Date();
        List<Map<String, Object>> changed = new ArrayList<>();
        for (KdsTicket t : tickets) {
            t.setRush_flag(1);
            t.setRush_at(now);
            t.setUpdated_at(now);
            ticketMapper.updateById(t);
            changed.add(toFlagPayload(t));
        }
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_id", orderId);
        payload.put("detail_id", detailId);
        payload.put("rush_flag", 1);
        payload.put("tickets", changed);
        pushService.dishFlagsChanged(shopId, payload);
        publishLineStatus(shopId, orderId, tickets);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("updated", changed.size());
        result.put("order_id", orderId);
        result.put("tickets", changed);
        return result;
    }

    /**
     * 扫描待做工单，持久化 overdue_flag；状态变化时推送多屏。
     */
    @Transactional
    public int refreshOverdueForShop(int shopId, int slaSeconds) {
        long nowMs = System.currentTimeMillis();
        Date now = new Date(nowMs);
        List<KdsTicket> pending = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("item_status", KdsItemStatus.PENDING)
                .eq("archived", 0));
        if (pending == null || pending.isEmpty()) {
            return 0;
        }
        Map<Integer, Integer> secondsByDetail = servingDurationService.resolveSecondsByDetailIds(
                pending.stream().map(KdsTicket::getDetail_id).filter(Objects::nonNull).collect(java.util.stream.Collectors.toSet()),
                slaSeconds, shopId);
        int changed = 0;
        Map<Integer, List<Map<String, Object>>> byOrder = new LinkedHashMap<>();
        Map<Integer, List<KdsTicket>> flippedByOrder = new LinkedHashMap<>();
        for (KdsTicket t : pending) {
            int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                    t.getDetail_id(), secondsByDetail, slaSeconds);
            // 定时扫描必须按当前菜品时长重新计算，菜品时长调大后也能清除旧超时标记。
            boolean shouldOverdue = isPastDeadline(t, itemSlaSeconds, nowMs);
            int cur = t.getOverdue_flag() != null ? t.getOverdue_flag() : 0;
            int next = shouldOverdue ? 1 : 0;
            if (cur == next) {
                continue;
            }
            t.setOverdue_flag(next);
            t.setOverdue_at(next == 1 ? now : null);
            t.setUpdated_at(now);
            ticketMapper.updateById(t);
            changed++;
            byOrder.computeIfAbsent(t.getOrder_id(), k -> new ArrayList<>()).add(toFlagPayload(t));
            flippedByOrder.computeIfAbsent(t.getOrder_id(), k -> new ArrayList<>()).add(t);
        }
        for (Map.Entry<Integer, List<Map<String, Object>>> e : byOrder.entrySet()) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("order_id", e.getKey());
            boolean anyOverdue = e.getValue().stream()
                    .anyMatch(ticket -> Integer.valueOf(1).equals(ticket.get("overdue_flag")));
            payload.put("overdue_flag", anyOverdue ? 1 : 0);
            payload.put("tickets", e.getValue());
            pushService.dishFlagsChanged(shopId, payload);
        }
        for (Map.Entry<Integer, List<KdsTicket>> e : flippedByOrder.entrySet()) {
            publishLineStatus(shopId, e.getKey(), e.getValue());
        }
        return changed;
    }


    /**
     * D025：将已更新的工单明细状态下行给收银端（失败不阻断，由收银端 bootstrap 兜底）。
     */
    private void publishLineStatus(int shopId, int orderId, Collection<KdsTicket> tickets) {
        if (tickets == null || tickets.isEmpty()) {
            return;
        }
        try {
            List<CashierKdsProjectionService.LineStatusDelta> deltas = new ArrayList<>();
            for (KdsTicket t : tickets) {
                deltas.add(CashierKdsProjectionService.LineStatusDelta.from(t, t.getDetail_id()));
            }
            projectionService.publishLineStatus(shopId, orderId, deltas);
        } catch (Exception ex) {
            log.warn("[kds] line-status publish failed shop={} order={}: {}", shopId, orderId, ex.getMessage());
        }
    }

    public static void appendFlagsToItemMap(Map<String, Object> item, KdsTicket t,
                                              Order order, OrderDetail detail,
                                              int slaSeconds, long nowMs) {
        int rush = t.getRush_flag() != null ? t.getRush_flag() : 0;
        int addDish = t.getAdd_dish_flag() != null ? t.getAdd_dish_flag() : addDishFlagInt(t, order, detail);
        boolean overdue = t.getOverdue_flag() != null && t.getOverdue_flag() == 1
                && t.getItem_status() != null && t.getItem_status() == KdsItemStatus.PENDING;
        if (!overdue) {
            overdue = resolveOverdueFlag(t, slaSeconds, nowMs);
        }
        item.put("rush_flag", rush);
        item.put("add_dish_flag", addDish);
        item.put("overdue_flag", overdue);
        if (t.getRush_at() != null) {
            item.put("rush_at", t.getRush_at());
        }
        if (t.getOverdue_at() != null) {
            item.put("overdue_at", t.getOverdue_at());
        }
    }
}
