package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsOrderAcceptance;
import com.lanf.kds.support.KdsPushPayloadBuilder;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 订单事件 → 持久化投影意图及可选 KDS 工单。意图失败必须回滚，可选工单失败单独记录。
 */
@Component
public class KdsOrderHook {

    private static final Logger log = LoggerFactory.getLogger(KdsOrderHook.class);

    public enum Trigger {
        CREATE, ADD_DISHES, PAID, REFUND, CANCEL, MANUAL
    }

    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsOrderStatusAggregator orderStatusAggregator;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsFlowBatchService flowBatchService;
    @Autowired
    private CashierKdsProjectionService cashierKdsProjectionService;
    @Autowired(required = false)
    private KdsWorkflowV2Service kdsWorkflowV2Service;

    @Transactional
    public void afterOrderCommitted(Order order, List<Integer> newDetailIds, Trigger trigger) {
        afterOrderCommitted(order, newDetailIds, trigger, true);
    }

    /** The add-dishes transaction has already recorded its durable projection intent. */
    @Transactional
    public void afterAddedDishesCommitted(Order order, List<Integer> newDetailIds) {
        afterOrderCommitted(order, newDetailIds, Trigger.ADD_DISHES, false);
    }

    private void afterOrderCommitted(Order order, List<Integer> newDetailIds, Trigger trigger, boolean recordProjection) {
        if (order == null || order.getId() == null) {
            return;
        }
        int shopId = order.getShop_id() != null ? order.getShop_id() : 0;
        if (shopId <= 0) {
            log.warn("[kds] skip hook: order_no={} missing shop_id, trigger={}", order.getOrder_no(), trigger);
            return;
        }
        try {
            if (trigger == Trigger.CREATE || trigger == Trigger.ADD_DISHES || trigger == Trigger.PAID || trigger == Trigger.MANUAL) {
                Order latest = orderService.getById(order.getId());
                if (latest == null) {
                    log.warn("[kds] skip hook: order_id={} not found, trigger={}", order.getId(), trigger);
                    return;
                }
                if (!KdsOrderAcceptance.isAccepted(latest)) {
                    log.info("[kds] skip hook: order_no={} order_receiving={} 未接单，不下发收银 KDS 投影或工单, trigger={}",
                            latest.getOrder_no(), latest.getOrder_receiving(), trigger);
                    return;
                }
                if (recordProjection) {
                    cashierKdsProjectionService.publishAfterCommit(order.getId(),
                            trigger == Trigger.ADD_DISHES ? "ORDER_UPDATED" : "ORDER_ACCEPTED",
                            trigger == Trigger.MANUAL ? "ADMIN" : null, null, newDetailIds);
                }
                // 云端接单是唯一的 KDS 下发门禁。收银端只能在收到该投影后创建本地 KDS 数据。
                if (!configService.isKdsEnabled(shopId)) {
                    log.info("[kds] cloud ticket disabled but accepted cashier delivery retained shop={} order={}", shopId, latest.getOrder_no());
                    return;
                }
                log.info("[kds] hook shop_id={} order_no={} order_id={} trigger={}",
                        shopId, latest.getOrder_no(), latest.getId(), trigger);
                ticketService.createTicketsForOrder(latest, newDetailIds, trigger);
            }
        } catch (Exception e) {
            log.warn("[kds] hook failed orderId={} trigger={}: {}", order.getId(), trigger, e.getMessage());
            throw e;
        }
    }

    /** 补偿已接单但因瞬时故障未建成工单的订单；不重复写收银端投影意图。 */
    public void ensureTicketsForAcceptedOrder(Order order) {
        afterOrderCommitted(order, null, Trigger.MANUAL, false);
    }

    public boolean hasActiveTicketsForOrder(Order order) {
        return order != null && order.getId() != null && order.getShop_id() != null
                && ticketService.hasActiveTicketsForOrder(order.getShop_id(), order.getId());
    }

    public boolean hasMissingTicketsForOrder(Order order) {
        return order != null && order.getId() != null && order.getShop_id() != null
                && ticketService.hasMissingTicketsForOrder(order);
    }

    @Transactional
    public void afterDetailQuantityReduced(int shopId, int detailId) {
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null) return;
        cashierKdsProjectionService.publishAfterCommit(detail.getMId(), "ORDER_UPDATED", null, null,
                java.util.Collections.singletonList(detailId));
        try {
            if (!configService.isKdsEnabled(shopId)) return;
            int lineQty = KdsTicketQuantityUtil.lineQuantity(detail.getQuantity());
            flowBatchService.clampAfterDetailChange(shopId, detailId, lineQty);
            if (kdsWorkflowV2Service != null && detail.getMId() != null) {
                Order order = orderService.getById(detail.getMId());
                if (order != null) {
                    kdsWorkflowV2Service.broadcastOrderAccepted(order, java.util.Collections.singletonList(detailId), true);
                }
            }
        } catch (Exception e) {
            log.warn("[kds] quantity sync failed shopId={} detailId={}: {}", shopId, detailId, e.getMessage());
        }
    }

    @Transactional
    public void afterRefundDetails(int shopId, List<Integer> detailIds) {
        if (detailIds != null) {
            java.util.Set<Integer> orderIds = new java.util.LinkedHashSet<>();
            for (Integer detailId : detailIds) {
                OrderDetail detail = detailId == null ? null : orderDetailService.getById(detailId);
                if (detail != null && detail.getMId() != null) orderIds.add(detail.getMId());
            }
            for (Integer orderId : orderIds) {
                cashierKdsProjectionService.publishAfterCommit(orderId, "ORDER_UPDATED", null, null, detailIds);
            }
        }
        try {
            if (!configService.isKdsEnabled(shopId)) return;
            ticketService.voidByDetailIds(shopId, detailIds, "refund");
        } catch (Exception e) {
            log.warn("[kds] void failed shopId={}: {}", shopId, e.getMessage());
        }
    }

    @Transactional
    public void afterOrderCancelled(Order order) {
        if (order == null || order.getId() == null || order.getShop_id() == null) {
            return;
        }
        int shopId = order.getShop_id();
        cashierKdsProjectionService.publishAfterCommit(order.getId(), "ORDER_CANCELLED", null, null, null);
        try {
            if (!configService.isKdsEnabled(shopId)) return;
            // 批量更新工单状态为VOID，避免循环调用updateItemStatus的性能问题
            Date now = new Date();
            int updated = ticketMapper.update(null, new UpdateWrapper<KdsTicket>()
                    .eq("order_id", order.getId())
                    .ne("item_status", KdsItemStatus.VOID)
                    .set("item_status", KdsItemStatus.VOID)
                    .set("void_reason", "order_cancelled")
                    .set("updated_at", now));

            if (updated > 0) {
                flowBatchService.voidByOrderId(shopId, order.getId(), "order_cancelled");
                orderStatusAggregator.aggregateAndSave(order.getId(), shopId, order.getOrder_no(), true);
                Map<String, Object> payload = new LinkedHashMap<>();
                payload.put("order_id", order.getId());
                payload.put("order_no", order.getOrder_no());
                KdsPushPayloadBuilder.enrichOrder(payload, order);
                pushService.cancelOrder(shopId, payload);
                if (kdsWorkflowV2Service != null) {
                    kdsWorkflowV2Service.broadcastOrderCancelled(shopId, order);
                }
            }
        } catch (Exception e) {
            log.warn("[kds] cancel hook failed orderId={}: {}", order.getId(), e.getMessage());
        }
    }
}
