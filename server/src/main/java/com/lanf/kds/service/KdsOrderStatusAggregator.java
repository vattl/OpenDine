package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsOrder;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.event.KdsOrderStatusChangedEvent;
import com.lanf.kds.mapper.KdsOrderMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.util.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class KdsOrderStatusAggregator {

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsOrderMapper kdsOrderMapper;
    @Autowired
    private KdsLegacySyncService legacySyncService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private ApplicationEventPublisher eventPublisher;

    /**
     * 整单状态聚合。
     *
     * 注意：调用方在外层事务内同步调用本方法时，任何内部异常都会污染外层事务
     * （标记 rollback-only），导致上层接口 500。本方法内部 try/catch 已把所有
     * 可恢复异常吞掉，仅当 SQL 语法错误等致命异常才会向上抛出。
     */
    @org.springframework.transaction.annotation.Transactional
    public int aggregateAndSave(int orderId, int shopId, String orderNo, boolean orderClosed) {
        try {
            if (!orderClosed) {
                Order order = orderService.getById(orderId);
                if (isKdsOrderEnded(order)) {
                    orderClosed = true;
                }
            }
            List<KdsTicket> tickets = orderClosed ? null : ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("order_id", orderId)
                    .ne("item_status", KdsItemStatus.VOID));
            Map<Integer, OrderDetail> details = loadDetails(tickets);
            int status = computeOrderStatus(tickets, orderClosed, details);
            try {
                legacySyncService.afterOrderKdsStatus(shopId, orderId, status);
            } catch (Exception ex) {
                log.warn("[kds] legacy 同步失败 order_id={}: {}", orderId, ex.getMessage());
            }
            Integer fromStatus = currentStatus(orderId);
            upsert(orderId, shopId, orderNo, status);
            if (fromStatus == null || fromStatus != status) {
                try {
                    eventPublisher.publishEvent(new KdsOrderStatusChangedEvent(
                            this, shopId, orderId, orderNo, fromStatus != null ? fromStatus : -1, status));
                } catch (Exception ex) {
                    log.warn("[kds] 状态事件发布失败 order_id={}: {}", orderId, ex.getMessage());
                }
            }
            return status;
        } catch (Exception ex) {
            log.warn("[kds] 整单状态聚合失败 order_id={}: {}", orderId, ex.getMessage(), ex);
            return KdsOrderStatus.WAITING;
        }
    }

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(KdsOrderStatusAggregator.class);

    private Integer currentStatus(int orderId) {
        KdsOrder row = kdsOrderMapper.selectById(orderId);
        return row != null ? row.getKds_order_status() : null;
    }

    /** 厨显 90（已关闭）仅用于取消单；结账（{@code success}）不影响厨显，仍按 KDS 工单聚合。 */
    private static boolean isKdsOrderEnded(Order order) {
        if (order == null) {
            return false;
        }
        String ts = order.getTransac_status();
        return ts != null && "cancelled".equals(ts.trim());
    }

    /**
     * 根据非 void 工单计算整单厨显状态（供单测）。
     */
    static int computeOrderStatus(List<KdsTicket> tickets, boolean orderClosed) {
        return computeOrderStatus(tickets, orderClosed, Collections.emptyMap());
    }

    static int computeOrderStatus(List<KdsTicket> tickets, boolean orderClosed, Map<Integer, OrderDetail> details) {
        if (orderClosed) {
            return KdsOrderStatus.CLOSED;
        }
        if (tickets == null || tickets.isEmpty()) {
            return KdsOrderStatus.WAITING;
        }
        if (hasQuantityProgress(tickets)) {
            return computeByQuantity(tickets, details);
        }
        return computeByItemStatus(tickets);
    }

    private static boolean hasQuantityProgress(List<KdsTicket> tickets) {
        for (KdsTicket t : tickets) {
            if (KdsTicketQuantityUtil.prepQuantity(t) > 0
                    || (t.getCooked_quantity() != null && t.getCooked_quantity() > 0)
                    || KdsTicketQuantityUtil.servedQuantity(t) > 0) {
                return true;
            }
        }
        return false;
    }

    private static int computeByQuantity(List<KdsTicket> tickets, Map<Integer, OrderDetail> details) {
        int totalLine = 0;
        int totalServed = 0;
        int totalProgress = 0;
        for (KdsTicket t : tickets) {
            OrderDetail d = details != null ? details.get(t.getDetail_id()) : null;
            int lineQty = KdsTicketQuantityUtil.lineQuantity(d != null ? d.getQuantity() : null);
            totalLine += lineQty;
            int served = KdsTicketQuantityUtil.servedQuantity(t);
            totalServed += served;
            if (KdsTicketQuantityUtil.prepQuantity(t) > 0
                    || KdsTicketQuantityUtil.cookedQuantity(t, lineQty) > 0
                    || served > 0) {
                totalProgress += Math.max(lineQty - served, 0);
            }
        }
        if (totalLine > 0 && totalServed >= totalLine) {
            return KdsOrderStatus.ALL_DONE;
        }
        if (totalServed > 0) {
            return KdsOrderStatus.PARTIAL;
        }
        if (totalProgress > 0) {
            return KdsOrderStatus.COOKING;
        }
        return KdsOrderStatus.WAITING;
    }

    private static int computeByItemStatus(List<KdsTicket> tickets) {
        int pending = 0;
        int cooking = 0;
        int done = 0;
        for (KdsTicket t : tickets) {
            int s = t.getItem_status() != null ? t.getItem_status() : KdsItemStatus.PENDING;
            if (s == KdsItemStatus.PENDING) {
                pending++;
            } else if (s == KdsItemStatus.COOKING) {
                cooking++;
            } else if (s == KdsItemStatus.DONE) {
                done++;
            }
        }
        int total = pending + cooking + done;
        if (total > 0 && done == total) {
            return KdsOrderStatus.ALL_DONE;
        }
        if (done > 0 && (pending > 0 || cooking > 0)) {
            return KdsOrderStatus.PARTIAL;
        }
        if (cooking > 0 || done > 0) {
            return KdsOrderStatus.COOKING;
        }
        return KdsOrderStatus.WAITING;
    }

    private Map<Integer, OrderDetail> loadDetails(List<KdsTicket> tickets) {
        if (tickets == null || tickets.isEmpty()) {
            return Collections.emptyMap();
        }
        Set<Integer> detailIds = tickets.stream()
                .map(KdsTicket::getDetail_id)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        if (detailIds.isEmpty()) {
            return Collections.emptyMap();
        }
        List<OrderDetail> list = orderDetailService.listByIds(detailIds);
        if (list == null || list.isEmpty()) {
            return Collections.emptyMap();
        }
        Map<Integer, OrderDetail> out = new HashMap<>();
        for (OrderDetail d : list) {
            if (d != null && d.getId() != null) {
                out.put(d.getId(), d);
            }
        }
        return out;
    }

    private void upsert(int orderId, int shopId, String orderNo, int status) {
        KdsOrder row = kdsOrderMapper.selectById(orderId);
        Date now = new Date();
        if (row == null) {
            row = new KdsOrder();
            row.setOrder_id(orderId);
            row.setShop_id(shopId);
            row.setOrder_no(orderNo);
            row.setKds_order_status(status);
            row.setRevision(1);
            row.setCreated_at(now);
            row.setUpdated_at(now);
            kdsOrderMapper.insert(row);
        } else {
            row.setKds_order_status(status);
            row.setRevision(row.getRevision() == null ? 1 : row.getRevision() + 1);
            row.setUpdated_at(now);
            kdsOrderMapper.updateById(row);
        }
    }
}
